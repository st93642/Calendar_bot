require 'time'

module CalendarBot
  module BotHelpers
    # Escape special characters for Telegram MarkdownV2
    # Reference: https://core.telegram.org/bots/api#markdownv2-style
    def escape_markdown(text)
      return '' if text.nil? || text.empty?
      
      # Characters that need to be escaped in MarkdownV2
      special_chars = ['_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!']
      
      escaped = text.to_s.dup
      special_chars.each do |char|
        escaped.gsub!(char, "\\#{char}")
      end
      
      escaped
    end

    # Format a timestamp with optional timezone support
    # If timezone is provided and valid, converts to that timezone
    # Otherwise uses UTC
    def format_timestamp(time_str, timezone = nil)
      time = Time.parse(time_str)
      
      # If timezone is provided, try to convert
      if timezone && !timezone.empty?
        begin
          require 'tzinfo'
          tz = TZInfo::Timezone.get(timezone)
          time = tz.to_local(time.utc)
          time.strftime("%b %d, %Y at %I:%M %p %Z")
        rescue TZInfo::InvalidTimezoneIdentifier, LoadError
          # Fall back to UTC if timezone is invalid or tzinfo not available
          time.utc.strftime("%b %d, %Y at %I:%M %p UTC")
        end
      else
        # Default to UTC
        time.utc.strftime("%b %d, %Y at %I:%M %p UTC")
      end
    rescue ArgumentError => e
      # If parsing fails, return the original string
      time_str
    end

    # Format a time range for display
    def format_time_range(start_time, end_time, timezone = nil)
      start = Time.parse(start_time)
      finish = Time.parse(end_time)
      
      if timezone && !timezone.empty?
        begin
          require 'tzinfo'
          tz = TZInfo::Timezone.get(timezone)
          start = tz.to_local(start.utc)
          finish = tz.to_local(finish.utc)
          
          # If same day, show date once
          if start.to_date == finish.to_date
            "#{start.strftime('%b %d, %Y')} • #{start.strftime('%I:%M %p')} - #{finish.strftime('%I:%M %p %Z')}"
          else
            "#{start.strftime('%b %d at %I:%M %p')} - #{finish.strftime('%b %d at %I:%M %p %Z')}"
          end
        rescue TZInfo::InvalidTimezoneIdentifier, LoadError
          # Fall back to UTC
          format_time_range_utc(start, finish)
        end
      else
        format_time_range_utc(start, finish)
      end
    rescue ArgumentError
      "#{start_time} - #{end_time}"
    end

    # Format a single event for display
    def format_event(event, index, timezone = nil)
      lines = []
      
      # Event number and title
      title = escape_markdown(event['title'])
      lines << "*#{index}\\. #{title}*"
      
      # Time range
      time_range = format_time_range(event['start_time'], event['end_time'], timezone)
      lines << "🕒 #{escape_markdown(time_range)}"
      
      # Description (if present)
      if event['description'] && !event['description'].empty?
        desc = event['description'].strip
        # Truncate long descriptions
        desc = desc[0..150] + '...' if desc.length > 150
        lines << "📝 #{escape_markdown(desc)}"
      end
      
      # Origin (custom vs imported)
      if event['custom']
        lines << "🏷️  Custom event"
      elsif event['imported_from_url']
        lines << "🔗 Imported from calendar"
      else
        lines << "🏷️  Event"
      end
      
      lines.join("\n")
    end

    # Generate a short, readable event ID
    # This is different from the UUID - it's for user reference
    def generate_event_id(event)
      # Use first 8 characters of UUID for readability
      event['id'][0..7]
    end

    private

    def format_time_range_utc(start, finish)
      start_utc = start.utc
      finish_utc = finish.utc
      
      # If same day, show date once
      if start_utc.to_date == finish_utc.to_date
        "#{start_utc.strftime('%b %d, %Y')} • #{start_utc.strftime('%I:%M %p')} - #{finish_utc.strftime('%I:%M %p UTC')}"
      else
        "#{start_utc.strftime('%b %d at %I:%M %p')} - #{finish_utc.strftime('%b %d at %I:%M %p UTC')}"
      end
    end
  end
end
