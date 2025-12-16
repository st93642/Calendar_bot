#!/usr/bin/env ruby

require 'telegram/bot'
require_relative 'lib/event_store'
require_relative 'lib/ics_importer'

module CalendarBot
  class Bot
    def initialize
      Config.initialize_storage
      @logger = Config.logger
      @token = Config::TELEGRAM_BOT_TOKEN
      @event_store = EventStore.new
      @importer = IcsImporter.new(@event_store)
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

    def setup_signal_handlers
      Signal.trap('INT') { graceful_shutdown }
      Signal.trap('TERM') { graceful_shutdown }
    end

    def graceful_shutdown
      @logger.info('Shutting down Telegram Calendar Bot...')
      exit(0)
    end

    def run_bot
      bot = Telegram::Bot::Client.new(@token)
      
      @logger.info('✓ Bot is ready and listening for messages')
      @logger.info("Broadcast lead time: #{Config::BROADCAST_LEAD_TIME} seconds")
      @logger.info("Events storage: #{Config.events_storage_path}")
      @logger.info("Total events in storage: #{@event_store.count}")

      begin
        bot.listen do |message|
          handle_message(bot, message)
        end
      rescue Interrupt
        graceful_shutdown
      end
    end

    def handle_message(bot, message)
      @logger.debug("Received message from #{message.from.username}: #{message.text}")

      case message.text
      when '/start'
        handle_start(bot, message)
      when '/help'
        handle_help(bot, message)
      when '/events'
        handle_list_events(bot, message)
      when '/import'
        handle_import_help(bot, message)
      when /^(\/import\s+)(https?:\/\/.+)/
        url = $2.strip
        handle_import_url(bot, message, url)
      else
        handle_unknown(bot, message)
      end
    end

    def handle_start(bot, message)
      response = "Welcome to Calendar Bot! 📅\n\n" +
                 "This bot can help you manage calendar events.\n\n" +
                 "Available commands:\n" +
                 "/events - List all events\n" +
                 "/import <URL> - Import ICS calendar from URL\n" +
                 "/help - Show this help message\n\n" +
                 "Current events: #{@event_store.count}"
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def handle_help(bot, message)
      response = "📅 Calendar Bot Commands:\n\n" +
                 "/events - List all events\n" +
                 "/import <URL> - Import ICS calendar from URL\n" +
                 "/help - Show this help message\n\n" +
                 "Current events: #{@event_store.count}"
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def handle_list_events(bot, message)
      events = @event_store.all_events
      
      if events.empty?
        response = "No events found. Add some events or import an ICS calendar."
      else
        response = "📅 Events (#{events.length}):\n\n"
        events.each_with_index do |event, i|
          response += "#{i + 1}. #{event['title']}\n"
          response += "   🕒 #{format_time(event['start_time'])}\n"
          response += "   🏷️  #{event['custom'] ? 'Custom' : 'Imported'}\n"
          response += "\n"
        end
      end
      
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def handle_import_help(bot, message)
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

    def handle_unknown(bot, message)
      response = "❓ Unknown command: #{message.text}\n\n" +
                 "Use /help to see available commands."
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def format_time(iso_time)
      begin
        time = Time.parse(iso_time)
        time.strftime("%Y-%m-%d %H:%M")
      rescue
        iso_time
      end
    end
  end
end

if __FILE__ == $0
  bot = CalendarBot::Bot.new
  bot.start
end
