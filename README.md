# rsnapshot-backup  

A simple wrapper around the `rsnapshot` tool to back up Docker-mounted volumes.  

## Overview  

`rsnapshot-backup` inspects running Docker containers and backs up their volumes based on labels you define. Host-mounted directories are excluded by default, while Docker volumes and NFS mounts are included.  

## Installation  

The recommended way to provision `rsnapshot-backup` is via `docker-compose`. Below is an example configuration; remember to replace `<version>` with the desired version number:  

```yaml
services:
  rsnapshot-backup:
    image: ghcr.io/aprice30/rsnapshot-backup:<version>
    container_name: rsnapshot-backup
    volumes:
      - backup:/data/backups
      - /var/run/docker.sock:/var/run/docker.sock 
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    restart: unless-stopped
volumes:
  backup:
```

## Usage  

`rsnapshot-backup` works by inspecting currently running containers and processing their labels to determine which volumes to back up.  

### Labels  

#### `rsnapshot-backup.enable`  

To include a container in the backup, add the following label:  

```yaml
labels:
  rsnapshot-backup.enable: true
```  

This will back up **all Docker volumes** associated with the container. Host-mounted directories are excluded, but NFS mounts will be included.  

#### `rsnapshot-backup.volumes`  

To back up specific volumes only, provide a comma-separated list of volume names:  

```yaml
labels:
  rsnapshot-backup.enable: true
  rsnapshot-backup.volumes: config
```  

This will restrict the backup to only the specified volumes (e.g., `config` in this example).