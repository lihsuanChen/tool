#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_ssh.sh"

APP_DIR="dcTrackApp"
# Hardcoded defaults (Consider moving these to .t_config in the future)
REMOTE_DEST="/var/lib/tomcat10/webapps"
SERVICE_NAME="tomcat10"

# ================= 1. GUARD CLAUSE =================
: "${TARGET_IP:?ERROR: This script must be run via the 't' dispatcher.}"

# ================= 2. BUILD (Maven) =================
# Use normalized version for logging, even if Maven handles the actual versioning
DISPLAY_VER="${VERSION_WITH_DOTS:-LATEST}"
log_step "BUILD" "Building Server (Version: ${YELLOW}${DISPLAY_VER}${NC})..."

# Detect where pom.xml is
if [ -f "./pom.xml" ]; then
    BUILD_CMD="mvn clean install -DskipTests -T 1C"
elif [ -f "./$APP_DIR/pom.xml" ]; then
    cd "$APP_DIR" || error_exit "Could not enter $APP_DIR"
    BUILD_CMD="mvn clean install -DskipTests -T 1C"
else
    error_exit "No pom.xml found. Are you in the 'server' root?"
fi

echo -e "Executing: ${YELLOW}${BUILD_CMD}${NC}"
$BUILD_CMD
if [ $? -ne 0 ]; then error_exit "Maven build failed."; fi

# Return to root if we changed dirs
if [ -f "../pom.xml" ]; then cd ..; fi

# ================= 3. LOCATE ARTIFACT =================
# Find the freshest WAR file
WAR_FILE=$(find . -type f -name "*.war" -path "*/target/*" | head -n 1)

if [ -z "$WAR_FILE" ]; then error_exit "No WAR file found in ./target."; fi
echo -e "Found Artifact: ${GREEN}${WAR_FILE}${NC}"

# ================= 4. UPLOAD (RSYNC) =================
log_step "UPLOAD" "Syncing WAR to ${TARGET_IP}..."

# We use rsync to upload to a temporary staging path first, then move it.
# This prevents Tomcat from trying to deploy a half-uploaded file if service is running.
rsync -avz -e ssh --progress "${WAR_FILE}" "${REMOTE_USER}@${TARGET_IP}:/tmp/dcTrackApp.war"

if [ $? -ne 0 ]; then error_exit "Upload failed."; fi

# ================= 5. DEPLOY & RESTART =================
log_step "REMOTE" "Deploying & Restarting ${SERVICE_NAME}..."

# Complex remote command:
# 1. Stop Tomcat
# 2. Delete old expanded folder (dcTrackApp/) to force fresh extraction
# 3. Clean Tomcat caches (work/temp) to prevent weird classloader issues
# 4. Move new WAR into place
# 5. Start Tomcat
REMOTE_CMDS="
    echo '[Remote] Stopping Tomcat...';
    systemctl stop ${SERVICE_NAME};

    echo '[Remote] Cleaning old deployment...';
    rm -rf ${REMOTE_DEST}/dcTrackApp;
    rm -rf /var/lib/${SERVICE_NAME}/work/Catalina/localhost/dcTrackApp;

    echo '[Remote] Installing new WAR...';
    mv /tmp/dcTrackApp.war ${REMOTE_DEST}/dcTrackApp.war;
    chmod 775 ${REMOTE_DEST}/dcTrackApp.war;

    echo '[Remote] Starting Tomcat...';
    systemctl start ${SERVICE_NAME};
"

ssh "${REMOTE_USER}@${TARGET_IP}" "${REMOTE_CMDS}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Server Deployment complete!${NC}"
else
    error_exit "Remote deployment sequence failed."
fi