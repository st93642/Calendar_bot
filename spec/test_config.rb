require 'dotenv'
require 'logger'
require 'securerandom'

# Test-specific configuration that doesn't require env vars
module TestConfig
  def self.logger
    @logger ||= Logger.new($stdout).tap do |log|
      log.level = Logger::INFO
      log.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} -- : #{msg}\n"
      end
    end
  end

  def self.events_storage_path
    @events_storage_path || './test_events.json'
  end

  def self.events_storage_path=(path)
    @events_storage_path = path
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