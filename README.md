# ICS Calendar Sync

A robust, enterprise-quality Swift tool that synchronizes events from ICS calendar subscriptions to your macOS Calendar via EventKit, with full support for delta and incremental updates.

**Now available as both a native macOS menu bar app and a powerful command-line tool.**

## What's New in v2.0

- **Native macOS Menu Bar App**: A beautiful SwiftUI-based GUI for managing multiple calendar feeds
- **Multi-Feed Support**: Sync multiple ICS calendars with independent settings
- **Per-Feed Notifications**: Control notifications for each feed individually
- **Calendar Picker**: Browse and select from your system calendars via EventKit
- **Default Calendar Setting**: Pre-select your preferred calendar for new feeds
- **Native Notifications**: Uses macOS UserNotifications framework (no AppleScript)
- **Calendar Access Detection**: Warns you if calendar permissions are missing

## Features

### Core Features
- **Zero Authentication Hassle**: Uses native macOS calendar permissions with no app-specific passwords or OAuth required
- **Automatic iCloud Sync**: Events sync to all your Apple devices via iCloud
- **Smart Delta Sync**: Only creates, updates, or deletes events that have changed
- **Bulletproof Deduplication**: Multi-layer event matching ensures no duplicates, even if iCloud changes event identifiers
- **Full ICS Support**: Handles recurring events, timezones, alarms, and all standard iCalendar properties

### GUI App Features (New in v2.0)
- **Menu Bar App**: Lives in your menu bar for quick access
- **Multi-Feed Management**: Add, edit, delete, and toggle multiple ICS feeds
- **Visual Calendar Picker**: Select target calendars from a dropdown showing all your calendars
- **Per-Feed Settings**: Independent sync intervals, notifications, and orphan deletion settings
- **Service Control**: Start/stop background sync service from the GUI
- **Status Overview**: See sync status, event counts, and last sync time at a glance
- **Calendar Access Warning**: Alerts you if calendar permissions need to be granted
- **Import/Export Configs**: Export your configuration to JSON or import from file (backwards compatible with CLI configs)
- **View Logs**: Quick access to log files for troubleshooting
- **Reset Sync State**: Clear sync state to start fresh without losing calendar events

### CLI Features
- **Background Sync**: Run as a daemon or install as a launchd service
- **Interactive Setup**: User-friendly setup wizard guides you through configuration
- **Non-Interactive Mode**: Scriptable setup for automation and CI/CD pipelines
- **Robust State Tracking**: SQLite-based state ensures reliable sync across runs
- **Secure Credential Storage**: Optional macOS Keychain integration for sensitive data
- **Flexible Output**: Text or JSON output formats for scripting and monitoring

## Requirements

- macOS 13.0 (Ventura) or later

## Installation

### GUI App (Recommended for Most Users)

#### Option 1: Download Pre-built App

