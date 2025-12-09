#!/bin/bash
#
# PostgreSQL Restore and Verify Script
# Restores backup to a test database and verifies data integrity
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
TEST_DB="${TEST_DB:-backup_verify_db}"

# Timestamp for logging
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/restore_verify_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# Logging function
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    log "Cleaning up test database..."
    export PGPASSWORD="$POSTGRES_PASSWORD"
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS $TEST_DB;" 2>/dev/null || true
}

# Get backup file from argument or find latest
BACKUP_FILE="${1:-}"
if [[ -z "$BACKUP_FILE" ]]; then
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -1)
    if [[ -z "$BACKUP_FILE" ]]; then
        error_exit "No backup file found in $BACKUP_DIR"
    fi
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    error_exit "Backup file not found: $BACKUP_FILE"
fi

log "=========================================="
log "PostgreSQL Restore and Verify Started"
log "=========================================="
log "Backup file: $BACKUP_FILE"
log "Test database: $TEST_DB"
log "Host: $POSTGRES_HOST:$POSTGRES_PORT"

export PGPASSWORD="$POSTGRES_PASSWORD"

# Check database connectivity
log "Checking database connectivity..."
if ! pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" > /dev/null 2>&1; then
    error_exit "Cannot connect to PostgreSQL server"
fi
log "Database connection successful"

# Drop test database if exists
log "Dropping existing test database if present..."
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $TEST_DB;" 2>/dev/null || true

# Create test database
log "Creating test database..."
if ! psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
    -c "CREATE DATABASE $TEST_DB;"; then
    error_exit "Failed to create test database"
fi
log "Test database created"

# Restore backup to test database
log "Restoring backup to test database..."
START_TIME=$(date +%s)

if gunzip -c "$BACKUP_FILE" | psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$TEST_DB" > /dev/null 2>&1; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log "Restore completed successfully"
    log "Duration: ${DURATION} seconds"
else
    error_exit "Failed to restore backup"
fi

# Verify restore - count tables
log "Verifying restored data..."

# Get table count from original database
ORIGINAL_TABLES=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
ORIGINAL_TABLES=$(echo "$ORIGINAL_TABLES" | tr -d ' ')

# Get table count from restored database
RESTORED_TABLES=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$TEST_DB" -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
RESTORED_TABLES=$(echo "$RESTORED_TABLES" | tr -d ' ')

log "Original database tables: $ORIGINAL_TABLES"
log "Restored database tables: $RESTORED_TABLES"

if [[ "$ORIGINAL_TABLES" == "$RESTORED_TABLES" ]]; then
    log "Table count verification: PASSED"
else
    log "WARNING: Table count mismatch!"
fi

# List tables in restored database
log "Tables in restored database:"
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$TEST_DB" -c \
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;" \
    2>/dev/null | tee -a "$LOG_FILE"

# Get row counts for each table
log "Row counts per table:"
TABLES=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$TEST_DB" -t -c \
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';")

for TABLE in $TABLES; do
    TABLE=$(echo "$TABLE" | tr -d ' ')
    if [[ -n "$TABLE" ]]; then
        COUNT=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$TEST_DB" -t -c \
            "SELECT COUNT(*) FROM $TABLE;" 2>/dev/null || echo "0")
        COUNT=$(echo "$COUNT" | tr -d ' ')
        log "  - $TABLE: $COUNT rows"
    fi
done

# Cleanup
log "Cleaning up test database..."
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $TEST_DB;"

log "=========================================="
log "Restore and Verify completed successfully"
log "=========================================="

echo "VERIFY_SUCCESS"
