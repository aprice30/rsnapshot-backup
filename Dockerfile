FROM ubuntu:24.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    docker.io \
    rsnapshot \
    rsync \
    cron \
    apt-transport-https \
    ca-certificates \
    && apt-get clean

# Add backup and entrypoint scripts
COPY rsnapshot-backup.sh /usr/local/bin/rsnapshot-backup.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/rsnapshot-backup.sh /usr/local/bin/entrypoint.sh

# Add a placeholder rsnapshot configuration (updated dynamically by the script)
COPY rsnapshot.conf /etc/rsnapshot.conf

# Set the working directory
WORKDIR /data

# Entrypoint to start cron and manage backups
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
