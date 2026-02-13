#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - DATABASE
# DESCRIPTION: Builds and runs the repository's native Migration Container.
# ==============================================================================

# Ensure execution abstraction is loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_exec.sh"

deploy_database_container() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- 1. CONTEXT DETECTION ---
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)
    local DOCKERFILE="./DevContainerFiles/dev.lb.migrate.Dockerfile"

    if [ ! -f "$DOCKERFILE" ]; then
        error_exit "Dockerfile not found at: ${DOCKERFILE}\nPlease navigate to the 'dctrack_database' git worktree."
    fi

    log_step "CONTEXT" "Detected Database Repo at: ${CURRENT_DIR}"

    # --- Remote Paths ---
    local REMOTE_BUILD_CTX="/dct_builds/db_migration_context"

    log_step "DEPLOY-DB" "Preparing Database Migration on ${TARGET_IP} (Local Mode: ${IS_LOCAL_MODE})..."

    # --- 2. EXECUTION STRATEGY ---
    echo -e "${YELLOW}Strategy: Build & Run 'dev.lb.migrate' image${NC}"

    if ! ui_confirm "Proceed with Migration?"; then
        echo "Cancelled."
        return 0
    fi

    # --- 3. SYNC LOGIC ---
    log_step "SYNC" "Syncing build context..."

    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo mkdir -p ${REMOTE_BUILD_CTX}" "false"

    # Sync sources to remote context
    sync_to_target "./src/files" "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_BUILD_CTX}/" "--delete --relative"
    sync_to_target "./DevContainerFiles" "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_BUILD_CTX}/" "--delete --relative"

    # ==============================================================================
    # [FIX] Local Mode Permission Patch
    # ==============================================================================
    if [ "$IS_LOCAL_MODE" == "true" ]; then
        if command -v sudo &> /dev/null; then sudo -v; fi
        local MY_UID=$(id -u)
        local MY_GID=$(id -g)
        run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo chown -R ${MY_UID}:${MY_GID} ${REMOTE_BUILD_CTX}" "false"
    fi

    # --- 4. BUILD & RUN LOGIC ---
    log_step "MIGRATE" "Building and Running Migration Container..."

    local REMOTE_CMDS="
        set -e
        cd ${REMOTE_BUILD_CTX}

        # 1. AUTO-DETECT NETWORK
        NETWORK_NAME=\$(sudo docker network ls --format '{{.Name}}' | grep 'collab' | head -n 1)

        if [ -z \"\$NETWORK_NAME\" ]; then
            echo -e '\033[0;31m[Remote] Error: Could not detect a *collab network.\033[0m'
            exit 1
        fi
        echo \"[Remote] Detected Network: \$NETWORK_NAME\"

        # 2. PATCH CONFIG
        CONFIG_FILE=\"./src/files/usr/local/sbin/database-config.sh\"
        if [ -f \"\$CONFIG_FILE\" ]; then
            echo '[Remote] Patching database-config.sh to use hostname \"db\"...'
            sed -i 's/localhost/db/g' \"\$CONFIG_FILE\"
            sed -i 's/127.0.0.1/db/g' \"\$CONFIG_FILE\"
        fi

        # 3. BUILD IMAGE
        echo '[Remote] Building Migration Image...'
        sudo docker build -t temp-db-migrator -f DevContainerFiles/dev.lb.migrate.Dockerfile .

        # 4. RUN MIGRATION
        echo '[Remote] Executing Migration...'
        sudo docker run --rm \\
            --network=\"\$NETWORK_NAME\" \\
            --name temp_migrator_run \\
            temp-db-migrator
    "

    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_CMDS}" "true"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Database Migration Completed!${NC}"
    else
        error_exit "Migration failed."
    fi
}