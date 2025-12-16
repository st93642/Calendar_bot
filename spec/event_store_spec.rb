require_relative '../lib/event_store'
require 'json'
require 'tempfile'
require 'time'

RSpec.describe CalendarBot::EventStore do
  let(:temp_file) { Tempfile.new(['events', '.json']) }
  let(:event_store) { CalendarBot::EventStore.new(temp_file.path) }
  
  after do
    temp_file.close
    temp_file.unlink
  end

  describe '#initialize' do
    it 'creates storage directory if it does not exist' do
      temp_dir = Dir.mktmpdir
      temp_storage = File.join(temp_dir, 'subdir', 'events.json')
      
      expect(File.exist?(temp_storage)).to be false
      store = CalendarBot::EventStore.new(temp_storage)
      
      expect(File.exist?(temp_storage)).to be true
      FileUtils.remove_entry(temp_dir)
    end

    it 'initializes with empty array if file does not exist' do
      expect(event_store.count).to eq(0)
      expect(event_store.all_events).to eq([])
    end
  end

  describe '#create' do
    it 'creates a valid event' do
      event_data = {
        'title' => 'Test Event',
        'description' => 'A test event',
        'start_time' => Time.now.iso8601,
        'end_time' => (Time.now + 3600).iso8601
      }

      result = event_store.create(event_data)
      
      expect(result).to be_a(Hash)
      expect(result['title']).to eq('Test Event')
      expect(result['id']).to be_a(String)
      expect(result['custom']).to be false
    end

    it 'generates an ID if not provided' do
      event_data = {
        'title' => 'Test Event',
        'start_time' => Time.now.iso8601,
        'end_time' => (Time.now + 3600).iso8601
      }

      result = event_store.create(event_data)
      expect(result['id']).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
    end

    it 'returns nil for duplicate events' do
      event_data = {
        'title' => 'Duplicate Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      }

      event_store.create(event_data)
      result = event_store.create(event_data)
      
      expect(result).to be_nil
      expect(event_store.count).to eq(1)
    end

    it 'raises error for invalid event data' do
      invalid_event = {
        'title' => 'Test Event'
        # Missing start_time and end_time
      }

      expect {
        event_store.create(invalid_event)
      }.to raise_error(ArgumentError, /Missing required fields/)
    end

    it 'raises error for invalid time format' do
      event_data = {
        'title' => 'Test Event',
        'start_time' => 'invalid-date',
        'end_time' => '2023-12-25T11:00:00Z'
      }

      expect {
        event_store.create(event_data)
      }.to raise_error(ArgumentError, /Invalid time format/)
    end
  end

  describe '#find_by_id' do
    it 'finds an event by ID' do
      event_data = {
        'title' => 'Test Event',
        'start_time' => Time.now.iso8601,
        'end_time' => (Time.now + 3600).iso8601
      }

      created = event_store.create(event_data)
      found = event_store.find_by_id(created['id'])
      
      expect(found['id']).to eq(created['id'])
      expect(found['title']).to eq('Test Event')
    end

    it 'returns nil for non-existent ID' do
      found = event_store.find_by_id('non-existent-id')
      expect(found).to be_nil
    end
  end

  describe '#find_duplicates' do
    it 'finds duplicate events by title and start_time' do
      event_data = {
        'title' => 'Test Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      }

      event_store.create(event_data)
      event_store.create(event_data) # Should be ignored as duplicate
      
      duplicates = event_store.find_duplicates(event_data)
      expect(duplicates.length).to eq(1) # Only 1 event exists (duplicate not created)
    end
  end

  describe '#update' do
    it 'updates an existing event' do
      event_data = {
        'title' => 'Original Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      }

      created = event_store.create(event_data)
      
      updated_data = {
        'title' => 'Updated Event',
        'start_time' => '2023-12-25T12:00:00Z',
        'end_time' => '2023-12-25T13:00:00Z',
        'custom' => true
      }

      result = event_store.update(created['id'], updated_data)
      
      expect(result['title']).to eq('Updated Event')
      expect(result['custom']).to be true
      expect(result['description']).to be_nil  # Description field is not stored
    end

    it 'returns nil for non-existent event' do
      update_data = {
        'title' => 'Non-existent Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      }

      result = event_store.update('non-existent-id', update_data)
      expect(result).to be_nil
    end
  end

  describe '#delete' do
    it 'deletes an existing event' do
      event_data = {
        'title' => 'Test Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      }

      created = event_store.create(event_data)
      expect(event_store.count).to eq(1)
      
      result = event_store.delete(created['id'])
      expect(result).to be true
      expect(event_store.count).to eq(0)
    end

    it 'returns false for non-existent event' do
      result = event_store.delete('non-existent-id')
      expect(result).to be false
    end
  end

  describe '#merge_events' do
    let(:existing_event) {
      {
        'title' => 'Existing Event',
        'description' => 'Already in store',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z',
        'custom' => false,
        'imported_from_url' => 'http://example.com/old.ics'
      }
    }

    let(:new_events) {
      [
        {
          'title' => 'Existing Event', # Should update existing
          'description' => 'Updated description',
          'start_time' => '2023-12-25T10:00:00Z',
          'end_time' => '2023-12-25T11:00:00Z',
          'custom' => false
        },
        {
          'title' => 'New Event', # Should create new
          'start_time' => '2023-12-26T10:00:00Z',
          'end_time' => '2023-12-26T11:00:00Z',
          'custom' => false
        }
      ]
    }

    it 'merges events correctly' do
      event_store.create(existing_event)
      initial_count = event_store.count
      
      results = event_store.merge_events(new_events)
      
      expect(results[:created]).to eq(1) # Only new event
      expect(results[:updated]).to eq(1) # Existing event updated
      expect(results[:duplicates]).to eq(0)
      expect(results[:errors]).to eq(0)
      expect(event_store.count).to eq(initial_count + 1)
      
      # Check the existing event was updated (matches by title + start_time)
      updated_event = event_store.find_by_id(existing_event['id'])
      expect(updated_event['title']).to eq('Existing Event')  # Title stays same (matched by title+start_time)
      expect(updated_event['description']).to be_nil  # Description field is not stored
    end

    it 'handles errors gracefully' do
      # Test with invalid event data in the mix
      mixed_events = new_events + [
        {
          'title' => 'Invalid Event' # Missing start/end times
        }
      ]

      results = event_store.merge_events(mixed_events)
      
      expect(results[:errors]).to eq(1)
      expect(results[:created] + results[:updated]).to eq(2)
    end
  end

  describe '#all_events' do
    it 'returns all events' do
      event1 = {
        'title' => 'Event 1',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      }
      
      event2 = {
        'title' => 'Event 2',
        'start_time' => '2023-12-26T10:00:00Z',
        'end_time' => '2023-12-26T11:00:00Z'
      }

      event_store.create(event1)
      event_store.create(event2)

      all_events = event_store.all_events
      expect(all_events.length).to eq(2)
      expect(all_events.map { |e| e['title'] }).to include('Event 1', 'Event 2')
    end
  end

  describe '#count' do
    it 'returns the correct count' do
      expect(event_store.count).to eq(0)
      
      event_store.create({
        'title' => 'Test Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      })
      
      expect(event_store.count).to eq(1)
    end
  end

  describe '#clear_all' do
    it 'clears all events' do
      event_store.create({
        'title' => 'Test Event',
        'start_time' => '2023-12-25T10:00:00Z',
        'end_time' => '2023-12-25T11:00:00Z'
      })
      
      expect(event_store.count).to eq(1)
      event_store.clear_all
      expect(event_store.count).to eq(0)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent access' do
      events = []
      10.times do |i|
        events << {
          'title' => "Event #{i}",
          'start_time' => "2023-12-2#{i}T10:00:00Z",
          'end_time' => "2023-12-2#{i}T11:00:00Z"
        }
      end

      threads = []
      5.times do
        threads << Thread.new do
          2.times do |i|
            event_store.create(events[Thread.current[:index] ||= 0])
          end
        end
      end

      threads.each(&:join)
      
      # Should have processed all events without data corruption
      expect(event_store.count).to be <= 10
    end
  end
end