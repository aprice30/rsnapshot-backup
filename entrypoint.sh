#!/bin/bash

# Ensure the cron service is running
service cron start

# Write the cron job for the backup script
CRON_FILE="/etc/cron.d/backup-cron"
echo "0 4 * * * root /usr/local/bin/rsnapshot-backup.sh >> /var/log/backup.log 2>&1" > $CRON_FILE
chmod 0644 $CRON_FILE
crontab $CRON_FILE

# Ensure the log file exists
touch /var/log/backup.log

# Keep the container running by tailing the log
tail -f /var/log/backup.log
