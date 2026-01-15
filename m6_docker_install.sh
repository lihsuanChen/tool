#!/bin/bash

install_docker_remote() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    # Pull config or set default
    local REGISTRY="${DOCKER_INSECURE_REGISTRY:-nexus.dev.sunbirddcim.com:8085}"
    local DATA_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"

    log_step "DOCKER-INSTALL" "Installing Docker on ${TARGET_IP}..."

    ssh -t "${REMOTE_USER}@${TARGET_IP}" "bash -s" << EOF
    set -e

    # 1. INSTALLATION (Standard Logic)
    if ! command -v docker &> /dev/null; then
        echo "[Remote] Installing Docker..."
        # (Simplified for brevity - assuming standard Rocky/Ubuntu logic from previous step)
        if [ -f /etc/redhat-release ]; then
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        elif [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        fi
    fi

    # 2. CONFIGURE DAEMON.JSON (From your Stale Doc)
    echo "[Remote] Configuring /etc/docker/daemon.json..."

    # Create the directory structure needed
    sudo mkdir -p "${DATA_ROOT}"

    # Write the config
    sudo tee /etc/docker/daemon.json > /dev/null <<JSON
{
   "insecure-registries": ["${REGISTRY}"],
   "data-root": "${DATA_ROOT}"
}
JSON

    # 3. RESTART SERVICE
    echo "[Remote] Restarting Docker to apply changes..."
    sudo systemctl stop docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # 4. PERMISSIONS
    sudo usermod -aG docker \$(whoami)

    echo "[Remote] Docker Setup Complete."
EOF
}