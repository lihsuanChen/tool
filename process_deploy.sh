#!/bin/bash

# ALWAYS load the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

# ================= DETECT CONTEXT =================
CURRENT_DIR=$(pwd)
BASENAME=$(basename "$CURRENT_DIR")

# Check 1: SERVER Mode (Maven)
# Fingerprint: Folder is named 'server' AND contains 'dcTrackApp'
if [ "$BASENAME" == "server" ] && [ -d "./dcTrackApp" ]; then
    log_step "DEPLOY" "Detected Repository Type: ${YELLOW}SERVER${NC}"
    bash "$SCRIPT_DIR/deploy_server.sh"

# Check 2: CLIENT Mode (Node.js)
# Fingerprint: Folder name contains 'client' AND contains 'package.json'
elif [[ "$CURRENT_DIR" == *"client"* ]] && [ -f "./package.json" ]; then
    log_step "DEPLOY" "Detected Repository Type: ${YELLOW}CLIENT${NC}"
    bash "$SCRIPT_DIR/deploy_client.sh"

# Check 3: DB MIGRATION Mode (Liquibase)
# Fingerprint: The unique changesets directory structure exists
elif [ -d "./src/files/opt/raritan/liquibase/changesets" ]; then
    log_step "DEPLOY" "Detected Repository Type: ${YELLOW}DATABASE${NC}"
    bash "$SCRIPT_DIR/deploy_database.sh"

else
    echo -e "${RED}CRITICAL ERROR: Unknown Repository Context${NC}"
    echo "Current directory: $CURRENT_DIR"
    echo "Could not identify the project type based on files."
    echo "Required Fingerprints:"
    echo -e "  1. Server:   Folder 'server' + 'dcTrackApp' subfolder"
    echo -e "  2. Client:   Folder name '*client*' + 'package.json'"
    echo -e "  3. Database: Folder './src/files/opt/raritan/liquibase/changesets'"
    exit 1
fi