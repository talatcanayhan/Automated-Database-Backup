#!/bin/bash
#
# Azure Blob Storage Upload Script
# Uploads backup files to Azure Blob Storage using SAS Token
#

set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Configuration
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
AZURE_CONTAINER_NAME="${AZURE_CONTAINER_NAME:-pg-backups}"
AZURE_SAS_TOKEN="${AZURE_SAS_TOKEN:-}"

# Timestamp for logging
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/upload_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# Logging function
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check required parameters
if [[ -z "$AZURE_STORAGE_ACCOUNT" ]]; then
    error_exit "AZURE_STORAGE_ACCOUNT is not set"
fi

if [[ -z "$AZURE_SAS_TOKEN" ]]; then
    error_exit "AZURE_SAS_TOKEN is not set"
fi

# Get backup file from argument or find latest
BACKUP_FILE="${1:-}"
if [[ -z "$BACKUP_FILE" ]]; then
    BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)
    if [[ -z "$BACKUP_FILE" ]]; then
        error_exit "No backup file found in $BACKUP_DIR"
    fi
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    error_exit "Backup file not found: $BACKUP_FILE"
fi

BLOB_NAME=$(basename "$BACKUP_FILE")
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

log "=========================================="
log "Azure Blob Storage Upload Started"
log "=========================================="
log "Storage Account: $AZURE_STORAGE_ACCOUNT"
log "Container: $AZURE_CONTAINER_NAME"
log "Backup file: $BACKUP_FILE"
log "Blob name: $BLOB_NAME"
log "File size: $BACKUP_SIZE"

# Construct the blob URL
BLOB_URL="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER_NAME}/${BLOB_NAME}?${AZURE_SAS_TOKEN}"

# Upload using curl
log "Uploading to Azure Blob Storage..."
START_TIME=$(date +%s)

HTTP_RESPONSE=$(curl -s -w "%{http_code}" -X PUT \
    -H "x-ms-blob-type: BlockBlob" \
    -H "Content-Type: application/gzip" \
    --data-binary "@$BACKUP_FILE" \
    "$BLOB_URL")

HTTP_CODE="${HTTP_RESPONSE: -3}"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [[ "$HTTP_CODE" == "201" ]]; then
    log "Upload completed successfully"
    log "HTTP Status: $HTTP_CODE (Created)"
    log "Duration: ${DURATION} seconds"

    # Log the blob URL (without SAS token for security)
    log "Blob URL: https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER_NAME}/${BLOB_NAME}"
else
    log "HTTP Status: $HTTP_CODE"
    log "Response: ${HTTP_RESPONSE:0:-3}"
    error_exit "Upload failed with HTTP status $HTTP_CODE"
fi

log "=========================================="
log "Upload process completed successfully"
log "=========================================="
