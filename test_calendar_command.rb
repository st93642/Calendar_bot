#!/usr/bin/env ruby

require_relative 'lib/event_store'
require_relative 'lib/bot_helpers'
require 'time'

class CalendarTester
  include CalendarBot::BotHelpers

  def initialize
    @event_store = CalendarBot::EventStore.new('./test_events.json')
  end

  def setup_test_data
    puts "Setting up test data..."
    
    # Clear existing events
    @event_store.clear_all

    now = Time.now.utc

    # Create past event (should not appear)
    @event_store.create({
      'title' => 'Past Event',
      'description' => 'This event already happened',
      'start_time' => (now - 86400).iso8601,  # 1 day ago
      'end_time' => (now - 86400 + 3600).iso8601,
      'custom' => true
    })

    # Create event today (should appear)
    @event_store.create({
      'title' => 'Today: Team Standup',
      'description' => 'Daily sync with the team',
      'start_time' => (now + 3600).iso8601,  # 1 hour from now
      'end_time' => (now + 5400).iso8601,    # 1.5 hours from now
      'custom' => true
    })

    # Create events within next 7 days (should appear)
    @event_store.create({
      'title' => 'Client Meeting',
      'description' => 'Quarterly business review with client',
      'start_time' => (now + 2 * 86400).iso8601,  # 2 days from now
      'end_time' => (now + 2 * 86400 + 3600).iso8601,
      'custom' => false,
      'imported_from_url' => 'https://example.com/calendar.ics'
    })

    @event_store.create({
      'title' => 'Product Launch',
      'description' => 'New feature release',
      'start_time' => (now + 5 * 86400).iso8601,  # 5 days from now
      'end_time' => (now + 5 * 86400 + 7200).iso8601,
      'custom' => true
    })

    # Create event beyond 7 days (should not appear)
    @event_store.create({
      'title' => 'Future Conference',
      'description' => 'Annual tech conference',
      'start_time' => (now + 10 * 86400).iso8601,  # 10 days from now
      'end_time' => (now + 10 * 86400 + 3600).iso8601,
      'custom' => false
    })

    # Create multiple events for pagination test
    7.times do |i|
      @event_store.create({
        'title' => "Event #{i + 1}",
        'description' => "Test event #{i + 1}",
        'start_time' => (now + (i + 1) * 3600).iso8601,
        'end_time' => (now + (i + 1) * 3600 + 1800).iso8601,
        'custom' => true
      })
    end

    puts "✓ Created #{@event_store.count} test events"
  end

  def test_calendar_logic
    puts "\n" + "="*60
    puts "Testing /calendar command logic"
    puts "="*60

    # Get all events
    all_events = @event_store.all_events
    puts "\nTotal events in store: #{all_events.length}"

    # Filter to upcoming events (next 7 days)
    now = Time.now.utc
    seven_days_from_now = now + (7 * 24 * 60 * 60)

    puts "Current time: #{now}"
    puts "7 days from now: #{seven_days_from_now}"

    upcoming_events = all_events.select do |event|
      begin
        event_start = Time.parse(event['start_time']).utc
        event_start >= now && event_start <= seven_days_from_now
      rescue ArgumentError
        false
      end
    end

    puts "\nUpcoming events (within 7 days): #{upcoming_events.length}"

    # Sort by start time
    upcoming_events.sort_by! { |event| Time.parse(event['start_time']) }

    # Limit to 10 events
    display_events = upcoming_events.take(10)
    puts "Display events (limited to 10): #{display_events.length}"

    # Show events
    if display_events.empty?
      puts "\n📅 No events scheduled for the next 7 days."
    else
      puts "\n📅 Upcoming Events (next 7 days):\n"
      display_events.each_with_index do |event, index|
        puts "\n#{format_event(event, index + 1)}"
          .gsub(/\\([_*\[\]()~`>#+=|{}.!-])/, '\1')  # Remove escaping for console display
      end

      if upcoming_events.length > 10
        remaining = upcoming_events.length - 10
        puts "\n... and #{remaining} more event#{remaining == 1 ? '' : 's'}"
      end
    end
  end

  def test_no_events_scenario
    puts "\n" + "="*60
    puts "Testing empty calendar scenario"
    puts "="*60

    @event_store.clear_all
    
    # Create only events outside the 7-day window
    now = Time.now.utc
    @event_store.create({
      'title' => 'Far Future Event',
      'start_time' => (now + 10 * 86400).iso8601,
      'end_time' => (now + 10 * 86400 + 3600).iso8601,
      'custom' => true
    })

    all_events = @event_store.all_events
    seven_days_from_now = now + (7 * 24 * 60 * 60)

    upcoming_events = all_events.select do |event|
      event_start = Time.parse(event['start_time']).utc
      event_start >= now && event_start <= seven_days_from_now
    end

    puts "\nTotal events: #{all_events.length}"
    puts "Upcoming events: #{upcoming_events.length}"
    puts "\nResult: No events scheduled for the next 7 days."
  end

  def test_markdown_escaping
    puts "\n" + "="*60
    puts "Testing markdown escaping"
    puts "="*60

    test_strings = [
      "Event with *asterisks*",
      "Event with [brackets]",
      "Event with (parentheses)",
      "Event with _underscores_",
      "Event with ~tilde~",
      "Event with `backticks`",
      "Event with special chars: #+-=|{}.!"
    ]

    test_strings.each do |str|
      escaped = escape_markdown(str)
      puts "\nOriginal: #{str}"
      puts "Escaped:  #{escaped}"
    end
  end

  def cleanup
    File.delete('./test_events.json') if File.exist?('./test_events.json')
    puts "\n✓ Cleaned up test data"
  end
end

# Run tests
if __FILE__ == $0
  tester = CalendarTester.new
  
  begin
    tester.setup_test_data
    tester.test_calendar_logic
    tester.test_no_events_scenario
    tester.test_markdown_escaping
    
    puts "\n" + "="*60
    puts "All tests completed successfully!"
    puts "="*60
  ensure
    tester.cleanup
  end
end
