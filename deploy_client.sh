#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

REMOTE_CLIENT_DEST="/opt/raritan/dcTrack/appClient"

# Validation
if [ ! -f "./package.json" ]; then error_exit "Missing package.json"; fi

# 1. NPM BUILD
log_step "BUILD" "Building Client (NPM)..."
echo "Running npm install..." && npm install
echo "Running npm rebuild node-sass..." && npm rebuild node-sass
echo "Running npm run source-map..." && npm run source-map

if [ ! -d "./dist" ]; then error_exit "Dist folder missing."; fi

# 2. CLEAN REMOTE FOLDER
log_step "REMOTE" "Cleaning remote folder..."
ssh "${REMOTE_USER}@${TARGET_IP}" "mkdir -p ${REMOTE_CLIENT_DEST} && rm -rf ${REMOTE_CLIENT_DEST}/*"

# 3. SCP DIST CONTENT
log_step "UPLOAD" "Syncing ./dist..."
scp -r ./dist/* "${REMOTE_USER}@${TARGET_IP}:${REMOTE_CLIENT_DEST}/"

# 4. SET PERMISSIONS
log_step "REMOTE" "Setting Permissions..."
ssh "${REMOTE_USER}@${TARGET_IP}" "chmod -R 777 ${REMOTE_CLIENT_DEST}/*"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Client Deployment complete!${NC}"
else
    error_exit "Client deploy failed."
fi