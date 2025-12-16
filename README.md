# EventStore & IcsImporter Implementation

This implementation provides a complete EventStore class for reading/writing events.json with thread-safe access, and an IcsImporter service for importing ICS calendar data with deduplication and merge capabilities.

## Features

### EventStore Class
- **Thread-safe JSON storage** using Mutex synchronization
- **Schema validation** for required fields and time format validation
- **CRUD operations**: Create, Read, Update, Delete events
- **Deduplication** by title + start_time combination
- **Merge logic** for batch operations (update existing, insert new)
- **Atomic file operations** with temporary file writes
- **UUID generation** for unique event IDs
- **Error handling** for malformed JSON and invalid data

### IcsImporter Class
- **URL import** with HTTP/HTTPS support and configurable timeout
- **File import** for local ICS files
- **ICS parsing** using the icalendar gem
- **Timezone normalization** to UTC ISO8601 format
- **Event validation** and error handling
- **Merge integration** with EventStore for seamless updates
- **Graceful error handling** for network and parsing failures

## Event Schema

```json
{
  "id": "uuid-string",
  "title": "Event Title",
  "description": "Event description or null",
  "start_time": "2023-12-25T10:00:00Z",
  "end_time": "2023-12-25T11:00:00Z",
  "custom": false,
  "imported_from_url": "http://example.com/calendar.ics"
}
```

## Usage Examples

### EventStore Basic Usage

```ruby
require_relative 'lib/event_store'
require_relative 'lib/ics_importer'

# Initialize EventStore
store = CalendarBot::EventStore.new('./events.json')

# Create events
event = {
  'title' => 'My Event',
  'description' => 'Event description',
  'start_time' => '2023-12-25T10:00:00Z',
  'end_time' => '2023-12-25T11:00:00Z',
  'custom' => true
}

created = store.create(event)
puts "Created: #{created['id']}"

# Find events
found = store.find_by_id(created['id'])
all_events = store.all_events

# Update events
updated = store.update(created['id'], {
  'title' => 'Updated Title',
  'description' => 'Updated description',
  'start_time' => '2023-12-25T10:00:00Z',
  'end_time' => '2023-12-25T11:00:00Z',
  'custom' => true
})

# Delete events
store.delete(created['id'])

# Check for duplicates
duplicates = store.find_duplicates(event)
```

### ICS Import

```ruby
# Initialize importer
importer = CalendarBot::IcsImporter.new(store)

# Import from URL
result = importer.import_from_url('http://example.com/calendar.ics')
if result[:success]
  puts "Imported #{result[:events_processed]} events"
  puts "Created: #{result[:merge_results][:created]}"
  puts "Updated: #{result[:merge_results][:updated]}"
  puts "Errors: #{result[:merge_results][:errors]}"
else
  puts "Import failed: #{result[:error]}"
end

# Import from file
result = importer.import_from_file('./calendar.ics')
```

### Merge Operations

```ruby
# Batch merge multiple events
new_events = [
  {
    'title' => 'Existing Event',  # Will update existing
    'start_time' => '2023-12-25T10:00:00Z',
    'end_time' => '2023-12-25T11:00:00Z',
    'custom' => false
  },
  {
    'title' => 'New Event',  # Will be created
    'start_time' => '2023-12-26T10:00:00Z',
    'end_time' => '2023-12-26T11:00:00Z',
    'custom' => false
  }
]

results = store.merge_events(new_events)
puts "Merge results: #{results}"
```

## Configuration

### Environment Variables
- `EVENTS_STORAGE_PATH`: Path to events.json file (default: './events.json')
- `LOG_LEVEL`: Logging level (default: 'info')

### Example .env file:
```
EVENTS_STORAGE_PATH=./data/events.json
LOG_LEVEL=info
```

## Thread Safety

The EventStore uses a Mutex to ensure thread-safe operations:
- All CRUD operations are synchronized
- File operations use atomic writes with temporary files
- Concurrent read/write access is properly handled
- Deadlock prevention through consistent lock ordering

## Error Handling

### EventStore Errors
- **ValidationError**: Missing required fields or invalid time format
- **JSON parsing errors**: Gracefully handled with logging
- **File system errors**: Proper error messages and logging

### IcsImporter Errors
- **Network errors**: Timeout handling, DNS resolution failures
- **Parse errors**: Invalid ICS content, malformed events
- **Validation errors**: Events missing required fields

## Testing

### Unit Tests
```bash
bundle exec rspec spec/
```

### Acceptance Tests
```bash
ruby acceptance_test.rb
```

### Demo
```bash
ruby demo.rb
```

### Using Rake
```bash
# Run unit tests
rake spec

# Run acceptance tests
rake acceptance

# Run demo
rake demo

# Run all tests
rake test

# Clean up test files
rake clean
```

## Acceptance Criteria ✓

All acceptance criteria have been implemented and tested:

1. **EventStore class** with JSON storage and thread-safe access ✓
2. **Schema validation** with required fields and time format validation ✓
3. **CRUD operations** with proper error handling ✓
4. **Deduplication** by title + start_time ✓
5. **IcsImporter** with URL and file import capabilities ✓
6. **ICS parsing** with timezone normalization ✓
7. **Merge logic** for updating existing and inserting new events ✓
8. **Error handling** for network and parsing failures ✓
9. **Unit tests** covering JSON persistence and duplicate detection ✓
10. **Acceptance tests** demonstrating all functionality ✓

## Files Structure

```
/home/engine/project/
├── lib/
│   ├── event_store.rb      # EventStore implementation
│   └── ics_importer.rb     # IcsImporter implementation
├── spec/
│   ├── event_store_spec.rb # Unit tests for EventStore
│   └── ics_importer_spec.rb # Unit tests for IcsImporter
├── config/
│   └── config.rb           # Configuration module
├── demo.rb                 # Basic functionality demo
├── acceptance_test.rb      # Comprehensive acceptance testing
├── Rakefile               # Task automation
├── Gemfile                # Ruby dependencies
└── README.md              # This file
```

## Dependencies

- `icalendar`: ICS calendar file parsing
- `mutex_m`: Mutex synchronization
- `net/http`: HTTP client for URL imports
- `uri`: URL parsing
- `securerandom`: UUID generation
- `rspec`: Testing framework
- `webmock`: HTTP request mocking for tests

## License

This project maintains the original MIT License.