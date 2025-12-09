#!/bin/bash
#
# PostgreSQL Backup Script
# Creates timestamped backups using pg_dump
#

set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Configuration
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:?POSTGRES_USER is required - set in .env file}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required - set in .env file}"
POSTGRES_DB="${POSTGRES_DB:-production_db}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# Create directories if they don't exist
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Timestamp for backup file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/${POSTGRES_DB}_backup_${TIMESTAMP}.sql.gz"
LOG_FILE="$LOG_DIR/backup_${TIMESTAMP}.log"

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

log "=========================================="
log "PostgreSQL Backup Started"
log "=========================================="
log "Database: $POSTGRES_DB"
log "Host: $POSTGRES_HOST:$POSTGRES_PORT"
log "Backup file: $BACKUP_FILE"

# Check if PostgreSQL is accessible
log "Checking database connectivity..."
export PGPASSWORD="$POSTGRES_PASSWORD"

if ! pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" > /dev/null 2>&1; then
    error_exit "Cannot connect to PostgreSQL server at $POSTGRES_HOST:$POSTGRES_PORT"
fi

log "Database connection successful"

# Perform backup
log "Starting pg_dump..."
START_TIME=$(date +%s)

if pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    --format=plain --no-owner --no-acl | gzip > "$BACKUP_FILE"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

    log "Backup completed successfully"
    log "Duration: ${DURATION} seconds"
    log "Backup size: $BACKUP_SIZE"
else
    error_exit "pg_dump failed"
fi

# Verify backup integrity
log "Verifying backup integrity..."
if gzip -t "$BACKUP_FILE" 2>/dev/null; then
    log "Backup integrity verified (gzip test passed)"
else
    error_exit "Backup integrity check failed"
fi

# Clean up old local backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED_COUNT=$(find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete -print | wc -l)
log "Deleted $DELETED_COUNT old backup(s)"

log "=========================================="
log "Backup process completed successfully"
log "=========================================="

# Output backup file path for use by upload script
echo "$BACKUP_FILE"
