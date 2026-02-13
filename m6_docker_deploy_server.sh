#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - SERVER
# DESCRIPTION: Context-aware build & sync for Java/Tomcat.
# ==============================================================================

# Ensure execution abstraction is loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_exec.sh"

deploy_server_container() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- 1. STRICT CONTEXT VALIDATION ---
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)
    local BASENAME
    BASENAME=$(basename "$CURRENT_DIR")

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
    local LOCAL_ARTIFACT_WAR="${CURRENT_DIR}/dcTrackApp/target/dcTrackApp.war"
    local STAGING_DIR="${CURRENT_DIR}/dcTrackApp/target/_docker_stage"

    # --- Remote Paths ---
    local REMOTE_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"
    local REMOTE_CONFIG_DIR="${REMOTE_ROOT}/platform/Docker/Dev"
    local REMOTE_APP_BASE="${DOCKER_APP_MOUNT:-/dct_builds/dctrack_app}"
    local REMOTE_ARTIFACT_PATH="${REMOTE_APP_BASE}/server/dcTrackApp/target/dcTrackApp"

    log_step "DEPLOY-SERVER" "Preparing Server (Tomcat) deployment to ${TARGET_IP} (Local Mode: ${IS_LOCAL_MODE})..."

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
    if [ ! -f "$LOCAL_ARTIFACT_WAR" ]; then
         error_exit "WAR file not found at: ${LOCAL_ARTIFACT_WAR}\nBuild required? Run 'mvn clean install' first."
    fi

    log_step "STAGE" "Exploding WAR to staging area..."
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

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

    # --- 5. SYNC CODE ---
    log_step "SYNC" "Transferring Artifacts..."

    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo mkdir -p ${REMOTE_ARTIFACT_PATH}" "false"

    echo -e "Syncing from Staging Area..."
    sync_to_target "${STAGING_DIR}/" "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_ARTIFACT_PATH}/" "--delete"

    # Cleanup remote artifacts to force Tomcat reload
    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo rm -rf ${REMOTE_APP_BASE}/WEB-INF ${REMOTE_APP_BASE}/META-INF ${REMOTE_APP_BASE}/resources 2>/dev/null || true" "false"

    # ==============================================================================
    # [FIX] Local Mode Permission Patch
    # ==============================================================================
    if [ "$IS_LOCAL_MODE" == "true" ]; then
        if command -v sudo &> /dev/null; then sudo -v; fi
        local MY_UID=$(id -u)
        local MY_GID=$(id -g)
        run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo chown -R ${MY_UID}:${MY_GID} ${REMOTE_ROOT}" "false"
    fi

    # --- 6. CONFIG & RESTART ---
    local REMOTE_CMDS="
        cd ${REMOTE_CONFIG_DIR}
        # Disable Image / Enable Volume
        sed -i '/tomcat_asset_service/s/^ *image:/    #image:/' docker-compose.yml
        sed -i '\|/dct_builds/dctrack_app/server/dcTrackApp/target/dcTrackApp|s/^\( *\)# - /\1- /' docker-compose.yml

        sudo chown -R 1000:1000 ${REMOTE_APP_BASE}
        sudo chmod -R 755 ${REMOTE_APP_BASE}

        echo '[Remote] Restarting Tomcat Service...'
        sudo docker compose up -d tomcat
    "

    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_CMDS}" "true"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Server Code Deployed!${NC}"
    else
        error_exit "Server deployment failed."
    fi
}