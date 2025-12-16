require 'dotenv'
require 'logger'

Dotenv.load

module Config
  # Telegram Bot Configuration
  TELEGRAM_BOT_TOKEN = ENV.fetch('TELEGRAM_BOT_TOKEN', nil).tap do |token|
    raise 'TELEGRAM_BOT_TOKEN is required' if token.nil? || token.empty?
  end

  # Bot Settings
  BROADCAST_LEAD_TIME = ENV.fetch('BROADCAST_LEAD_TIME', '1440').to_i  # 24 hours in minutes

  # Broadcast Scheduler Configuration
  BROADCAST_ENABLED = ENV.fetch('BROADCAST_ENABLED', 'false')
  BROADCAST_CHECK_INTERVAL = ENV.fetch('BROADCAST_CHECK_INTERVAL', '30').to_i
  BROADCAST_TARGET_GROUPS = ENV.fetch('BROADCAST_TARGET_GROUPS', '')

  # Storage Configuration
  EVENTS_STORAGE_PATH = ENV.fetch('EVENTS_STORAGE_PATH', './events.json')
  
  # Redis Configuration (for Heroku)
  # REDIS_URL is automatically set by Heroku Redis addon
  REDIS_URL = ENV.fetch('REDIS_URL', nil)
  
  # USE_REDIS determines if Redis should be used:
  # 1. If REDIS_URL is set (e.g., by Heroku addon), Redis is used
  # 2. If USE_REDIS=true is explicitly set, Redis is used (requires REDIS_URL)
  # 3. Otherwise, file-based storage is used
  USE_REDIS = !REDIS_URL.nil? || ENV.fetch('USE_REDIS', 'false').downcase == 'true'

  # Logging Configuration
  LOG_LEVEL = ENV.fetch('LOG_LEVEL', 'info').to_sym

  class << self
    def logger
      @logger ||= Logger.new($stdout).tap do |log|
        log.level = Logger.const_get(LOG_LEVEL.upcase)
        log.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} -- : #{msg}\n"
        end
      end
    end

    def events_storage_path
      EVENTS_STORAGE_PATH
    end

    def ensure_storage_directory
      dir = File.dirname(events_storage_path)
      Dir.mkdir(dir) unless Dir.exist?(dir)
    end

    def storage_initialized?
      File.exist?(events_storage_path)
    end

    def initialize_storage
      if USE_REDIS
        logger.info("Using Redis storage")
      else
        logger.info("Using file-based storage: #{events_storage_path}")
        ensure_storage_directory
        unless storage_initialized?
          File.write(events_storage_path, '[]')
        end
      end
    end

    def create_redis_client
      return nil unless USE_REDIS || REDIS_URL
      
      begin
        require 'redis'
        redis_url = REDIS_URL || 'redis://localhost:6379/0'
        logger.info("Connecting to Redis at #{redis_url.gsub(/:[^:@]+@/, ':***@')}")
        Redis.new(url: redis_url)
      rescue LoadError
        logger.error("Redis gem not available. Install it with: gem install redis")
        nil
      rescue => e
        logger.error("Failed to connect to Redis: #{e.message}")
        nil
      end
    end
  end
end
