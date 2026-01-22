#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_ssh.sh"

# ================= CONFIGURATION =================
# We prefer variables from .t_config, but keep fallbacks just in case
SERVICE_NAME="${TOMCAT_SERVICE:-tomcat10}"
APP_NAME="${TOMCAT_APP_NAME:-dcTrackApp}"
REMOTE_DEST="${TOMCAT_WEBAPPS:-/var/lib/tomcat10/webapps}"

# ================= 1. GUARD CLAUSE =================
: "${TARGET_IP:?ERROR: This script must be run via the 't' dispatcher.}"

# ================= 2. BUILD (Maven) =================
DISPLAY_VER="${VERSION_WITH_DOTS:-LATEST}"
log_step "BUILD" "Building Server (Version: ${YELLOW}${DISPLAY_VER}${NC})..."

# Detect where pom.xml is
if [ -f "./pom.xml" ]; then
    BUILD_CMD="mvn clean install -DskipTests -T 1C"
elif [ -f "./${APP_NAME}/pom.xml" ]; then
    cd "${APP_NAME}" || error_exit "Could not enter ${APP_NAME}"
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
WAR_FILE=$(find . -type f -name "*.war" -path "*/target/*" | head -n 1)

if [ -z "$WAR_FILE" ]; then error_exit "No WAR file found in ./target."; fi
echo -e "Found Artifact: ${GREEN}${WAR_FILE}${NC}"

# ================= 4. UPLOAD (RSYNC) =================
log_step "UPLOAD" "Syncing WAR to ${TARGET_IP}:${REMOTE_DEST}..."

# Upload to tmp first
rsync -avz -e ssh --progress "${WAR_FILE}" "${REMOTE_USER}@${TARGET_IP}:/tmp/${APP_NAME}.war"

if [ $? -ne 0 ]; then error_exit "Upload failed."; fi

# ================= 5. DEPLOY & RESTART =================
log_step "REMOTE" "Deploying & Restarting ${SERVICE_NAME}..."

REMOTE_CMDS="
    echo '[Remote] Stopping ${SERVICE_NAME}...';
    systemctl stop ${SERVICE_NAME};

    echo '[Remote] Cleaning old deployment...';
    rm -rf ${REMOTE_DEST}/${APP_NAME};
    rm -rf /var/lib/${SERVICE_NAME}/work/Catalina/localhost/${APP_NAME};

    echo '[Remote] Installing new WAR...';
    mv /tmp/${APP_NAME}.war ${REMOTE_DEST}/${APP_NAME}.war;
    chmod 775 ${REMOTE_DEST}/${APP_NAME}.war;

    echo '[Remote] Starting ${SERVICE_NAME}...';
    systemctl start ${SERVICE_NAME};
"

ssh "${REMOTE_USER}@${TARGET_IP}" "${REMOTE_CMDS}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Server Deployment complete!${NC}"
else
    error_exit "Remote deployment sequence failed."
fi