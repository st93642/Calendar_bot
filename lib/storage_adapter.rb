require 'json'
require 'mutex_m'
require 'securerandom'

module CalendarBot
  # Base interface for storage adapters
  class StorageAdapter
    def read_events
      raise NotImplementedError, "#{self.class} must implement #read_events"
    end

    def write_events(events)
      raise NotImplementedError, "#{self.class} must implement #write_events"
    end

    def available?
      raise NotImplementedError, "#{self.class} must implement #available?"
    end

    # Hook for initialization tasks (e.g., ensuring storage exists)
    # Override in subclasses if needed
    def initialize_storage
      # Default: no-op
    end
  end

  # File-based storage adapter (default for local development)
  class FileStorageAdapter < StorageAdapter
    def initialize(storage_path, logger)
      @storage_path = storage_path
      @logger = logger
      initialize_storage
    end

    def read_events
      begin
        content = File.read(@storage_path)
        return [] if content.nil? || content.strip.empty?
        JSON.parse(content)
      rescue JSON::ParserError => e
        @logger.error("Invalid JSON in events storage: #{e.message}")
        []
      rescue Errno::ENOENT
        []
      end
    end

    def write_events(events)
      begin
        temp_path = "#{@storage_path}.tmp"
        File.write(temp_path, JSON.pretty_generate(events))
        File.rename(temp_path, @storage_path)
      rescue => e
        @logger.error("Failed to write events: #{e.message}")
        raise
      end
    end

    def available?
      true # File storage is always available
    end

    def initialize_storage
      dir = File.dirname(@storage_path)
      Dir.mkdir(dir) unless Dir.exist?(dir)
      unless File.exist?(@storage_path)
        File.write(@storage_path, '[]')
      end
    end

    private
  end

  # Redis-based storage adapter (for Heroku deployment)
  class RedisStorageAdapter < StorageAdapter
    REDIS_KEY = 'calendar_bot:events'

    def initialize(redis_client, logger)
      @redis = redis_client
      @logger = logger
    end

    def read_events
      begin
        data = @redis.get(REDIS_KEY)
        return [] if data.nil?
        JSON.parse(data)
      rescue JSON::ParserError => e
        @logger.error("Invalid JSON in Redis storage: #{e.message}")
        []
      rescue => e
        @logger.error("Failed to read from Redis: #{e.message}")
        []
      end
    end

    def write_events(events)
      begin
        @redis.set(REDIS_KEY, JSON.generate(events))
      rescue => e
        @logger.error("Failed to write to Redis: #{e.message}")
        raise
      end
    end

    def available?
      begin
        @redis.ping == 'PONG'
      rescue => e
        @logger.error("Redis not available: #{e.message}")
        false
      end
    end
  end
end
