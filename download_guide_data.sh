#!/bin/bash

# ==============================================================================
# SCRIPT CONFIGURATION
# ==============================================================================
# --- Paths ---
SCRIPT_DIR="${SCRIPT_DIR:-/mnt/cache/appdata/tvguidegetter}"
PLEX_XML_PATH="${PLEX_XML_PATH:-/mnt/cache/appdata/Plex/OTA.xml}"
JELLYFIN_XML_PATH="${JELLYFIN_XML_PATH:-/mnt/cache/appdata/jellyfin/OTA.xml}"

# --- Script Details ---
SCRIPT_NAME="${SCRIPT_NAME:-HDHomeRunEPG_To_XmlTv.py}"
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/IncubusVictim/HDHomeRunEPG-to-XmlTv/main/HDHomeRunEPG_To_XmlTv.py}"
SYSLOG_SCRIPT_NAME="${SYSLOG_SCRIPT_NAME:-EPG_Updater}"

# --- Device ---
HDHOMERUN_IP="${HDHOMERUN_IP:-10.0.1.128}"

# --- Permissions ---
FILE_OWNER="${FILE_OWNER:-nobody:users}"

# --- Backups ---
MAX_BACKUPS="${MAX_BACKUPS:-5}"

# ==============================================================================
# INTERNAL VARIABLES (DO NOT MODIFY)
# ==============================================================================
LOCAL_SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
LOG_FILE="${SCRIPT_DIR}/epg_update.log"
LOCK_FILE="${SCRIPT_DIR}/epg_update.lock"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TMP_XML_PATH="${SCRIPT_DIR}/OTA.xml.tmp"
TMP_PY_SCRIPT_PATH=$(mktemp)
SCRIPT_STATUS="SUCCESS"
SCRIPT_DETAILS=""

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# --- Logging ---
log() {
    local level="$1"
    local message="$2"
    local log_entry
    log_entry="$(date '+%Y-%m-%d %H:%M:%S') [$level] $message"
    echo "$log_entry"
    echo "$log_entry" >> "$LOG_FILE"
}
info() { log "INFO" "$1"; }
warn() { log "WARN" "$1"; }
error() {
    log "ERROR" "$1"
    if [[ "$SCRIPT_STATUS" == "SUCCESS" ]]; then
        SCRIPT_STATUS="FAILURE"
        SCRIPT_DETAILS="$1"
    fi
}

# --- File and Process Management ---
cleanup() {
    info "Running cleanup..."
    rm -f "$TMP_PY_SCRIPT_PATH"
    rm -f "$TMP_XML_PATH"
    rm -f "$LOCK_FILE"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    local syslog_message
    if [[ "$SCRIPT_STATUS" == "SUCCESS" ]]; then
        if [[ -z "$SCRIPT_DETAILS" ]]; then
            SCRIPT_DETAILS="All EPG data updated successfully."
        fi
        syslog_message="${SYSLOG_SCRIPT_NAME} - [SUCCESS] ${SCRIPT_DETAILS} at ${timestamp}"
    else
        syslog_message="${SYSLOG_SCRIPT_NAME} - [FAILURE] ${SCRIPT_DETAILS} at ${timestamp}"
    fi
    logger -t "root" "$syslog_message"
    info "Final status message sent to syslog."
    info "Cleanup finished."
}

