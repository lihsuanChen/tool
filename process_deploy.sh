#!/bin/bash

# ALWAYS load the library to ensure functions (log_step, error_exit) are defined
# We use BASH_SOURCE[0] to ensure we find the file relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

# Configuration specific to this process
APP_DIR="dcTrackApp"
REMOTE_DEST="/var/lib/tomcat10/webapps"

# 1. CONFIRM LOCATION
log_step "DEPLOY" "Checking Working Directory"
CURRENT_DIR=$(pwd)
BASENAME=$(basename "$CURRENT_DIR")

# We strictly enforce running from the 'server' directory
if [ "$BASENAME" != "server" ]; then
    echo -e "${RED}CRITICAL ERROR: Invalid Run Location${NC}"
    echo "You are currently in: $CURRENT_DIR"
    echo "You MUST be inside the '.../server' directory to run deployment."
    exit 1
fi

if [ ! -d "./$APP_DIR" ]; then
    error_exit "Folder '$APP_DIR' not found inside $(pwd)."
fi

# 2. BUILD WAR
log_step "DEPLOY" "Building WAR with Maven"
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

# 3. SCP TO REMOTE
log_step "DEPLOY" "Uploading WAR"
WAR_FILE=$(find ./$APP_DIR/target -name "*.war" -type f | head -n 1)

if [ -z "$WAR_FILE" ]; then error_exit "No WAR file found in ./$APP_DIR/target"; fi

echo "Uploading $WAR_FILE to ${TARGET_IP}..."
scp "$WAR_FILE" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DEST}/dcTrackApp.war"

if [ $? -ne 0 ]; then error_exit "SCP transfer failed."; fi

# 4. RESTART TOMCAT
log_step "DEPLOY" "Restarting Remote Tomcat"
REMOTE_CMDS="
cd ${REMOTE_DEST} && \
rm -rf dcTrackApp && \
chmod 777 dcTrackApp.war && \
systemctl restart tomcat10.service
"

ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMDS"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Deployment complete!${NC}"
else
    error_exit "Remote restart failed."
fi