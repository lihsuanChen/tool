#!/bin/bash

# ================= COLORS & FORMATTING =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_step() {
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "STEP $1: $2"
    echo -e "${BLUE}==================================================${NC}"
}

error_exit() {
    # If gum is available, use it for a pretty error
    if command -v gum &> /dev/null; then
        gum style --foreground 196 --border double --padding "1 2" "ERROR: $1"
    else
        echo -e "${RED}ERROR: $1${NC}"
    fi
    exit 1
}

# ================= DEPENDENCY CHECKS =================
ensure_local_key() {
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        echo "Local SSH key not found. Generating default RSA key..."
        # -f is required to avoid interactive prompts
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
    fi
}

ensure_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        echo -e "${YELLOW}Dependency 'sshpass' is missing.${NC}"
        echo "Attempting auto-installation..."

        if [ "$EUID" -ne 0 ] && ! command -v sudo &> /dev/null; then
             error_exit "Cannot install 'sshpass' (not root and sudo missing). Install it manually."
        fi

        if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y sshpass;
        elif command -v dnf &> /dev/null; then sudo dnf install -y sshpass;
        elif command -v yum &> /dev/null; then sudo yum install -y sshpass;
        else error_exit "PackageManager not found. Please install 'sshpass' manually."; fi
    fi
}

# ================= CREDENTIAL MANAGEMENT =================
ensure_bridge_password() {
    local FORCE_UPDATE=$1
    local TEST_IP=$2
    # Fallback to 'sunbird' if BRIDGE_USER is not set externally
    local B_USER="${BRIDGE_USER:-sunbird}"
    local AUTH="${AUTH_FILE:-$HOME/.sunbird_auth}"

    if [ ! -f "$AUTH" ] || [ "$FORCE_UPDATE" == "true" ]; then
        ensure_sshpass

        # === GUM INTEGRATION START ===
        if command -v gum &> /dev/null; then
             echo -e "${YELLOW}Security Setup: Authentication Required for '$B_USER'${NC}"

             while true; do
                # Use gum for masked input
                PASSWORD=$(gum input --password --placeholder "Enter Password for $B_USER...")
                echo ""

                if [ -z "$PASSWORD" ]; then
                    gum style --foreground 196 "Password cannot be empty."
                    continue
                fi

                # Verification Logic
                if [ -n "$TEST_IP" ]; then
                    echo -n "Verifying password against $TEST_IP... "
                    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${B_USER}@${TEST_IP}" "exit" 2>/dev/null

                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}VALID.${NC}"
                        break
                    else
                        gum style --foreground 196 "INVALID PASSWORD" "Access rejected by ${B_USER}@${TEST_IP}"
                        gum confirm "Try again?" || exit 1
                    fi
                else
                    echo -e "${YELLOW}No IP provided for verification. Saving blindly.${NC}"
                    break
                fi
            done
        else
            # === LEGACY FALLBACK ===
            echo -e "${YELLOW}Security Setup: Input correct password for '$B_USER'.${NC}"
            while true; do
                read -sp "Enter Password for $B_USER: " PASSWORD
                echo ""

                if [ -n "$TEST_IP" ]; then
                    echo -n "Verifying password against $TEST_IP... "
                    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${B_USER}@${TEST_IP}" "exit" 2>/dev/null

                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}VALID.${NC}"
                        break
                    else
                        echo -e "${RED}INVALID.${NC}"
                        read -p "Retry? (y/n): " RETRY
                        if [[ "$RETRY" =~ ^[Nn]$ ]]; then echo -e "${RED}Aborted.${NC}"; exit 1; fi
                    fi
                else
                    break
                fi
            done
        fi
        # === END AUTH LOGIC ===

        echo "$PASSWORD" > "$AUTH"
        chmod 600 "$AUTH"
        echo -e "${GREEN}Password securely saved to $AUTH.${NC}"
    fi
}

# ================= REMOTE SETUP LOGIC =================

