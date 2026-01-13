#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_ssh.sh"

REMOTE_CLIENT_DEST="/opt/raritan/dcTrack/appClient"

# ================= 1. PRE-FLIGHT CHECKS =================
# Guard Clause: Ensure this runs via tool_main.sh
: "${TARGET_IP:?ERROR: This script must be run via the 't' dispatcher.}"

# Validation
if [ ! -f "./package.json" ]; then error_exit "Missing package.json in $(pwd)"; fi

# Version Logic (Inherited from tool_main.sh)
CLIENT_VERSION="${VERSION_WITH_DOTS:-9.3.5}"

log_step "BUILD" "Preparing Client Build (Version: ${YELLOW}${CLIENT_VERSION}${NC})..."

# ================= 2. SMART DEPENDENCY INSTALL =================
# Only install if node_modules is missing or we explicitly asked for it?
# For now, we keep it safe: install if missing, otherwise rely on user keeping it up to date.
if [ ! -d "./node_modules" ]; then
    echo -e "${YELLOW}node_modules missing. Running npm install...${NC}"
    npm install
else
    echo -e "${BLUE}node_modules found. Skipping full install (run 'npm ci' manually if needed).${NC}"
fi

# SMART NODE-SASS CHECK
# Don't blindly rebuild node-sass unless it's actually in package.json
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
log_step "DEPLOY" "Syncing files to ${TARGET_IP}..."

# We use rsync instead of SCP.
# -a: Archive mode (preserves permissions/times)
# -v: Verbose
# -z: Compress
# --delete: Remove files on remote that are no longer in local ./dist
# -e ssh: Use SSH transport
rsync -avz --delete -e ssh ./dist/ "${REMOTE_USER}@${TARGET_IP}:${REMOTE_CLIENT_DEST}/"

if [ $? -ne 0 ]; then error_exit "Rsync failed."; fi

# ================= 5. PERMISSIONS & FINALIZATION =================
# Reset permissions just in case
log_step "REMOTE" "Finalizing Permissions..."
ssh "${REMOTE_USER}@${TARGET_IP}" "chmod -R 755 ${REMOTE_CLIENT_DEST}"

echo -e "${GREEN}SUCCESS: Client Deployment complete!${NC}"