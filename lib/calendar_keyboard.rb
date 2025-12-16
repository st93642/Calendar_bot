require 'date'

module CalendarBot
  class CalendarKeyboard
    def self.generate_month(year, month)
      date = Date.new(year, month, 1)
      days_in_month = Date.new(year, month, -1).day
      start_weekday = date.wday # 0 = Sunday
      
      # Create keyboard
      keyboard = []
      
      # Month/Year header
      keyboard << [{
        text: "#{date.strftime('%B %Y')}",
        callback_data: "ignore"
      }]
      
      # Navigation row
      keyboard << [
        { text: "◀️", callback_data: "prev_month:#{year}:#{month}" },
        { text: "Today", callback_data: "today" },
        { text: "▶️", callback_data: "next_month:#{year}:#{month}" }
      ]
      
      # Weekday headers
      keyboard << [
        { text: "Su", callback_data: "ignore" },
        { text: "Mo", callback_data: "ignore" },
        { text: "Tu", callback_data: "ignore" },
        { text: "We", callback_data: "ignore" },
        { text: "Th", callback_data: "ignore" },
        { text: "Fr", callback_data: "ignore" },
        { text: "Sa", callback_data: "ignore" }
      ]
      
      # Calendar days
      week = []
      
      # Add empty cells for days before month starts
      start_weekday.times { week << { text: " ", callback_data: "ignore" } }
      
      # Add days of month
      (1..days_in_month).each do |day|
        callback = "date:#{year}-#{month.to_s.rjust(2, '0')}-#{day.to_s.rjust(2, '0')}"
        week << { text: day.to_s, callback_data: callback }
        
        if week.length == 7
          keyboard << week
          week = []
        end
      end
      
      # Fill last week if incomplete
      if week.any?
        (7 - week.length).times { week << { text: " ", callback_data: "ignore" } }
        keyboard << week
      end
      
      # Cancel button
      keyboard << [{ text: "❌ Cancel", callback_data: "cancel_date" }]
      
      keyboard
    end
    
    def self.generate_time_selector(selected_date, hour = 9)
      keyboard = []
      
      # Header
      keyboard << [{
        text: "Select Time for #{selected_date}",
        callback_data: "ignore"
      }]
      
      # Hour selector (showing 6 hours at a time)
      hours_row = []
      (hour...[hour + 6, 24].min).each do |h|
        hours_row << {
          text: "#{h.to_s.rjust(2, '0')}:00",
          callback_data: "time:#{selected_date}:#{h}:00"
        }
      end
      keyboard << hours_row if hours_row.any?
      
      # Navigation
      nav = []
      nav << { text: "⬆️ Earlier", callback_data: "time_nav:#{selected_date}:#{[hour - 6, 0].max}" } if hour > 0
      nav << { text: "⬇️ Later", callback_data: "time_nav:#{selected_date}:#{hour + 6}" } if hour < 18
      keyboard << nav if nav.any?
      
      # Common times
      keyboard << [
        { text: "09:00 🌅", callback_data: "time:#{selected_date}:9:00" },
        { text: "12:00 🕛", callback_data: "time:#{selected_date}:12:00" },
        { text: "18:00 🌆", callback_data: "time:#{selected_date}:18:00" }
      ]
      
      # Back and Cancel
      keyboard << [
        { text: "⬅️ Back to Calendar", callback_data: "back_to_calendar" },
        { text: "❌ Cancel", callback_data: "cancel_date" }
      ]
      
      keyboard
    end
  end
end