# 1. SETUP ROOT (Bridge User -> Sudo -> Set Root Pass -> Config SSHD)
setup_root_creds() {
    local B_USER=$1
    local IP=$2
    local AUTH="${AUTH_FILE:-$HOME/.sunbird_auth}"

    if [ ! -f "$AUTH" ]; then error_exit "No saved password. Run 't setpass' first."; fi
    local PASS=$(cat "$AUTH")

    log_step "ROOT-SETUP" "Configuring Root Access on $IP (via $B_USER)..."

    # Self-Healing: Fix Host Key mismatch before attempting connection
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${B_USER}@${IP}" "exit" 2>/dev/null
    if [ $? -ne 0 ]; then
         echo -e "${YELLOW}Initial connection failed. Attempting to clear bad Host Keys for $IP...${NC}"
         ssh-keygen -R "$IP" &>/dev/null
    fi

    # Prompt for Password Sync
    echo -e "${YELLOW}Warning: This will enable Root Login and update SSHD config.${NC}"
    echo -e "Remote root password will be set to match your local bridge password."

    # Use gum confirm if available
    if command -v gum &> /dev/null; then
        if gum confirm "Continue with password sync?"; then
            SYNC_CONFIRM="y"
        else
            SYNC_CONFIRM="n"
        fi
    else
        read -p "Continue? (y/N): " SYNC_CONFIRM
    fi

    if [[ ! "$SYNC_CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Skipping password sync.${NC}"
        PASS_CMD="echo '[Remote] Skipping Password Update...';"
    else
        echo -e "${BLUE}Syncing password...${NC}"
        PASS_CMD="echo \"root:$PASS\" | chpasswd;"
    fi

    # Remote Script Block
    REMOTE_SCRIPT="echo '$PASS' | sudo -S -p '' bash -c '
        $PASS_CMD
        echo \"[Remote] Configuring SSHD...\"
        sed -i \"s/^#\?PermitRootLogin.*/PermitRootLogin yes/g\" /etc/ssh/sshd_config
        sed -i \"s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g\" /etc/ssh/sshd_config
        sed -i \"s/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g\" /etc/ssh/sshd_config

        echo \"[Remote] Restarting SSHD...\"
        if command -v systemctl &> /dev/null; then systemctl restart sshd; else service sshd restart; fi
    '"

    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -t "${B_USER}@${IP}" "$REMOTE_SCRIPT"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Root setup complete.${NC}"
    else
        error_exit "Root setup failed. Ensure $B_USER has sudo rights."
    fi
}

# 2. INSTALL KEYS (Bootstrap Root Access)
install_ssh_key() {
    local USER=$1
    local IP=$2
    local B_USER="${BRIDGE_USER:-sunbird}"
    local AUTH="${AUTH_FILE:-$HOME/.sunbird_auth}"

    ensure_bridge_password "false" "$IP"
    local PASS=$(cat "$AUTH")
    ensure_local_key

    log_step "BOOTSTRAP" "Bootstrapping SSH Keys for $USER@$IP..."

    # Upload Key via Bridge
    echo -e "Uploading local public key..."
    sshpass -p "$PASS" scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa.pub ${B_USER}@${IP}:/tmp/temp_key.pub 2>/dev/null

    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Upload failed. Verification of stored password required.${NC}"
        ensure_bridge_password "true" "$IP"
        PASS=$(cat "$AUTH")
        # Retry
        sshpass -p "$PASS" scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa.pub ${B_USER}@${IP}:/tmp/temp_key.pub
        if [ $? -ne 0 ]; then error_exit "Failed to upload key even after password update."; fi
    fi

    # Install Key to Root
    echo -e "Installing key to /root/.ssh/authorized_keys..."
    REMOTE_SCRIPT="echo '$PASS' | sudo -S -p '' bash -c '
        mkdir -p /root/.ssh
        cat /tmp/temp_key.pub >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        chmod 700 /root/.ssh
        rm /tmp/temp_key.pub
        # Ensure SSHD allows keys
        sed -i \"s/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g\" /etc/ssh/sshd_config
        if command -v systemctl &> /dev/null; then systemctl reload sshd; else service sshd reload; fi
    '"

    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no ${B_USER}@${IP} "$REMOTE_SCRIPT"

    if [ $? -eq 0 ]; then echo -e "${GREEN}Keys Installed!${NC}"; else error_exit "Key installation failed."; fi
}

# 3. CHECK CONNECTIVITY (The Entry Point)
check_and_setup_ssh() {
    local USER=$1
    local IP=$2

    echo -e "Checking SSH connection to ${USER}@${IP}..."

    # Try Silent Connection first
    # BatchMode=yes fails instantly if key/pass not available
    ssh -o BatchMode=yes -o ConnectTimeout=4 "${USER}@${IP}" "exit" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSH Connection OK.${NC}"
        return 0
    fi

    echo -e "${YELLOW}Direct SSH failed.${NC}"

    # HEALING: Host Key Verification Failure?
    echo -e "${YELLOW}Attempting Self-Healing (Clearing Host Key)...${NC}"
    ssh-keygen -R "$IP" &>/dev/null

    # Retry connection after clear
    ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no "${USER}@${IP}" "exit" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Connection Restored (Host Key Reset).${NC}"
        return 0
    fi

    # If still failing, we need to install keys
    echo -e "${YELLOW}Authentication failed. Initiating Bootstrap Protocol...${NC}"
    install_ssh_key "$USER" "$IP"

    # Final Verification
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no "${USER}@${IP}" "exit"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Setup Successful!${NC}"
        return 0
    else
        error_exit "Setup completed but Root login still failed."
    fi
}