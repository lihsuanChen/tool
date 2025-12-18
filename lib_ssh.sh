#!/bin/bash

# ================= COLORS =================
export GREEN='\033[0;32m'
export BLUE='\033[0;34m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

# ================= HELPERS =================
log_step() {
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

error_exit() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# ================= SSH LOGIC =================
check_and_setup_ssh() {
    local USER=$1
    local IP=$2
    
    log_step "SSH" "Verifying connection to ${USER}@${IP}"

    # Check connectivity using batch mode
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER}@${IP}" "echo Connection Success" 2>/dev/null; then
        echo -e "${GREEN}SSH Key already configured. Connection valid.${NC}"
    else
        echo -e "${YELLOW}SSH Key not detected or connection failed.${NC}"
        echo -e "We need to set up the SSH key for passwordless access."
        read -p "Do you want to run ssh-copy-id now? (y/n): " SETUP_KEY
        
        if [[ "$SETUP_KEY" =~ ^[Yy]$ ]]; then
            echo "Running ssh-copy-id..."
            ssh-copy-id "${USER}@${IP}"
            if [ $? -eq 0 ]; then
                 echo -e "${GREEN}SSH Key saved successfully.${NC}"
            else
                 echo -e "${RED}Failed to save SSH key. You might need to enter password manually later.${NC}"
            fi
        else
            echo "Skipping key save."
        fi
    fi
}