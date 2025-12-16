# Telegram Calendar Bot

A Telegram bot for managing calendar events with ICS import capabilities, automatic broadcast reminders, and admin features.

## Features

### 🤖 Telegram Bot Commands
- **`/start`** - Welcome message and command overview
- **`/help`** - Detailed help and command descriptions
- **`/calendar`** - Show upcoming events (next 7 days, max 10 entries)
- **`/events`** - List all events in storage
- **`/import <URL>`** - Import ICS calendar from URL (Admin only)
- **`/add_event`** - Add a new custom event (Interactive flow)
- **`/delete_event <ID>`** - Delete an event (Admin only)
- **`/broadcast_status`** - Check scheduler status (Admin only)
- **`/broadcast_check`** - Force broadcast check (Admin only)

### 📡 Broadcast Scheduler
- **Automatic reminders** sent to configured group chats
- **Configurable lead time** - send reminders X hours before events
- **Duplicate prevention** - tracks sent reminders to avoid repeats
- **Persistent metadata** - survives bot restarts
- **Admin commands** for monitoring and manual triggers

### 🗃️ EventStore Class
- **Thread-safe JSON storage** using Mutex synchronization
- **Schema validation** for required fields and time format validation
- **CRUD operations**: Create, Read, Update, Delete events
- **Deduplication** by title + start_time combination
- **Merge logic** for batch operations (update existing, insert new)
- **Atomic file operations** with temporary file writes
- **UUID generation** for unique event IDs
- **Error handling** for malformed JSON and invalid data

### 📥 IcsImporter Class
- **URL import** with HTTP/HTTPS support and configurable timeout
- **File import** for local ICS files
- **ICS parsing** using the icalendar gem
- **Timezone normalization** to UTC ISO8601 format
- **Event validation** and error handling
- **Merge integration** with EventStore for seamless updates
- **Graceful error handling** for network and parsing failures

### 📅 Calendar Command Features
- **Smart filtering** - Shows only future events within next 7 days
- **Pagination** - Displays up to 10 events with overflow indicator
- **Rich formatting** - Title, time range, description, and origin for each event
- **Markdown escaping** - Proper handling of special characters for Telegram
- **Timezone support** - Infrastructure for per-user timezone preferences (defaults to UTC)
- **Empty state** - Graceful handling when no upcoming events exist

## 🚀 Quick Start

### 1. Setup via BotFather

