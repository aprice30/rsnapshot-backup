#!/bin/bash
echo "Running Backup for docker containers..."

# Function to get containers with the label "rsnapshot-backup.enable=true"
get_backup_containers() {
    docker ps --filter "label=rsnapshot-backup.enable=true" --format "{{.Names}}"
}

# Function to resolve volume mount paths for a container
resolve_volume_paths() {
    local container=$1
    local volume_names=$2
    local resolved_paths=""

    for volume in $(echo "$volume_names" | tr ',' ' '); do
        # Resolve the volume mount point using docker inspect
        local volume_path
        volume_path=$(docker inspect --format '{{range .Mounts}}{{if eq .Name "'$volume'"}}{{.Source}}{{end}}{{end}}' "$container")
        if [ -z "$volume_path" ]; then
            echo "Warning: Could not resolve volume $volume for container $container" >&2
            continue
        fi
        resolved_paths="$resolved_paths $volume_path"
    done

    echo "$resolved_paths"
}

# Get the list of containers to backup
CONTAINERS=$(get_backup_containers)

if [ -z "$CONTAINERS" ]; then
    echo "No containers found with label rsnapshot-backup.enable=true. Exiting.">&2
    exit 0
fi

# Temporary rsnapshot.conf path
TEMP_CONF="/tmp/rsnapshot.conf"

# Start creating the rsnapshot configuration with proper tabs
echo -e "config_version\t1.2" > $TEMP_CONF
echo -e "snapshot_root\t/data/backups/" >> $TEMP_CONF
echo -e "no_create_root\t1" >> $TEMP_CONF
echo -e "cmd_rsync\t/usr/bin/rsync" >> $TEMP_CONF
echo -e "sync_first\t1" >> $TEMP_CONF
echo -e "rsync_long_args\t--delete\t--numeric-ids\t--relative\t--delete-excluded\t--exclude=.sync\t--inplace\t--partial" >> $TEMP_CONF
echo -e "rsync_short_args\t-rlptDv" >> $TEMP_CONF

# Include container volumes in rsnapshot conf
backup_points_added=false
for container in $CONTAINERS; do
    # Get the backup volumes for this container
    VOLUMES=$(docker inspect --format '{{index .Config.Labels "rsnapshot-backup.volumes"}}' "$container")
    if [ -z "$VOLUMES" ]; then
        echo "No volumes specified for container: $container. Skipping.">&2
        continue
    fi

    # Resolve the actual paths of the volumes
    RESOLVED_PATHS=$(resolve_volume_paths "$container" "$VOLUMES")
    if [ -z "$RESOLVED_PATHS" ]; then
        echo "No valid volumes resolved for container: $container. Skipping.">&2
        continue
    fi

    # Add resolved paths to snapshot configuration
    for path in $RESOLVED_PATHS; do
        echo -e "backup\t$path/\t$container/" >> $TEMP_CONF
        backup_points_added=true
    done
done

# Check if any backup points were added
if ! $backup_points_added; then
    echo "No valid backup points found. Exiting.">&2
    exit 0
fi

# Stop containers before backup
for container in $CONTAINERS; do
    echo "Stopping container: $container"
    docker stop $container
done

# Add the default retain policies (with tabs)
echo -e "retain\tdaily\t7" >> $TEMP_CONF
echo -e "retain\tweekly\t4" >> $TEMP_CONF
echo -e "retain\tmonthly\t6" >> $TEMP_CONF

# Run rsnapshot
echo "Starting rsnapshot backup..."

echo "Running rsnapshot sync..."
rm -rf /data/backups/.sync
rsnapshot -c $TEMP_CONF sync

echo "Running rsnapshot daily..."
rsnapshot -c $TEMP_CONF daily

# If its Monday=1 then run weekly backup
DAY_OF_WEEK=$(date +%u)
if [ "$DAY_OF_WEEK" -eq 1 ]; then
    echo "Running rsnapshot weekly backup..."
    rsnapshot -c $TEMP_CONF weekly
else
    echo "Skipping weekly backup."
fi

# If its Day=1 then run monthly backup
DAY_OF_MONTH=$(date +%d)
if [ "$DAY_OF_MONTH" -eq 01 ]; then
    echo "Running rsnapshot monthly backup..."
    rsnapshot -c $TEMP_CONF monthly
else
    echo "Skipping monthly backup."
fi

# Restart containers
for container in $CONTAINERS; do
    echo "Starting container: $container"
    docker start "$container"
done

echo "Backup completed!"
