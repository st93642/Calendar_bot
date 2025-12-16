#!/usr/bin/env ruby

require 'telegram/bot'
require 'time'
require_relative 'config/config'
require_relative 'lib/event_store'
require_relative 'lib/ics_importer'
require_relative 'lib/bot_helpers'
require_relative 'lib/broadcast_scheduler'

module CalendarBot
  class Bot
    include BotHelpers
    
    def initialize
      ::Config.initialize_storage
      @logger = ::Config.logger
      @token = ::Config::TELEGRAM_BOT_TOKEN
      
      # Create storage adapter based on configuration
      storage_adapter = create_storage_adapter
      @event_store = EventStore.new(nil, storage_adapter)
      
      @importer = IcsImporter.new(@event_store)
      @broadcast_scheduler = BroadcastScheduler.new(@event_store, @logger)
      
      # State management for interactive commands
      @user_states = {} # Key: "#{chat_id}:#{user_id}", Value: { step: :symbol, data: {} }
      
      # Cache for admin status
      @admin_cache = {} # Key: "#{chat_id}:#{user_id}", Value: { is_admin: boolean, timestamp: Time }
    end

    def start
      @logger.info('Starting Telegram Calendar Bot...')

      begin
        setup_signal_handlers
        run_bot
      rescue Interrupt, StandardError => e
        @logger.error("Bot failed to start: #{e.message}")
        @logger.debug(e.backtrace.join("\n"))
        exit(1) if e.is_a?(StandardError)
      end
    end

    private

    def create_storage_adapter
      if ::Config::USE_REDIS
        redis_client = ::Config.create_redis_client
        if redis_client
          redis_adapter = CalendarBot::RedisStorageAdapter.new(redis_client, @logger)
          if redis_adapter.available?
            @logger.info("✓ Using Redis storage adapter")
            return redis_adapter
          else
            @logger.warn("Redis not available, falling back to file storage")
          end
        else
          @logger.warn("Redis client creation failed, falling back to file storage")
        end
      end
      
      @logger.info("✓ Using file storage adapter: #{::Config.events_storage_path}")
      CalendarBot::FileStorageAdapter.new(::Config.events_storage_path, @logger)
    end

    def setup_signal_handlers
      Signal.trap('INT') { graceful_shutdown }
      Signal.trap('TERM') { graceful_shutdown }
    end

    def graceful_shutdown
      @logger.info('Shutting down Telegram Calendar Bot...')
      @broadcast_scheduler.stop if @broadcast_scheduler
      exit(0)
    end

    def run_bot
      bot = Telegram::Bot::Client.new(@token)
      
      @logger.info('✓ Bot is ready and listening for messages')
      storage_type = ::Config::USE_REDIS ? "Redis" : "File (#{::Config.events_storage_path})"
      @logger.info("Events storage type: #{storage_type}")
      @logger.info("Total events in storage: #{@event_store.count}")
      
      # Setup and start broadcast scheduler
      @broadcast_scheduler.set_bot_client(bot)
      scheduler_started = @broadcast_scheduler.start
      
      if scheduler_started
        @logger.info("Scheduler status: #{@broadcast_scheduler.status.inspect}")
      end

      begin
        bot.listen do |message|
          handle_message(bot, message)
        end
      rescue Interrupt
        graceful_shutdown
      end
    end

    def handle_message(bot, message)
      return unless message.respond_to?(:text) && message.text # Ignore non-text messages
      
      @logger.debug("Received message from #{message.from.username}: #{message.text}")

      # Check if user is in a conversation flow
      user_key = "#{message.chat.id}:#{message.from.id}"
      if @user_states.key?(user_key)
        handle_conversation_step(bot, message, user_key)
        return
      end

      case message.text
      when '/start'
        handle_start(bot, message)
      when '/help'
        handle_help(bot, message)
      when '/calendar'
        handle_calendar(bot, message)
      when '/events'
        handle_list_events(bot, message)
      when '/import'
        handle_import_help(bot, message)
      when /^(\/import\s+)(https?:\/\/.+)/
        url = $2.strip
        if is_admin?(bot, message)
          handle_import_url(bot, message, url)
        else
          send_forbidden(bot, message)
        end
      when '/add_event'
        handle_add_event(bot, message)
      when /^(\/delete_event\s+)(.+)/
        id = $2.strip
        if is_admin?(bot, message)
          handle_delete_event(bot, message, id)
        else
          send_forbidden(bot, message)
        end
      when '/delete_event'
        bot.api.send_message(chat_id: message.chat.id, text: "⚠️ Usage: /delete_event <event_id>\nUse /events to find the ID.")
      when '/broadcast_status'
        handle_broadcast_status(bot, message)
      when '/broadcast_check'
        handle_broadcast_check(bot, message)
      else
        handle_unknown(bot, message) unless message.text.start_with?('/') == false # Ignore normal chat
      end
    end

    def handle_start(bot, message)
      response = "Welcome to Calendar Bot! 📅\n\n" +
                 "This bot can help you manage calendar events.\n\n" +
                 "Available commands:\n" +
                 "/calendar - Show upcoming events (next 7 days)\n" +
                 "/events - List all events\n" +
                 "/add_event - Add a new custom event\n" +
                 "/import <URL> - Import ICS calendar from URL (Admin only)\n" +
                 "/delete_event <ID> - Delete an event (Admin only)\n" +
                 "/help - Show this help message\n\n" +
                 "Current events: #{@event_store.count}"
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def handle_help(bot, message)
      response = "📅 Calendar Bot Commands:\n\n" +
                 "/calendar - Show upcoming events (next 7 days)\n" +
                 "/events - List all events\n" +
                 "/add_event - Add a new custom event (Interactive)\n" +
                 "/import <URL> - Import ICS calendar from URL (Admin only)\n" +
                 "/delete_event <ID> - Delete an event (Admin only)\n" +
                 "/broadcast_status - Check scheduler status (Admin only)\n" +
                 "/broadcast_check - Force scheduler check (Admin only)\n" +
                 "/help - Show this help message\n\n" +
                 "💡 The /calendar command shows events happening in the next 7 days, limited to 10 entries.\n\n" +
                 "Current events: #{@event_store.count}"
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def handle_calendar(bot, message)
      # Get timezone from message context if available (future enhancement)
      # For now, we'll use UTC as default
      timezone = nil
      
      # Get all events
      all_events = @event_store.all_events
      
      # Filter to upcoming events (next 7 days)
      now = Time.now.utc
      seven_days_from_now = now + (7 * 24 * 60 * 60)
      
      upcoming_events = all_events.select do |event|
        begin
          event_start = Time.parse(event['start_time']).utc
          event_start >= now && event_start <= seven_days_from_now
        rescue ArgumentError
          false
        end
      end
      
      # Sort by start time
      upcoming_events.sort_by! { |event| Time.parse(event['start_time']) }
      
      # Limit to 10 events
      display_events = upcoming_events.take(10)
      
      if display_events.empty?
        response = "📅 *Upcoming Events*\n\n" +
                   "No events scheduled for the next 7 days\\.\n\n" +
                   "Use /import to add events from an ICS calendar\\."
        bot.api.send_message(chat_id: message.chat.id, text: response, parse_mode: 'MarkdownV2')
      else
        # Build response with formatted events
        response_parts = ["📅 *Upcoming Events* \\(next 7 days\\)\n"]
        
        display_events.each_with_index do |event, index|
          response_parts << ""
          response_parts << format_event(event, index + 1, timezone)
        end
        
        # Add pagination note if there are more events
        if upcoming_events.length > 10
          remaining = upcoming_events.length - 10
          response_parts << ""
          response_parts << "\\.\\.\\. and #{remaining} more event#{remaining == 1 ? '' : 's'}"
        end
        
        response = response_parts.join("\n")
        
        begin
          bot.api.send_message(chat_id: message.chat.id, text: response, parse_mode: 'MarkdownV2')
        rescue Telegram::Bot::Exceptions::ResponseError => e
          # If markdown parsing fails, send plain text
          @logger.error("Markdown parsing failed: #{e.message}")
          plain_response = response.gsub(/\\/, '')
          bot.api.send_message(chat_id: message.chat.id, text: plain_response)
        end
      end
    rescue StandardError => e
      @logger.error("Calendar command error: #{e.message}")
      @logger.debug(e.backtrace.join("\n"))
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "❌ Error retrieving calendar events. Please try again later."
      )
    end

    def handle_list_events(bot, message)
      events = @event_store.all_events
      
      if events.empty?
        response = "No events found. Add some events or import an ICS calendar."
      else
        response_parts = ["📅 Events (#{events.length}):\n"]
        events.each_with_index do |event, i|
          response_parts << "#{i + 1}. #{event['title']}"
          response_parts << "   ID: `#{event['id']}`" # Useful for deletion
          response_parts << "   🕒 #{format_time(event['start_time'])}"
          response_parts << "   🏷️  #{event['custom'] ? 'Custom' : 'Imported'}"
          response_parts << ""
        end
        response = response_parts.join("\n")
      end
      
      # Split message if too long (Telegram limit is 4096)
      if response.length > 4000
        chunks = response.chars.each_slice(4000).map(&:join)
        chunks.each do |chunk|
          bot.api.send_message(chat_id: message.chat.id, text: chunk, parse_mode: 'Markdown')
        end
      else
        bot.api.send_message(chat_id: message.chat.id, text: response, parse_mode: 'Markdown')
      end
    end

    def handle_import_help(bot, message)
      if is_admin?(bot, message)
        response = "🔄 ICS Import Help:\n\n" +
                   "To import an ICS calendar, use:\n" +
                   "/import <URL>\n\n" +
                   "Example:\n" +
                   "/import https://example.com/calendar.ics\n\n" +
                   "This will:\n" +
                   "• Download the ICS file\n" +
                   "• Parse calendar events\n" +
                   "• Merge with existing events\n" +
                   "• Skip duplicates (same title + time)\n" +
                   "• Update existing events if found"
        bot.api.send_message(chat_id: message.chat.id, text: response)
      else
        send_forbidden(bot, message)
      end
    end

    def handle_import_url(bot, message, url)
      bot.api.send_message(chat_id: message.chat.id, text: "🔄 Importing calendar from #{url}...")

      begin
        result = @importer.import_from_url(url)
        
        if result[:success]
          response = "✅ Import completed!\n\n" +
                     "Events processed: #{result[:events_processed]}\n" +
                     "Created: #{result[:merge_results][:created]}\n" +
                     "Updated: #{result[:merge_results][:updated]}\n" +
                     "Errors: #{result[:merge_results][:errors]}\n\n" +
                     "Total events now: #{@event_store.count}"
        else
          response = "❌ Import failed: #{result[:error]}"
        end
        
        bot.api.send_message(chat_id: message.chat.id, text: response)
      rescue StandardError => e
        @logger.error("Import error: #{e.message}")
        bot.api.send_message(chat_id: message.chat.id, text: "❌ Import failed: #{e.message}")
      end
    end
    
    # --- Interactive /add_event flow ---
    
    def handle_add_event(bot, message)
      user_key = "#{message.chat.id}:#{message.from.id}"
      
      @user_states[user_key] = {
        step: :title,
        event_data: { 'custom' => true }
      }
      
      bot.api.send_message(chat_id: message.chat.id, text: "📝 Adding new event.\n\nPlease enter the **Event Title** (or type /cancel to abort):", parse_mode: 'Markdown')
    end
    
    def handle_conversation_step(bot, message, user_key)
      state = @user_states[user_key]
      
      if message.text == '/cancel'
        @user_states.delete(user_key)
        bot.api.send_message(chat_id: message.chat.id, text: "❌ Operation cancelled.")
        return
      end

      case state[:step]
      when :title
        state[:event_data]['title'] = message.text
        state[:step] = :description
        bot.api.send_message(chat_id: message.chat.id, text: "📝 Enter **Description** (or type 'skip' for none):", parse_mode: 'Markdown')
        
      when :description
        desc = message.text
        state[:event_data]['description'] = (desc.downcase == 'skip') ? nil : desc
        state[:step] = :start_time
        bot.api.send_message(chat_id: message.chat.id, text: "🕒 Enter **Start Time** (YYYY-MM-DD HH:MM):", parse_mode: 'Markdown')
        
      when :start_time
        begin
          time = Time.parse(message.text)
          state[:event_data]['start_time'] = time.utc.iso8601
          state[:step] = :end_time
          bot.api.send_message(chat_id: message.chat.id, text: "🕓 Enter **End Time** (YYYY-MM-DD HH:MM):", parse_mode: 'Markdown')
        rescue ArgumentError
          bot.api.send_message(chat_id: message.chat.id, text: "❌ Invalid format. Please use YYYY-MM-DD HH:MM:")
        end
        
      when :end_time
        begin
          time = Time.parse(message.text)
          end_time = time.utc.iso8601
          
          # Validate end time > start time
          start_time = Time.parse(state[:event_data]['start_time'])
          if time <= start_time
             bot.api.send_message(chat_id: message.chat.id, text: "❌ End time must be after start time. Please try again:")
             return
          end

          state[:event_data]['end_time'] = end_time
          
          # Try to create
          result = @event_store.create(state[:event_data])
          
          if result
            bot.api.send_message(chat_id: message.chat.id, text: "✅ Event *#{result['title']}* created successfully!", parse_mode: 'Markdown')
          else
            bot.api.send_message(chat_id: message.chat.id, text: "⚠️ Failed to create event (possibly duplicate title + time).")
          end
          
          @user_states.delete(user_key)
        rescue ArgumentError
          bot.api.send_message(chat_id: message.chat.id, text: "❌ Invalid format. Please use YYYY-MM-DD HH:MM:")
        end
      end
    end
    
    # --- Delete Event ---
    
    def handle_delete_event(bot, message, id)
      if @event_store.delete(id)
        bot.api.send_message(chat_id: message.chat.id, text: "✅ Event deleted successfully.")
      else
        bot.api.send_message(chat_id: message.chat.id, text: "❌ Event not found with ID: #{id}")
      end
    end

    def handle_unknown(bot, message)
      if message.text.start_with?('/')
        response = "❓ Unknown command: #{message.text}\n\n" +
                   "Use /help to see available commands."
        bot.api.send_message(chat_id: message.chat.id, text: response)
      end
    end

    def format_time(iso_time)
      begin
        time = Time.parse(iso_time)
        time.strftime("%Y-%m-%d %H:%M")
      rescue
        iso_time
      end
    end
    
    # --- Admin Verification ---
    
    def is_admin?(bot, message)
      # Private chats: User is always authorized
      return true if message.chat.type == 'private'
      
      user_id = message.from.id
      chat_id = message.chat.id
      cache_key = "#{chat_id}:#{user_id}"
      
      # Check cache (5 mins)
      if @admin_cache[cache_key] && Time.now - @admin_cache[cache_key][:timestamp] < 300
        return @admin_cache[cache_key][:is_admin]
      end
      
      begin
        member = bot.api.get_chat_member(chat_id: chat_id, user_id: user_id)
        
        # Handle various return types from the gem
        status = if member.respond_to?(:result)
                   member.result['status']
                 elsif member.respond_to?(:status)
                   member.status
                 elsif member.is_a?(Hash)
                   member['result']['status'] rescue member['status']
                 else
                   nil
                 end
        
        is_admin = ['creator', 'administrator'].include?(status)
        
        @admin_cache[cache_key] = { is_admin: is_admin, timestamp: Time.now }
        is_admin
      rescue StandardError => e
        @logger.error("Admin check failed: #{e.message}")
        false
      end
    end
    
    def send_forbidden(bot, message)
      bot.api.send_message(chat_id: message.chat.id, text: "⛔ You must be an admin to use this command.")
    end

    # --- Broadcast Scheduler Commands ---
    
    def handle_broadcast_status(bot, message)
      if is_admin?(bot, message)
        status = @broadcast_scheduler.status
        
        response = "📡 Broadcast Scheduler Status:\n\n" +
                   "Enabled: #{status[:enabled] ? '✅ Yes' : '❌ No'}\n" +
                   "Check Interval: #{status[:check_interval]} minutes\n" +
                   "Lead Time: #{status[:lead_time]} minutes (#{status[:lead_time] / 60} hours)\n" +
                   "Target Groups: #{status[:target_groups].join(', ')}\n" +
                   "Metadata Entries: #{status[:metadata_count]}\n" +
                   "Next Run: #{status[:next_run] ? status[:next_run].strftime('%Y-%m-%d %H:%M:%S UTC') : 'N/A'}"
        
        bot.api.send_message(chat_id: message.chat.id, text: response)
      else
        send_forbidden(bot, message)
      end
    end
    
    def handle_broadcast_check(bot, message)
      if is_admin?(bot, message)
        bot.api.send_message(chat_id: message.chat.id, text: "🔄 Running broadcast check...")
        
        @broadcast_scheduler.force_check
        
        bot.api.send_message(chat_id: message.chat.id, text: "✅ Broadcast check completed.")
      else
        send_forbidden(bot, message)
      end
    end
  end
end

if __FILE__ == $0
  bot = CalendarBot::Bot.new
  bot.start
end
