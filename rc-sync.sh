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
        "INFO") printf "${BLUE}[INFO]${NC} %s\n" "$message" ;;
        "SUCCESS") printf "${GREEN}[SUCCESS]${NC} %s\n" "$message" ;;
        "WARNING") printf "${YELLOW}[WARNING]${NC} %s\n" "$message" ;;
        "ERROR") printf "${RED}[ERROR]${NC} %s\n" "$message" ;;
        *) printf "%s\n" "$message" ;;
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

# Function to get file size that works on both macOS and Linux
get_file_size() {
    local file="$1"
    if stat -f %z "$file" 2>/dev/null; then
        # macOS
        return
    elif stat -c %s "$file" 2>/dev/null; then
        # Linux
        return
    else
        # Fallback using ls
        ls -l "$file" | awk '{print $5}'
    fi
}

# Function to sync WAV files
sync_wav_files() {
    local total_files=0
    local copied_files=0
    local skipped_files=0
    local error_files=0

    log_message "Starting synchronization of WAV files..." "INFO"

    # Get list of track directories once and cache it
    local track_dirs=$(ls -1 "$SOURCE_DIR" 2>/dev/null | grep -E '^[0-9]{3}_[12]$')

    if [ -z "$track_dirs" ]; then
        log_message "No track directories found in $SOURCE_DIR" "WARNING"
        return 1
    fi

    # First pass: analyze changes per bank
    for bank_num in 1 2 3 4 5 6 7 8; do
        local new_count=0
        local mod_count=0
        local del_count=0
        local bank_dir="bank_${bank_num}"
        local changes_detected=""

        # First check for deleted files in this bank
        if [ -d "$BACKUP_DIR/$bank_dir" ]; then
            for backup_file in $(find "$BACKUP_DIR/$bank_dir" -maxdepth 1 -name "*.WAV" 2>/dev/null); do
                [ -f "$backup_file" ] || continue

                local track_name=$(basename "$backup_file" .WAV)
                local slot_num=${track_name%_*}  # More efficient than sed
                slot_num=$(echo "$slot_num" | sed 's/^0*//')  # Remove leading zeros safely
                local file_bank_num=$(( (10#$slot_num - 1) / 8 + 1 ))

                [ "$file_bank_num" -ne "$bank_num" ] && continue

                if [ ! -f "$SOURCE_DIR/$track_name/$track_name.WAV" ]; then
                    del_count=$((del_count + 1))
                    changes_detected="yes"
                fi
            done
        fi

        for track_dir in $track_dirs; do
            local slot_num=${track_dir%_*}  # More efficient than sed
            slot_num=$(echo "$slot_num" | sed 's/^0*//')  # Remove leading zeros safely
            local current_bank_num=$(( (10#$slot_num - 1) / 8 + 1 ))  # Force base-10
            [ "$current_bank_num" -ne "$bank_num" ] && continue

            local wav_file="$SOURCE_DIR/$track_dir/$track_dir.WAV"
            local backup_wav="$BACKUP_DIR/$bank_dir/$track_dir.WAV"

            if [ -f "$wav_file" ]; then
                if [ ! -f "$backup_wav" ]; then
                    new_count=$((new_count + 1))
                    changes_detected="yes"
                else
                    # First compare sizes (fast)
                    local src_size=$(get_file_size "$wav_file")
                    local dst_size=$(get_file_size "$backup_wav")

                    if [ "$src_size" != "$dst_size" ] || \
                       [ "$(head -c 65536 "$wav_file" | cksum | awk '{print $1}')" != \
                         "$(head -c 65536 "$backup_wav" | cksum | awk '{print $1}')" ]; then
                        mod_count=$((mod_count + 1))
                        changes_detected="yes"
                    fi
                fi
            fi
        done

        # Skip if no changes in this bank
        [ -z "$changes_detected" ] && continue

        # If there are only new files (no modifications or deletions), process without prompting
        if [ $new_count -gt 0 ] && [ $mod_count -eq 0 ] && [ $del_count -eq 0 ]; then
            log_message "Processing new files for bank_${bank_num}" "INFO"
            for track_dir in $track_dirs; do
                local slot_num=${track_dir%_*}
                slot_num=$(echo "$slot_num" | sed 's/^0*//')
                local current_bank_num=$(( (10#$slot_num - 1) / 8 + 1 ))
                [ "$current_bank_num" -ne "$bank_num" ] && continue

                local wav_file="$SOURCE_DIR/$track_dir/$track_dir.WAV"
                local backup_wav="$BACKUP_DIR/$bank_dir/$track_dir.WAV"

                if [ -f "$wav_file" ] && [ ! -f "$backup_wav" ]; then
                    mkdir -p "$BACKUP_DIR/$bank_dir"
                    log_message "Copying: $track_dir.WAV to $bank_dir" "INFO"
                    cp "$wav_file" "$backup_wav"
                    if [ $? -eq 0 ]; then
                        ((copied_files++))
                    else
                        log_message "Failed to copy $track_dir.WAV" "ERROR"
                        ((error_files++))
                    fi
                fi
            done
            continue
        fi

        # Show bank header before changes
        printf "\nChanges detected in bank_%d:\n" "$bank_num"

        # Show deleted files
        if [ -d "$BACKUP_DIR/$bank_dir" ]; then
            for backup_file in $(find "$BACKUP_DIR/$bank_dir" -maxdepth 1 -name "*.WAV" 2>/dev/null); do
                [ -f "$backup_file" ] || continue
                local track_name=$(basename "$backup_file" .WAV)
                local slot_num=${track_name%_*}
                slot_num=$(echo "$slot_num" | sed 's/^0*//')
                local file_bank_num=$(( (10#$slot_num - 1) / 8 + 1 ))
                [ "$file_bank_num" -ne "$bank_num" ] && continue
                if [ ! -f "$SOURCE_DIR/$track_name/$track_name.WAV" ]; then
                    printf "${RED}delete: %s${NC}\n" "$track_name.WAV"
                fi
            done
        fi

        # Show new, modified, and unchanged files
        for track_dir in $track_dirs; do
            local slot_num=${track_dir%_*}
            slot_num=$(echo "$slot_num" | sed 's/^0*//')
            local current_bank_num=$(( (10#$slot_num - 1) / 8 + 1 ))
            [ "$current_bank_num" -ne "$bank_num" ] && continue

            local wav_file="$SOURCE_DIR/$track_dir/$track_dir.WAV"
            local backup_wav="$BACKUP_DIR/$bank_dir/$track_dir.WAV"

            if [ -f "$wav_file" ]; then
                if [ ! -f "$backup_wav" ]; then
                    printf "${GREEN}copy: %s${NC}\n" "$track_dir.WAV"
                else
                    local src_size=$(get_file_size "$wav_file")
                    local dst_size=$(get_file_size "$backup_wav")
                    if [ "$src_size" != "$dst_size" ] || \
                       [ "$(head -c 65536 "$wav_file" | cksum | awk '{print $1}')" != \
                         "$(head -c 65536 "$backup_wav" | cksum | awk '{print $1}')" ]; then
                        printf "${YELLOW}replace: %s${NC}\n" "$track_dir.WAV"
                    else
                        printf "keep: %s\n" "$track_dir.WAV"
                    fi
                fi
            fi
        done

        # Prompt for confirmation
        printf "\nApply these changes? (y/N) "
        read -r response
        if [ "${response}" != "y" ] && [ "${response}" != "Y" ]; then
            log_message "Skipping changes for bank_${bank_num}" "WARNING"
            continue
        fi

        # Process approved changes
        for track_dir in $track_dirs; do
            local slot_num=${track_dir%_*}
            slot_num=$(echo "$slot_num" | sed 's/^0*//')
            local current_bank_num=$(( (10#$slot_num - 1) / 8 + 1 ))
            [ "$current_bank_num" -ne "$bank_num" ] && continue

            local wav_file="$SOURCE_DIR/$track_dir/$track_dir.WAV"
            local backup_wav="$BACKUP_DIR/$bank_dir/$track_dir.WAV"

            # Skip if directory is empty or WAV file doesn't exist
            if [ ! -f "$wav_file" ]; then
                continue
            fi

            # Create bank directory if needed
            mkdir -p "$BACKUP_DIR/$bank_dir"

            ((total_files++))

            # Copy the file if it's new or different
            if [ ! -f "$backup_wav" ] || \
               [ "$(get_file_size "$wav_file")" != "$(get_file_size "$backup_wav")" ] || \
               [ "$(head -c 65536 "$wav_file" | cksum | awk '{print $1}')" != \
                 "$(head -c 65536 "$backup_wav" | cksum | awk '{print $1}')" ]; then
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
                ((skipped_files++))
            fi
        done

        # Process deletions if user approved changes
        if [ $del_count -gt 0 ]; then
            find "$BACKUP_DIR/$bank_dir" -maxdepth 1 -name "*.WAV" -type f | while read -r backup_file; do
                local track_name=$(basename "$backup_file" .WAV)
                if [ ! -f "$SOURCE_DIR/$track_name/$track_name.WAV" ]; then
                    log_message "Deleting: $track_name.WAV from $bank_dir" "INFO"
                    rm "$backup_file"
                fi
            done
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
