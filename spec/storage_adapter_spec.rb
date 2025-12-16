require_relative '../lib/storage_adapter'
require 'tempfile'
require 'logger'
require 'securerandom'
require 'fileutils'

RSpec.describe CalendarBot::StorageAdapter do
  let(:logger) { Logger.new(nil) }

  describe CalendarBot::FileStorageAdapter do
    let(:temp_file) { Tempfile.new(['events', '.json']) }
    let(:adapter) { CalendarBot::FileStorageAdapter.new(temp_file.path, logger) }

    after do
      temp_file.close
      temp_file.unlink
    end

    describe '#initialize' do
      it 'initializes storage file with empty array' do
        # Use a new path that doesn't exist yet
        temp_path = File.join(Dir.tmpdir, "test_events_#{SecureRandom.hex(8)}.json")
        adapter = CalendarBot::FileStorageAdapter.new(temp_path, logger)
        
        expect(File.exist?(temp_path)).to be true
        content = File.read(temp_path)
        expect(content).to eq('[]')
        
        File.delete(temp_path) if File.exist?(temp_path)
      end

      it 'creates parent directory if it does not exist' do
        temp_dir = Dir.mktmpdir
        nested_path = File.join(temp_dir, 'subdir', 'events.json')
        
        adapter = CalendarBot::FileStorageAdapter.new(nested_path, logger)
        
        expect(File.exist?(nested_path)).to be true
        FileUtils.remove_entry(temp_dir)
      end
    end

    describe '#available?' do
      it 'returns true' do
        expect(adapter.available?).to be true
      end
    end

    describe '#read_events' do
      it 'returns empty array for new storage' do
        expect(adapter.read_events).to eq([])
      end

      it 'returns stored events' do
        events = [
          { 'id' => '1', 'title' => 'Event 1' },
          { 'id' => '2', 'title' => 'Event 2' }
        ]
        adapter.write_events(events)
        
        expect(adapter.read_events).to eq(events)
      end

      it 'handles empty file' do
        File.write(temp_file.path, '')
        expect(adapter.read_events).to eq([])
      end

      it 'handles whitespace-only file' do
        File.write(temp_file.path, "  \n  \t  ")
        expect(adapter.read_events).to eq([])
      end

      it 'handles invalid JSON' do
        File.write(temp_file.path, 'invalid json')
        expect(adapter.read_events).to eq([])
      end

      it 'handles missing file' do
        # Create adapter first, then delete the file
        File.delete(temp_file.path) if File.exist?(temp_file.path)
        expect(adapter.read_events).to eq([])
      end
    end

    describe '#write_events' do
      it 'writes events to file' do
        events = [{ 'id' => '1', 'title' => 'Test Event' }]
        adapter.write_events(events)
        
        content = File.read(temp_file.path)
        parsed = JSON.parse(content)
        expect(parsed).to eq(events)
      end

      it 'uses atomic write (temp file then rename)' do
        events = [{ 'id' => '1', 'title' => 'Test' }]
        
        # This should not raise an error even if read concurrently
        expect { adapter.write_events(events) }.not_to raise_error
      end
    end
  end

  describe CalendarBot::RedisStorageAdapter do
    let(:redis_mock) { double('Redis') }
    let(:adapter) { CalendarBot::RedisStorageAdapter.new(redis_mock, logger) }

    describe '#available?' do
      it 'returns true when Redis responds to ping' do
        allow(redis_mock).to receive(:ping).and_return('PONG')
        expect(adapter.available?).to be true
      end

      it 'returns false when Redis fails to ping' do
        allow(redis_mock).to receive(:ping).and_raise(StandardError.new('Connection refused'))
        expect(adapter.available?).to be false
      end
    end

    describe '#read_events' do
      it 'returns empty array when key does not exist' do
        allow(redis_mock).to receive(:get).and_return(nil)
        expect(adapter.read_events).to eq([])
      end

      it 'returns stored events' do
        events = [{ 'id' => '1', 'title' => 'Event 1' }]
        allow(redis_mock).to receive(:get).and_return(JSON.generate(events))
        
        expect(adapter.read_events).to eq(events)
      end

      it 'handles invalid JSON' do
        allow(redis_mock).to receive(:get).and_return('invalid json')
        expect(adapter.read_events).to eq([])
      end

      it 'handles Redis errors' do
        allow(redis_mock).to receive(:get).and_raise(StandardError.new('Connection error'))
        expect(adapter.read_events).to eq([])
      end
    end

    describe '#write_events' do
      it 'stores events as JSON' do
        events = [{ 'id' => '1', 'title' => 'Test Event' }]
        expect(redis_mock).to receive(:set).with('calendar_bot:events', JSON.generate(events))
        
        adapter.write_events(events)
      end

      it 'raises error on Redis failure' do
        events = [{ 'id' => '1', 'title' => 'Test' }]
        allow(redis_mock).to receive(:set).and_raise(StandardError.new('Connection error'))
        
        expect { adapter.write_events(events) }.to raise_error(StandardError)
      end
    end
  end
end
