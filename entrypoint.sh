#!/bin/bash

echo "Starting rsnapshot backup"

# Set some defaults up
CRON_SCHEDULE="${CRON_SCHEDULE:-0 4 * * *}" # 4am trigger time
BACKUP_ON_START=${BACKUP_ON_START:-false}

# Ensure the cron service is running
echo "Cron schedule of $CRON_SCHEDULE"
service cron start

# Write the cron job for the backup script with the provided schedule
CRON_FILE="/etc/cron.d/backup-cron"
echo "$CRON_SCHEDULE /usr/local/bin/rsnapshot-backup.sh >> /var/log/backup.log 2>&1" > $CRON_FILE
chmod 0644 $CRON_FILE
crontab $CRON_FILE

# Ensure the log file exists
touch /var/log/backup.log

if $BACKUP_ON_START; then
    echo "Running backup on startup"
    ./usr/local/bin/rsnapshot-backup.sh
fi

# Keep the container running by tailing the log
tail -f /var/log/backup.log