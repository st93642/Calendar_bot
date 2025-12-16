require 'dotenv'
require 'logger'

Dotenv.load

module Config
  # Telegram Bot Configuration
  TELEGRAM_BOT_TOKEN = ENV.fetch('TELEGRAM_BOT_TOKEN', nil).tap do |token|
    raise 'TELEGRAM_BOT_TOKEN is required' if token.nil? || token.empty?
  end

  # Bot Settings
  BROADCAST_LEAD_TIME = ENV.fetch('BROADCAST_LEAD_TIME', '300').to_i

  # Broadcast Scheduler Configuration
  BROADCAST_ENABLED = ENV.fetch('BROADCAST_ENABLED', 'false')
  BROADCAST_CHECK_INTERVAL = ENV.fetch('BROADCAST_CHECK_INTERVAL', '30').to_i
  BROADCAST_TARGET_GROUPS = ENV.fetch('BROADCAST_TARGET_GROUPS', '')

  # Storage Configuration
  EVENTS_STORAGE_PATH = ENV.fetch('EVENTS_STORAGE_PATH', './events.json')

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
      ensure_storage_directory
      unless storage_initialized?
        File.write(events_storage_path, '[]')
      end
    end
  end
end
