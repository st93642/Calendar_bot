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
Storage is selected automatically in [bot.rb](../bot.rb#L48-L66):
1. If `REDIS_URL` set → try Redis, fallback to file on failure
2. Otherwise → use file at `EVENTS_STORAGE_PATH` (default: `./events.json`)

Redis key: `calendar_bot:events` stores JSON array of events.

### State Management Pattern
Multi-step commands use `@user_states` hash with key `"#{chat_id}:#{user_id}"`:
```ruby
@user_states[user_key] = { step: :awaiting_title, data: {} }
```
See [bot.rb](../bot.rb#L25) for initialization and conversation handling at [bot.rb](../bot.rb#L106-L110).

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

Test pattern: Use `Tempfile` for isolated storage in specs (see [spec/event_store_spec.rb](../spec/event_store_spec.rb#L7-L12)).

### Debugging
- Logs go to stdout, format in [config/config.rb](../config/config.rb#L42-L46)
- Set `LOG_LEVEL=debug` for detailed output
- Admin status cached in `@admin_cache` hash with TTL (see [bot.rb](../bot.rb#L28))

## Key Conventions

### Event Schema
Events require: `id`, `title`, `start_time`, `end_time` (ISO8601), `custom` (boolean). Duplicates detected by `title + start_time` match (see [lib/event_store.rb](../lib/event_store.rb#L98-L102)).

### Admin-Only Commands
Admin check via Telegram API `getChatMember` with result caching. Admin commands: `/import`, `/delete_event`, `/broadcast_status`, `/broadcast_check`.

### Markdown Escaping
All user-facing text uses MarkdownV2 requiring escape of `_*[]()~`>#+-=|{}.!` via `escape_markdown` helper (see [lib/bot_helpers.rb](../lib/bot_helpers.rb#L6-L17)). Falls back to plain text on parse errors.

### Thread Safety
`EventStore` uses `Mutex_m` mixin for thread-safe operations. All read/write wrapped in `synchronize` blocks (see [lib/event_store.rb](../lib/event_store.rb#L43)).

### Broadcast Deduplication
`BroadcastScheduler` maintains `@broadcast_metadata` hash with last send times to prevent duplicate reminders for the same event (see [lib/broadcast_scheduler.rb](../lib/broadcast_scheduler.rb#L14-L17)).

## Heroku Deployment

### Critical Files
- **[Procfile](../Procfile)**: Defines `worker` dyno (not web), runs `bot.rb`
- **[runtime.txt](../runtime.txt)**: Specifies Ruby version (currently 3.4.7)

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
1. Add case in [bot.rb](../bot.rb#L112-L147) `handle_message`
2. Check admin status with `is_admin?(bot, message)` if needed
3. Use `bot.api.send_message` with `parse_mode: 'MarkdownV2'` and escaping

### Storage Adapter Implementation
Inherit from `StorageAdapter`, implement: `read_events`, `write_events`, `available?`, `initialize_storage`. See [lib/storage_adapter.rb](../lib/storage_adapter.rb#L6-L16) interface.

### Time Handling
Store as ISO8601 strings, parse with `Time.parse(time_str).utc`. Display with `format_timestamp` helper supporting timezone conversion via TZInfo (see [lib/bot_helpers.rb](../lib/bot_helpers.rb#L23-L43)).
