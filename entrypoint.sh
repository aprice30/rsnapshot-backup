#!/bin/bash

# Default schedule is 4 AM daily if CRON_SCHEDULE is not set
CRON_SCHEDULE="${CRON_SCHEDULE:-0 4 * * *}"

# Ensure the cron service is running
echo "Cron schedule: $CRON_SCHEDULE"
service cron start

# Write the cron job for the backup script with the provided schedule
CRON_FILE="/etc/cron.d/backup-cron"
echo "$CRON_SCHEDULE root /usr/local/bin/rsnapshot-backup.sh >> /var/log/backup.log 2>&1" > $CRON_FILE
chmod 0644 $CRON_FILE
crontab $CRON_FILE

# Ensure the log file exists
touch /var/log/backup.log

# Keep the container running by tailing the log
tail -f /var/log/backup.log