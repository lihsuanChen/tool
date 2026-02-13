#!/bin/bash

# Ensure execution abstraction is loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_exec.sh"

optimize_docker_storage() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # Configuration
    local TARGET_PARTITION="/var/oculan"
    local NEW_STORAGE_DIR="/var/oculan/docker-data"
    local FSTAB="/etc/fstab"

    log_step "OPTIMIZE" "Moving Docker storage to ${NEW_STORAGE_DIR} on ${TARGET_IP} (Local Mode: ${IS_LOCAL_MODE})..."

    # Construct command string
    # We use \ to escape variables that should be evaluated at runtime (Remote or Local shell)
    local REMOTE_CMDS="
    set -e

    # 1. DETECT CURRENT LOCATION
    # We ask Docker where the data root is currently set.
    CURRENT_DOCKER_DIR=\$(sudo docker info -f '{{.DockerRootDir}}')

    if [ -z \"\$CURRENT_DOCKER_DIR\" ]; then
        echo -e '\033[0;31m[Remote] Error: Could not detect Docker Root Directory. Is Docker running?\033[0m'
        exit 1
    fi

    echo \"[Remote] Detected current Docker storage at: \$CURRENT_DOCKER_DIR\"

    # 2. PRE-FLIGHT CHECKS
    if [ ! -d \"${TARGET_PARTITION}\" ]; then
        echo -e '\033[0;31m[Remote] Error: Target partition ${TARGET_PARTITION} not found.\033[0m'
        exit 1
    fi

    # Check if already mounted
    if mount | grep -q \"${NEW_STORAGE_DIR} on \$CURRENT_DOCKER_DIR\"; then
        echo -e '\033[0;32m[Remote] Success: Docker is already optimized (Mounted).\033[0m'
        exit 0
    fi

    echo -e '\033[1;33m[Remote] Starting Storage Migration...\033[0m'

    # 3. STOP DOCKER
    echo '[Remote] Stopping Docker Service...'
    sudo systemctl stop docker
    sudo systemctl stop docker.socket 2>/dev/null || true
    sleep 3

    # 4. MIGRATE DATA
    echo '[Remote] Creating target directory at ${NEW_STORAGE_DIR}...'
    sudo mkdir -p \"${NEW_STORAGE_DIR}\"

    echo \"[Remote] Copying data from \$CURRENT_DOCKER_DIR to ${NEW_STORAGE_DIR}...\"
    # -a: Archive mode
    sudo rsync -a \"\$CURRENT_DOCKER_DIR/\" \"${NEW_STORAGE_DIR}/\"

    # 5. CLEANUP OLD DATA (Free up Root Space)
    echo '[Remote] Verifying copy and cleaning old storage...'
    if [ \"\$(ls -A ${NEW_STORAGE_DIR})\" ]; then
        # Remove contents of the original folder to reclaim space
        sudo rm -rf \"\$CURRENT_DOCKER_DIR\"/*
        echo '[Remote] Old data removed from Root partition.'
    else
        echo -e '\033[0;31m[Remote] Error: Copy failed (Target empty). Aborting.\033[0m'
        exit 1
    fi

    # 6. MOUNT (BIND)
    echo \"[Remote] Mounting ${NEW_STORAGE_DIR} -> \$CURRENT_DOCKER_DIR...\"
    sudo mount --bind \"${NEW_STORAGE_DIR}\" \"\$CURRENT_DOCKER_DIR\"

    # 7. PERSISTENCE (FSTAB)
    echo '[Remote] Updating /etc/fstab...'
    if ! grep -q \"${NEW_STORAGE_DIR}\" \"${FSTAB}\"; then
        echo \"${NEW_STORAGE_DIR}    \$CURRENT_DOCKER_DIR    none    bind    0    0\" | sudo tee -a \"${FSTAB}\"
    fi

    # 8. RESTART DOCKER
    echo '[Remote] Restarting Docker...'
    sudo systemctl start docker

    echo -e '\033[0;32m[Remote] SUCCESS: Docker storage moved to ${TARGET_PARTITION}.\033[0m'
    echo -e 'Available space for Docker:'
    df -h \"\$CURRENT_DOCKER_DIR\" | tail -1
    "

    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_CMDS}" "true"
}