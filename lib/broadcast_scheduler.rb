require 'rufus-scheduler'
require 'time'
require_relative 'event_store'
require_relative 'bot_helpers'

module CalendarBot
  class BroadcastScheduler
    include BotHelpers

    def initialize(event_store, logger = nil)
      @event_store = event_store
      @scheduler = Rufus::Scheduler.new
      @logger = logger || create_default_logger
      @broadcast_metadata = {}
      @metadata_mutex = Mutex.new
      
      # Load existing broadcast metadata
      load_broadcast_metadata
      
      # Setup configuration
      setup_configuration
    end

    def start
      return unless @config[:enabled]
      
      @logger.info("Starting Broadcast Scheduler...")
      @logger.info("  Check interval: #{@config[:check_interval]} minutes")
      @logger.info("  Lead time: #{@config[:lead_time]} minutes (#{@config[:lead_time] / 60} hours)")
      @logger.info("  Target groups: #{@config[:target_groups].join(', ')}")
      
      # Schedule the periodic check
      @scheduler.every "#{@config[:check_interval]}m" do
        check_and_broadcast_events
      end
      
      # Run initial check after a short delay
      @scheduler.in '30s' do
        check_and_broadcast_events
      end
      
      @logger.info("✓ Broadcast scheduler started successfully")
      true
    rescue StandardError => e
      @logger.error("Failed to start broadcast scheduler: #{e.message}")
      @logger.debug(e.backtrace.join("\n"))
      false
    end

    def stop
      @scheduler.shutdown if @scheduler
      @logger.info("✓ Broadcast scheduler stopped")
    end

    def check_and_broadcast_events
      @logger.debug("Running scheduled broadcast check...")
      
      begin
        events = @event_store.all_events
        now = Time.now.utc
        
        events.each do |event|
          process_event_for_broadcast(event, now)
        end
        
        # Save metadata periodically
        save_broadcast_metadata if rand < 0.1 # 10% chance to save
        
      rescue StandardError => e
        @logger.error("Error during broadcast check: #{e.message}")
        @logger.debug(e.backtrace.join("\n"))
      end
    end

    def process_event_for_broadcast(event, now)
      event_id = event['id']
      event_start = parse_time(event['start_time'])
      return unless event_start
      
      # Skip if event has already passed
      return if event_start <= now
      
      # Calculate when to send reminder
      reminder_time = event_start - (@config[:lead_time] * 60)
      
      # Check if it's time to send reminder
      if now >= reminder_time
        # Check if we haven't sent this reminder yet
        last_broadcast = get_last_broadcast_time(event_id)
        
        if last_broadcast.nil? || (reminder_time > last_broadcast)
          send_broadcast_reminder(event, reminder_time)
          set_last_broadcast_time(event_id, now)
        end
      end
    end

    def send_broadcast_reminder(event, reminder_time)
      return unless @config[:enabled] && @config[:target_groups].any?
      
      @logger.info("Sending broadcast reminder for event: #{event['title']}")
      
      message = build_broadcast_message(event, reminder_time)
      
      # Send to all configured groups
      @config[:target_groups].each do |chat_id|
        begin
          broadcast_to_chat(chat_id, message)
          @logger.debug("Sent reminder to chat #{chat_id}")
        rescue StandardError => e
          @logger.error("Failed to send reminder to chat #{chat_id}: #{e.message}")
        end
      end
    end

    def build_broadcast_message(event, reminder_time)
      start_time = format_timestamp(event['start_time'])
      end_time = format_timestamp(event['end_time'])
      
      lines = ["🔔 Event Reminder"]
      lines << ""
      lines << "*#{escape_markdown(event['title'])}*"
      lines << ""
      lines << "🕒 #{start_time}"
      lines << "   to #{end_time}"
      lines << ""
      lines << "⏰ Reminder sent #{format_time_ago(reminder_time)}"
      
      lines.join("\n")
    end

    def broadcast_to_chat(chat_id, message)
      return unless @bot_client
      
      @bot_client.api.send_message(
        chat_id: chat_id,
        text: message,
        parse_mode: 'Markdown'
      )
    end

    def set_bot_client(bot_client)
      @bot_client = bot_client
    end

    # Manual trigger for testing
    def force_check
      check_and_broadcast_events
    end

    # Get scheduler status
    def status
      {
        enabled: @config[:enabled],
        check_interval: @config[:check_interval],
        lead_time: @config[:lead_time],
        target_groups: @config[:target_groups],
        next_run: @scheduler&.jobs&.first&.next_time,
        metadata_count: @broadcast_metadata.size
      }
    end

    private

    def create_default_logger
      Logger.new($stdout).tap do |log|
        log.level = Logger::INFO
        log.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity.ljust(5)} -- : #{msg}\n"
        end
      end
    end

    def setup_configuration
      @config = {
        enabled: ENV.fetch('BROADCAST_ENABLED', 'false').downcase == 'true',
        check_interval: ENV.fetch('BROADCAST_CHECK_INTERVAL', '30').to_i,
        lead_time: ENV.fetch('BROADCAST_LEAD_TIME', '300').to_i, # minutes
        target_groups: parse_target_groups
      }
      
      # Validate configuration
      if @config[:enabled]
        unless @config[:target_groups].any?
          @logger.warn("Broadcast enabled but no target groups configured")
          @config[:enabled] = false
        end
        
        if @config[:check_interval] < 5
          @logger.warn("Check interval too low, setting to 5 minutes")
          @config[:check_interval] = 5
        end
        
        if @config[:lead_time] < 1
          @logger.warn("Lead time too low, setting to 1 minute")
          @config[:lead_time] = 1
        end
      end
    end

    def parse_target_groups
      groups = ENV.fetch('BROADCAST_TARGET_GROUPS', '').strip
      return [] if groups.empty?
      
      groups.split(',').map(&:strip).select do |group_id|
        !group_id.empty?
      end
    end

    def parse_time(time_str)
      Time.parse(time_str) rescue nil
    end

    def format_time_ago(time)
      now = Time.now.utc
      diff = now - time
      
      if diff < 60
        "#{diff.to_i} seconds ago"
      elsif diff < 3600
        "#{(diff / 60).to_i} minutes ago"
      else
        "#{(diff / 3600).to_i} hours ago"
      end
    end

    # Broadcast metadata persistence
    def load_broadcast_metadata
      metadata_path = get_metadata_path
      
      begin
        if File.exist?(metadata_path)
          content = File.read(metadata_path)
          @broadcast_metadata = JSON.parse(content) || {}
          @logger.debug("Loaded #{@broadcast_metadata.size} broadcast metadata entries")
        end
      rescue StandardError => e
        @logger.error("Failed to load broadcast metadata: #{e.message}")
        @broadcast_metadata = {}
      end
    end

    def save_broadcast_metadata
      metadata_path = get_metadata_path
      
      @metadata_mutex.synchronize do
        begin
          temp_path = "#{metadata_path}.tmp"
          File.write(temp_path, JSON.pretty_generate(@broadcast_metadata))
          File.rename(temp_path, metadata_path)
          @logger.debug("Saved broadcast metadata")
        rescue StandardError => e
          @logger.error("Failed to save broadcast metadata: #{e.message}")
        end
      end
    end

    def get_last_broadcast_time(event_id)
      @metadata_mutex.synchronize do
        @broadcast_metadata[event_id]&.dig('last_broadcast')
      end
    end

    def set_last_broadcast_time(event_id, time)
      @metadata_mutex.synchronize do
        @broadcast_metadata[event_id] ||= {}
        @broadcast_metadata[event_id]['last_broadcast'] = time.to_i
      end
    end

    def get_metadata_path
      event_store_path = @event_store.instance_variable_get(:@storage_path)
      base_path = File.dirname(event_store_path)
      File.join(base_path, 'broadcast_metadata.json')
    end
  end
end