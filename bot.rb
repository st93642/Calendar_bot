#!/usr/bin/env ruby

require 'telegram/bot'
require_relative 'config/config'

module CalendarBot
  class Bot
    def initialize
      Config.initialize_storage
      @logger = Config.logger
      @token = Config::TELEGRAM_BOT_TOKEN
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
      @logger.info("Events storage: #{Config::EVENTS_STORAGE_PATH}")

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
      else
        @logger.debug("Unknown command: #{message.text}")
      end
    end

    def handle_start(bot, message)
      response = "Welcome to Calendar Bot! 📅\n\nUse /help to see available commands."
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end

    def handle_help(bot, message)
      response = "Available commands:\n/start - Start the bot\n/help - Show this help message"
      bot.api.send_message(chat_id: message.chat.id, text: response)
    end
  end
end

if __FILE__ == $0
  bot = CalendarBot::Bot.new
  bot.start
end
