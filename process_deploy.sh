#!/bin/bash

# ALWAYS load the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

# ================= DETECT CONTEXT =================
CURRENT_DIR=$(pwd)
BASENAME=$(basename "$CURRENT_DIR")

# Check 1: SERVER Mode
# Rule: Folder name is 'server' AND it contains 'dcTrackApp' subfolder
if [ "$BASENAME" == "server" ] && [ -d "./dcTrackApp" ]; then
    DEPLOY_TYPE="SERVER"
    APP_DIR="dcTrackApp"
    REMOTE_DEST="/var/lib/tomcat10/webapps"

# Check 2: CLIENT Mode
# Rule: Folder path ends in 'dctrack_app_client' (Standard repo name)
elif [[ "$CURRENT_DIR" == *"/dctrack_app_client" ]]; then
    DEPLOY_TYPE="CLIENT"
    REMOTE_CLIENT_DEST="/opt/raritan/dcTrack/appClient"

    # Validation
    if [ ! -f "./package.json" ]; then
        error_exit "Context detected as CLIENT, but 'package.json' is missing."
    fi

else
    echo -e "${RED}CRITICAL ERROR: Unknown Repository Context${NC}"
    echo "Current directory: $CURRENT_DIR"
    echo "To deploy, you must be in one of these locations:"
    echo -e "  1. A folder named ${YELLOW}'server'${NC} (containing 'dcTrackApp')"
    echo -e "  2. The ${YELLOW}'dctrack_app_client'${NC} repository"
    exit 1
fi

log_step "DEPLOY" "Detected Repository Type: ${YELLOW}$DEPLOY_TYPE${NC}"

# ================= SERVER DEPLOYMENT FLOW =================
if [ "$DEPLOY_TYPE" == "SERVER" ]; then

    # 1. BUILD WAR
    log_step "BUILD" "Building Server (Maven)..."

    # We already confirmed dcTrackApp exists in the detection step above
    if [ -f "./pom.xml" ]; then
        mvn clean install -DskipTests -T 1C
    elif [ -f "./$APP_DIR/pom.xml" ]; then
        cd "$APP_DIR"
        mvn clean install -DskipTests -T 1C
        cd ..
    else
        error_exit "No pom.xml found."
    fi

    if [ $? -ne 0 ]; then error_exit "Maven build failed."; fi

    # 2. SCP TO REMOTE
    log_step "UPLOAD" "Uploading WAR to ${TARGET_IP}..."
    WAR_FILE=$(find ./$APP_DIR/target -name "*.war" -type f | head -n 1)

    if [ -z "$WAR_FILE" ]; then error_exit "No WAR file found in ./$APP_DIR/target"; fi

    scp "$WAR_FILE" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DEST}/dcTrackApp.war"

    if [ $? -ne 0 ]; then error_exit "SCP transfer failed."; fi

    # 3. RESTART TOMCAT
    log_step "REMOTE" "Restarting Remote Tomcat..."
    REMOTE_CMDS="
    cd ${REMOTE_DEST} && \
    rm -rf dcTrackApp && \
    chmod 777 dcTrackApp.war && \
    systemctl restart tomcat10.service
    "

    ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMDS"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Server Deployment complete!${NC}"
    else
        error_exit "Remote restart failed."
    fi

# ================= CLIENT DEPLOYMENT FLOW =================
elif [ "$DEPLOY_TYPE" == "CLIENT" ]; then

    # 1. NPM BUILD
    log_step "BUILD" "Building Client (NPM)..."

    echo "Running npm install..."
    npm install
    if [ $? -ne 0 ]; then error_exit "npm install failed."; fi

    echo "Running npm rebuild node-sass..."
    npm rebuild node-sass
    if [ $? -ne 0 ]; then error_exit "npm rebuild node-sass failed."; fi

    echo "Running npm run source-map..."
    npm run source-map
    if [ $? -ne 0 ]; then error_exit "npm run source-map failed."; fi

    if [ ! -d "./dist" ]; then
        error_exit "Build finished, but './dist' folder is missing."
    fi

    # 2. CLEAN REMOTE FOLDER
    log_step "REMOTE" "Cleaning remote folder: $REMOTE_CLIENT_DEST"
    CLEAN_CMD="mkdir -p ${REMOTE_CLIENT_DEST} && rm -rf ${REMOTE_CLIENT_DEST}/*"

    ssh "${REMOTE_USER}@${TARGET_IP}" "$CLEAN_CMD"
    if [ $? -ne 0 ]; then error_exit "Failed to clean remote client folder."; fi

    # 3. SCP DIST CONTENT
    log_step "UPLOAD" "Syncing ./dist to ${TARGET_IP}..."
    scp -r ./dist/* "${REMOTE_USER}@${TARGET_IP}:${REMOTE_CLIENT_DEST}/"

    if [ $? -ne 0 ]; then error_exit "SCP transfer failed."; fi

    # 4. SET PERMISSIONS
    log_step "REMOTE" "Setting Permissions (chmod 777)..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "chmod -R 777 ${REMOTE_CLIENT_DEST}/*"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Client Deployment complete!${NC}"
    else
        error_exit "Remote permission setting failed."
    fi

fi