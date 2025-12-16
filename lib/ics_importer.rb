require 'net/http'
require 'uri'
require 'icalendar'
require_relative 'event_store'

module CalendarBot
  class IcsImporter
    def initialize(event_store = nil, timeout = 30)
      @event_store = event_store || EventStore.new
      @timeout = timeout
      @logger = Config.logger
    end

    def import_from_url(url)
      raise ArgumentError, "URL is required" if url.nil? || url.strip.empty?
      
      @logger.info("Starting ICS import from: #{url}")
      
      begin
        # Fetch ICS content
        ics_content = fetch_ics_content(url.strip)
        
        # Parse ICS content
        events = parse_ics_content(ics_content, url)
        
        if events.empty?
          @logger.warn("No events found in ICS content from: #{url}")
          return { success: false, message: "No events found", events_processed: 0, source_url: url }
        end
        
        # Merge events into store
        results = @event_store.merge_events(events)
        
        @logger.info("ICS import completed: #{results[:created]} created, #{results[:updated]} updated, #{results[:duplicates]} duplicates, #{results[:errors]} errors")
        
        {
          success: true,
          events_processed: events.length,
          merge_results: results,
          source_url: url
        }
        
      rescue StandardError => e
        @logger.error("Failed to import ICS from #{url}: #{e.message}")
        @logger.debug(e.backtrace.join("\n"))
        {
          success: false,
          error: e.message,
          source_url: url
        }
      end
    end

    def import_from_file(file_path)
      raise ArgumentError, "File path is required" if file_path.nil? || file_path.strip.empty?
      
      @logger.info("Starting ICS import from file: #{file_path}")
      
      begin
        ics_content = File.read(file_path)
        events = parse_ics_content(ics_content, "file://#{file_path}")
        
        if events.empty?
          @logger.warn("No events found in ICS file: #{file_path}")
          return { success: false, message: "No events found", events_processed: 0 }
        end
        
        results = @event_store.merge_events(events)
        
        @logger.info("ICS file import completed: #{results[:created]} created, #{results[:updated]} updated, #{results[:duplicates]} duplicates, #{results[:errors]} errors")
        
        {
          success: true,
          events_processed: events.length,
          merge_results: results,
          source_file: file_path
        }
        
      rescue StandardError => e
        @logger.error("Failed to import ICS file #{file_path}: #{e.message}")
        {
          success: false,
          error: e.message,
          source_file: file_path
        }
      end
    end

    private

    def fetch_ics_content(url)
      uri = URI.parse(url)
      
      # Validate URL scheme
      unless ['http', 'https'].include?(uri.scheme)
        raise ArgumentError, "URL must use HTTP or HTTPS scheme"
      end
      
      @logger.debug("Fetching ICS content from: #{url}")
      
      response = Net::HTTP.start(uri.host, uri.port, 
                                use_ssl: uri.scheme == 'https',
                                read_timeout: @timeout,
                                open_timeout: @timeout) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        request['User-Agent'] = 'CalendarBot/1.0 (ICS Importer)'
        http.request(request)
      end
      
      unless response.is_a?(Net::HTTPSuccess)
        raise StandardError, "HTTP #{response.code}: #{response.message}"
      end
      
      response.body
    rescue Net::OpenTimeout
      raise StandardError, "Connection timeout after #{@timeout} seconds"
    rescue Net::ReadTimeout
      raise StandardError, "Read timeout after #{@timeout} seconds"
    rescue SocketError => e
      raise StandardError, "DNS resolution failed: #{e.message}"
    rescue StandardError => e
      raise StandardError, "Failed to fetch ICS content: #{e.message}"
    end

    def parse_ics_content(ics_content, source_url)
      events = []
      
      begin
        # Parse the ICS content
        calendars = Icalendar::Calendar.parse(ics_content)
        
        if calendars.empty?
          @logger.warn("No calendars found in ICS content")
          return events
        end
        
        calendars.each do |calendar|
          calendar.events.each do |ical_event|
            begin
              normalized_event = normalize_ical_event(ical_event, source_url)
              events << normalized_event if normalized_event
            rescue => e
              @logger.warn("Failed to normalize event: #{e.message}")
            end
          end
        end
        
        @logger.debug("Parsed #{events.length} events from ICS content")
        events
        
      rescue => e
        raise StandardError, "Failed to parse ICS content: #{e.message}"
      end
    end

    def normalize_ical_event(ical_event, source_url)
      # Extract basic properties
      title = ical_event.summary.to_s.strip
      
      # Skip events without required fields
      if title.empty?
        @logger.debug("Skipping event without title")
        return nil
      end
      
      # Parse and normalize timezones
      start_time = parse_ical_time(ical_event.dtstart)
      end_time = parse_ical_time(ical_event.dtend)
      
      # If no end time, assume 1 hour duration
      if end_time.nil?
        end_time = start_time + 3600 if start_time
      end
      
      # Validate times
      if start_time.nil? || end_time.nil?
        @logger.debug("Skipping event with invalid times: #{title}")
        return nil
      end
      
      # Build normalized event structure
      {
        'title' => title,
        'start_time' => start_time.utc.iso8601,
        'end_time' => end_time.utc.iso8601,
        'custom' => false,
        'imported_from_url' => source_url
      }
      
    rescue => e
      @logger.debug("Failed to normalize event #{ical_event.summary}: #{e.message}")
      nil
    end

    def parse_ical_time(time_obj)
      return nil if time_obj.nil?
      
      begin
        # Handle different time types from icalendar gem
        case time_obj
        when Icalendar::Values::Date, Icalendar::Values::DateTime
          time_obj.iso8601 ? Time.parse(time_obj.iso8601) : nil
        when Time, DateTime
          time_obj.to_time
        when Date
          time_obj.to_time
        else
          # Try to parse as string
          Time.parse(time_obj.to_s) rescue nil
        end
      rescue => e
        @logger.debug("Failed to parse time #{time_obj}: #{e.message}")
        nil
      end
    end
  end
end