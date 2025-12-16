require_relative 'test_config'
require_relative '../lib/event_store'
require_relative '../lib/bot_helpers'
require 'time'
require 'timecop'

RSpec.describe 'Calendar Command Functionality' do
  include CalendarBot::BotHelpers

  let(:temp_storage) { './spec/test_calendar_events.json' }
  let(:event_store) { CalendarBot::EventStore.new(temp_storage) }

  before do
    # Clean up test storage
    File.delete(temp_storage) if File.exist?(temp_storage)
  end

  after do
    # Clean up test storage
    File.delete(temp_storage) if File.exist?(temp_storage)
  end

  describe 'filtering upcoming events' do
    it 'shows only future events within next 7 days' do
      Timecop.freeze(Time.parse('2024-12-20T12:00:00Z')) do
        # Create events at different times
        past_event = {
          'title' => 'Past Event',
          'start_time' => '2024-12-19T10:00:00Z',
          'end_time' => '2024-12-19T11:00:00Z'
        }

        today_event = {
          'title' => 'Today Event',
          'start_time' => '2024-12-20T14:00:00Z',
          'end_time' => '2024-12-20T15:00:00Z'
        }

        within_7_days = {
          'title' => 'Next Week Event',
          'start_time' => '2024-12-25T10:00:00Z',
          'end_time' => '2024-12-25T11:00:00Z'
        }

        beyond_7_days = {
          'title' => 'Far Future Event',
          'start_time' => '2024-12-30T10:00:00Z',
          'end_time' => '2024-12-30T11:00:00Z'
        }

        event_store.create(past_event)
        event_store.create(today_event)
        event_store.create(within_7_days)
        event_store.create(beyond_7_days)

        # Filter logic from calendar command
        all_events = event_store.all_events
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

        # Should include today_event and within_7_days
        # Should exclude past_event and beyond_7_days
        expect(upcoming_events.length).to eq(2)
        titles = upcoming_events.map { |e| e['title'] }
        expect(titles).to include('Today Event', 'Next Week Event')
        expect(titles).not_to include('Past Event', 'Far Future Event')
      end
    end

    it 'sorts events by start time' do
      Timecop.freeze(Time.parse('2024-12-20T12:00:00Z')) do
        event1 = {
          'title' => 'Event C',
          'start_time' => '2024-12-25T10:00:00Z',
          'end_time' => '2024-12-25T11:00:00Z'
        }

        event2 = {
          'title' => 'Event A',
          'start_time' => '2024-12-21T10:00:00Z',
          'end_time' => '2024-12-21T11:00:00Z'
        }

        event3 = {
          'title' => 'Event B',
          'start_time' => '2024-12-23T10:00:00Z',
          'end_time' => '2024-12-23T11:00:00Z'
        }

        event_store.create(event1)
        event_store.create(event2)
        event_store.create(event3)

        all_events = event_store.all_events
        now = Time.now.utc
        seven_days_from_now = now + (7 * 24 * 60 * 60)

        upcoming_events = all_events.select do |event|
          event_start = Time.parse(event['start_time']).utc
          event_start >= now && event_start <= seven_days_from_now
        end

        sorted_events = upcoming_events.sort_by { |event| Time.parse(event['start_time']) }

        expect(sorted_events.map { |e| e['title'] }).to eq(['Event A', 'Event B', 'Event C'])
      end
    end

    it 'limits results to 10 events' do
      Timecop.freeze(Time.parse('2024-12-20T12:00:00Z')) do
        # Create 15 events within next 7 days
        15.times do |i|
          event = {
            'title' => "Event #{i + 1}",
            'start_time' => (Time.now.utc + (i * 3600)).iso8601,
            'end_time' => (Time.now.utc + (i * 3600) + 3600).iso8601
          }
          event_store.create(event)
        end

        all_events = event_store.all_events
        now = Time.now.utc
        seven_days_from_now = now + (7 * 24 * 60 * 60)

        upcoming_events = all_events.select do |event|
          event_start = Time.parse(event['start_time']).utc
          event_start >= now && event_start <= seven_days_from_now
        end

        display_events = upcoming_events.take(10)

        expect(display_events.length).to eq(10)
        expect(upcoming_events.length).to be > 10
      end
    end
  end

  describe 'empty calendar scenario' do
    it 'handles no upcoming events gracefully' do
      Timecop.freeze(Time.parse('2024-12-20T12:00:00Z')) do
        # Create only past events
        past_event = {
          'title' => 'Past Event',
          'start_time' => '2024-12-19T10:00:00Z',
          'end_time' => '2024-12-19T11:00:00Z'
        }

        event_store.create(past_event)

        all_events = event_store.all_events
        now = Time.now.utc
        seven_days_from_now = now + (7 * 24 * 60 * 60)

        upcoming_events = all_events.select do |event|
          event_start = Time.parse(event['start_time']).utc
          event_start >= now && event_start <= seven_days_from_now
        end

        expect(upcoming_events).to be_empty
      end
    end
  end

  describe 'event formatting' do
    it 'formats events with proper details' do
      event = {
        'id' => 'test-uuid-123',
        'title' => 'Team Meeting',
        'description' => 'Weekly sync',
        'start_time' => '2024-12-25T10:00:00Z',
        'end_time' => '2024-12-25T11:00:00Z',
        'custom' => true
      }

      formatted = format_event(event, 1)

      expect(formatted).to be_a(String)
      expect(formatted).not_to be_empty
      expect(formatted).to include('Team Meeting')
    end

    it 'includes origin information for imported events' do
      imported_event = {
        'id' => 'test-uuid-456',
        'title' => 'Imported Event',
        'description' => 'From external calendar',
        'start_time' => '2024-12-25T10:00:00Z',
        'end_time' => '2024-12-25T11:00:00Z',
        'custom' => false,
        'imported_from_url' => 'https://example.com/cal.ics'
      }

      formatted = format_event(imported_event, 1)

      expect(formatted).to include('Imported from calendar')
    end
  end
end
