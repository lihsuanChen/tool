#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - SERVER
# DESCRIPTION: Context-aware build & sync for Java/Tomcat.
# ==============================================================================

deploy_server_container() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- 1. CONTEXT DETECTION & PRE-FLIGHT CHECK ---
    local CURRENT_DIR
    CURRENT_DIR=$(pwd)
    local LOCAL_ARTIFACT_DIR=""
    local LOCAL_ARTIFACT_WAR=""

    if [ -f "./pom.xml" ]; then
        # Scenario A: We are in 'server' root (contains dcTrackApp subfolder)
        if [ -d "./dcTrackApp" ]; then
            log_step "CONTEXT" "Detected Server Root at: ${CURRENT_DIR}"
            LOCAL_ARTIFACT_DIR="${CURRENT_DIR}/dcTrackApp/target/dcTrackApp"
            LOCAL_ARTIFACT_WAR="${CURRENT_DIR}/dcTrackApp/target/dcTrackApp.war"

        # Scenario B: We are inside 'dcTrackApp' module
        elif grep -q "artifactId>dcTrackApp<" pom.xml 2>/dev/null || [ -d "./src/main/webapp" ]; then
            log_step "CONTEXT" "Detected App Module at: ${CURRENT_DIR}"
            LOCAL_ARTIFACT_DIR="${CURRENT_DIR}/target/dcTrackApp"
            LOCAL_ARTIFACT_WAR="${CURRENT_DIR}/target/dcTrackApp.war"
        else
            error_exit "Found pom.xml but could not identify 'dcTrackApp' structure.\nPlease run from the 'server' root or 'dcTrackApp' folder."
        fi
    else
        error_exit "No 'pom.xml' found in ${CURRENT_DIR}.\nPlease navigate to your Server git worktree before deploying."
    fi

    # --- Remote Paths ---
    local REMOTE_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"
    local REMOTE_CONFIG_DIR="${REMOTE_ROOT}/platform/Docker/Dev"
    local REMOTE_APP_BASE="${DOCKER_APP_MOUNT:-/dct_builds/dctrack_app}"
    local REMOTE_ARTIFACT_PATH="${REMOTE_APP_BASE}/server/dcTrackApp/target/dcTrackApp"

    log_step "DEPLOY-SERVER" "Preparing Server (Tomcat) deployment to ${TARGET_IP}..."

    # --- 2. BUILD STRATEGY ---
    echo -e "${YELLOW}Choose Deployment Strategy:${NC}"
    local STRATEGY
    STRATEGY=$(ui_choose "Direct Deploy (Use existing artifacts)" "Build & Deploy (mvn clean install)")

    if [[ "$STRATEGY" == "Build"* ]]; then
        echo -e "\n${BLUE}Starting Maven Build in ${CURRENT_DIR}...${NC}"
        # We are already in the correct directory due to pre-checks
        mvn clean install -DskipTests -T 1C
        if [ $? -ne 0 ]; then error_exit "Maven build failed."; fi
        echo -e "${GREEN}Build Successful!${NC}\n"
    fi

    # --- 3. SYNC CODE ---
    log_step "SYNC" "Transferring Artifacts..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "sudo mkdir -p ${REMOTE_ARTIFACT_PATH}"

    if [ -d "$LOCAL_ARTIFACT_DIR" ]; then
        echo -e "Syncing Exploded WAR from: ${YELLOW}${LOCAL_ARTIFACT_DIR}${NC}"
        rsync -avz -e ssh --delete "${LOCAL_ARTIFACT_DIR}/" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_ARTIFACT_PATH}/"

        # Cleanup root container artifacts to force Tomcat to reload from the mount
        ssh "${REMOTE_USER}@${TARGET_IP}" "sudo rm -rf ${REMOTE_APP_BASE}/WEB-INF ${REMOTE_APP_BASE}/META-INF ${REMOTE_APP_BASE}/resources 2>/dev/null || true"

    elif [ -f "$LOCAL_ARTIFACT_WAR" ]; then
        echo -e "Syncing WAR file..."
        rsync -avz -e ssh "$LOCAL_ARTIFACT_WAR" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_ARTIFACT_PATH}/dcTrackApp.war"
    else
        echo -e "${YELLOW}No artifacts found at: ${LOCAL_ARTIFACT_DIR}${NC}"
        error_exit "Build required? Run 'mvn clean install' first."
    fi

    # --- 4. CONFIG & RESTART ---
    ssh -t "${REMOTE_USER}@${TARGET_IP}" "
        cd ${REMOTE_CONFIG_DIR}
        # Disable Image / Enable Volume
        sed -i '/tomcat_asset_service/s/^ *image:/    #image:/' docker-compose.yml
        sed -i '\|/dct_builds/dctrack_app/server/dcTrackApp/target/dcTrackApp|s/^\( *\)# - /\1- /' docker-compose.yml

        sudo chown -R 1000:1000 ${REMOTE_APP_BASE}
        sudo chmod -R 755 ${REMOTE_APP_BASE}

        echo '[Remote] Restarting Tomcat Service...'
        sudo docker compose restart tomcat
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Server Code Deployed!${NC}"
    else
        error_exit "Server deployment failed."
    fi
}