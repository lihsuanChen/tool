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
        
        # If running interactively, ask permission.
        read -p "Do you want to run ssh-copy-id now? (y/n): " SETUP_KEY
        
        if [[ "$SETUP_KEY" =~ ^[Yy]$ ]]; then
            install_ssh_key "$USER" "$IP"
        else
            echo "Skipping key save."
        fi
    fi
}

# NEW FUNCTION: Installs key AND handles "Host Identification Changed" errors
install_ssh_key() {
    local USER=$1
    local IP=$2
    
    echo -e "Running ssh-copy-id for ${YELLOW}${USER}@${IP}${NC}..."
    
    # 1. Try to install the key and capture output
    OUTPUT=$(ssh-copy-id "${USER}@${IP}" 2>&1)
    EXIT_CODE=$?
    
    # 2. Check if it failed due to "REMOTE HOST IDENTIFICATION HAS CHANGED"
    if [[ "$OUTPUT" == *"REMOTE HOST IDENTIFICATION HAS CHANGED"* ]]; then
        echo -e "${RED}WARNING: Host key mismatch detected.${NC}"
        echo -e "${YELLOW}Automatically removing old host key for $IP...${NC}"
        
        # Run the fix command
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" >/dev/null 2>&1
        
        echo -e "${YELLOW}Old key removed. Retrying connection...${NC}"
        echo "---------------------------------------------------"
        
        # Retry the copy command
        ssh-copy-id "${USER}@${IP}"
        EXIT_CODE=$?
    else
        # If it wasn't the specific host key error, just print the original output
        echo "$OUTPUT"
    fi

    # 3. Final Success/Fail check
    if [ $EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}SSH Key saved successfully.${NC}"
    else
            echo -e "${RED}Failed to save SSH key. You may need to enter password manually.${NC}"
    fi
}