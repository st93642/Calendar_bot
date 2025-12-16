# Storage Configuration Guide

This document explains how to configure and use different storage backends for the Calendar Bot.

## Overview

The Calendar Bot supports two storage backends:

1. **File-based Storage** - Default for local development
2. **Redis Key-Value Storage** - Recommended for Heroku deployment

The bot automatically selects the appropriate storage backend based on environment configuration.

## Storage Backends

### 1. File-Based Storage (Default)

File-based storage saves events as JSON in a local file. This is perfect for:
- Local development and testing
- Single-instance deployments
- Environments with persistent filesystems

**Configuration:**

```bash
# .env
EVENTS_STORAGE_PATH=./events.json
```

**Characteristics:**
- ✅ Simple and easy to set up
- ✅ No external dependencies
- ✅ Human-readable storage format
- ⚠️ Not suitable for ephemeral filesystems (like Heroku)
- ⚠️ Single-instance only (no horizontal scaling)

### 2. Redis Key-Value Storage (Recommended for Heroku)

Redis storage uses a Redis database to persist events. This is ideal for:
- Heroku deployments (dyno filesystem is ephemeral)
- Cloud environments
- Production deployments requiring persistence

**Configuration:**

```bash
# .env
REDIS_URL=redis://localhost:6379/0
# OR
USE_REDIS=true  # Forces Redis usage with REDIS_URL
```

**Characteristics:**
- ✅ Persistent across dyno restarts
- ✅ Fast key-value access
- ✅ Suitable for cloud deployments
- ✅ Automatic with Heroku Redis addon
- ⚠️ Requires Redis server

## Automatic Storage Selection

The bot automatically selects storage based on this logic:

1. **If `REDIS_URL` is set** → Use Redis storage
2. **If `USE_REDIS=true` and `REDIS_URL` is set** → Use Redis storage
3. **Otherwise** → Use file-based storage at `EVENTS_STORAGE_PATH`

If Redis fails to connect, the bot automatically falls back to file-based storage.

## Heroku Deployment with Redis

### Step 1: Add Heroku Redis

```bash
heroku addons:create heroku-redis:mini -a your-app-name
```

This automatically sets the `REDIS_URL` environment variable.

### Step 2: Verify Configuration

```bash
heroku config -a your-app-name | grep REDIS_URL
```

You should see:
```
REDIS_URL: redis://...
```

### Step 3: Deploy and Check Logs

```bash
git push heroku main
heroku logs --tail -a your-app-name
```

Look for log messages indicating Redis storage:
```
[INFO] Using Redis storage adapter
[INFO] Events storage type: Redis
```

### Heroku Redis Plans

| Plan | Price | Storage | Best For |
|------|-------|---------|----------|
| hobby-dev | Free* | 25 MB | Testing |
| mini | $3/month | 25 MB | Small to medium bots |
| premium-0 | $15/month | 100 MB | Large calendars |

*Free tier has limited availability

## Local Development with Redis

If you want to test Redis locally:

### Using Docker

```bash
# Start Redis
docker run -d -p 6379:6379 redis:7-alpine

# Set environment variable
export REDIS_URL=redis://localhost:6379/0

# Run bot
bundle exec ruby bot.rb
```

### Using Native Redis

```bash
# Install Redis (Ubuntu/Debian)
sudo apt-get install redis-server

# Start Redis
redis-server

# Set environment variable
export REDIS_URL=redis://localhost:6379/0

# Run bot
bundle exec ruby bot.rb
```

## Migrating Between Storage Backends

### From File to Redis

1. Export your events from file storage:
   ```ruby
   require 'json'
   events = JSON.parse(File.read('events.json'))
   ```

2. Set up Redis and configure `REDIS_URL`

3. Import events using bot commands:
   - Use `/add_event` for individual events
   - Use `/import <url>` for ICS calendars

### From Redis to File

1. Use Redis CLI to export data:
   ```bash
   redis-cli GET calendar_bot:events > events_backup.json
   ```

2. Switch to file storage by removing `REDIS_URL`

3. Import the events as needed

## Storage Format

Both backends store events in the same JSON format:

```json
[
  {
    "id": "uuid",
    "title": "Event Title",
    "description": "Event description",
    "start_time": "2023-12-25T10:00:00Z",
    "end_time": "2023-12-25T11:00:00Z",
    "custom": true,
    "imported_from_url": null
  }
]
```

### Redis Key

Events are stored under the key: `calendar_bot:events`

## Troubleshooting

### Redis Connection Issues

If you see errors like "Failed to connect to Redis":

1. Check Redis is running:
   ```bash
   redis-cli ping
   # Should return: PONG
   ```

2. Verify `REDIS_URL` is correct:
   ```bash
   echo $REDIS_URL
   ```

3. Check Redis logs:
   ```bash
   heroku redis:info -a your-app-name
   ```

### Fallback to File Storage

If Redis fails, the bot automatically falls back to file storage. Check logs for:
```
[WARN] Redis not available, falling back to file storage
[INFO] Using file storage adapter: ./events.json
```

### Data Loss on Heroku Without Redis

If you're seeing events disappear after dyno restarts:
- You're using file storage on Heroku's ephemeral filesystem
- Solution: Add Heroku Redis addon (see above)

## Advanced Configuration

### Custom Redis Configuration

You can customize Redis connection parameters:

```ruby
# In config/config.rb, modify create_redis_client method
Redis.new(
  url: redis_url,
  timeout: 5,
  reconnect_attempts: 3,
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
)
```

### Multiple Storage Backends

Currently, the bot uses a single storage backend at a time. To use multiple backends simultaneously, you would need to modify the `EventStore` class to support replication.

## Performance Considerations

### File Storage
- Read/Write: O(n) where n is file size
- Suitable for: < 10,000 events
- Bottleneck: File I/O and JSON parsing

### Redis Storage
- Read/Write: O(1) for single event operations
- Suitable for: Any size (limited by Redis memory)
- Bottleneck: Network latency

## Security

### File Storage
- Ensure proper file permissions (600 or 644)
- Don't commit events.json to version control (add to .gitignore)

### Redis Storage
- Use SSL/TLS for production (Heroku Redis includes this)
- Use strong Redis passwords
- Don't expose Redis port publicly
- Heroku Redis automatically handles security

## Monitoring

### Check Storage Type

Look for this in bot startup logs:
```
[INFO] Events storage type: Redis
# or
[INFO] Events storage type: File (./events.json)
```

### Monitor Redis Usage (Heroku)

```bash
heroku redis:info -a your-app-name
```

Shows:
- Memory usage
- Connected clients
- Keyspace information

## Summary

| Feature | File Storage | Redis Storage |
|---------|-------------|---------------|
| Persistence on Heroku | ❌ | ✅ |
| Setup Complexity | Simple | Moderate |
| External Dependencies | None | Redis Server |
| Cost | Free | $0-15/month |
| Performance | Good for small datasets | Excellent |
| Recommended For | Local dev | Production/Heroku |

For Heroku deployments, **always use Redis storage** to ensure your events persist across dyno restarts and deploys.
