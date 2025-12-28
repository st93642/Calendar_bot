#!/usr/bin/env ruby

require 'telegram/bot'
require 'time'
require_relative 'config/config'
require_relative 'lib/event_store'
require_relative 'lib/ics_importer'
require_relative 'lib/bot_helpers'
require_relative 'lib/broadcast_scheduler'
require_relative 'lib/calendar_keyboard'

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
        bot.listen do |update|
          case update
          when Telegram::Bot::Types::CallbackQuery
            handle_callback_query(bot, update)
          when Telegram::Bot::Types::Message
            handle_message(bot, update)
          end
        end
      rescue Interrupt
        graceful_shutdown
      end
    end

    def handle_message(bot, message)
      return unless message.respond_to?(:text) && message.text # Ignore non-text messages
      
      @logger.debug("Received message from #{message.from.username} (chat_id: #{message.chat.id}, type: #{message.chat.type}): #{message.text}")

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
          # Delete the user's message to hide the URL from the group
          begin
            bot.api.delete_message(chat_id: message.chat.id, message_id: message.message_id)
          rescue => e
            @logger.warn("Could not delete import message: #{e.message}")
          end
          handle_import_url(bot, message, url)
        else
          send_forbidden(bot, message)
        end
      when '/add_event'
        # Delete the command message to keep conversation private
        begin
          bot.api.delete_message(chat_id: message.chat.id, message_id: message.message_id)
        rescue => e
          @logger.warn("Could not delete add_event message: #{e.message}")
        end
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
                 "💡 The /calendar command shows events happening in the next 7 days, limited to 5 entries.\n\n" +
                 "Current events: #{@event_store.count}"
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def handle_calendar(bot, message)
      # Get timezone from message context if available (future enhancement)
      # For now, we'll use UTC as default
      timezone = nil
      
      # Track message IDs for auto-deletion (include the user's trigger command too)
      message_ids = [message.message_id]
      
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
      
      # Limit to 5 events to avoid message length issues
      display_events = upcoming_events.take(5)
      
      if display_events.empty?
        response = "📅 *Upcoming Events*\n\n" +
                   "No events scheduled for the next 7 days.\n\n" +
                   "Use /import to add events from an ICS calendar."
        msg = bot.api.send_message(chat_id: message.chat.id, text: response, parse_mode: 'Markdown')
        message_ids << msg.dig('result', 'message_id')
      else
        # Send events one by one to avoid message length issues
        header = "📅 Upcoming Events (next 7 days)\n\nShowing #{display_events.length} of #{upcoming_events.length} event#{upcoming_events.length == 1 ? '' : 's'}\n"
        msg = bot.api.send_message(chat_id: message.chat.id, text: header)
        message_ids << msg.dig('result', 'message_id')
        
        display_events.each_with_index do |event, index|
          event_text = format_event_plain(event, index + 1, timezone)
          msg = bot.api.send_message(chat_id: message.chat.id, text: event_text)
          message_ids << msg.dig('result', 'message_id')
        end
        
        # Add pagination note if there are more events
        if upcoming_events.length > 5
          remaining = upcoming_events.length - 5
          note = "\nUse /events to see all #{upcoming_events.length} events"
          msg = bot.api.send_message(chat_id: message.chat.id, text: note)
          message_ids << msg.dig('result', 'message_id')
        end
      end
      
      # Schedule deletion of all messages after 3 minutes
      schedule_message_deletion(bot, message.chat.id, message_ids, 180)
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
      
      # Track message IDs for auto-deletion (include the user's trigger command too)
      message_ids = [message.message_id]
      
      if events.empty?
        response = "No events found. Add some events or import an ICS calendar."
        msg = bot.api.send_message(chat_id: message.chat.id, text: response)
        message_ids << msg.dig('result', 'message_id')
      else
        # Sort events by start time
        events.sort_by! { |event| Time.parse(event['start_time']) }
        
        # Send header first
        header = "📅 Events (#{events.length}):\n"
        msg = bot.api.send_message(chat_id: message.chat.id, text: header)
        message_ids << msg.dig('result', 'message_id')
        
        # Send each event as a separate message to avoid length/parsing issues
        events.each_with_index do |event, i|
          event_parts = []
          event_parts << "#{i + 1}. #{event['title']}"
          event_parts << "   ID: #{event['id']}"
          event_parts << "   🕒 #{format_time(event['start_time'])}"
          event_parts << "   🏷️  #{event['custom'] ? 'Custom' : 'Imported'}"
          
          event_text = event_parts.join("\n")
          
          # Send as plain text to avoid Markdown parsing issues with special characters
          msg = bot.api.send_message(chat_id: message.chat.id, text: event_text)
          message_ids << msg.dig('result', 'message_id')
        end
      end
      
      # Schedule deletion of all messages after 3 minutes
      schedule_message_deletion(bot, message.chat.id, message_ids, 180)
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
    
    # Handle calendar keyboard callbacks
    def handle_callback_query(bot, query)
      user_key = "#{query.message.chat.id}:#{query.from.id}"
      data = query.data
      
      # Answer callback to remove loading state
      bot.api.answer_callback_query(callback_query_id: query.id)
      
      case data
      when 'ignore'
        # Do nothing for header/label buttons
        return
        
      when 'cancel_date'
        @user_states.delete(user_key)
        bot.api.edit_message_text(
          chat_id: query.message.chat.id,
          message_id: query.message.message_id,
          text: "❌ Event creation cancelled."
        )
        
      when /^prev_month:(\d+):(\d+)$/
        year, month = $1.to_i, $2.to_i
        new_date = Date.new(year, month, 1) << 1  # Previous month
        keyboard = CalendarKeyboard.generate_month(new_date.year, new_date.month)
        bot.api.edit_message_reply_markup(
          chat_id: query.message.chat.id,
          message_id: query.message.message_id,
          reply_markup: { inline_keyboard: keyboard }
        )
        
      when /^next_month:(\d+):(\d+)$/
        year, month = $1.to_i, $2.to_i
        new_date = Date.new(year, month, 1) >> 1  # Next month
        keyboard = CalendarKeyboard.generate_month(new_date.year, new_date.month)
        bot.api.edit_message_reply_markup(
          chat_id: query.message.chat.id,
          message_id: query.message.message_id,
          reply_markup: { inline_keyboard: keyboard }
        )
        
      when 'today'
        handle_date_selected(bot, query, Date.today.to_s, user_key)
        
      when /^date:(.+)$/
        selected_date = $1
        handle_date_selected(bot, query, selected_date, user_key)
        
      when /^time_nav:(.+):(\d+)$/
        selected_date, hour = $1, $2.to_i
        keyboard = CalendarKeyboard.generate_time_selector(selected_date, hour)
        bot.api.edit_message_reply_markup(
          chat_id: query.message.chat.id,
          message_id: query.message.message_id,
          reply_markup: { inline_keyboard: keyboard }
        )
        
      when /^time:(.+):(\d+):(\d+)$/
        selected_date, hour, minute = $1, $2.to_i, $3.to_i
        handle_time_selected(bot, query, selected_date, hour, minute, user_key)
        
      when 'back_to_calendar'
        state = @user_states[user_key]
        if state
          keyboard = CalendarKeyboard.generate_month(Date.today.year, Date.today.month)
          bot.api.edit_message_text(
            chat_id: query.message.chat.id,
            message_id: query.message.message_id,
            text: "📅 Select #{state[:step] == :awaiting_start_time ? 'start' : 'end'} date:",
            reply_markup: { inline_keyboard: keyboard }
          )
        end
        
      when 'use_manual_input'
        state = @user_states[user_key]
        if state
          step_name = state[:step] == :awaiting_start_time ? 'start' : 'end'
          bot.api.edit_message_text(
            chat_id: query.message.chat.id,
            message_id: query.message.message_id,
            text: "🕒 Enter **#{step_name.capitalize} Time** (DD MM YY HH MM):",
            parse_mode: 'Markdown'
          )
          state[:step] = state[:step] == :awaiting_start_time ? :start_time : :end_time
        end
      end
    rescue StandardError => e
      @logger.error("Callback query error: #{e.message}")
      @logger.debug(e.backtrace.join("\n"))
      bot.api.answer_callback_query(
        callback_query_id: query.id,
        text: "❌ Error processing selection. Please try again."
      )
    end
    
    def handle_date_selected(bot, query, selected_date, user_key)
      state = @user_states[user_key]
      return unless state
      
      keyboard = CalendarKeyboard.generate_time_selector(selected_date)
      step_name = state[:step] == :awaiting_start_time ? 'start' : 'end'
      
      bot.api.edit_message_text(
        chat_id: query.message.chat.id,
        message_id: query.message.message_id,
        text: "⏰ Select #{step_name} time for #{selected_date}:",
        reply_markup: { inline_keyboard: keyboard }
      )
    end
    
    def handle_time_selected(bot, query, selected_date, hour, minute, user_key)
      state = @user_states[user_key]
      return unless state
      
      time_str = "#{selected_date} #{hour.to_s.rjust(2, '0')}:#{minute.to_s.rjust(2, '0')}"
      time = Time.parse(time_str).utc.iso8601
      
      if state[:step] == :awaiting_start_time
        state[:event_data]['start_time'] = time
        state[:step] = :awaiting_end_time
        
        # Show calendar for end time
        keyboard = CalendarKeyboard.generate_month(Date.today.year, Date.today.month)
        bot.api.edit_message_text(
          chat_id: query.message.chat.id,
          message_id: query.message.message_id,
          text: "📅 Select end date:",
          reply_markup: { inline_keyboard: keyboard }
        )
      else
        # Validate end time > start time
        start_time = Time.parse(state[:event_data]['start_time'])
        end_time = Time.parse(time_str)
        
        if end_time <= start_time
          bot.api.answer_callback_query(
            callback_query_id: query.id,
            text: "❌ End time must be after start time!",
            show_alert: true
          )
          return
        end
        
        state[:event_data]['end_time'] = time
        
        # Create the event
        result = @event_store.create(state[:event_data])
        
        if result
          bot.api.edit_message_text(
            chat_id: query.message.chat.id,
            message_id: query.message.message_id,
            text: "✅ Event *#{escape_markdown(result['title'])}* created successfully!\n\n" +
                  "🕒 #{escape_markdown(format_timestamp(result['start_time']))}\n" +
                  "   to #{escape_markdown(format_timestamp(result['end_time']))}",
            parse_mode: 'MarkdownV2'
          )
        else
          bot.api.edit_message_text(
            chat_id: query.message.chat.id,
            message_id: query.message.message_id,
            text: "⚠️ Failed to create event (possibly duplicate title + time)."
          )
        end
        
        @user_states.delete(user_key)
      end
    end
    
    def handle_conversation_step(bot, message, user_key)
      state = @user_states[user_key]
      
      # Delete user's message to keep event details private
      begin
        bot.api.delete_message(chat_id: message.chat.id, message_id: message.message_id)
      rescue => e
        @logger.warn("Could not delete conversation message: #{e.message}")
      end
      
      if message.text == '/cancel'
        @user_states.delete(user_key)
        bot.api.send_message(chat_id: message.chat.id, text: "❌ Operation cancelled.")
        return
      end

      case state[:step]
      when :title
        state[:event_data]['title'] = message.text
        state[:step] = :awaiting_start_time
        
        # Show calendar keyboard for start time
        keyboard = CalendarKeyboard.generate_month(Date.today.year, Date.today.month)
        keyboard << [{ text: "✍️ Enter Manually", callback_data: "use_manual_input" }]
        
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "📅 Select start date:",
          reply_markup: { inline_keyboard: keyboard }
        )
        
      when :description
        # Skip description - we don't store it anymore
        state[:step] = :awaiting_start_time
        
        # Show calendar keyboard
        keyboard = CalendarKeyboard.generate_month(Date.today.year, Date.today.month)
        keyboard << [{ text: "✍️ Enter Manually", callback_data: "use_manual_input" }]
        
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "📅 Select start date:",
          reply_markup: { inline_keyboard: keyboard }
        )
        
      when :start_time
        begin
          # Validate format: DD MM YY HH MM
          unless message.text.match?(/\d{2}\s+\d{2}\s+\d{2}\s+\d{2}\s+\d{2}/)
            bot.api.send_message(chat_id: message.chat.id, text: "❌ Invalid format. Use DD MM YY HH MM\nExample: 31 12 25 14 00")
            return
          end
          
          time = Time.strptime(message.text, "%d %m %y %H %M")
          state[:event_data]['start_time'] = time.utc.iso8601
          state[:step] = :end_time
          bot.api.send_message(chat_id: message.chat.id, text: "🕓 Enter **End Time** (DD MM YY HH MM):", parse_mode: 'Markdown')
        rescue ArgumentError
          bot.api.send_message(chat_id: message.chat.id, text: "❌ Invalid date/time. Please use DD MM YY HH MM:")
        end
        
      when :awaiting_start_time
        # User chose manual input from calendar keyboard
        state[:step] = :start_time
        handle_conversation_step(bot, message, user_key)
        return
        
      when :awaiting_end_time
        # User chose manual input from calendar keyboard
        state[:step] = :end_time
        handle_conversation_step(bot, message, user_key)
        return
        
      when :end_time
        begin
          # Validate format: DD MM YY HH MM
          unless message.text.match?(/\d{2}\s+\d{2}\s+\d{2}\s+\d{2}\s+\d{2}/)
            bot.api.send_message(chat_id: message.chat.id, text: "❌ Invalid format. Use DD MM YY HH MM\nExample: 31 12 25 15 00")
            return
          end
          
          time = Time.strptime(message.text, "%d %m %y %H %M")
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
          bot.api.send_message(chat_id: message.chat.id, text: "❌ Invalid date/time. Please use DD MM YY HH MM:")
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
        time.strftime("%d/%b/%Y %H:%M")
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
    
    # Schedule message deletion after specified delay
    def schedule_message_deletion(bot, chat_id, message_ids, delay_seconds)
      Thread.new do
        sleep(delay_seconds)
        message_ids.each do |msg_id|
          begin
            bot.api.delete_message(chat_id: chat_id, message_id: msg_id)
          rescue => e
            @logger.debug("Could not delete message #{msg_id}: #{e.message}")
          end
        end
      end
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