check_lock() {
    if [ -e "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE")
        if ps -p "$pid" > /dev/null; then
            error "Lock file exists and process $pid is running. Aborting."
            exit 1
        else
            warn "Stale lock file found. Removing."
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

check_directories() {
    info "Checking if required directories exist..."
    for dir in "$SCRIPT_DIR" "$BACKUP_DIR"; do
        if ! mkdir -p "$dir"; then
            error "Failed to create directory '$dir'"
            exit 4
        fi
    done
    info "Directories verified."
    return 0
}

download_script() {
    info "Attempting to download script from ${SCRIPT_URL}"
    if curl -sSfL -o "$TMP_PY_SCRIPT_PATH" "$SCRIPT_URL"; then
        info "Download successful"
        return 0
    else
        warn "Failed to download script"
        return 1
    fi
}

backup_xml() {
    local file_to_backup="$1"
    if [[ ! -f "$file_to_backup" ]]; then
        info "No existing file at '$file_to_backup' to back up."
        return
    fi
    local filename
    filename=$(basename "$file_to_backup")
    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local backup_file="${BACKUP_DIR}/${filename}_${timestamp}.bak"
    info "Backing up '$file_to_backup' to '$backup_file'"
    cp -p "$file_to_backup" "$backup_file"
    info "Pruning old backups for ${filename}, keeping last ${MAX_BACKUPS}..."
    find "$BACKUP_DIR" -name "${filename}_*.bak" -print0 | xargs -0 ls -t | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================
main() {
    trap cleanup EXIT
    
    check_directories || exit 4
    
    info "=================================================="
    info "Starting EPG update process..."
    
    check_lock
    
    local required_cmds=(curl /usr/local/bin/python cmp logger chown cp mktemp stat find xargs)
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command '$cmd' not found"
            exit 3
        fi
    done
    
    info "Checking for new version of ${SCRIPT_NAME}..."
    if ! download_script; then
        if [[ -f "$LOCAL_SCRIPT_PATH" ]]; then
            warn "Download failed. Proceeding with existing local script."
        else
            error "Download failed and no local script exists."
            exit 5
        fi
    elif [[ ! -f "$LOCAL_SCRIPT_PATH" ]] || ! cmp -s "$TMP_PY_SCRIPT_PATH" "$LOCAL_SCRIPT_PATH"; then
        info "New version found. Updating local script."
        mv "$TMP_PY_SCRIPT_PATH" "$LOCAL_SCRIPT_PATH"
        chmod +x "$LOCAL_SCRIPT_PATH"
        info "Successfully updated ${SCRIPT_NAME}."
    else
        info "Local script is already up to date."
        rm -f "$TMP_PY_SCRIPT_PATH"
    fi

    info "Verifying Python dependencies..."
    if ! /usr/local/bin/python -c "import requests" &>/dev/null; then
        info "'requests' module not found. Attempting to install with pip..."
        if /usr/local/bin/python -m pip install requests; then
            info "'requests' installed successfully."
        else
            error "Failed to install 'requests' with pip. Please install it manually and try again."
            exit 9
        fi
    else
        info "'requests' module is already installed."
    fi
    
    info "Running Python script to generate EPG data into temporary file..."
    local python_output
    local retries=3
    local wait_time=30
    local attempt=1
    
    while [[ $attempt -le $retries ]]; do
        # <<< CRITICAL CHANGE HERE: Use --filename instead of --output
        if python_output=$(/usr/local/bin/python "$LOCAL_SCRIPT_PATH" --host "$HDHOMERUN_IP" --filename "$TMP_XML_PATH" 2>&1); then
            info "Python script completed successfully on attempt $attempt."
            if [ -s "$TMP_XML_PATH" ]; then
                info "Temporary EPG file created successfully at ${TMP_XML_PATH}."
                break
            else
                error "Python script ran but created an empty EPG file. Output: $python_output"
            fi
        fi
        
        warn "Python script failed on attempt $attempt. Output: $python_output"
        if [[ $attempt -eq $retries ]]; then
            error "Python script failed to generate a valid EPG file after $retries attempts. Aborting."
            exit 6
        fi
        
        warn "Waiting ${wait_time}s before retry..."
        sleep "$wait_time"
        ((attempt++))
    done

    info "Deploying EPG file to Plex and Jellyfin..."
    
    backup_xml "$PLEX_XML_PATH"
    backup_xml "$JELLYFIN_XML_PATH"

    info "Copying EPG data to Plex directory..."
    if ! cp -p "$TMP_XML_PATH" "$PLEX_XML_PATH"; then
        error "Failed to copy EPG data to Plex directory."
        exit 7
    fi

    info "Copying EPG data to Jellyfin directory..."
    if ! cp -p "$TMP_XML_PATH" "$JELLYFIN_XML_PATH"; then
        error "Failed to copy EPG data to Jellyfin directory."
        exit 7
    fi
    
    info "Setting file ownership for EPG files..."
    if ! chown "$FILE_OWNER" "$PLEX_XML_PATH" "$JELLYFIN_XML_PATH"; then
        error "Failed to set file ownership."
        exit 8
    fi
    
    SCRIPT_DETAILS="EPG data for Plex and Jellyfin updated successfully."
    info "EPG update process completed successfully."
    info "=================================================="
}

# --- Run the main function ---
main "$@"