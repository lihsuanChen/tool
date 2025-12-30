#!/bin/bash

# ALWAYS load the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

# ================= DETECT CONTEXT =================
CURRENT_DIR=$(pwd)
BASENAME=$(basename "$CURRENT_DIR")

# Check 1: SERVER Mode
if [ "$BASENAME" == "server" ] && [ -d "./dcTrackApp" ]; then
    log_step "DEPLOY" "Detected Repository Type: ${YELLOW}SERVER${NC}"
    bash "$SCRIPT_DIR/deploy_server.sh"

# Check 2: CLIENT Mode
elif [[ "$CURRENT_DIR" == *"/dctrack_app_client" ]]; then
    log_step "DEPLOY" "Detected Repository Type: ${YELLOW}CLIENT${NC}"
    bash "$SCRIPT_DIR/deploy_client.sh"

# Check 3: DB MIGRATION Mode
elif [[ "$CURRENT_DIR" == *"/dctrack_database" ]]; then
    log_step "DEPLOY" "Detected Repository Type: ${YELLOW}DATABASE${NC}"
    bash "$SCRIPT_DIR/deploy_database.sh"

else
    echo -e "${RED}CRITICAL ERROR: Unknown Repository Context${NC}"
    echo "Current directory: $CURRENT_DIR"
    echo "To deploy, you must be in one of these locations:"
    echo -e "  1. .../server"
    echo -e "  2. .../dctrack_app_client"
    echo -e "  3. .../dctrack_database"
    exit 1
fi