#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_ssh.sh"

# Load Destination from Config (with fallback)
REMOTE_CLIENT_DEST="${DEST_CLIENT_DIST:-/opt/raritan/dcTrack/appClient}"

# ================= 1. PRE-FLIGHT CHECKS =================
: "${TARGET_IP:?ERROR: This script must be run via the 't' dispatcher.}"

# Validation
if [ ! -f "./package.json" ]; then error_exit "Missing package.json in $(pwd)"; fi

CLIENT_VERSION="${VERSION_WITH_DOTS:-9.3.5}"

log_step "BUILD" "Preparing Client Build (Version: ${YELLOW}${CLIENT_VERSION}${NC})..."

# ================= 2. SMART DEPENDENCY INSTALL =================
if [ ! -d "./node_modules" ]; then
    echo -e "${YELLOW}node_modules missing. Running npm install...${NC}"
    npm install
else
    echo -e "${BLUE}node_modules found. Skipping full install.${NC}"
fi

# SMART NODE-SASS CHECK
if grep -q "\"node-sass\"" package.json; then
    echo -e "${BLUE}Detected 'node-sass'. Running rebuild...${NC}"
    npm rebuild node-sass
fi

# ================= 3. BUILD ARTIFACT =================
CMD="npm run source-map -- --env version=${CLIENT_VERSION}"
echo -e "Executing: ${YELLOW}${CMD}${NC}"
$CMD

if [ $? -ne 0 ]; then error_exit "npm build failed."; fi
if [ ! -d "./dist" ]; then error_exit "Build finished but './dist' folder is missing."; fi

# ================= 4. FAST SYNC (RSYNC) =================
log_step "DEPLOY" "Syncing files to ${TARGET_IP}:${REMOTE_CLIENT_DEST}..."

rsync -avz --delete -e ssh ./dist/ "${REMOTE_USER}@${TARGET_IP}:${REMOTE_CLIENT_DEST}/"

if [ $? -ne 0 ]; then error_exit "Rsync failed."; fi

# ================= 5. PERMISSIONS & FINALIZATION =================
log_step "REMOTE" "Finalizing Permissions..."
ssh "${REMOTE_USER}@${TARGET_IP}" "chmod -R 755 ${REMOTE_CLIENT_DEST}"

echo -e "${GREEN}SUCCESS: Client Deployment complete!${NC}"