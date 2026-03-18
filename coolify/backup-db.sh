#!/usr/bin/env bash
#
# Wellvo — Automated PostgreSQL Backup Script
# Schedule via cron: 0 3 * * * /opt/wellvo/coolify/backup-db.sh
#
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/wellvo}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DATABASE_URL="${DATABASE_URL:?DATABASE_URL environment variable is required}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/wellvo-backup-${TIMESTAMP}.sql.gz"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

echo "[$(date -Iseconds)] Starting Wellvo database backup..."

# Run pg_dump with compression
pg_dump "${DATABASE_URL}" --no-owner --no-acl --compress=9 -f "${BACKUP_FILE}"

# Validate backup is non-empty
FILESIZE=$(stat -c%s "${BACKUP_FILE}" 2>/dev/null || stat -f%z "${BACKUP_FILE}" 2>/dev/null)
if [ "${FILESIZE}" -lt 100 ]; then
  echo "[$(date -Iseconds)] ERROR: Backup file is suspiciously small (${FILESIZE} bytes). Aborting cleanup."
  exit 1
fi

echo "[$(date -Iseconds)] Backup complete: ${BACKUP_FILE} ($(numfmt --to=iec ${FILESIZE}))"

# Remove backups older than retention period
DELETED=$(find "${BACKUP_DIR}" -name "wellvo-backup-*.sql.gz" -mtime +${RETENTION_DAYS} -print -delete | wc -l)
if [ "${DELETED}" -gt 0 ]; then
  echo "[$(date -Iseconds)] Cleaned up ${DELETED} backup(s) older than ${RETENTION_DAYS} days"
fi

echo "[$(date -Iseconds)] Backup process finished. Current backups:"
ls -lh "${BACKUP_DIR}"/wellvo-backup-*.sql.gz 2>/dev/null | tail -5
