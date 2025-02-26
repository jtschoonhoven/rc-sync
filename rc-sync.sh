#!/usr/bin/env sh

# RC-202 Sync Script
# This script synchronizes WAV files between a BOSS RC-202/505 Loop Station and a local backup directory

# Configuration
SOURCE_DIR="/Volumes/BOSS_RC-202/ROLAND/WAVE"
BACKUP_DIR=""  # Will be set later
LOG_FILE=""    # Will be set after BACKUP_DIR is determined

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Echo to terminal with color depending on level
    case "$level" in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        *) echo -e "$message" ;;
    esac

    # Log to file if the backup directory exists
    if [ -d "$BACKUP_DIR" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

# Function to check if RC-202 is connected
check_device_connected() {
    if [ ! -d "$SOURCE_DIR" ]; then
        log_message "BOSS RC-202 not found at $SOURCE_DIR" "ERROR"
        log_message "Please connect your BOSS RC-202 Loop Station via USB and try again." "INFO"
        return 1
    else
        log_message "BOSS RC-202 detected at $SOURCE_DIR" "SUCCESS"
        return 0
    fi
}

# Function to create backup directory if it doesn't exist
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_message "Creating backup directory: $BACKUP_DIR" "INFO"
        mkdir -p "$BACKUP_DIR"

        if [ $? -eq 0 ]; then
            log_message "Backup directory created successfully" "SUCCESS"
        else
            log_message "Failed to create backup directory" "ERROR"
            return 1
        fi
    else
        log_message "Backup directory already exists: $BACKUP_DIR" "INFO"
    fi

    # Create log file if it doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        log_message "Created log file: $LOG_FILE" "INFO"
    fi

    return 0
}

# Function to sync WAV files
sync_wav_files() {
    local total_files=0
    local copied_files=0
    local skipped_files=0
    local error_files=0

    log_message "Starting synchronization of WAV files..." "INFO"

    # Get list of track directories
    local track_dirs=$(ls -1 "$SOURCE_DIR" 2>/dev/null)

    if [ -z "$track_dirs" ]; then
        log_message "No track directories found in $SOURCE_DIR" "WARNING"
        return 1
    fi

    # Process each track directory
    for track_dir in $track_dirs; do
        # Skip if not a directory or doesn't match expected pattern
        if [ ! -d "$SOURCE_DIR/$track_dir" ] || ! echo "$track_dir" | grep -qE '^([0-9]{3})_[12]$'; then
            continue
        fi

        # Extract the slot number from the directory name and remove leading zeros
        local slot_num=$(echo "$track_dir" | sed 's/^0*\([1-9][0-9]*\)_.*/\1/')
        # Calculate bank number (1-8 -> bank_1, 9-16 -> bank_2, etc.)
        local bank_num=$(( (slot_num - 1) / 8 + 1 ))
        local bank_dir="bank_${bank_num}"

        # Path to WAV file
        local wav_file="$SOURCE_DIR/$track_dir/$track_dir.WAV"

        # Skip if directory is empty or WAV file doesn't exist
        if [ ! -f "$wav_file" ]; then
            log_message "Skipping empty directory: $track_dir" "INFO"
            continue
        fi

        # Create bank directory if it doesn't exist
        mkdir -p "$BACKUP_DIR/$bank_dir"

        local backup_wav="$BACKUP_DIR/$bank_dir/$track_dir.WAV"

        ((total_files++))

        # Check if we need to copy the file
        if [ ! -f "$backup_wav" ] || [ "$wav_file" -nt "$backup_wav" ]; then
            log_message "Copying: $track_dir.WAV to $bank_dir" "INFO"
            cp "$wav_file" "$backup_wav"

            if [ $? -eq 0 ]; then
                ((copied_files++))
            else
                log_message "Failed to copy $track_dir.WAV" "ERROR"
                ((error_files++))
                continue
            fi
        else
            log_message "Skipping: $track_dir.WAV (not modified)" "INFO"
            ((skipped_files++))
        fi
    done

    # Display summary
    log_message "Synchronization complete!" "SUCCESS"
    log_message "Total files: $total_files" "INFO"
    log_message "Files copied: $copied_files" "INFO"
    log_message "Files skipped (not modified): $skipped_files" "INFO"

    if [ $error_files -gt 0 ]; then
        log_message "Files with errors: $error_files" "WARNING"
    fi

    return 0
}

# Function to print usage information
print_usage() {
    echo ""
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Options:"
    echo "  -d, --dir DIR    Specify backup directory (overrides RC_BACKUP_DIR)"
    echo "  -h, --help       Show this help message"
    echo ""
}

# Function to parse command line arguments
parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -d|--dir)
                if [ -z "$2" ]; then
                    log_message "Error: Directory argument is missing" "ERROR"
                    print_usage
                    exit 1
                fi
                BACKUP_DIR="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_message "Unknown option: $1" "ERROR"
                print_usage
                exit 1
                ;;
        esac
    done

    # If BACKUP_DIR not set via arguments, try environment variable
    if [ -z "$BACKUP_DIR" ]; then
        if [ -z "$RC_BACKUP_DIR" ]; then
            log_message "Please select a backup destination with `--dir` (or set RC_BACKUP_DIR)" "ERROR"
            print_usage
            exit 1
        fi
        BACKUP_DIR="$RC_BACKUP_DIR"
    fi

    # Set LOG_FILE after BACKUP_DIR is determined
    LOG_FILE="$BACKUP_DIR/sync_log.txt"
}

# Main execution
main() {
    log_message "========================================" "INFO"
    log_message "RC-202 Sync Tool - Starting" "INFO"
    log_message "========================================" "INFO"

    # Parse command line arguments first, before any logging
    parse_arguments "$@"

    # Check if device is connected
    if ! check_device_connected; then
        exit 1
    fi

    # Create backup directory
    if ! create_backup_dir; then
        exit 1
    fi

    # Sync WAV files
    if ! sync_wav_files; then
        log_message "Synchronization process encountered errors" "WARNING"
        exit 1
    fi

    log_message "========================================" "INFO"
    log_message "RC-202 Sync Tool - Completed" "INFO"
    log_message "========================================" "INFO"

    exit 0
}

# Run main function with all arguments
main "$@"
