#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - SERVER
# DESCRIPTION: Context-aware build & sync for Java/Tomcat.
# Support: Remote (SSH) & Local (WSL2/Linux)
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
        exit 1
    fi

    # --- 2. DEFINE PATHS ---
    local LOCAL_ARTIFACT_WAR="${CURRENT_DIR}/dcTrackApp/target/dcTrackApp.war"
    local STAGING_DIR="${CURRENT_DIR}/dcTrackApp/target/_docker_stage"

    # --- Remote Paths (Compatible with your old script) ---
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
        echo -e "\n${BLUE}Starting Maven Build...${NC}"
        mvn clean install -DskipTests -T 1C
        if [ $? -ne 0 ]; then error_exit "Maven build failed."; fi
    fi

    # --- 4. STAGING ---
    if [ ! -f "$LOCAL_ARTIFACT_WAR" ]; then
         error_exit "WAR file not found. Build required?"
    fi

    log_step "STAGE" "Exploding WAR to staging area..."
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"

    if command -v unzip &> /dev/null; then
        unzip -q "$LOCAL_ARTIFACT_WAR" -d "$STAGING_DIR"
    elif command -v jar &> /dev/null; then
        pushd "$STAGING_DIR" > /dev/null; jar -xf "$LOCAL_ARTIFACT_WAR"; popd > /dev/null
    fi

    # --- 5. SYNC CODE ---
    log_step "SYNC" "Transferring Artifacts..."

    # Create directory (Works for both Local/Remote via abstraction)
    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo mkdir -p ${REMOTE_ARTIFACT_PATH}" "false"

    echo -e "Syncing from Staging Area..."
    sync_to_target "${STAGING_DIR}/" "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_ARTIFACT_PATH}/" "--delete"

    # Cleanup meta files to force reload
    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo rm -rf ${REMOTE_APP_BASE}/WEB-INF ${REMOTE_APP_BASE}/META-INF ${REMOTE_APP_BASE}/resources 2>/dev/null || true" "false"

    # --- 6. CONFIG & PERMISSION FIX (The Hybrid Solution) ---
    # This block executes commands on the target (Local or Remote)
    # We added specific 'chmod +x' and 'mkdir' logic to fix the Local Docker issues.
    local REMOTE_CMDS="
        set -e
        cd ${REMOTE_CONFIG_DIR}

        # --- A. Docker Compose Patching ---
        sed -i '/tomcat_asset_service/s/^ *image:/    #image:/' docker-compose.yml
        sed -i '\|/dct_builds/dctrack_app/server/dcTrackApp/target/dcTrackApp|s/^\( *\)# - /\1- /' docker-compose.yml

        # --- B. PERMISSION FIXES (Crucial for Local/WSL2) ---
        echo '[Deploy] Applying permission fixes...'

        # 1. Fix App Code Ownership (Legacy logic, good for Remote)
        if [ -d \"${REMOTE_APP_BASE}\" ]; then
            sudo chown -R 1000:1000 ${REMOTE_APP_BASE}
            sudo chmod -R 755 ${REMOTE_APP_BASE}
            # [NEW] Force +x on scripts (Fixes 'catalina.sh permission denied')
            sudo find ${REMOTE_APP_BASE} -name \"*.sh\" -exec chmod +x {} \;
        fi

        # 2. Fix Docker Config Scripts (Fixes 'permission denied' inside platform dir)
        if [ -d \"${REMOTE_ROOT}/platform\" ]; then
             sudo chown -R 1000:1000 \"${REMOTE_ROOT}/platform\"
             sudo find \"${REMOTE_ROOT}/platform\" -name \"*.sh\" -exec chmod +x {} \;
        fi

        # 3. Pre-create Volume Mounts (Fixes 'can\'t create /etc/raritan/system-uuid')
        # We manually create the host path so it's owned by 1000, not root.
        sudo mkdir -p /var/oculan/raritan
        sudo chown -R 1000:1000 /var/oculan/raritan

        # --- C. Restart ---
        echo '[Deploy] Restarting Tomcat...'
        # We use --build to ensure permission changes in 'platform' are picked up
        sudo docker compose up -d --build tomcat
    "

    # Execute
    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_CMDS}" "true"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Server Code Deployed & Permissions Secured!${NC}"
    else
        error_exit "Server deployment failed."
    fi
}