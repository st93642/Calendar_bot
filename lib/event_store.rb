require 'json'
require 'mutex_m'
require 'securerandom'
require 'logger'
require_relative 'storage_adapter'

# Config that works for both tests and production
module CalendarBot
  module Config
    def self.logger
      @logger ||= Logger.new($stdout).tap do |log|
        log.level = Logger::INFO
        log.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} -- : #{msg}\n"
        end
      end
    end

    def self.events_storage_path
      ENV['EVENTS_STORAGE_PATH'] || './events.json'
    end

    def self.ensure_storage_directory
      dir = File.dirname(events_storage_path)
      Dir.mkdir(dir) unless Dir.exist?(dir)
    end

    def self.storage_initialized?
      File.exist?(events_storage_path)
    end

    def self.initialize_storage
      ensure_storage_directory
      unless storage_initialized?
        File.write(events_storage_path, '[]')
      end
    end
  end
end

module CalendarBot
  class EventStore
    include Mutex_m
    
    EVENT_SCHEMA = {
      'type' => 'object',
      'properties' => {
        'id' => { 'type' => 'string' },
        'title' => { 'type' => 'string' },
        'description' => { 'type' => ['string', 'null'] },
        'start_time' => { 'type' => 'string', 'format' => 'date-time' },
        'end_time' => { 'type' => 'string', 'format' => 'date-time' },
        'custom' => { 'type' => 'boolean' },
        'imported_from_url' => { 'type' => ['string', 'null'] }
      },
      'required' => ['id', 'title', 'start_time', 'end_time', 'custom']
    }

    def initialize(storage_path = nil, storage_adapter = nil)
      @storage_path = storage_path || Config.events_storage_path
      @mutex = Mutex.new
      @logger = Config.logger
      
      # Use provided adapter or create default file adapter
      @storage_adapter = storage_adapter || FileStorageAdapter.new(@storage_path, @logger)
    end

    def all_events
      synchronize do
        read_events
      end
    end

    def find_by_id(id)
      synchronize do
        events = read_events
        events.find { |event| event['id'] == id }
      end
    end

    def find_duplicates(event_data)
      synchronize do
        events = read_events
        title = event_data['title']
        start_time = event_data['start_time']
        
        events.select do |event|
          event['title'] == title && event['start_time'] == start_time
        end
      end
    end

    def create(event_data)
      validate_event!(event_data)
      
      synchronize do
        events = read_events
        
        # Check for duplicates by title + start_time
        duplicates = events.select do |event|
          event['title'] == event_data['title'] && event['start_time'] == event_data['start_time']
        end
        
        if duplicates.any?
          @logger.debug("Found #{duplicates.size} duplicate(s) for event: #{event_data['title']}")
          return nil # Don't create duplicates
        end
        
        # Generate ID if not provided
        event_data['id'] ||= generate_id
        
        # Set defaults
        event_data['custom'] = event_data.fetch('custom', false)
        event_data['imported_from_url'] = event_data.fetch('imported_from_url', nil)
        event_data['description'] = event_data.fetch('description', nil)
        
        events << event_data
        write_events(events)
        
        @logger.info("Created event: #{event_data['title']}")
        event_data
      end
    end

    def update(id, event_data)
      synchronize do
        events = read_events
        index = events.find_index { |event| event['id'] == id }
        
        if index.nil?
          @logger.warn("Event not found for update: #{id}")
          return nil
        end
        
        validate_event!(event_data)
        
        # Preserve the ID
        event_data['id'] = id
        events[index] = event_data.merge(
          'imported_from_url' => event_data.fetch('imported_from_url', events[index]['imported_from_url']),
          'custom' => event_data.fetch('custom', events[index]['custom'])
        )
        
        write_events(events)
        @logger.info("Updated event: #{event_data['title']}")
        event_data
      end
    end

    def delete(id)
      synchronize do
        events = read_events
        initial_count = events.length
        events.reject! { |event| event['id'] == id }
        
        if events.length < initial_count
          write_events(events)
          @logger.info("Deleted event: #{id}")
          true
        else
          @logger.warn("Event not found for deletion: #{id}")
          false
        end
      end
    end

    def merge_events(new_events)
      results = { created: 0, updated: 0, duplicates: 0, errors: 0 }
      
      synchronize do
        existing_events = read_events
        new_events.each do |new_event|
          begin
            # Validate the new event
            validate_event!(new_event)
            
            # Check for existing events with same title + start_time
            existing_index = existing_events.find_index do |existing|
              existing['title'] == new_event['title'] && existing['start_time'] == new_event['start_time']
            end
            
            if existing_index
              # Update existing event
              new_event['id'] = existing_events[existing_index]['id']
              new_event['imported_from_url'] = new_event.fetch('imported_from_url', 
                                                              existing_events[existing_index]['imported_from_url'])
              new_event['custom'] = new_event.fetch('custom', existing_events[existing_index]['custom'])
              existing_events[existing_index] = new_event
              results[:updated] += 1
            else
              # Create new event
              new_event['id'] ||= generate_id
              existing_events << new_event
              results[:created] += 1
            end
            
          rescue => e
            @logger.error("Failed to merge event #{new_event['title']}: #{e.message}")
            results[:errors] += 1
          end
        end
        
        write_events(existing_events)
      end
      
      results
    end

    def clear_all
      synchronize do
        write_events([])
        @logger.info("Cleared all events")
      end
    end

    def count
      synchronize do
        read_events.length
      end
    end

    private

    def synchronize(&block)
      @mutex.synchronize(&block)
    end

    def read_events
      @storage_adapter.read_events
    end

    def write_events(events)
      @storage_adapter.write_events(events)
    end

    def generate_id
      SecureRandom.uuid
    end

    def validate_event!(event_data)
      required_fields = ['title', 'start_time', 'end_time']
      missing_fields = required_fields.select { |field| event_data[field].nil? || event_data[field].to_s.empty? }
      
      unless missing_fields.empty?
        raise ArgumentError, "Missing required fields: #{missing_fields.join(', ')}"
      end

      # Validate time format (basic ISO 8601 check)
      [event_data['start_time'], event_data['end_time']].each do |time_str|
        begin
          Time.parse(time_str)
        rescue ArgumentError
          raise ArgumentError, "Invalid time format: #{time_str}"
        end
      end
    end
  end
end