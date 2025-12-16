require_relative '../lib/event_store'
require_relative '../lib/ics_importer'
require 'webmock/rspec'
require 'time'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.describe CalendarBot::IcsImporter do
  let(:event_store) { CalendarBot::EventStore.new }
  let(:importer) { CalendarBot::IcsImporter.new(event_store) }
  
  describe '#initialize' do
    it 'initializes with default timeout' do
      importer = CalendarBot::IcsImporter.new
      expect(importer.instance_variable_get(:@timeout)).to eq(30)
    end

    it 'initializes with custom timeout' do
      importer = CalendarBot::IcsImporter.new(nil, 60)
      expect(importer.instance_variable_get(:@timeout)).to eq(60)
    end

    it 'uses provided event store' do
      custom_store = double('EventStore')
      importer = CalendarBot::IcsImporter.new(custom_store)
      expect(importer.instance_variable_get(:@event_store)).to eq(custom_store)
    end
  end

  describe '#import_from_url' do
    let(:valid_ics_content) do
      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:test1@example.com
        DTSTART:20231225T100000Z
        DTEND:20231225T110000Z
        SUMMARY:Christmas Event
        DESCRIPTION:Christmas celebration
        END:VEVENT
        BEGIN:VEVENT
        UID:test2@example.com
        DTSTART:20231226T140000Z
        DTEND:20231226T150000Z
        SUMMARY:New Year's Event
        END:VEVENT
        END:VCALENDAR
      ICS
    end

    let(:invalid_ics_content) do
      "This is not valid ICS content"
    end

    it 'raises error for empty URL' do
      expect {
        importer.import_from_url('')
      }.to raise_error(ArgumentError, /URL is required/)
    end

    it 'raises error for nil URL' do
      expect {
        importer.import_from_url(nil)
      }.to raise_error(ArgumentError, /URL is required/)
    end

    it 'raises error for invalid URL scheme' do
      result = importer.import_from_url('ftp://example.com/calendar.ics')
      expect(result[:success]).to be false
      expect(result[:error]).to match(/HTTP or HTTPS scheme/)
    end

    it 'handles HTTP request errors' do
      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 404, body: 'Not Found')

      result = importer.import_from_url('http://example.com/calendar.ics')
      expect(result[:success]).to be false
      expect(result[:error]).to match(/HTTP 404/)
    end

    it 'handles connection timeout' do
      stub_request(:get, 'http://example.com/calendar.ics')
        .to_timeout

      result = importer.import_from_url('http://example.com/calendar.ics')
      expect(result[:success]).to be false
      expect(result[:error]).to match(/timeout/i)
    end

    it 'successfully imports valid ICS content' do
      # Clear any existing events from previous tests
      event_store.clear_all
      
      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: valid_ics_content)

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be true
      expect(result[:events_processed]).to eq(2)
      expect(result[:merge_results][:created]).to eq(2)
      expect(result[:merge_results][:updated]).to eq(0)
      expect(result[:source_url]).to eq('http://example.com/calendar.ics')
      
      # Check that events were actually stored
      stored_events = event_store.all_events
      expect(stored_events.length).to eq(2)
      
      christmas_event = stored_events.find { |e| e['title'] == 'Christmas Event' }
      expect(christmas_event).not_to be_nil
      expect(christmas_event['imported_from_url']).to eq('http://example.com/calendar.ics')
      expect(christmas_event['custom']).to be false
    end

    it 'handles invalid ICS content' do
      # Clear any existing events from previous tests
      event_store.clear_all
      
      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: invalid_ics_content)

      result = importer.import_from_url('http://example.com/calendar.ics')

      # Icalendar gem is lenient - it parses but finds no calendars/events
      expect(result[:success]).to be false
      expect(result[:message]).to eq('No events found')
    end

    it 'handles empty ICS content' do
      # Clear any existing events from previous tests
      event_store.clear_all
      
      empty_ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        END:VCALENDAR
      ICS
      
      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: empty_ics)

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be false
      expect(result[:message]).to eq('No events found')
      expect(event_store.count).to eq(0)
    end

    it 'skips events without titles' do
      # Clear any existing events from previous tests
      event_store.clear_all
      
      ics_without_titles = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:test1@example.com
        DTSTART:20231225T100000Z
        DTEND:20231225T110000Z
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: ics_without_titles)

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be false
      expect(result[:message]).to eq('No events found')
      expect(event_store.count).to eq(0)
    end

    it 'normalizes timezone information' do
      timezone_ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:test@example.com
        DTSTART;TZID=America/New_York:20231225T100000
        DTEND;TZID=America/New_York:20231225T110000
        SUMMARY:Timezone Event
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: timezone_ics)

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be true
      expect(result[:events_processed]).to eq(1)
      
      stored_event = event_store.all_events.first
      expect(stored_event['start_time']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      expect(stored_event['end_time']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
    end

    it 'handles events without end times' do
      ics_without_end = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:test@example.com
        DTSTART:20231225T100000Z
        SUMMARY:Event without end time
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: ics_without_end)

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be true
      expect(result[:events_processed]).to eq(1)
      
      stored_event = event_store.all_events.first
      # Should set end time to start_time + 1 hour
      expect(stored_event['end_time']).not_to be_nil
      expect(stored_event['end_time']).not_to eq(stored_event['start_time'])
    end
  end

  describe '#import_from_file' do
    let(:temp_file) { Tempfile.new(['test', '.ics']) }
    let(:valid_ics_content) do
      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:filetest@example.com
        DTSTART:20231225T100000Z
        DTEND:20231225T110000Z
        SUMMARY:File Test Event
        DESCRIPTION:Testing file import
        END:VEVENT
        END:VCALENDAR
      ICS
    end

    before do
      temp_file.write(valid_ics_content)
      temp_file.flush
    end

    after do
      temp_file.close
      temp_file.unlink
    end

    it 'raises error for empty file path' do
      expect {
        importer.import_from_file('')
      }.to raise_error(ArgumentError, /File path is required/)
    end

    it 'successfully imports from file' do
      # Clear any existing events from previous tests
      event_store.clear_all
      
      result = importer.import_from_file(temp_file.path)

      expect(result[:success]).to be true
      expect(result[:events_processed]).to eq(1)
      expect(result[:source_file]).to eq(temp_file.path)
      
      stored_events = event_store.all_events
      expect(stored_events.length).to eq(1)
      expect(stored_events.first['title']).to eq('File Test Event')
    end

    it 'handles non-existent file' do
      result = importer.import_from_file('/non/existent/file.ics')
      expect(result[:success]).to be false
      expect(result[:error]).to match(/No such file or directory/)
    end
  end

  describe 'merge functionality' do
    let(:existing_event) {
      {
        'title' => 'Existing Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z',
        'custom' => true,
        'imported_from_url' => 'http://old.com/old.ics'
      }
    }

    let(:import_ics) do
      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:existing@example.com
        DTSTART:20231225T100000Z
        DTEND:20231225T110000Z
        SUMMARY:Existing Event
        DESCRIPTION:Updated description
        END:VEVENT
        BEGIN:VEVENT
        UID:new@example.com
        DTSTART:20231226T100000Z
        DTEND:20231226T110000Z
        SUMMARY:New Event
        END:VEVENT
        END:VCALENDAR
      ICS
    end

    it 'updates existing events and creates new ones' do
      event_store.create(existing_event)
      initial_count = event_store.count
      
      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: import_ics)

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be true
      expect(result[:merge_results][:created]).to eq(1) # New event
      expect(result[:merge_results][:updated]).to eq(1) # Updated existing
      expect(event_store.count).to eq(initial_count + 1)
      
      # Check that the existing event was updated
      updated_event = event_store.find_by_id(existing_event['id'])
      expect(updated_event['description']).to eq('Updated description')
      expect(updated_event['imported_from_url']).to eq('http://example.com/calendar.ics')
    end

    it 'avoids creating duplicates' do
      # Clear any existing events from previous tests
      event_store.clear_all
      
      duplicate_event = {
        'title' => 'Duplicate Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      }
      
      # First create the event
      event_store.create(duplicate_event)
      
      # Then try to import the same event
      duplicate_ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:duplicate@example.com
        DTSTART:20231225T100000Z
        DTEND:20231225T110000Z
        SUMMARY:Duplicate Event
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: duplicate_ics)

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be true
      expect(result[:merge_results][:created]).to eq(0) # No new events
      expect(result[:merge_results][:updated]).to eq(1) # Event updated with import info
      expect(event_store.count).to eq(1) # Still only one event
    end
  end

  describe 'error handling' do
    it 'gracefully handles malformed events' do
      # Clear any existing events from previous tests
      event_store.clear_all
      
      malformed_ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        UID:good@example.com
        DTSTART:20231225T100000Z
        DTEND:20231225T110000Z
        SUMMARY:Good Event
        END:VEVENT
        BEGIN:VEVENT
        UID:bad@example.com
        DTSTART:invalid
        DTEND:20231225T110000Z
        SUMMARY:Bad Event
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:get, 'http://example.com/calendar.ics')
        .to_return(status: 200, body: malformed_ics)

      result = importer.import_from_url('http://example.com/calendar.ics')

      # Malformed events cause parse errors
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Failed to parse ICS content/i)
    end

    it 'handles network connectivity issues' do
      stub_request(:get, 'http://example.com/calendar.ics')
        .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

      result = importer.import_from_url('http://example.com/calendar.ics')

      expect(result[:success]).to be false
      expect(result[:error]).to match(/DNS resolution failed/)
    end
  end
end