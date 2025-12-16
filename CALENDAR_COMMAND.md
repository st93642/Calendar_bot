# Calendar Command Feature

This document describes the `/calendar` command implementation for the Telegram Calendar Bot.

## Overview

The `/calendar` command provides users with a quick view of upcoming events scheduled within the next 7 days. It's designed to show only relevant, future events with proper formatting and pagination support.

## Features

### 1. Time Filtering
- **Future Events Only**: Displays events with start times >= current time
- **7-Day Window**: Shows events happening within the next 7 days from now
- **Smart Sorting**: Events are sorted chronologically by start time

### 2. Pagination and Truncation
- **10 Event Limit**: Displays up to 10 events at once to prevent message overflow
- **Overflow Indicator**: Shows "... and X more events" when more than 10 events exist
- **Clear Messaging**: Informs users when no upcoming events are found

### 3. Event Formatting

Each event is displayed with:
- **Title**: Bold, markdown-formatted event title
- **Time Range**: Formatted start and end times with timezone
- **Description**: Event description (truncated to 150 chars if too long)
- **Origin**: Indicates whether event is custom or imported

Example output:
```
📅 Upcoming Events (next 7 days)

*1. Team Meeting*
🕒 Dec 25, 2024 • 10:00 AM - 11:00 AM UTC
📝 Weekly sync with the team
🏷️  Custom event

*2. Client Call*
🕒 Dec 26, 2024 • 02:00 PM - 03:00 PM UTC
📝 Quarterly business review
🔗 Imported from calendar
```

### 4. Markdown Escaping

All user-provided text (titles, descriptions) is properly escaped for Telegram's MarkdownV2 format to prevent parsing errors. Special characters like `*`, `_`, `[`, `]`, `(`, `)`, `~`, `` ` ``, `>`, `#`, `+`, `-`, `=`, `|`, `{`, `}`, `.`, and `!` are automatically escaped.

### 5. Timezone Support (Future Enhancement)

The helper functions support timezone configuration:
- Currently defaults to UTC
- Infrastructure in place for per-user or per-group timezone preferences
- Can be extended by passing timezone parameter to formatting functions

## Usage

### User Commands

```
/calendar
```

Shows upcoming events for the next 7 days.

### Bot Responses

**With Events:**
```
📅 Upcoming Events (next 7 days)

*1. Daily Standup*
🕒 Dec 16, 2025 • 09:00 AM - 09:30 AM UTC
📝 Team sync meeting
🏷️  Custom event

*2. Product Review*
🕒 Dec 18, 2025 • 02:00 PM - 04:00 PM UTC
📝 Quarterly product roadmap review
🔗 Imported from calendar

... and 3 more events
```

**Without Events:**
```
📅 Upcoming Events

No events scheduled for the next 7 days.

Use /import to add events from an ICS calendar.
```

**Error:**
```
❌ Error retrieving calendar events. Please try again later.
```

## Technical Implementation

### File Structure

```
lib/
├── bot_helpers.rb           # Formatting and utility functions
├── event_store.rb          # Event storage and retrieval
└── ics_importer.rb         # ICS calendar import

bot.rb                      # Main bot with command handlers
```

### Key Functions

#### `handle_calendar(bot, message)`
Main handler for the `/calendar` command:
1. Retrieves all events from EventStore
2. Filters to upcoming events (next 7 days)
3. Sorts by start time
4. Limits to 10 events
5. Formats and sends response

#### `format_event(event, index, timezone = nil)`
Formats a single event for display with proper markdown escaping and all details.

#### `format_time_range(start_time, end_time, timezone = nil)`
Formats event time range, intelligently handling same-day vs multi-day events.

#### `escape_markdown(text)`
Escapes special characters for Telegram MarkdownV2 format.

### Event Filtering Logic

```ruby
now = Time.now.utc
seven_days_from_now = now + (7 * 24 * 60 * 60)

upcoming_events = all_events.select do |event|
  begin
    event_start = Time.parse(event['start_time']).utc
    event_start >= now && event_start <= seven_days_from_now
  rescue ArgumentError
    false
  end
end
```

## Testing

### Unit Tests

Run helper function tests:
```bash
bundle exec rspec spec/bot_helpers_spec.rb
```

### Integration Tests

Run calendar command logic tests:
```bash
bundle exec rspec spec/calendar_command_spec.rb
```

### Manual Testing

Run the test script:
```bash
ruby test_calendar_command.rb
```

### Test Coverage

- ✅ Filtering future events within 7-day window
- ✅ Excluding past events
- ✅ Excluding events beyond 7 days
- ✅ Sorting by start time
- ✅ Pagination (10 event limit)
- ✅ Empty calendar scenario
- ✅ Markdown escaping
- ✅ Event formatting with all details
- ✅ Custom vs imported event display

## Acceptance Criteria

✅ **Time Filtering**: Shows only future events within next 7 days  
✅ **Pagination**: Limits display to 10 events with overflow indicator  
✅ **Formatting**: Events show title, time range, description, and origin  
✅ **Markdown Safety**: All text properly escaped for Telegram  
✅ **Empty State**: Graceful handling when no events exist  
✅ **Error Handling**: Catches and logs errors, shows user-friendly message  
✅ **Help Text**: `/start` and `/help` updated to include `/calendar` command  
✅ **Sorting**: Events displayed chronologically  

## Future Enhancements

1. **Timezone Configuration**: Support per-user or per-group timezone settings
2. **Custom Time Range**: Allow users to specify custom date ranges (e.g., `/calendar 14` for 14 days)
3. **Event Details**: Add command to get full details of a specific event by ID
4. **Inline Buttons**: Add navigation buttons for paging through more than 10 events
5. **Calendar View**: Generate visual calendar grid for the week
6. **Reminders**: Allow users to set reminders for upcoming events
7. **RSVP**: Enable users to mark attendance for events

## Configuration

No additional configuration required. The command works with existing EventStore configuration.

## Dependencies

- `telegram-bot-ruby` - Telegram Bot API
- `time` - Ruby standard library for time parsing
- `logger` - Logging support

## API Reference

### BotHelpers Module

#### `escape_markdown(text) → String`
Escapes special characters for Telegram MarkdownV2.

**Parameters:**
- `text` (String, nil) - Text to escape

**Returns:** Escaped string, or empty string if nil

---

#### `format_timestamp(time_str, timezone = nil) → String`
Formats ISO 8601 timestamp to human-readable format.

**Parameters:**
- `time_str` (String) - ISO 8601 timestamp
- `timezone` (String, optional) - Timezone identifier (e.g., 'America/New_York')

**Returns:** Formatted timestamp string

---

#### `format_time_range(start_time, end_time, timezone = nil) → String`
Formats time range with smart same-day detection.

**Parameters:**
- `start_time` (String) - ISO 8601 start timestamp
- `end_time` (String) - ISO 8601 end timestamp
- `timezone` (String, optional) - Timezone identifier

**Returns:** Formatted time range string

---

#### `format_event(event, index, timezone = nil) → String`
Formats complete event details with markdown.

**Parameters:**
- `event` (Hash) - Event data from EventStore
- `index` (Integer) - Display number (1-based)
- `timezone` (String, optional) - Timezone identifier

**Returns:** Formatted event string with markdown escaping

---

#### `generate_event_id(event) → String`
Generates short, readable event ID from UUID.

**Parameters:**
- `event` (Hash) - Event data with 'id' field

**Returns:** First 8 characters of event UUID

## License

This project maintains the original MIT License.
