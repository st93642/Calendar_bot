# Copilot Instructions for Calendar Bot

## Project Overview
A Ruby Telegram bot for managing calendar events with ICS import, Redis/file storage, and automatic broadcast reminders. Main entry point: [bot.rb](../bot.rb). Designed for Heroku deployment with ephemeral filesystem support.

## Architecture

### Core Components
- **[bot.rb](../bot.rb)**: Main bot class with Telegram webhook handling, command routing, and stateful conversation management (`@user_states` hash tracks multi-step interactions)
- **[lib/event_store.rb](../lib/event_store.rb)**: Thread-safe event CRUD with mutex synchronization, delegates to storage adapters
- **[lib/storage_adapter.rb](../lib/storage_adapter.rb)**: Pluggable storage with `FileStorageAdapter` (JSON) and `RedisStorageAdapter` (key-value)
- **[lib/broadcast_scheduler.rb](../lib/broadcast_scheduler.rb)**: Rufus-scheduler for timed reminders, maintains `@broadcast_metadata` to prevent duplicate sends
- **[lib/bot_helpers.rb](../lib/bot_helpers.rb)**: Telegram MarkdownV2 escaping and time formatting utilities
- **[lib/calendar_keyboard.rb](../lib/calendar_keyboard.rb)**: Interactive inline calendar/time picker keyboards for date/time selection
- **[config/config.rb](../config/config.rb)**: Environment-based config with automatic Redis detection via `REDIS_URL`

### Storage Selection Logic
Storage is selected automatically in [bot.rb](../bot.rb):
1. If `REDIS_URL` set → try Redis, fallback to file on failure
2. Otherwise → use file at `EVENTS_STORAGE_PATH` (default: `./events.json`)

Redis key: `calendar_bot:events` stores JSON array of events.

### State Management Pattern
Multi-step commands use `@user_states` hash with key `"#{chat_id}:#{user_id}"`:
```ruby
@user_states[user_key] = { step: :awaiting_title, data: {} }
```
See [bot.rb](../bot.rb) for initialization and conversation handling.

### Interactive Calendar Keyboard
The bot uses inline keyboards for date/time selection in `/add_event`:
- Month view with navigation (prev/next month, today button)
- Time selector with hour slots and quick time buttons
- Callback queries handle user selections (see `handle_callback_query` in [bot.rb](../bot.rb))
- Manual input fallback available via "Enter Manually" button
- Date format validation prevents time-only inputs (requires YYYY-MM-DD HH:MM)

## Development Workflow

### Local Setup
```bash
bundle install
cp .env.example .env  # Add TELEGRAM_BOT_TOKEN
bundle exec ruby bot.rb
```

### Testing
```bash
rake spec              # RSpec unit tests
rake acceptance        # Integration test with fake Telegram client
rake test              # All tests
rake clean             # Remove temp test files
```

Test patterns:
- **Storage isolation**: Use `Tempfile` for isolated storage in specs (see [spec/event_store_spec.rb](../spec/event_store_spec.rb))
- **Time mocking**: Use `Timecop` gem to freeze/travel time for broadcast scheduler and event timing tests
- **HTTP mocking**: Use `WebMock` to stub ICS URL fetches in [spec/ics_importer_spec.rb](../spec/ics_importer_spec.rb)
- **Test config**: [spec/test_config.rb](../spec/test_config.rb) provides test-specific configuration

### Debugging
- Logs go to stdout, format in [config/config.rb](../config/config.rb)
- Set `LOG_LEVEL=debug` for detailed output
- Admin status cached in `@admin_cache` hash with TTL (see [bot.rb](../bot.rb))

## Key Conventions

### Event Schema
Events require: `id`, `title`, `start_time`, `end_time` (ISO8601), `custom` (boolean). Duplicates detected by `title + start_time` match (see [lib/event_store.rb](../lib/event_store.rb)).

### Admin-Only Commands
Admin check via Telegram API `getChatMember` with result caching. Admin commands: `/import`, `/delete_event`, `/broadcast_status`, `/broadcast_check`.

### Markdown Escaping
All user-facing text uses MarkdownV2 requiring escape of: `_` `*` `[` `]` `(` `)` `~` `` ` `` `>` `#` `+` `-` `=` `|` `{` `}` `.` `!`

