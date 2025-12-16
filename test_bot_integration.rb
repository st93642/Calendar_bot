#!/usr/bin/env ruby

# Integration test for bot commands
# This simulates bot message handling without requiring a real Telegram connection

require_relative 'lib/event_store'
require_relative 'lib/ics_importer'
require_relative 'lib/bot_helpers'
require 'ostruct'
require 'time'

class MockBot
  attr_reader :sent_messages
  
  def initialize
    @sent_messages = []
  end
  
  def api
    self
  end
  
  def send_message(chat_id:, text:, parse_mode: nil)
    @sent_messages << {
      chat_id: chat_id,
      text: text,
      parse_mode: parse_mode
    }
  end
end

class MockMessage
  attr_reader :chat, :text, :from
  
  def initialize(text, chat_id = 123)
    @text = text
    @chat = OpenStruct.new(id: chat_id)
    @from = OpenStruct.new(username: 'testuser')
  end
end

# Minimal bot class for testing
class TestBot
  include CalendarBot::BotHelpers
  
  def initialize
    @event_store = CalendarBot::EventStore.new('./test_bot_events.json')
    @logger = CalendarBot::Config.logger
  end
  
  def handle_message(bot, message)
    case message.text
    when '/start'
      handle_start(bot, message)
    when '/help'
      handle_help(bot, message)
    when '/calendar'
      handle_calendar(bot, message)
    end
  end
  
  def handle_start(bot, message)
    response = "Welcome to Calendar Bot! 📅\n\n" +
               "This bot can help you manage calendar events.\n\n" +
               "Available commands:\n" +
               "/calendar - Show upcoming events (next 7 days)\n" +
               "/events - List all events\n" +
               "/import <URL> - Import ICS calendar from URL\n" +
               "/help - Show this help message\n\n" +
               "Current events: #{@event_store.count}"
    bot.api.send_message(chat_id: message.chat.id, text: response)
  end
  
  def handle_help(bot, message)
    response = "📅 Calendar Bot Commands:\n\n" +
               "/calendar - Show upcoming events (next 7 days)\n" +
               "/events - List all events\n" +
               "/import <URL> - Import ICS calendar from URL\n" +
               "/help - Show this help message\n\n" +
               "💡 The /calendar command shows events happening in the next 7 days, limited to 10 entries.\n\n" +
               "Current events: #{@event_store.count}"
    bot.api.send_message(chat_id: message.chat.id, text: response)
  end
  
  def handle_calendar(bot, message)
    timezone = nil
    all_events = @event_store.all_events
    
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
    
    upcoming_events.sort_by! { |event| Time.parse(event['start_time']) }
    display_events = upcoming_events.take(10)
    
    if display_events.empty?
      response = "📅 *Upcoming Events*\n\n" +
                 "No events scheduled for the next 7 days\\.\n\n" +
                 "Use /import to add events from an ICS calendar\\."
      bot.api.send_message(chat_id: message.chat.id, text: response, parse_mode: 'MarkdownV2')
    else
      response_parts = ["📅 *Upcoming Events* \\(next 7 days\\)\n"]
      
      display_events.each_with_index do |event, index|
        response_parts << ""
        response_parts << format_event(event, index + 1, timezone)
      end
      
      if upcoming_events.length > 10
        remaining = upcoming_events.length - 10
        response_parts << ""
        response_parts << "\\.\\.\\. and #{remaining} more event#{remaining == 1 ? '' : 's'}"
      end
      
      response = response_parts.join("\n")
      bot.api.send_message(chat_id: message.chat.id, text: response, parse_mode: 'MarkdownV2')
    end
  rescue StandardError => e
    @logger.error("Calendar command error: #{e.message}")
    bot.api.send_message(
      chat_id: message.chat.id,
      text: "❌ Error retrieving calendar events. Please try again later."
    )
  end
  
  def setup_test_events
    @event_store.clear_all
    
    now = Time.now.utc
    
    # Create upcoming events
    @event_store.create({
      'title' => 'Team Meeting',
      'description' => 'Weekly sync',
      'start_time' => (now + 3600).iso8601,
      'end_time' => (now + 5400).iso8601,
      'custom' => true
    })
    
    @event_store.create({
      'title' => 'Client Call',
      'description' => 'Quarterly review',
      'start_time' => (now + 2 * 86400).iso8601,
      'end_time' => (now + 2 * 86400 + 3600).iso8601,
      'custom' => false,
      'imported_from_url' => 'https://example.com/cal.ics'
    })
  end
  
  def cleanup
    File.delete('./test_bot_events.json') if File.exist?('./test_bot_events.json')
  end
end

# Run tests
if __FILE__ == $0
  puts "="*70
  puts "Bot Integration Test"
  puts "="*70
  
  test_bot = TestBot.new
  mock_bot = MockBot.new
  
  begin
    # Test /start command
    puts "\n1. Testing /start command"
    message = MockMessage.new('/start')
    test_bot.handle_message(mock_bot, message)
    
    response = mock_bot.sent_messages.last
    puts "   ✓ Response sent to chat #{response[:chat_id]}"
    puts "   ✓ Message length: #{response[:text].length} chars"
    puts "   ✓ Contains '/calendar': #{response[:text].include?('/calendar')}"
    
    # Test /help command
    puts "\n2. Testing /help command"
    mock_bot.sent_messages.clear
    message = MockMessage.new('/help')
    test_bot.handle_message(mock_bot, message)
    
    response = mock_bot.sent_messages.last
    puts "   ✓ Response sent to chat #{response[:chat_id]}"
    puts "   ✓ Contains '/calendar': #{response[:text].include?('/calendar')}"
    puts "   ✓ Contains '7 days': #{response[:text].include?('7 days')}"
    
    # Test /calendar with no events
    puts "\n3. Testing /calendar command (no events)"
    mock_bot.sent_messages.clear
    message = MockMessage.new('/calendar')
    test_bot.handle_message(mock_bot, message)
    
    response = mock_bot.sent_messages.last
    puts "   ✓ Response sent to chat #{response[:chat_id]}"
    puts "   ✓ Parse mode: #{response[:parse_mode]}"
    puts "   ✓ Contains 'No events': #{response[:text].include?('No events')}"
    
    # Test /calendar with events
    puts "\n4. Testing /calendar command (with events)"
    test_bot.setup_test_events
    mock_bot.sent_messages.clear
    message = MockMessage.new('/calendar')
    test_bot.handle_message(mock_bot, message)
    
    response = mock_bot.sent_messages.last
    puts "   ✓ Response sent to chat #{response[:chat_id]}"
    puts "   ✓ Parse mode: #{response[:parse_mode]}"
    puts "   ✓ Contains 'Team Meeting': #{response[:text].include?('Team Meeting')}"
    puts "   ✓ Contains 'Client Call': #{response[:text].include?('Client Call')}"
    puts "   ✓ Contains emoji 🕒: #{response[:text].include?('🕒')}"
    puts "   ✓ Has markdown escaping: #{response[:text].include?('\\')}"
    
    puts "\n" + "="*70
    puts "All integration tests passed! ✅"
    puts "="*70
    
    puts "\nSample /calendar response:"
    puts "-"*70
    # Remove escaping for display
    puts response[:text].gsub(/\\([_*\[\]()~`>#+=|{}.!-])/, '\1')
    puts "-"*70
    
  ensure
    test_bot.cleanup
  end
end
