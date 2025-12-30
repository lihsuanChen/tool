#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

APP_DIR="dcTrackApp"
REMOTE_DEST="/var/lib/tomcat10/webapps"

# 1. BUILD WAR
log_step "BUILD" "Building Server (Maven)..."
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
log_step "UPLOAD" "Uploading WAR..."
WAR_FILE=$(find ./$APP_DIR/target -name "*.war" -type f | head -n 1)

if [ -z "$WAR_FILE" ]; then error_exit "No WAR file found"; fi

scp "$WAR_FILE" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DEST}/dcTrackApp.war"
if [ $? -ne 0 ]; then error_exit "SCP failed."; fi

# 3. RESTART TOMCAT
log_step "REMOTE" "Restarting Tomcat..."
REMOTE_CMDS="cd ${REMOTE_DEST} && rm -rf dcTrackApp && chmod 777 dcTrackApp.war && systemctl restart tomcat10.service"
ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMDS"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Server Deployment complete!${NC}"
else
    error_exit "Restart failed."
fi