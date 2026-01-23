#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - SERVER
# DESCRIPTION: Context-aware build & sync for Java/Tomcat.
# ==============================================================================

deploy_server_container() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- 1. STRICT CONTEXT VALIDATION (Match m5_process_deploy.sh) ---
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)
    local BASENAME
    BASENAME=$(basename "$CURRENT_DIR")

    # Fingerprint: Folder is named 'server' AND contains 'dcTrackApp'
    if [ "$BASENAME" == "server" ] && [ -d "./dcTrackApp" ]; then
        log_step "CONTEXT" "Detected Server Root at: ${CURRENT_DIR}"
    else
        echo -e "${RED}CRITICAL ERROR: Invalid Repository Context${NC}"
        echo "Current directory: $CURRENT_DIR"
        echo "Could not identify the project type based on files."
        echo "Required Fingerprint for Docker Server Deploy:"
        echo -e "  Folder 'server' + 'dcTrackApp' subfolder"
        exit 1
    fi

    # --- 2. DEFINE PATHS ---
    # Since we passed validation, we know exactly where we are.
    local LOCAL_ARTIFACT_WAR="${CURRENT_DIR}/dcTrackApp/target/dcTrackApp.war"
    local STAGING_DIR="${CURRENT_DIR}/dcTrackApp/target/_docker_stage"

    # --- Remote Paths ---
    local REMOTE_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"
    local REMOTE_CONFIG_DIR="${REMOTE_ROOT}/platform/Docker/Dev"
    local REMOTE_APP_BASE="${DOCKER_APP_MOUNT:-/dct_builds/dctrack_app}"
    local REMOTE_ARTIFACT_PATH="${REMOTE_APP_BASE}/server/dcTrackApp/target/dcTrackApp"

    log_step "DEPLOY-SERVER" "Preparing Server (Tomcat) deployment to ${TARGET_IP}..."

    # --- 3. BUILD STRATEGY ---
    echo -e "${YELLOW}Choose Deployment Strategy:${NC}"
    local STRATEGY
    STRATEGY=$(ui_choose "Direct Deploy (Use existing artifacts)" "Build & Deploy (mvn clean install)")

    if [[ "$STRATEGY" == "Build"* ]]; then
        echo -e "\n${BLUE}Starting Maven Build in ${CURRENT_DIR}...${NC}"
        mvn clean install -DskipTests -T 1C
        if [ $? -ne 0 ]; then error_exit "Maven build failed."; fi
        echo -e "${GREEN}Build Successful!${NC}\n"
    fi

    # --- 4. STAGING (EXPLODE WAR) ---
    # We ignore the default Maven exploded dir because it may lack META-INF data.
    # Instead, we explode the WAR into a custom staging area.

    if [ ! -f "$LOCAL_ARTIFACT_WAR" ]; then
         error_exit "WAR file not found at: ${LOCAL_ARTIFACT_WAR}\nBuild required? Run 'mvn clean install' first."
    fi

    log_step "STAGE" "Exploding WAR to staging area (for Rsync optimization)..."

    # Clean and Re-create Staging Dir
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

    # Extract WAR
    if command -v unzip &> /dev/null; then
        unzip -q "$LOCAL_ARTIFACT_WAR" -d "$STAGING_DIR"
    elif command -v jar &> /dev/null; then
        pushd "$STAGING_DIR" > /dev/null
        jar -xf "$LOCAL_ARTIFACT_WAR"
        popd > /dev/null
    else
        error_exit "Cannot extract WAR. Please install 'unzip' or ensure JDK 'jar' is in PATH."
    fi

    if [ $? -ne 0 ]; then error_exit "Failed to extract WAR file."; fi

    # === DEBUG INFO ===
    echo -e "DEBUG: Stage created at: ${YELLOW}${STAGING_DIR}${NC}"
    # ==================

    # --- 5. SYNC CODE ---
    log_step "SYNC" "Transferring Artifacts..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "sudo mkdir -p ${REMOTE_ARTIFACT_PATH}"

    echo -e "Syncing from Staging Area..."
    # We sync the CONTENTS of the staging dir to the remote artifact path
    rsync -avz -e ssh --delete "${STAGING_DIR}/" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_ARTIFACT_PATH}/"

    # Cleanup root container artifacts to force Tomcat to reload from the mount
    ssh "${REMOTE_USER}@${TARGET_IP}" "sudo rm -rf ${REMOTE_APP_BASE}/WEB-INF ${REMOTE_APP_BASE}/META-INF ${REMOTE_APP_BASE}/resources 2>/dev/null || true"

    # --- 6. CONFIG & RESTART ---
    ssh -t "${REMOTE_USER}@${TARGET_IP}" "
        cd ${REMOTE_CONFIG_DIR}
        # Disable Image / Enable Volume
        sed -i '/tomcat_asset_service/s/^ *image:/    #image:/' docker-compose.yml
        sed -i '\|/dct_builds/dctrack_app/server/dcTrackApp/target/dcTrackApp|s/^\( *\)# - /\1- /' docker-compose.yml

        sudo chown -R 1000:1000 ${REMOTE_APP_BASE}
        sudo chmod -R 755 ${REMOTE_APP_BASE}

        echo '[Remote] Restarting Tomcat Service...'
        sudo docker compose up -d tomcat
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Server Code Deployed!${NC}"
    else
        error_exit "Server deployment failed."
    fi
}