Use `escape_markdown` helper (see [lib/bot_helpers.rb](../lib/bot_helpers.rb)). Falls back to plain text on parse errors.

### Error Handling & Fallbacks
- **Storage adapter fallback**: If Redis unavailable, automatically falls back to file storage (see [bot.rb](../bot.rb))
- **Markdown parse errors**: Use plain text fallback when MarkdownV2 parsing fails in `escape_markdown` (see [lib/bot_helpers.rb](../lib/bot_helpers.rb))
- **ICS import HTTP errors**: Comprehensive error handling for network timeouts, DNS failures, and HTTP errors (see [lib/ics_importer.rb](../lib/ics_importer.rb))
- **Telegram API failures**: Message deletion and broadcast operations catch exceptions and log warnings instead of crashing (see [bot.rb](../bot.rb))
- **Event validation**: Duplicate detection by title+start_time prevents duplicate event creation (see [lib/event_store.rb](../lib/event_store.rb))

### Thread Safety
`EventStore` uses `Mutex_m` mixin for thread-safe operations. All read/write wrapped in `synchronize` blocks (see [lib/event_store.rb](../lib/event_store.rb)).

### Broadcast Deduplication
`BroadcastScheduler` maintains `@broadcast_metadata` hash with last send times to prevent duplicate reminders for the same event (see [lib/broadcast_scheduler.rb](../lib/broadcast_scheduler.rb)).

## Message Privacy & Cleanup

### Private Message Deletion
Sensitive command messages are deleted for privacy:
- `/add_event` and `/import` user messages are deleted to hide event details
- Callback query responses don't create visible feedback (use `answer_callback_query` with no alert)
- Calendar and list messages are scheduled for auto-deletion after 3 minutes via `schedule_message_deletion` (see [bot.rb](../bot.rb))

### Conversation Flow for /add_event
1. User sends `/add_event` → message deleted, state set to `:title`, bot asks for title
2. User enters title → message deleted, state changes to `:awaiting_start_time`, calendar keyboard shown
3. Callback: date selected → show time selector with hour slots (starting at 9 AM)
4. Callback: time selected → convert to ISO8601 UTC, state changes to `:awaiting_end_time`
5. Callback: end time selected → validate `end_time > start_time`, create event, delete state
6. Fallback: User can click "Enter Manually" to input datetime as string (format: `YYYY-MM-DD HH:MM`)

## Heroku Deployment

### Critical Files
- **[Procfile](../Procfile)**: Defines `worker` dyno (not web), runs `bot.rb`
- **[runtime.txt](../runtime.txt)**: Specifies Ruby version (currently 3.4.6)

### Environment Config
Required: `TELEGRAM_BOT_TOKEN`
Storage: `REDIS_URL` (auto-set by Heroku Redis addon) or `EVENTS_STORAGE_PATH`
Broadcasts: `BROADCAST_ENABLED=true`, `BROADCAST_TARGET_GROUPS=-1001234567890`

### Storage Recommendation
Use Heroku Redis addon (`heroku addons:create heroku-redis:mini`) for persistence across dyno restarts. Without Redis, events stored in `/tmp/` are ephemeral.

## External Dependencies
- **telegram-bot-ruby**: Webhook handling and API calls
- **icalendar**: ICS parsing in [lib/ics_importer.rb](../lib/ics_importer.rb)
- **rufus-scheduler**: Cron-like scheduling for broadcasts
- **redis**: Optional, for Heroku storage
- **dotenv**: Local env loading (production uses Heroku config vars)

## Common Patterns

### Adding New Commands
1. Add case in [bot.rb](../bot.rb) `handle_message`
2. Check admin status with `is_admin?(bot, message)` if needed
3. Use `bot.api.send_message` with `parse_mode: 'MarkdownV2'` and escaping

### Storage Adapter Implementation
Inherit from `StorageAdapter`, implement: `read_events`, `write_events`, `available?`, `initialize_storage`. See [lib/storage_adapter.rb](../lib/storage_adapter.rb) interface.

### Time Handling
Store as ISO8601 strings, parse with `Time.parse(time_str).utc`. Display with `format_timestamp` helper supporting timezone conversion via TZInfo (see [lib/bot_helpers.rb](../lib/bot_helpers.rb)).
