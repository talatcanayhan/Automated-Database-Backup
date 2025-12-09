#!/bin/bash
#
# Cron Setup Script
# Configures daily automated backups
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_SCRIPT="$SCRIPT_DIR/full_backup_workflow.sh"

# Default: Run daily at 2:00 AM
CRON_SCHEDULE="${1:-0 2 * * *}"

echo "Setting up cron job for PostgreSQL backup..."
echo "Schedule: $CRON_SCHEDULE"
echo "Script: $WORKFLOW_SCRIPT"

# Make scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# Create cron entry
CRON_ENTRY="$CRON_SCHEDULE $WORKFLOW_SCRIPT >> $SCRIPT_DIR/../logs/cron.log 2>&1"

# Check if cron job already exists
EXISTING_CRON=$(crontab -l 2>/dev/null | grep -F "$WORKFLOW_SCRIPT" || true)

if [[ -n "$EXISTING_CRON" ]]; then
    echo "Cron job already exists:"
    echo "$EXISTING_CRON"
    read -p "Replace existing cron job? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi
    # Remove existing entry
    crontab -l 2>/dev/null | grep -v -F "$WORKFLOW_SCRIPT" | crontab -
fi

# Add new cron entry
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

echo ""
echo "Cron job installed successfully!"
echo ""
echo "Current crontab entries:"
crontab -l

echo ""
echo "To view logs: tail -f $SCRIPT_DIR/../logs/cron.log"
echo "To remove: crontab -e (and delete the backup line)"
