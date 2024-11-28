#!/bin/bash

# Function to get containers with the label "rsnapshot-backup.enable=true"
get_backup_containers() {
    docker ps --filter "label=rsnapshot-backup.enable=true" --format "{{.Names}}"
}

# Function to resolve volume mount paths for a container
resolve_volume_paths() {
    local container=$1
    local volume_names=$2
    local resolved_paths=""

    # If no volumes are specified, fetch all Docker volumes for the container
    if [ -z "$volume_names" ]; then
        volume_names=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{" "}}{{end}}{{end}}' "$container")
    fi

    # Resolve the volume mount paths
    for volume in $(echo "$volume_names" | tr ',' ' '); do
        local volume_path
        # Ensure the volume is of type "volume" (not bind-mounted paths)
        volume_path=$(docker inspect --format '{{range .Mounts}}{{if and (eq .Name "'$volume'") (eq .Type "volume")}}{{.Source}}{{end}}{{end}}' "$container")
        if [ -z "$volume_path" ]; then
            echo "Warning: Could not resolve Docker volume $volume for container $container" >&2
            continue
        fi
        resolved_paths="$resolved_paths $volume_path"
    done

    echo "$resolved_paths"
}

# Function to rebuild the rsnapshot.conf file
rebuild_rsnapshot_conf() {
    echo "Rebuilding rsnapshot configuration..."
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

    if [ -z "$CONTAINERS" ]; then
        echo "No containers found with label rsnapshot-backup.enable=true. Exiting." >&2
        exit 0
    fi

    for container in $CONTAINERS; do
        VOLUMES=$(docker inspect --format '{{index .Config.Labels "rsnapshot-backup.volumes"}}' "$container")
        RESOLVED_PATHS=$(resolve_volume_paths "$container" "$VOLUMES")
        if [ -z "$RESOLVED_PATHS" ]; then
            echo "No valid volumes resolved for container: $container. Skipping." >&2
            continue
        fi

        for path in $RESOLVED_PATHS; do
            # Extract the volume name by removing the '_data' suffix
            volume_name=$(basename "$(dirname "$path")")
            # Append the backup configuration with the volume name as the subfolder
            echo -e "backup\t$path/\t$container/$volume_name/" >> $TEMP_CONF
            echo "Will backup $path for $container" 

            backup_points_added=true
        done
    done

    if ! $backup_points_added; then
        echo "No valid backup points found. Exiting." >&2
        exit 0
    fi

    # Add the default retain policies (with tabs)
    echo -e "retain\tdaily\t7" >> $TEMP_CONF
    echo -e "retain\tweekly\t4" >> $TEMP_CONF
    echo -e "retain\tmonthly\t6" >> $TEMP_CONF
}

# Stop containers before backup
stop_containers() {
    for container in $CONTAINERS; do
        echo "Stopping container: $container"
        docker stop "$container"
    done
}

# Restart containers after backup
start_containers() {
    for container in $CONTAINERS; do
        echo "Starting container: $container"
        docker start "$container"
    done
}

# Function to run rsnapshot commands
run_rsnapshot() {
    echo "Running rsnapshot backup..."

    echo "Running rsnapshot sync..."
    rm -rf /data/backups/.sync
    rsnapshot -c /tmp/rsnapshot.conf sync

    echo "Running rsnapshot daily..."
    rsnapshot -c /tmp/rsnapshot.conf daily

    # If it's Monday=1 then run weekly backup
    DAY_OF_WEEK=$(date +%u)
    if [ "$DAY_OF_WEEK" -eq 1 ]; then
        echo "Running rsnapshot weekly backup..."
        rsnapshot -c /tmp/rsnapshot.conf weekly
    else
        echo "Skipping weekly backup."
    fi

    # If it's Day=1 then run monthly backup
    DAY_OF_MONTH=$(date +%d)
    if [ "$DAY_OF_MONTH" -eq 01 ]; then
        echo "Running rsnapshot monthly backup..."
        rsnapshot -c /tmp/rsnapshot.conf monthly
    else
        echo "Skipping monthly backup."
    fi
}

CONTAINERS=$(get_backup_containers)

# Main execution based on command-line argument
case "$1" in
    rebuild)
        rebuild_rsnapshot_conf
        ;;
    backup)
        rebuild_rsnapshot_conf
        stop_containers
        run_rsnapshot
        start_containers
        ;;
    *)
        echo "Usage: $0 {rebuild|backup}"
        exit 1
        ;;
esac

echo "Operation completed!"