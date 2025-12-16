# Telegram Calendar Bot

A Telegram bot for managing calendar events with ICS import, automatic reminders, and admin features.

## Features

- 📅 View upcoming events and import ICS calendars
- 🔔 Automatic broadcast reminders before events
- 👥 Works in private chats and groups
- 🔒 Admin-only commands for event management

## Bot Commands

- `/start` - Welcome message
- `/help` - Show available commands
- `/calendar` - Show upcoming events (next 7 days)
- `/events` - List all events
- `/import <URL>` - Import ICS calendar (Admin)
- `/add_event` - Add custom event (Interactive)
- `/delete_event <ID>` - Delete event (Admin)
- `/broadcast_status` - Check reminder scheduler (Admin)

## Quick Start

### 1. Create Bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot` and follow instructions
3. Save your bot token

### 2. Local Setup

```bash
git clone https://github.com/st93642/Calendar_bot.git
cd Calendar_bot
bundle install
cp .env.example .env
# Edit .env with your bot token
bundle exec ruby bot.rb
```

### 3. Required Environment Variables

```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
```

### 4. Optional Configuration

```bash
EVENTS_STORAGE_PATH=./events.json
LOG_LEVEL=info
BROADCAST_ENABLED=false
BROADCAST_CHECK_INTERVAL=30
BROADCAST_LEAD_TIME=300
BROADCAST_TARGET_GROUPS=-1001234567890
```

## Heroku Deployment

### Prerequisites

- [Heroku CLI](https://devcenter.heroku.com/articles/heroku-cli) installed
- Heroku account
- Git repository

### Deployment Steps

1. **Create Heroku app:**
   ```bash
   heroku create your-calendar-bot
   ```

2. **Set environment variables:**
   ```bash
   heroku config:set TELEGRAM_BOT_TOKEN=your_bot_token_here
   heroku config:set EVENTS_STORAGE_PATH=/tmp/events.json
   heroku config:set LOG_LEVEL=info
   ```

3. **Optional - Enable broadcast reminders:**
   ```bash
   heroku config:set BROADCAST_ENABLED=true
   heroku config:set BROADCAST_CHECK_INTERVAL=30
   heroku config:set BROADCAST_LEAD_TIME=300
   heroku config:set BROADCAST_TARGET_GROUPS=-1001234567890
   ```

4. **Deploy to Heroku:**
   ```bash
   git push heroku main
   ```

5. **Scale worker dyno:**
   ```bash
   heroku ps:scale worker=1
   ```

6. **View logs:**
   ```bash
   heroku logs --tail
   ```

### Important Notes

- The bot runs as a **worker** dyno (not web), so it doesn't need a port
- Events are stored in `/tmp/events.json` on Heroku (temporary - resets on dyno restart)
- For persistent storage, consider using [Heroku Postgres](https://elements.heroku.com/addons/heroku-postgresql) or [AWS S3](https://elements.heroku.com/addons/bucketeer) addons
- The `Procfile` and `runtime.txt` files are already configured

### Finding Group Chat IDs

To get your Telegram group chat ID:

1. Add your bot to the group
2. Send a message mentioning the bot
3. Check Heroku logs: `heroku logs --tail`
4. Look for the chat ID in the log output (negative number like `-1001234567890`)

### Troubleshooting

- **Bot not responding:** Check logs with `heroku logs --tail`
- **Worker not running:** Verify with `heroku ps` and scale with `heroku ps:scale worker=1`
- **Events not persisting:** Use database addon for permanent storage

## Testing

```bash
# Run tests
bundle exec rspec spec/

# Run acceptance tests
ruby acceptance_test.rb
```

## Project Structure

```
Calendar_bot/
├── bot.rb                      # Main bot file
├── lib/
│   ├── event_store.rb         # Event storage and management
│   ├── ics_importer.rb        # ICS calendar import
│   ├── bot_helpers.rb         # Formatting helpers
│   └── broadcast_scheduler.rb # Reminder scheduler
├── spec/                       # RSpec tests
├── config/
│   └── config.rb              # Configuration
├── Gemfile                     # Ruby dependencies
├── Procfile                    # Heroku worker configuration
├── runtime.txt                 # Ruby version for Heroku
└── .env.example               # Environment variable template
```

## License

MIT License