1. **Create a bot with BotFather**:
   - Message [@BotFather](https://t.me/BotFather) on Telegram
   - Send `/newbot` command
   - Follow instructions to get your bot token

2. **Add your bot to groups** (optional):
   - In group settings, add your bot as administrator
   - This allows `/import` and `/delete_event` commands

### 2. Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd telegram-calendar-bot

# Install dependencies
bundle install
```

### 3. Environment Configuration

Create a `.env` file in the project root:

```bash
cp .env.example .env
```

Edit `.env` with your settings:

```bash
# Required: Telegram Bot Token from BotFather
TELEGRAM_BOT_TOKEN=1234567890:ABCdefGHIjklMNOpqrsTUVwxyz

# Storage path (default: ./events.json)
EVENTS_STORAGE_PATH=./data/events.json

# Logging level
LOG_LEVEL=info

# Broadcast Scheduler (optional)
BROADCAST_ENABLED=false
BROADCAST_CHECK_INTERVAL=30
BROADCAST_LEAD_TIME=300
BROADCAST_TARGET_GROUPS=-1001234567890,-1009876543210
```

### 4. Running the Bot

```bash
# Start the bot
bundle exec ruby bot.rb

# Or using rake
rake demo
```

## 📋 Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TELEGRAM_BOT_TOKEN` | ✅ Yes | - | Bot token from BotFather |
| `EVENTS_STORAGE_PATH` | ❌ No | `./events.json` | Path to events storage file |
| `LOG_LEVEL` | ❌ No | `info` | Logging level (debug, info, warn, error) |
| `BROADCAST_ENABLED` | ❌ No | `false` | Enable/disable broadcast scheduler |
| `BROADCAST_CHECK_INTERVAL` | ❌ No | `30` | Minutes between scheduler checks |
| `BROADCAST_LEAD_TIME` | ❌ No | `300` | Minutes before event to send reminder |
| `BROADCAST_TARGET_GROUPS` | ❌ No | - | Comma-separated group chat IDs |

### Finding Group Chat IDs

Group chat IDs are negative numbers (e.g., `-1001234567890`). To find your group ID:

1. Add the bot to your group
2. Send a message to the group mentioning the bot
3. Check logs or use this script:

```ruby
require 'telegram/bot'

Telegram::Bot::Client.run('YOUR_BOT_TOKEN') do |bot|
  bot.listen do |message|
    puts "Chat ID: #{message.chat.id}"
    puts "Chat Type: #{message.chat.type}"
    puts "Chat Title: #{message.chat.title}"
    puts "---"
  end
end
```

## 🗂️ Event Schema

Events are stored in JSON format with the following structure:

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

## 📡 Broadcast Scheduler

### How It Works

The scheduler runs every X minutes (configurable) and:
1. Scans all stored events
2. Checks if any events are due for reminders
3. Sends reminders to configured groups Y minutes before event start
4. Tracks sent reminders to avoid duplicates
5. Persists metadata across bot restarts

### Configuration Examples

**Daily reminders (24 hours before):**
```bash
BROADCAST_ENABLED=true
BROADCAST_LEAD_TIME=1440
BROADCAST_CHECK_INTERVAL=60
BROADCAST_TARGET_GROUPS=-1001234567890
```

**Hourly reminders (2 hours before):**
```bash
BROADCAST_ENABLED=true
BROADCAST_LEAD_TIME=120
BROADCAST_CHECK_INTERVAL=15
BROADCAST_TARGET_GROUPS=-1001234567890,-1009876543210
```

**Meeting reminders (30 minutes before):**
```bash
BROADCAST_ENABLED=true
BROADCAST_LEAD_TIME=30
BROADCAST_CHECK_INTERVAL=5
BROADCAST_TARGET_GROUPS=-1001234567890
```

### Admin Commands

- **`/broadcast_status`** - Check if scheduler is running and view configuration
- **`/broadcast_check`** - Manually trigger a broadcast check

## 📖 Usage Examples

### Adding Events

#### Interactive /add_event
```
User: /add_event
Bot: 📝 Adding new event.
    Please enter the Event Title (or type /cancel to abort):
User: Team Meeting
Bot: 📝 Enter Description (or type 'skip' for none):
User: Weekly sync meeting
Bot: 🕒 Enter Start Time (YYYY-MM-DD HH:MM):
User: 2024-01-15 14:00
Bot: 🕓 Enter End Time (YYYY-MM-DD HH:MM):
User: 2024-01-15 15:00
Bot: ✅ Event *Team Meeting* created successfully!
```

### Importing ICS Calendars

```
Admin: /import https://example.com/company_calendar.ics
Bot: 🔄 Importing calendar from https://example.com/company_calendar.ics...
Bot: ✅ Import completed!
     Events processed: 15
     Created: 8
     Updated: 5
     Errors: 2
     Total events now: 23
```

### Viewing Events

```
User: /calendar
Bot: 📅 Upcoming Events (next 7 days)

1. *Team Meeting*
   🕒 Jan 15, 2024 • 2:00 PM - 3:00 PM UTC
   📝 Weekly sync meeting
   🏷️ Custom event

2. *Project Deadline*
   🕒 Jan 16, 2024 • 11:59 PM - 11:59 PM UTC
   🔗 Imported from calendar
```

### Managing Events

```
Admin: /events
Bot: 📅 Events (5):

1. Team Meeting
   ID: `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
   🕒 2024-01-15 14:00
   🏷️ Custom

2. Project Deadline
   ID: `f1e2d3c4-b5a6-7890-cdef-1234567890ab`
   🕒 2024-01-16 23:59
   🏷️ Imported

Admin: /delete_event a1b2c3d4-e5f6-7890-abcd-ef1234567890
Bot: ✅ Event deleted successfully.
```

## 🖥️ Deployment

### Local Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec spec/

# Start bot
bundle exec ruby bot.rb
```

### VPS Deployment

#### Option 1: Systemd Service

1. **Create service file:**
   ```bash
   sudo nano /etc/systemd/system/calendar-bot.service
   ```

2. **Service configuration:**
   ```ini
   [Unit]
   Description=Telegram Calendar Bot
   After=network.target

   [Service]
   Type=simple
   User=calendar-bot
   WorkingDirectory=/home/calendar-bot
   Environment=BUNDLE_GEMFILE=/home/calendar-bot/Gemfile
   ExecStart=/usr/local/bin/bundle exec ruby bot.rb
   Restart=always
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   ```

3. **Start and enable:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable calendar-bot
   sudo systemctl start calendar-bot
   sudo systemctl status calendar-bot
   ```

#### Option 2: Cron with Monitoring

1. **Create a wrapper script:**
   ```bash
   #!/bin/bash
   cd /home/calendar-bot
   exec bundle exec ruby bot.rb >> bot.log 2>&1
   ```

2. **Cron entry (runs on reboot):**
   ```cron
   @reboot /home/calendar-bot/start-bot.sh
   0 */6 * * * /usr/bin/pkill -f "ruby bot.rb" && /home/calendar-bot/start-bot.sh
   ```

### Environment Setup on VPS

```bash
# Install Ruby and dependencies
sudo apt update
sudo apt install ruby-full ruby-bundler git

# Create user
sudo useradd -m -s /bin/bash calendar-bot
sudo su - calendar-bot

# Setup bot
git clone <your-repo-url>
cd telegram-calendar-bot
bundle install --deployment --without development test

# Configure
cp .env.example .env
nano .env  # Edit with your settings
```

## 💾 Storage & Backup

### Events Storage

Events are stored in `events.json` (or custom path via `EVENTS_STORAGE_PATH`):

```bash
# Backup events
cp events.json events-$(date +%Y%m%d).json

# Restore events
cp events-backup.json events.json

# Check storage size
ls -lh events.json
```

### Broadcast Metadata

Broadcast scheduler creates `broadcast_metadata.json` in the same directory as events:

```json
{
  "a1b2c3d4-e5f6-7890-abcd-ef1234567890": {
    "last_broadcast": 1705123456
  }
}
```

### Data Management

```bash
# View all events (formatted)
cat events.json | jq '.'

# Count events
cat events.json | jq 'length'

# Clear all events
echo '[]' > events.json

# Export specific event
cat events.json | jq '.[] | select(.title == "Team Meeting")'

# Remove old events (before specific date)
cat events.json | jq '.[] | select(.start_time > "2024-01-01T00:00:00Z")' > events_new.json
mv events_new.json events.json
```

### Changing Broadcast Timing

To change when reminders are sent:

1. **Edit .env file:**
   ```bash
   # Send reminders 2 hours before events
   BROADCAST_LEAD_TIME=120
   ```

2. **Restart the bot:**
   ```bash
   sudo systemctl restart calendar-bot
   ```

3. **Or update while running (admin only):**
   - Use `/broadcast_check` to test with current settings
   - Check status with `/broadcast_status`

### Resetting Event Data

```bash
# Option 1: Clear all events (keeps metadata)
echo '[]' > events.json

# Option 2: Full reset (events + metadata)
echo '[]' > events.json
rm -f broadcast_metadata.json

# Option 3: Keep only future events
cat events.json | jq '.[] | select(.start_time > "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'")' > events_new.json
mv events_new.json events.json
```

## 🔧 EventStore & IcsImporter Classes

### EventStore Usage

```ruby
require_relative 'lib/event_store'

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
require_relative 'lib/ics_importer'
require_relative 'lib/event_store'

# Initialize
store = CalendarBot::EventStore.new('./events.json')
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

## 🔒 Thread Safety

The EventStore uses a Mutex to ensure thread-safe operations:
- All CRUD operations are synchronized
- File operations use atomic writes with temporary files
- Concurrent read/write access is properly handled
- Deadlock prevention through consistent lock ordering

## 🛠️ Error Handling

### EventStore Errors
- **ValidationError**: Missing required fields or invalid time format
- **JSON parsing errors**: Gracefully handled with logging
- **File system errors**: Proper error messages and logging

### IcsImporter Errors
- **Network errors**: Timeout handling, DNS resolution failures
- **Parse errors**: Invalid ICS content, malformed events
- **Validation errors**: Events missing required fields

### Broadcast Scheduler Errors
- **Network errors**: Telegram API failures
- **Configuration errors**: Invalid group IDs, malformed settings
- **Data errors**: Corrupted metadata, invalid event data

## 🧪 Testing

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

## 📂 Files Structure

```
/home/engine/project/
├── lib/
│   ├── event_store.rb          # EventStore implementation
│   ├── ics_importer.rb         # IcsImporter implementation
│   ├── bot_helpers.rb          # Formatting and utility methods
│   └── broadcast_scheduler.rb  # Broadcast scheduler implementation
├── spec/
│   ├── event_store_spec.rb     # Unit tests for EventStore
│   └── ics_importer_spec.rb    # Unit tests for IcsImporter
├── config/
│   └── config.rb               # Configuration module
├── bot.rb                      # Main bot implementation
├── demo.rb                     # Basic functionality demo
├── acceptance_test.rb          # Comprehensive acceptance testing
├── Rakefile                    # Task automation
├── Gemfile                     # Ruby dependencies
└── README.md                   # This file
```

## 📦 Dependencies

- **`telegram-bot-ruby`**: Telegram Bot API client
- **`icalendar`**: ICS calendar file parsing
- **`rufus-scheduler`**: Job scheduler for broadcast reminders
- **`mutex_m`**: Mutex synchronization for thread safety
- **`securerandom`**: UUID generation for unique event IDs
- **`dotenv`**: Environment variable management
- **`logger`**: Logging functionality
- **`rspec`**: Testing framework (development)
- **`webmock`**: HTTP request mocking for tests (development)
- **`timecop`**: Time manipulation for tests (development)

## 🆘 Troubleshooting

### Bot Not Responding
1. Check token is correct in `.env`
2. Verify bot is added to groups (for admin commands)
3. Check logs for errors: `journalctl -u calendar-bot`

### Broadcast Not Working
1. Verify `BROADCAST_ENABLED=true` in `.env`
2. Check group chat IDs are correct (negative numbers)
3. Use `/broadcast_status` to check configuration
4. Try `/broadcast_check` for manual trigger

### Import Failing
1. Verify URL is accessible: `curl -I <ICS_URL>`
2. Check bot has internet access
3. Review logs for specific error messages

### Events Not Saving
1. Check write permissions on storage directory
2. Verify JSON format is valid
3. Check disk space: `df -h`

## 📝 License

This project maintains the original MIT License.