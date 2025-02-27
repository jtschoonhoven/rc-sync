# rc-sync
Backup and sync audio files between a Boss RC-202/505 Loop Station and computer
## Overview

A shell script to synchronize WAV files between a BOSS RC-202/505 Loop Station and a local backup directory. The script provides:

- Two-way sync of WAV files between device and backup location
- Bank-by-bank change detection and sync
- Safe exports of existing files before changes
- Detailed logging of all operations
- Restore exported banks
- Support for both macOS and Linux

## Installation

1. Clone this repository
2. Make the script executable: `chmod +x rc-sync.sh`
3. Set your backup directory either:
   - Via environment variable: `export RC_BACKUP_DIR="/path/to/backup"`
   - Or using the `--dir` flag when running

## Usage

### Basic Sync

```bash
./rc-sync.sh
```

This will:
1. Compare files between device and backup
2. Show changes bank by bank
3. Prompt for action on each changed bank

### Sync Options
When changes are detected in a bank, you'll be presented with these options:

- **[E] Export tracks before applying changes (safe)**
  - Save the existing backup to the `exports/` folder before applying changes
  - Use this if the incoming changes are a new project and you want to export your old project

- **[a] Apply changes (destructive)**
  - Updates the existing backup in-place
  - Use this when the incoming changes are improvements to the existing project

- **[r] Revert and push local changes to loop station (dangerous)**
  - Replaces files on the loop station _from_ the latest backup
  - Use this when you don't want the incoming changes and are OK with deleting them

- **[s] Skip this bank and do nothing (no backup)**
  - Skips to the next bank without making any changes or backups

### Restore from Backup
```bash
./rc-sync.sh --restore name-of-project-in-exports-folder
```

Restores files from a previous project in `exports/` back to the loop station in the original location.

### Directory Structure
```
backup_dir/
├── bank_1/
├── bank_2/
├── ...
├── bank_8/
├── exports/
│   ├── 2024-03-14_bank_1/
│   └── my-cool-project/
└── sync_log.txt
```

### Command Line Options
```bash
./rc-sync.sh [OPTIONS]
Options:
  -d, --dir DIR    Specify backup directory (overrides RC_BACKUP_DIR)
  -r, --restore    Restore from a project in exports directory
  -h, --help       Show this help message
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Automation

### Mac

You can run this script automatically whenever your loop station is connected like so:

```
# 1. Create a launch agent:
cat << 'EOF' > ~/Library/LaunchAgents/com.io.github.jtschoonhoven.mountscript.plist
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.io.github.jtschoonhoven.mountscript</string>

    <key>WatchPaths</key>
    <array>
        <!-- EDIT ME: THIS SHOULD MATCH THE NAME OF YOUR DRIVE -->
        <string>/Volumes/BOSS_RC-202</string>
    </array>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>cd ~ && /usr/bin/open -a Terminal -n -F -W $(realpath ~/src/rc-sync/rc-sync.sh)</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/mountscript.stdout</string>

    <key>StandardErrorPath</key>
    <string>/tmp/mountscript.stderr</string>
</dict>
</plist>
EOF

# 2. Load the service:
launchctl load ~/Library/LaunchAgents/com.io.github.jtschoonhoven.mountscript.plist

# 3. Check status
launchctl list | grep mountscript

# 4. Check logs
tail -f /tmp/mountscript.stdout
tail -f /tmp/mountscript.stderr

# 5. To disable
launchctl unload ~/Library/LaunchAgents/com.io.github.jtschoonhoven.mountscript.plist
```
