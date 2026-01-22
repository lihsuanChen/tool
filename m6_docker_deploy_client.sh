#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - CLIENT (Angular/Node)
# DESCRIPTION: Context-aware build & sync for Client logic.
# ==============================================================================

deploy_client_container() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- 1. CONTEXT DETECTION & PRE-FLIGHT CHECK ---
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)
    local LOCAL_DIST="${CURRENT_DIR}/dist"

    if [ -f "./package.json" ]; then
        log_step "CONTEXT" "Detected Client Root at: ${CURRENT_DIR}"
    else
        error_exit "No 'package.json' found in ${CURRENT_DIR}.\nPlease navigate to your Client git worktree before deploying."
    fi

    # --- Remote Paths ---
    local REMOTE_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"
    local REMOTE_CONFIG_DIR="${REMOTE_ROOT}/platform/Docker/Dev"
    local REMOTE_CLIENT_DIR="/dct_builds/dctrack_app_client"

    log_step "DEPLOY-CLIENT" "Preparing Client (Angular) deployment to ${TARGET_IP}..."

    # --- 2. VERSION SELECTION ---
    echo -e "${YELLOW}Select Client Version to Build:${NC}"
    local CLIENT_VER
    CLIENT_VER=$(ui_choose "9.4.0" "9.3.5" "9.3.0" "9.2.0")
    echo -e "Target Version: ${GREEN}${CLIENT_VER}${NC}"

    # --- 3. BUILD LOGIC ---
    if ui_confirm "Build Client Code now?"; then
        # Smart Dependency Check
        if [ ! -d "./node_modules" ]; then
            echo -e "${YELLOW}Installing dependencies...${NC}"
            npm install
        fi
        # Specific fix for legacy node-sass issues
        if grep -q "\"node-sass\"" package.json; then
            echo -e "${BLUE}Rebuilding node-sass...${NC}"
            npm rebuild node-sass
        fi

        echo -e "${BLUE}Running Build for ${CLIENT_VER}...${NC}"
        npm run source-map -- --env version="${CLIENT_VER}"
        if [ $? -ne 0 ]; then error_exit "npm build failed."; fi
    else
        echo "Skipping build (using existing dist)..."
    fi

    # Verify Dist Exists
    if [ ! -d "$LOCAL_DIST" ]; then
        error_exit "Dist folder not found at: ${LOCAL_DIST}\nDid the build fail?"
    fi

    # --- 4. SYNC LOGIC ---
    log_step "SYNC" "Syncing Client 'dist' folder..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "sudo mkdir -p ${REMOTE_CLIENT_DIR}"

    # Sync contents of ./dist/ to remote .../dist/
    rsync -avz -e ssh --delete "${LOCAL_DIST}" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_CLIENT_DIR}/"

    # --- 5. DOCKER CONFIG & RESTART ---
    ssh -t "${REMOTE_USER}@${TARGET_IP}" "
        cd ${REMOTE_CONFIG_DIR}

        # Inject Volume Logic
        if ! grep -q \"/dct_builds/dctrack_app_client/dist\" docker-compose.yml; then
            echo '[Remote] Adding Client Volume to docker-compose.yml...'
            # Insert after web_assets public volume mapping
            sed -i '\|web_assets:/opt/raritan/polaris/rails/main/public/|a \      - /dct_builds/dctrack_app_client/dist:/opt/raritan/dcTrack/appClient/' docker-compose.yml
        else
             # Ensure it is uncommented
             sed -i '\|/dct_builds/dctrack_app_client/dist|s/^\( *\)- /\1# - /' docker-compose.yml
             sed -i '\|/dct_builds/dctrack_app_client/dist|s/^\( *\)# - /\1- /' docker-compose.yml
        fi

        echo '[Remote] Restarting WebAssets Container...'
        sudo docker compose up -d webassets
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Client Code Deployed!${NC}"
    else
        error_exit "Client deployment failed."
    fi
}