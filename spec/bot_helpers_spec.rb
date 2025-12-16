require_relative 'test_config'
require_relative '../lib/bot_helpers'
require 'time'

RSpec.describe CalendarBot::BotHelpers do
  include CalendarBot::BotHelpers

  describe '#escape_markdown' do
    it 'escapes special markdown characters' do
      text = "Test_with*special[chars](and)more~`>#+-=|{}.!"
      escaped = escape_markdown(text)
      
      # All special chars should be escaped
      expect(escaped).to include('\\_')
      expect(escaped).to include('\\*')
      expect(escaped).to include('\\[')
      expect(escaped).to include('\\]')
      expect(escaped).to include('\\(')
      expect(escaped).to include('\\)')
    end

    it 'handles nil and empty strings' do
      expect(escape_markdown(nil)).to eq('')
      expect(escape_markdown('')).to eq('')
    end

    it 'handles normal text without special chars' do
      text = "Normal text"
      expect(escape_markdown(text)).to eq("Normal text")
    end
  end

  describe '#format_timestamp' do
    it 'formats ISO timestamp to readable format in UTC' do
      time_str = '2024-12-25T10:30:00Z'
      formatted = format_timestamp(time_str)
      
      expect(formatted).to include('Dec 25, 2024')
      expect(formatted).to include('10:30 AM UTC')
    end

    it 'handles invalid time strings gracefully' do
      invalid = 'not-a-time'
      expect(format_timestamp(invalid)).to eq(invalid)
    end
  end

  describe '#format_time_range' do
    it 'formats time range for same day events' do
      start_time = '2024-12-25T10:00:00Z'
      end_time = '2024-12-25T11:30:00Z'
      
      result = format_time_range(start_time, end_time)
      
      expect(result).to include('Dec 25, 2024')
      expect(result).to include('10:00 AM')
      expect(result).to include('11:30 AM')
    end

    it 'formats time range for multi-day events' do
      start_time = '2024-12-25T10:00:00Z'
      end_time = '2024-12-26T11:30:00Z'
      
      result = format_time_range(start_time, end_time)
      
      expect(result).to include('Dec 25')
      expect(result).to include('Dec 26')
    end

    it 'handles invalid times gracefully' do
      start_time = 'invalid'
      end_time = 'also-invalid'
      
      result = format_time_range(start_time, end_time)
      expect(result).to include(start_time)
      expect(result).to include(end_time)
    end
  end

  describe '#format_event' do
    let(:event) do
      {
        'id' => 'test-uuid-123',
        'title' => 'Team Meeting',
        'description' => 'Weekly sync meeting',
        'start_time' => '2024-12-25T10:00:00Z',
        'end_time' => '2024-12-25T11:00:00Z',
        'custom' => true
      }
    end

    it 'formats event with all details' do
      result = format_event(event, 1)
      
      expect(result).to include('1\\.')  # Escaped number
      expect(result).to include('Team Meeting')
      expect(result).to include('🕒')
      expect(result).to include('🏷️')
      expect(result).to include('Custom event')
    end

    it 'formats imported event' do
      imported_event = event.merge(
        'custom' => false,
        'imported_from_url' => 'https://example.com/calendar.ics'
      )
      result = format_event(imported_event, 1)
      
      expect(result).to include('Imported from calendar')
    end
  end

  describe '#generate_event_id' do
    it 'returns first 8 characters of UUID' do
      event = { 'id' => '12345678-1234-1234-1234-123456789012' }
      short_id = generate_event_id(event)
      
      expect(short_id).to eq('12345678')
      expect(short_id.length).to eq(8)
    end
  end
end
