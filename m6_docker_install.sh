#!/bin/bash

# Ensure execution abstraction is loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_exec.sh"

install_docker_remote() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    # Pull config or set default
    local REGISTRY="${DOCKER_INSECURE_REGISTRY:-nexus.dev.sunbirddcim.com:8085}"
    local DATA_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"

    log_step "DOCKER-INSTALL" "Installing Docker on ${TARGET_IP} (Local Mode: ${IS_LOCAL_MODE})..."

    # Construct the command string.
    # We add a new Step 5 for Connectivity Check & Repair
    local REMOTE_CMDS="
    set -e

    # 1. INSTALLATION (Standard Logic)
    if ! command -v docker &> /dev/null; then
        echo '[Remote] Installing Docker...'
        if [ -f /etc/redhat-release ]; then
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        elif [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        fi
    fi

    # 2. CONFIGURE DAEMON.JSON
    echo '[Remote] Configuring /etc/docker/daemon.json...'
    sudo mkdir -p \"${DATA_ROOT}\"

    # Force overwrite to ensure config is clean
    echo '{
   \"insecure-registries\": [\"${REGISTRY}\"],
   \"data-root\": \"${DATA_ROOT}\"
}' | sudo tee /etc/docker/daemon.json > /dev/null

    # 3. RESTART SERVICE (Standard Restart)
    echo '[Remote] Restarting Docker to apply changes...'
    if command -v systemctl &> /dev/null; then
        sudo systemctl stop docker
        sudo systemctl start docker
        sudo systemctl enable docker
    else
        sudo service docker restart
    fi

    # 4. PERMISSIONS
    sudo usermod -aG docker \$(whoami)

    # ==========================================
    # 5. [NEW] NEXUS CONNECTIVITY CHECK & REPAIR
    # ==========================================
    echo '[Remote] Verifying Nexus Registry connectivity (${REGISTRY})...'

    # Try a simple connection check (timeout 3s)
    if ! curl --connect-timeout 3 -s http://${REGISTRY} > /dev/null; then
        echo -e '\033[1;33m[Remote] Warning: Connection to Nexus failed. Docker might be in a zombie state.\033[0m'
        echo '[Remote] >>> Initiating Deep Repair Mode <<<'

        # A. Hard Stop (Include Socket)
        echo '[Remote] Stopping Docker Socket & Service...'
        sudo systemctl stop docker.socket 2>/dev/null || true
        sudo systemctl stop docker

        # B. Reload Daemon (Clears some internal states)
        sudo systemctl daemon-reload

        # C. Restart
        echo '[Remote] Starting Docker Service...'
        sudo systemctl start docker

        # D. Re-Verify
        echo '[Remote] Re-verifying connectivity...'
        if curl --connect-timeout 3 -s http://${REGISTRY} > /dev/null; then
             echo -e '\033[0;32m[Remote] SUCCESS: Nexus connection restored!\033[0m'
        else
             echo -e '\033[0;31m[Remote] ERROR: Still cannot connect to Nexus. Please check your VPN or Network.\033[0m'
             # We don't exit 1 here to avoid breaking the whole flow if VPN is just off
        fi
    else
        echo -e '\033[0;32m[Remote] Nexus Connection OK.\033[0m'
    fi

    echo '[Remote] Docker Setup Complete.'
    "

    # Execute via abstraction
    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_CMDS}" "true"
}