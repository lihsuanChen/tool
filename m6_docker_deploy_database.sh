#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - DATABASE
# DESCRIPTION: Builds and runs the repository's native Migration Container.
# ==============================================================================

deploy_database_container() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- 1. CONTEXT DETECTION ---
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)

    # Verify we have the Dockerfile and Source files
    local DOCKERFILE="./DevContainerFiles/dev.lb.migrate.Dockerfile"
    local SRC_FILES="./src/files"

    if [ ! -f "$DOCKERFILE" ]; then
        error_exit "Dockerfile not found at: ${DOCKERFILE}\nPlease navigate to the 'dctrack_database' git worktree."
    fi

    log_step "CONTEXT" "Detected Database Repo at: ${CURRENT_DIR}"

    # --- Remote Paths ---
    local REMOTE_BUILD_CTX="/dct_builds/db_migration_context"

    log_step "DEPLOY-DB" "Preparing Database Migration on ${TARGET_IP}..."

    # --- 2. EXECUTION STRATEGY ---
    echo -e "${YELLOW}Strategy: Build & Run 'dev.lb.migrate' image${NC}"
    echo -e "This uses the logic defined in 03-database-migrate.sh (Tables, Functions, Views...)"

    if ! ui_confirm "Proceed with Migration?"; then
        echo "Cancelled."
        return 0
    fi

    # --- 3. SYNC LOGIC ---
    log_step "SYNC" "Syncing build context..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "sudo mkdir -p ${REMOTE_BUILD_CTX}"

    # We need 'src/files' and 'DevContainerFiles' to build the image
    # We sync them to a clean context folder on the remote
    rsync -avz -e ssh --delete --relative \
        "./src/files" \
        "./DevContainerFiles" \
        "${REMOTE_USER}@${TARGET_IP}:${REMOTE_BUILD_CTX}/"

    # --- 4. BUILD & RUN LOGIC ---
    log_step "MIGRATE" "Building and Running Migration Container..."

    ssh -t "${REMOTE_USER}@${TARGET_IP}" "
        set -e
        cd ${REMOTE_BUILD_CTX}

        # 1. AUTO-DETECT NETWORK
        NETWORK_NAME=\$(sudo docker network ls --format '{{.Name}}' | grep 'collab' | head -n 1)

        if [ -z \"\$NETWORK_NAME\" ]; then
            echo -e '\033[0;31m[Remote] Error: Could not detect a *collab network.\033[0m'
            exit 1
        fi
        echo \"[Remote] Detected Network: \$NETWORK_NAME\"

        # 2. PATCH CONFIG (Crucial for Docker Networking)
        # Ensure the script points to the 'db' container, not localhost
        CONFIG_FILE=\"./src/files/usr/local/sbin/database-config.sh\"
        if [ -f \"\$CONFIG_FILE\" ]; then
            echo '[Remote] Patching database-config.sh to use hostname \"db\"...'
            # Replace localhost or 127.0.0.1 with 'db' (the docker service name)
            sed -i 's/localhost/db/g' \"\$CONFIG_FILE\"
            sed -i 's/127.0.0.1/db/g' \"\$CONFIG_FILE\"
        fi

        # 3. BUILD IMAGE
        echo '[Remote] Building Migration Image...'
        sudo docker build -t temp-db-migrator -f DevContainerFiles/dev.lb.migrate.Dockerfile .

        # 4. RUN MIGRATION
        echo '[Remote] Executing Migration...'
        # We run on the detected network so we can reach 'db:5432'
        sudo docker run --rm \\
            --network=\"\$NETWORK_NAME\" \\
            --name temp_migrator_run \\
            temp-db-migrator
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Database Migration Completed!${NC}"
    else
        error_exit "Migration failed."
    fi
}