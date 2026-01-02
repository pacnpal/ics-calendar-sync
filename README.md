# ICS Calendar Sync

A robust, enterprise-quality Swift command-line tool that synchronizes events from ICS calendar subscriptions to your macOS Calendar via EventKit, with full support for delta and incremental updates.

## Features

- **Zero Authentication Hassle**: Uses native macOS calendar permissions with no app-specific passwords or OAuth required
- **Automatic iCloud Sync**: Events sync to all your Apple devices via iCloud
- **Smart Delta Sync**: Only creates, updates, or deletes events that have changed
- **Full ICS Support**: Handles recurring events, timezones, alarms, and all standard iCalendar properties
- **Background Sync**: Run as a daemon or install as a launchd service
- **Interactive Setup**: User-friendly setup wizard guides you through configuration
- **Non-Interactive Mode**: Scriptable setup for automation and CI/CD pipelines
- **Robust State Tracking**: SQLite-based state ensures reliable sync across runs
- **Secure Credential Storage**: Optional macOS Keychain integration for sensitive data
- **Flexible Output**: Text or JSON output formats for scripting and monitoring

## Requirements

- macOS 13.0 (Ventura) or later

## Installation

### Pre-built Binary (Recommended)

Download the latest release from the [Releases page](https://github.com/pacnpal/ics-calendar-sync/releases).

#### Which binary should I download?

| Your Mac | Download | How to check |
|----------|----------|--------------|
| Apple Silicon | `arm64` | Apple menu > About This Mac shows "Chip: Apple M1/M2/M3/M4" |
| Intel | `x86_64` | Apple menu > About This Mac shows "Processor: Intel" |
| **Not sure** | `universal` | Works on all Macs |

#### Installation steps

1. Download the appropriate `.zip` file from the [Releases page](https://github.com/pacnpal/ics-calendar-sync/releases)

2. Open Terminal and run the following commands (assuming downloaded to ~/Downloads):

```bash
# Extract the zip (replace ARCH with arm64, x86_64, or universal)
cd ~/Downloads
unzip ics-calendar-sync-ARCH-v1.0.0.zip

# Remove quarantine attribute
xattr -d com.apple.quarantine ics-calendar-sync-*

# Install to /usr/local/bin
sudo mv ics-calendar-sync-* /usr/local/bin/ics-calendar-sync

# Verify installation
ics-calendar-sync --version
```

#### macOS Security Warning

macOS quarantines files downloaded from the internet. The `xattr` command above removes this. If you skip that step, you have two alternatives:

**Option 1: Right-click to open (macOS 14 and earlier)**

1. Right-click (or Control-click) the binary in Finder
2. Select **Open** from the context menu
3. Click **Open** in the dialog

Note: This method does not work on macOS 15 or later.

**Option 2: Allow via System Settings**

If you see "cannot be opened because it is from an unidentified developer":

1. Open **System Settings** then **Privacy & Security**
2. Scroll down to find the blocked app message
3. Click **Allow Anyway**
4. Run the command again and click **Open** when prompted

### From Source

Requires Xcode 15.0+ and Swift 5.9+.

```bash
# Clone the repository
git clone https://github.com/pacnpal/ics-calendar-sync.git
cd ics-calendar-sync

# Build the release binary
swift build -c release

# Install to your local bin (optional)
cp .build/release/ics-calendar-sync ~/.local/bin/

# Make sure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

### Build Universal Binary (Intel + Apple Silicon)

```bash
swift build -c release --arch arm64 --arch x86_64
```

## Quick Start

### 1. Run the Setup Wizard

```bash
ics-calendar-sync setup
```

The interactive wizard will guide you through:
- Granting calendar access
- Entering your ICS subscription URL
- Selecting a target calendar
- Configuring sync options
- Setting up background sync

**Important**: On first run, macOS will prompt you to grant calendar access. You **must** click "Allow" or "OK" when prompted, otherwise the app cannot read or write to your calendars. See [Calendar Access](#calendar-access) in troubleshooting if you accidentally denied access.

### 2. Manual Sync

```bash
ics-calendar-sync sync
```

### 3. Enable Background Sync

```bash
ics-calendar-sync install
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `setup` | Interactive setup wizard |
| `sync` | Run a single sync operation (default command) |
| `daemon` | Run in daemon mode (continuous sync) |
| `status` | Show sync status and statistics |
| `validate` | Validate configuration file |
| `list` | List events currently tracked |
| `calendars` | List available calendars |
| `reset` | Reset sync state (requires `--force`) |
| `install` | Install as launchd background service |
| `uninstall` | Remove launchd background service |

### Global Options

```
-c, --config <path>    Config file path [default: ~/.config/ics-calendar-sync/config.json]
-v, --verbose          Increase verbosity (can repeat: -v, -vv)
-q, --quiet            Suppress non-error output
--dry-run              Show what would happen without making changes
--json                 Output in JSON format
--version              Show version
-h, --help             Show help
```

### Command-Specific Options

#### sync

```
--full                 Force full sync, ignoring existing state
```

#### daemon

```
--interval <minutes>   Override sync interval from configuration
```

#### setup

```
--non-interactive      Use defaults and flags instead of interactive prompts
--ics-url <url>        ICS subscription URL (required in non-interactive mode)
--calendar <name>      Target calendar name [default: Subscribed Events]
--skip-sync            Skip initial sync after setup
```

#### list

```
-l <count>             Maximum number of events to show [default: 20]
--all                  Show all events
```

#### reset

```
--force                Required to confirm reset operation
```

### Examples

```bash
# Run sync with verbose output
ics-calendar-sync sync -v

# Very verbose output for debugging
ics-calendar-sync sync -vv

# Dry run to see what would change
ics-calendar-sync sync --dry-run

# Force full resync (ignores state, re-syncs everything)
ics-calendar-sync sync --full

# Run daemon with custom interval
ics-calendar-sync daemon --interval 30

# Check sync status
ics-calendar-sync status

# Get status as JSON (useful for monitoring)
ics-calendar-sync status --json

# List tracked events
ics-calendar-sync list

# List all tracked events
ics-calendar-sync list --all

# List available calendars
ics-calendar-sync calendars

# Reset sync state
ics-calendar-sync reset --force

# Non-interactive setup for automation
ics-calendar-sync setup --non-interactive \
  --ics-url "https://example.com/calendar.ics" \
  --calendar "Work Events"

# Non-interactive setup without initial sync
ics-calendar-sync setup --non-interactive \
  --ics-url "https://example.com/calendar.ics" \
  --skip-sync
```

## Configuration

Configuration is stored in `~/.config/ics-calendar-sync/config.json`:

```json
{
  "source": {
    "url": "https://example.com/calendar.ics",
    "headers": {
      "Authorization": "Bearer ${ICS_AUTH_TOKEN}"
    },
    "timeout": 30,
    "verify_ssl": true
  },
  "destination": {
    "calendar_name": "Subscribed Events",
    "create_if_missing": true,
    "source_preference": "icloud"
  },
  "sync": {
    "delete_orphans": true,
    "summary_prefix": "",
    "window_days_past": 30,
    "window_days_future": 365,
    "sync_alarms": true
  },
  "state": {
    "path": "~/.local/share/ics-calendar-sync/state.db"
  },
  "logging": {
    "level": "info",
    "format": "text"
  },
  "daemon": {
    "interval_minutes": 15
  },
  "notifications": {
    "enabled": false,
    "on_success": false,
    "on_failure": true,
    "on_partial": true,
    "sound": "default"
  }
}
```

### Configuration Reference

#### source

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | string | (required) | ICS subscription URL |
| `headers` | object | `{}` | HTTP headers to send with requests |
| `timeout` | integer | `30` | Request timeout in seconds (1-300) |
| `verify_ssl` | boolean | `true` | Verify SSL certificates |

#### destination

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `calendar_name` | string | `"Subscribed Events"` | Target calendar name |
| `create_if_missing` | boolean | `true` | Create calendar if it does not exist |
| `source_preference` | string | `"icloud"` | Preferred calendar source: `icloud`, `local`, or `any` |

#### sync

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `delete_orphans` | boolean | `true` | Delete events removed from source |
| `summary_prefix` | string | `""` | Prefix to add to event titles |
| `window_days_past` | integer | `30` | Sync events this many days in the past |
| `window_days_future` | integer | `365` | Sync events this many days in the future |
| `sync_alarms` | boolean | `true` | Sync event alarms/reminders |

#### state

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `path` | string | `~/.local/share/ics-calendar-sync/state.db` | Path to SQLite state database |

#### logging

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `level` | string | `"info"` | Log level: `debug`, `info`, `warning`, `error` |
| `format` | string | `"text"` | Output format: `text` or `json` |

#### daemon

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `interval_minutes` | integer | `15` | Minutes between sync cycles (minimum 1) |

#### notifications

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable macOS notifications |
| `on_success` | boolean | `false` | Notify on successful sync |
| `on_failure` | boolean | `true` | Notify when sync fails |
| `on_partial` | boolean | `true` | Notify when sync completes with errors |
| `sound` | string | `"default"` | Notification sound (or `null` for silent) |

**Example notifications configuration:**

```json
{
  "notifications": {
    "enabled": true,
    "on_success": false,
    "on_failure": true,
    "on_partial": true,
    "sound": "default"
  }
}
```

Available sounds are located in `/System/Library/Sounds/` (e.g., `"Ping"`, `"Glass"`, `"Blow"`). Set to `null` to disable sounds.

### Environment Variables

You can use environment variables in the configuration with `${VAR_NAME}` syntax:

- `ICS_AUTH_TOKEN`: Bearer token for authenticated feeds
- `ICS_USERNAME`: Username for basic auth
- `ICS_PASSWORD`: Password for basic auth

Example with environment variable:

```json
{
  "source": {
    "url": "https://example.com/calendar.ics",
    "headers": {
      "Authorization": "Bearer ${ICS_AUTH_TOKEN}"
    }
  }
}
```

### Keychain Storage

Credentials can be stored securely in the macOS Keychain. The setup wizard offers this option, or you can configure it programmatically using the KeychainHelper API.

## Authentication

### Bearer Token

```json
{
  "source": {
    "url": "https://example.com/calendar.ics",
    "headers": {
      "Authorization": "Bearer your-token-here"
    }
  }
}
```

Or using environment variable:

```json
{
  "source": {
    "headers": {
      "Authorization": "Bearer ${ICS_AUTH_TOKEN}"
    }
  }
}
```

### Basic Authentication

```json
{
  "source": {
    "headers": {
      "Authorization": "Basic base64-encoded-credentials"
    }
  }
}
```

You can generate the base64 credentials with:

```bash
echo -n "username:password" | base64
```

### Custom Headers

Any custom headers can be added to requests:

```json
{
  "source": {
    "headers": {
      "X-Api-Key": "your-api-key",
      "X-Custom-Header": "custom-value"
    }
  }
}
```

## Background Service

### Install as launchd Service

```bash
ics-calendar-sync install
```

This creates a launchd plist at `~/Library/LaunchAgents/com.ics-calendar-sync.plist` and starts the service.

### Manage the Service

```bash
# Check if running
launchctl list | grep ics-calendar-sync

# View logs
tail -f ~/Library/Logs/ics-calendar-sync/stdout.log

# Stop service
launchctl unload ~/Library/LaunchAgents/com.ics-calendar-sync.plist

# Start service
launchctl load ~/Library/LaunchAgents/com.ics-calendar-sync.plist

# Remove service
ics-calendar-sync uninstall
```

### View Logs

```bash
# Using macOS unified logging
log show --predicate 'subsystem == "com.ics-calendar-sync"' --last 1h

# Or view stdout/stderr logs
tail -f ~/Library/Logs/ics-calendar-sync/stdout.log
tail -f ~/Library/Logs/ics-calendar-sync/stderr.log
```

## How It Works

### Delta Sync Algorithm

1. **Fetch**: Download ICS feed from source URL
2. **Parse**: Extract all VEVENT components
3. **Hash**: Calculate content hash for each event using SHA-256
4. **Compare**: Match against stored state to detect changes
5. **Detect Changes**:
   - New events (UID not in state): Create in calendar
   - Modified events (hash changed or sequence increased): Update in calendar
   - Missing events (in state but not in ICS): Delete from calendar (if configured)
6. **Apply**: Execute creates, updates, and deletes via EventKit
7. **Persist**: Store new state to SQLite database

### State Tracking

The tool uses `calendarItemExternalIdentifier` from EventKit as the stable identifier. This ID persists across app restarts and system reboots, ensuring reliable event tracking.

State is stored in a SQLite database containing:
- Source UID (from ICS)
- Calendar item external identifier (from EventKit)
- Content hash (for change detection)
- Sequence number (from ICS SEQUENCE property)
- Last sync timestamp

### Conflict Resolution

The source ICS feed always wins. If an event is modified both in the ICS and locally in Calendar.app, the ICS version takes precedence on the next sync.

### Recurring Events

The tool fully supports iCalendar recurrence rules (RRULE), including:
- Daily, weekly, monthly, and yearly patterns
- By-day, by-month, by-monthday modifiers
- Exception dates (EXDATE)
- Recurrence IDs for modified instances

## Troubleshooting

### Calendar Access

This app requires access to your calendars via macOS Calendar permissions. When you first run the app, macOS will display a permission dialog asking to allow access.

#### Granting Access on First Run

When prompted with "ics-calendar-sync would like to access your calendars":
- Click **OK** or **Allow** to grant access
- If you click **Don't Allow**, the app will not be able to sync events

#### If You Accidentally Denied Access

If you see "Calendar access denied" or "Calendar access not determined":

1. Open **System Settings** (or System Preferences on older macOS)
2. Go to **Privacy & Security** then **Calendars**
3. Find **Terminal** (or **iTerm**, or whatever terminal app you use)
4. Toggle the switch **ON** to enable calendar access
5. You may need to quit and restart your terminal app
6. Re-run `ics-calendar-sync setup` or `ics-calendar-sync sync`

#### Calendar Access for Background Service

If you installed the background service with `ics-calendar-sync install`, the launchd service runs under your user account and inherits calendar permissions from Terminal. If background sync is not working:

1. Run `ics-calendar-sync sync` manually from Terminal first to trigger the permission prompt
2. Grant access when prompted
3. The background service should now work

#### Full Disk Access (macOS Sonoma and later)

On macOS Sonoma (14.0) and later, some calendar operations may require Full Disk Access:

1. Open **System Settings** then **Privacy & Security** then **Full Disk Access**
2. Click the **+** button
3. Navigate to your terminal app (e.g., `/Applications/Utilities/Terminal.app`)
4. Add it to the list and ensure it's enabled

#### Still Having Permission Issues?

If you continue to have calendar access problems:

1. Check if the Calendar app itself is working (open Calendar.app and verify your calendars appear)
2. Try signing out and back into iCloud in System Settings if using iCloud calendars
3. Run with verbose output to see detailed errors: `ics-calendar-sync sync -vv`
4. Check the system console for permission-related errors: `log show --predicate 'subsystem == "com.apple.TCC"' --last 5m`

### Events Not Appearing

1. Check sync status: `ics-calendar-sync status`
2. Verify calendar exists: `ics-calendar-sync calendars`
3. Run with verbose output: `ics-calendar-sync sync -vv`
4. Check if events are in date window (default: 30 days past, 365 days future)
5. Verify the ICS URL is accessible: `curl -I "your-ics-url"`

### Background Service & Daemon

#### Checking if the Service is Running

```bash
# Check if the service is loaded and running
launchctl list | grep ics-calendar-sync

# Expected output when running:
# 12345  0  com.ics-calendar-sync
# (PID)  (exit code)  (label)

# If no output, the service is not loaded
```

#### Service Not Starting

If `ics-calendar-sync install` succeeded but the service isn't running:

1. **Check if the plist exists:**
   ```bash
   ls -la ~/Library/LaunchAgents/com.ics-calendar-sync.plist
   ```

2. **Verify the plist is valid:**
   ```bash
   plutil -lint ~/Library/LaunchAgents/com.ics-calendar-sync.plist
   ```

3. **Check launchd for errors:**
   ```bash
   launchctl error $(launchctl list | grep ics-calendar-sync | awk '{print $2}')
   ```

4. **View service logs:**
   ```bash
   cat ~/Library/Logs/ics-calendar-sync/stderr.log
   cat ~/Library/Logs/ics-calendar-sync/stdout.log
   ```

5. **Try running manually to see errors:**
   ```bash
   ics-calendar-sync daemon
   ```

#### Manually Starting/Stopping the Service

```bash
# Stop the service
launchctl unload ~/Library/LaunchAgents/com.ics-calendar-sync.plist

# Start the service
launchctl load ~/Library/LaunchAgents/com.ics-calendar-sync.plist

# Restart (stop then start)
launchctl unload ~/Library/LaunchAgents/com.ics-calendar-sync.plist && \
launchctl load ~/Library/LaunchAgents/com.ics-calendar-sync.plist
```

#### Service Keeps Stopping

If the service starts but stops unexpectedly:

1. **Check exit codes:**
   ```bash
   launchctl list | grep ics-calendar-sync
   # Second column shows last exit code (0 = success)
   ```

2. **Common exit codes:**
   - `0`: Normal exit
   - `1`: General error (check stderr.log)
   - `78`: Configuration error
   - `126`: Permission denied

3. **Check for crash logs:**
   ```bash
   ls ~/Library/Logs/DiagnosticReports/ | grep ics-calendar-sync
   ```

#### Reinstalling the Service

If the service is in a bad state:

```bash
# Uninstall completely
ics-calendar-sync uninstall

# Verify removal
launchctl list | grep ics-calendar-sync
ls ~/Library/LaunchAgents/com.ics-calendar-sync.plist

# Reinstall
ics-calendar-sync install
```

#### Service Not Syncing Events

If the service is running but events aren't syncing:

1. **Check sync status:**
   ```bash
   ics-calendar-sync status
   ```

2. **Verify calendar permissions** (see [Calendar Access](#calendar-access) above)

3. **Check the logs for sync errors:**
   ```bash
   tail -100 ~/Library/Logs/ics-calendar-sync/stdout.log
   ```

4. **Test manual sync:**
   ```bash
   ics-calendar-sync sync -v
   ```

#### Viewing Live Logs

To watch the service logs in real-time:

```bash
# Watch stdout
tail -f ~/Library/Logs/ics-calendar-sync/stdout.log

# Watch stderr
tail -f ~/Library/Logs/ics-calendar-sync/stderr.log

# Watch both
tail -f ~/Library/Logs/ics-calendar-sync/*.log
```

### SSL Certificate Errors

If you are connecting to a server with a self-signed certificate:

```json
{
  "source": {
    "verify_ssl": false
  }
}
```

Note: Disabling SSL verification is not recommended for production use.

### Reset and Start Fresh

```bash
# Reset sync state (events in calendar are not affected)
ics-calendar-sync reset --force

# Run full sync
ics-calendar-sync sync --full
```

### Configuration Errors

Validate your configuration file:

```bash
ics-calendar-sync validate
```

This will report any syntax errors or invalid values.

## Development

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Universal binary (Intel + Apple Silicon)
swift build -c release --arch arm64 --arch x86_64

# Run tests
swift test
```

### Project Structure

```
ics-calendar-sync/
├── Package.swift
├── Sources/ics-calendar-sync/
│   ├── CLI/
│   │   ├── Arguments.swift      # Command-line argument definitions
│   │   ├── Commands.swift       # Command implementations
│   │   └── SetupWizard.swift    # Interactive setup wizard
│   ├── ICS/
│   │   ├── ICSParser.swift      # ICS file parser
│   │   ├── ICSEvent.swift       # Event data model
│   │   └── ICSFetcher.swift     # HTTP fetching logic
│   ├── Calendar/
│   │   ├── CalendarManager.swift    # EventKit integration
│   │   ├── EventMapper.swift        # ICS to EventKit mapping
│   │   └── RecurrenceMapper.swift   # Recurrence rule mapping
│   ├── Sync/
│   │   ├── SyncEngine.swift     # Main sync orchestration
│   │   ├── SyncState.swift      # SQLite state management
│   │   └── ContentHash.swift    # Content hashing for change detection
│   ├── Config/
│   │   ├── Configuration.swift  # Configuration model and loading
│   │   └── KeychainHelper.swift # Secure credential storage
│   ├── Scheduling/
│   │   ├── Daemon.swift         # Background daemon runner
│   │   ├── LaunchdGenerator.swift   # launchd plist generation
│   │   └── SignalHandler.swift      # Unix signal handling
│   └── Utilities/
│       ├── Errors.swift         # Error types
│       ├── Extensions.swift     # Swift extensions
│       └── Logger.swift         # Logging infrastructure
└── Tests/
    └── ics-calendar-syncTests/
        ├── Fixtures/            # Test ICS files
        ├── ICSParserTests.swift
        ├── ContentHashTests.swift
        └── RecurrenceMapperTests.swift
```

### Running Tests

```bash
# Run all tests
swift test

# With verbose output
swift test --verbose

# Specific test class
swift test --filter ICSParserTests

# Specific test method
swift test --filter ICSParserTests/testBasicEvent
```

### Dependencies

- [Swift Argument Parser](https://github.com/apple/swift-argument-parser) (1.3.0+): Command-line interface
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) (0.15.0+): State persistence
- EventKit (system framework): Calendar integration

## Version

Current version: 1.0.0

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome. Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- Built with [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- SQLite handling via [SQLite.swift](https://github.com/stephencelis/SQLite.swift)
- Calendar integration via Apple EventKit framework
