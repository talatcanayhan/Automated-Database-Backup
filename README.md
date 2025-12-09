# Automated Database Backup

Automated PostgreSQL backup system with verification and Azure Blob Storage upload.

## Features

- Automated backups using `pg_dump`
- Backup verification via restore to test database
- Azure Blob Storage upload
- Cron scheduling support
- Configurable retention policy

## Setup

1. Copy `.env.example` to `.env` and fill in your credentials:
   ```bash
   cp .env.example .env
   ```

2. Start the PostgreSQL container:
   ```bash
   cd docker && docker-compose up -d
   ```

3. Run a backup:
   ```bash
   ./scripts/backup.sh
   ```

## Scripts

| Script | Description |
|--------|-------------|
| `backup.sh` | Creates compressed database backup |
| `restore_and_verify.sh` | Verifies backup by restoring to test database |
| `upload_to_azure.sh` | Uploads backup to Azure Blob Storage |
| `full_backup_workflow.sh` | Runs complete backup pipeline |
| `setup_cron.sh` | Configures automated daily backups |

## Configuration

All configuration is done via environment variables. See `.env.example` for available options.

## License

MIT