Download the macOS App from the [Releases page](https://github.com/pacnpal/ics-calendar-sync/releases):

| Your Mac | Download |
|----------|----------|
| Apple Silicon (M1/M2/M3/M4) | `ICS-Calendar-Sync-macOS-App-arm64-v2.0.0.zip` |
| Intel | `ICS-Calendar-Sync-macOS-App-x86_64-v2.0.0.zip` |
| **Not sure** | `ICS-Calendar-Sync-macOS-App-universal-v2.0.0.zip` |

1. Extract the zip file
2. Drag **ICS Calendar Sync.app** to your Applications folder
3. Launch the app - it will appear in your menu bar
4. On first launch, grant calendar access when prompted

#### Option 2: Build from Source

Requires Xcode 15.0+ with Swift 5.9+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Clone the repository
git clone https://github.com/pacnpal/ics-calendar-sync.git
cd ics-calendar-sync

# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build the app
xcodebuild -project ICSCalendarSyncGUI.xcodeproj -scheme "ICS Calendar Sync" -configuration Release build

# The app will be in DerivedData. To copy to Applications:
cp -R ~/Library/Developer/Xcode/DerivedData/ICSCalendarSyncGUI-*/Build/Products/Release/"ICS Calendar Sync.app" /Applications/
```

Or use the convenience script:
```bash
./scripts/build-app.sh
```

### CLI Tool

#### Pre-built Binary

Download the latest release from the [Releases page](https://github.com/pacnpal/ics-calendar-sync/releases).

| Your Mac | Download | How to check |
|----------|----------|--------------|
| Apple Silicon | `ics-calendar-sync-cli-arm64-v2.0.0.zip` | Apple menu > About This Mac shows "Chip: Apple M1/M2/M3/M4" |
| Intel | `ics-calendar-sync-cli-x86_64-v2.0.0.zip` | Apple menu > About This Mac shows "Processor: Intel" |
| **Not sure** | `ics-calendar-sync-cli-universal-v2.0.0.zip` | Works on all Macs |

```bash
# Extract the zip (replace ARCH with arm64, x86_64, or universal)
cd ~/Downloads
unzip ics-calendar-sync-cli-ARCH-v2.0.0.zip

# Remove quarantine attribute
xattr -d com.apple.quarantine ics-calendar-sync-*

# Install to /usr/local/bin
sudo install -m 755 ics-calendar-sync-* /usr/local/bin/ics-calendar-sync

# Verify installation
ics-calendar-sync --version
```

#### From Source

```bash
# Clone the repository
git clone https://github.com/pacnpal/ics-calendar-sync.git
cd ics-calendar-sync

# Build the release binary
swift build -c release

# Install to your local bin
sudo install -m 755 .build/release/ics-calendar-sync /usr/local/bin/

# Verify installation
ics-calendar-sync --version
```

#### macOS Security Warning

macOS quarantines files downloaded from the internet. The `xattr` command above removes this. If you skip that step:

**Option 1: Allow via System Settings**

1. Open **System Settings** then **Privacy & Security**
2. Scroll down to find the blocked app message
3. Click **Allow Anyway**
4. Run the command again and click **Open** when prompted

## Quick Start

### GUI App

1. **Launch the app** - Click the calendar icon in your menu bar
2. **Open Settings** - Click "Settings..." in the dropdown menu
3. **Add a feed** - Click "Add Feed" and enter:
   - A name for the feed (optional)
   - The ICS URL
   - Select a target calendar from the dropdown
   - Configure sync interval and options
4. **Enable notifications** (optional) - Toggle global notifications and per-feed settings
5. **Start syncing** - Click "Sync All Feeds" or enable the background service

### CLI

```bash
# Run the setup wizard
ics-calendar-sync setup

# Manual sync
ics-calendar-sync sync

# Enable background sync
ics-calendar-sync install
```

## GUI App Guide

### Menu Bar

Click the calendar icon in your menu bar to see:

- **Status**: Current sync status and last sync time
- **Event count**: Total number of synced events
- **Feed list**: Quick view of your configured feeds (up to 5)
- **Actions**:
  - Sync All Feeds (Cmd+R)
  - Refresh Status
  - Start/Stop Service
  - Settings... (Cmd+,)
  - View Logs...
  - Quit (Cmd+Q)

### Settings Window

The settings window has three sections:

#### 1. Calendar Feeds

A list of all your configured feeds showing:
- Enable/disable toggle
- Feed name and target calendar
- Sync interval
- Edit and delete buttons

**Actions:**
- **Import**: Load a configuration from a JSON file (compatible with v1.x CLI configs)
- **Export**: Save your current configuration to a JSON file
- **Add Feed**: Create a new feed configuration

#### 2. Global Settings

- **Notifications**: Master toggle for all notifications (overrides per-feed settings when off)
- **Default Calendar**: Pre-selects this calendar when adding new feeds
- **Service Status**: Shows if the background sync service is running
- **View Logs**: Opens the logs folder in Finder
- **Reset Sync State**: Clears all sync state (events in calendars are not affected)

#### 3. Status Bar

Shows at-a-glance information:
- Number of feeds (total and enabled)
- Total event count
- Last sync time
- App version

### Feed Editor

When adding or editing a feed:

| Field | Description |
|-------|-------------|
| Name | Optional nickname for the feed |
| ICS URL | The calendar subscription URL |
| Calendar | Target calendar (dropdown of all system calendars) |
| Interval | How often to sync (5, 15, 30, or 60 minutes) |
| Delete orphaned events | Remove events that are no longer in the ICS |
| Show notifications | Send notifications for this feed's sync results |
| Enabled | Whether this feed should be synced |

### Calendar Access

The app needs permission to access your calendars. If access is not granted:

1. An orange warning banner appears in Settings
2. Click **Open Settings** to go directly to System Settings > Privacy & Security > Calendars
3. Enable access for **ICS Calendar Sync**
4. Return to the app - the calendar list will populate automatically

### Configuration Storage

The GUI app stores its configuration at:
```
~/.config/ics-calendar-sync/gui-config.json
```

This is separate from the CLI configuration to allow both to operate independently.

### CLI and GUI Compatibility

The GUI app and CLI tool are **100% feature compatible** and share the same core sync engine:

| Feature | GUI | CLI |
|---------|-----|-----|
| Sync calendar feeds | ✅ | ✅ |
| Background service | ✅ | ✅ |
| Multiple feeds | ✅ Native support | Use multiple config files |
| Notifications | ✅ Native | ✅ macOS notifications |
| Import/Export configs | ✅ | Manual JSON editing |
| View logs | ✅ One-click | `tail -f ~/Library/Logs/...` |
| Reset sync state | ✅ One-click | `ics-calendar-sync reset --force` |
| Migrate UID markers | Via CLI | `ics-calendar-sync migrate` |
| List tracked events | Via CLI | `ics-calendar-sync list` |
| Dry run mode | Via CLI | `ics-calendar-sync sync --dry-run` |

**Config Migration:** The GUI can import configurations from both v2.0 GUI format and v1.x CLI format. When importing a CLI config, it automatically converts the single-feed format to a GUI feed entry.

**Shared State:** Both apps use the same SQLite state database at `~/.local/share/ics-calendar-sync/state.db`, so sync history is shared.

## CLI Usage

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
| `migrate` | Add UID markers to existing calendar events |
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

### Examples

```bash
# Run sync with verbose output
ics-calendar-sync sync -v

# Dry run to see what would change
ics-calendar-sync sync --dry-run

# Force full resync
ics-calendar-sync sync --full

# Run daemon with custom interval
ics-calendar-sync daemon --interval 30

# Check sync status as JSON
ics-calendar-sync status --json

# List available calendars
ics-calendar-sync calendars

# Non-interactive setup
ics-calendar-sync setup --non-interactive \
  --ics-url "https://example.com/calendar.ics" \
  --calendar "Work Events"
```

## Configuration

### GUI Configuration

The GUI stores multi-feed configuration in `~/.config/ics-calendar-sync/gui-config.json`:

```json
{
  "feeds": [
    {
      "id": "uuid-here",
      "name": "Work Calendar",
      "icsURL": "https://example.com/work.ics",
      "calendarName": "Work",
      "syncInterval": 15,
      "deleteOrphans": true,
      "isEnabled": true,
      "notificationsEnabled": true
    }
  ],
  "notifications_enabled": true,
  "default_calendar": "Personal",
  "global_sync_interval": 15
}
```

### CLI Configuration

The CLI uses `~/.config/ics-calendar-sync/config.json`:

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
  "daemon": {
    "interval_minutes": 15
  },
  "notifications": {
    "enabled": false,
    "on_success": false,
    "on_failure": true
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

### Environment Variables

Use environment variables in CLI configuration with `${VAR_NAME}` syntax:

```json
{
  "source": {
    "headers": {
      "Authorization": "Bearer ${ICS_AUTH_TOKEN}"
    }
  }
}
```

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

Generate base64 credentials:
```bash
echo -n "username:password" | base64
```

## Background Service

### Using the GUI

1. Open the menu bar dropdown
2. Click **Start Service** to begin background sync
3. Click **Stop Service** to pause background sync

The service status is shown in the Settings window.

### Using the CLI

```bash
# Install as launchd service
ics-calendar-sync install

# Check if running
launchctl list | grep ics-calendar-sync

# View logs
tail -f ~/Library/Logs/ics-calendar-sync/stdout.log

# Remove service
ics-calendar-sync uninstall
```

## How It Works

### Delta Sync Algorithm

1. **Fetch**: Download ICS feed from source URL
2. **Parse**: Extract all VEVENT components
3. **Deduplicate**: Remove duplicate UIDs (keeps highest sequence number)
4. **Hash**: Calculate content hash using SHA-256
5. **Compare**: Match against stored state to detect changes
6. **Apply**: Execute creates, updates, and deletes via EventKit
7. **Persist**: Store new state to SQLite database

### Bulletproof Event Matching

To prevent duplicates even when iCloud changes EventKit identifiers:

1. **Calendar Item External ID**: Primary stable identifier
2. **Event Identifier**: Secondary EventKit identifier
3. **Embedded UID Marker**: `[ICS-SYNC-UID:xxx]` in notes field
4. **Fuzzy Property Match**: Title and time matching for legacy events

### State Tracking

State is stored in SQLite containing:
- Source UID (from ICS)
- Calendar item identifiers (from EventKit)
- Content hash (for change detection)
- Sequence number (from ICS)
- Last sync timestamp

## Troubleshooting

### Calendar Access

#### GUI App

If you see the orange "Calendar Access Required" banner:

1. Click **Open Settings** in the banner
2. Enable **ICS Calendar Sync** in the Calendars list
3. Return to the app

#### CLI Tool

If you see "Calendar access denied":

1. Open **System Settings** > **Privacy & Security** > **Calendars**
2. Enable your terminal app (Terminal, iTerm, etc.)
3. Restart your terminal and run the command again

### Events Not Appearing

1. Check sync status: `ics-calendar-sync status` or view in GUI
2. Verify calendar exists: `ics-calendar-sync calendars`
3. Run with verbose output: `ics-calendar-sync sync -vv`
4. Check if events are within the date window

### Reset and Start Fresh

```bash
# Reset sync state
ics-calendar-sync reset --force

# Run full sync
ics-calendar-sync sync --full
```

## Development

### Building

```bash
# Build CLI (debug)
swift build

# Build CLI (release)
swift build -c release

# Build GUI app (requires XcodeGen)
brew install xcodegen       # Install XcodeGen if needed
xcodegen generate           # Generate Xcode project
xcodebuild -project ICSCalendarSyncGUI.xcodeproj -scheme "ICS Calendar Sync" -configuration Release build

# Or use the convenience script
./scripts/build-app.sh

# Run tests
swift test
```

### Project Structure

```
ics-calendar-sync/
├── Package.swift
├── project.yml                    # XcodeGen spec for GUI
├── scripts/
│   └── build-app.sh              # GUI build script
├── Resources/
│   ├── Info.plist                # GUI app info
│   └── ICSCalendarSyncGUI.entitlements
├── Sources/
│   ├── ics-calendar-sync/        # CLI source
│   │   ├── CLI/
│   │   ├── ICS/
│   │   ├── Calendar/
│   │   ├── Sync/
│   │   ├── Config/
│   │   └── Utilities/
│   └── ICSCalendarSyncGUI/       # GUI source
│       ├── App.swift             # Main app entry
│       ├── SyncViewModel.swift   # State management
│       ├── MenuBarView.swift     # Menu bar UI
│       └── SettingsView.swift    # Settings window
└── Tests/
    ├── ics-calendar-syncTests/   # CLI tests
    └── ICSCalendarSyncGUITests/  # GUI tests
```

### Running Tests

```bash
# All tests
swift test

# CLI tests only
swift test --filter ics-calendar-syncTests

# GUI tests only
swift test --filter ICSCalendarSyncGUITests

# Specific test
swift test --filter SyncViewModelTests/testAddFeed
```

### Dependencies

- [Swift Argument Parser](https://github.com/apple/swift-argument-parser) (1.3.0+): CLI interface
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) (0.15.0+): State persistence
- EventKit (system): Calendar integration
- UserNotifications (system): Native notifications
- SwiftUI (system): GUI framework

## Version

Current version: **2.0.0**

### Changelog

#### v2.0.0
- Added native macOS menu bar GUI app
- Multi-feed support with independent settings
- Per-feed notification controls
- Calendar picker using EventKit
- Default calendar setting
- Native UserNotifications framework
- Calendar access detection and warning UI
- Import/export configuration (backwards compatible with v1.x CLI configs)
- View logs from GUI
- Reset sync state from GUI
- 100% feature compatibility between CLI and GUI
- Comprehensive test suite for GUI (150+ tests)

#### v1.1.2
- Fixed EventKit date range queries
- Improved duplicate cleanup in migrate command

#### v1.1.1
- Added migrate command for UID marker migration

#### v1.1.0
- Bulletproof deduplication system
- Embedded UID markers in event notes

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- Built with [Swift Argument Parser](https://github.com/apple/swift-argument-parser)
- SQLite handling via [SQLite.swift](https://github.com/stephencelis/SQLite.swift)
- Calendar integration via Apple EventKit framework
- GUI built with SwiftUI and generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen)
