#!/bin/bash
#
# Full Backup Workflow Script
# Orchestrates: Backup -> Verify -> Upload to Azure
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WORKFLOW_LOG="$LOG_DIR/workflow_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# Logging function
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$WORKFLOW_LOG"
}

log "=========================================="
log "FULL BACKUP WORKFLOW STARTED"
log "=========================================="

# Step 1: Create backup
log "Step 1: Creating database backup..."
BACKUP_FILE=$("$SCRIPT_DIR/backup.sh" | tail -1)

if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
    log "ERROR: Backup failed - no backup file created"
    exit 1
fi
log "Backup created: $BACKUP_FILE"

# Step 2: Restore and verify
log "Step 2: Restoring and verifying backup..."
VERIFY_RESULT=$("$SCRIPT_DIR/restore_and_verify.sh" "$BACKUP_FILE" | tail -1)

if [[ "$VERIFY_RESULT" != "VERIFY_SUCCESS" ]]; then
    log "ERROR: Backup verification failed"
    exit 1
fi
log "Backup verification passed"

# Step 3: Upload to Azure
log "Step 3: Uploading to Azure Blob Storage..."
"$SCRIPT_DIR/upload_to_azure.sh" "$BACKUP_FILE"

if [[ $? -ne 0 ]]; then
    log "ERROR: Azure upload failed"
    exit 1
fi
log "Azure upload completed"

log "=========================================="
log "FULL BACKUP WORKFLOW COMPLETED SUCCESSFULLY"
log "=========================================="

# Send success notification (optional - can be extended)
log "Backup workflow finished at $(date)"
