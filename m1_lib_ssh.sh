#!/bin/bash

# COLORS
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
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

ensure_local_key() {
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        echo "Local SSH key not found. Generating..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
    fi
}

ensure_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        echo -e "${YELLOW}Dependency 'sshpass' is missing.${NC}"
        echo "Attempting auto-installation..."
        if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y sshpass;
        elif command -v dnf &> /dev/null; then sudo dnf install -y sshpass;
        elif command -v yum &> /dev/null; then sudo yum install -y sshpass;
        else error_exit "Please install 'sshpass' manually."; fi
    fi
}

# ================= PASSWORD VALIDATION & UPDATE =================
ensure_bridge_password() {
    local FORCE_UPDATE=$1
    local TEST_IP=$2
    local BRIDGE_USER="sunbird"

    if [ ! -f "$AUTH_FILE" ] || [ "$FORCE_UPDATE" == "true" ]; then
        echo -e "${YELLOW}Security Setup: Input correct password for '$BRIDGE_USER'.${NC}"
        ensure_sshpass

        while true; do
            read -sp "Enter Password: " PASSWORD
            echo ""

            local CHECK_IP="$TEST_IP"

            if [ -z "$CHECK_IP" ]; then
                echo -e "${BLUE}Tip: Provide an IP to verify this password works.${NC}"
                read -p "Validation IP (Press Enter to skip check): " USER_IP
                if [ -n "$USER_IP" ]; then CHECK_IP="$USER_IP"; fi
            fi

            if [ -n "$CHECK_IP" ]; then
                echo -n "Verifying password against $CHECK_IP... "
                # Attempt connection; if it fails, it might be a key issue, but we only validate password here.
                # We use StrictHostKeyChecking=no to try and bypass prompts, but known_hosts conflicts still block it.
                sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${BRIDGE_USER}@${CHECK_IP}" "exit" 2>/dev/null

                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}SUCCESS.${NC}"
                    break
                else
                    echo -e "${RED}FAILED.${NC}"
                    # Hint about host key issues during password check
                    echo -e "Password rejected (or Host Key Changed) by ${BRIDGE_USER}@${CHECK_IP}."

                    read -p "Try typing it again? (y/n): " RETRY
                    if [[ "$RETRY" =~ ^[Nn]$ ]]; then echo -e "${RED}Aborted by user.${NC}"; exit 1; fi
                fi
            else
                echo -e "${YELLOW}Skipping verification.${NC}"
                break
            fi
        done

        echo "$PASSWORD" > "$AUTH_FILE"
        chmod 600 "$AUTH_FILE"
        echo -e "${GREEN}Password updated and saved.${NC}"
    fi
}

# ================= SETUP ROOT CREDENTIALS (WITH PROMPT) =================
setup_root_creds() {
    local BRIDGE=$1  # The user we login as (sunbird)
    local IP=$2

    # 1. Get the password we recorded for the bridge user
    if [ ! -f "$AUTH_FILE" ]; then
        error_exit "No saved password found. Run 't setpass' first."
    fi
    local PASS=$(cat "$AUTH_FILE")

    log_step "ROOT-SETUP" "Configuring Root Access via '${BRIDGE}'..."

    # SELF-HEALING CHECK (Fixes 'Host Identification Changed')
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${BRIDGE}@${IP}" "exit" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Connection check failed. Attempting to fix Host Key...${NC}"
        ssh-keygen -R "$IP" &>/dev/null
    fi

    # 2. PROMPT FOR PASSWORD OVERWRITE
    echo -e "${YELLOW}Warning: This will configure SSHD and optionally sync credentials.${NC}"
    echo -e "Do you want to OVERWRITE the remote 'root' password to match the bridge password?"
    read -p "Sync Password? (y/N): " SYNC_CONFIRM

    local PASS_CMD=""
    if [[ "$SYNC_CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Will sync password.${NC}"
        PASS_CMD="echo \"[Remote] Syncing Root Password...\"; echo \"root:$PASS\" | chpasswd;"
    else
        echo -e "${BLUE}Skipping password change (Configuring SSHD only).${NC}"
        PASS_CMD="echo \"[Remote] Keeping existing Root Password...\";"
    fi

    # 3. Construct Remote Command (Run as Bridge -> Sudo -> Bash)
    REMOTE_SCRIPT="echo '$PASS' | sudo -S -p '' bash -c '
        $PASS_CMD

        echo \"[Remote] Configuring SSHD for Root Login...\";
        # Ensure Root Login is allowed
        sed -i \"s/^#\?PermitRootLogin.*/PermitRootLogin yes/g\" /etc/ssh/sshd_config;

        # Ensure Password Auth is allowed (Required if we just set the password)
        sed -i \"s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g\" /etc/ssh/sshd_config;

        # Ensure Pubkey Auth is allowed (Good practice)
        sed -i \"s/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g\" /etc/ssh/sshd_config;

        echo \"[Remote] Restarting SSHD...\";
        if command -v systemctl &> /dev/null; then systemctl restart sshd; else service sshd restart; fi
    '"

    # 4. Execute via SSHPASS
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -t "${BRIDGE}@${IP}" "$REMOTE_SCRIPT"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Root setup complete on ${IP}.${NC}"
        echo -e "You can now login: ${YELLOW}ssh root@${IP}${NC}"
    else
        error_exit "Failed to set root credentials. (Does $BRIDGE have sudo rights?)"
    fi
}

# ================= SSH INSTALL KEY LOGIC =================
install_ssh_key() {
    local USER=$1
    local IP=$2
    local BRIDGE="sunbird"

    ensure_bridge_password "false" "$IP"
    local PASS=$(cat "$AUTH_FILE")
    ensure_local_key

    log_step "BOOTSTRAP" "Attempting to bootstrap ROOT access via $BRIDGE..."

    # 2. ATTEMPT 1: Upload Key
    echo -e "Uploading local key to remote /tmp..."
    sshpass -p "$PASS" scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa.pub ${BRIDGE}@${IP}:/tmp/temp_key.pub 2>/dev/null

    # 3. IF FAILED: Prompt user to fix password
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Authentication failed with stored password.${NC}"
        echo -e "The saved password seems incorrect for ${YELLOW}${IP}${NC}."
        ensure_bridge_password "true" "$IP"
        PASS=$(cat "$AUTH_FILE")
        echo -e "Retrying upload with new password..."
        sshpass -p "$PASS" scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa.pub ${BRIDGE}@${IP}:/tmp/temp_key.pub
        if [ $? -ne 0 ]; then error_exit "Still failed to upload key."; fi
    fi

    echo -e "Configuring Root Access & SSH Config..."
    REMOTE_SCRIPT="echo '$PASS' | sudo -S -p '' bash -c 'echo \"[Remote] Configuring sshd...\"; sed -i \"s/^#\?PermitRootLogin.*/PermitRootLogin yes/g\" /etc/ssh/sshd_config; echo \"[Remote] Installing keys...\"; mkdir -p /root/.ssh; cat /tmp/temp_key.pub >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; chmod 700 /root/.ssh; rm /tmp/temp_key.pub; echo \"[Remote] Restarting SSHD...\"; if command -v systemctl &> /dev/null; then systemctl restart sshd; else service sshd restart; fi'"

    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no ${BRIDGE}@${IP} "$REMOTE_SCRIPT"

    if [ $? -eq 0 ]; then echo -e "${GREEN}Bootstrap Complete!${NC}"; else error_exit "Failed to configure remote server."; fi
}

check_and_setup_ssh() {
    local USER=$1
    local IP=$2
    echo -e "Checking SSH connection to ${USER}@${IP}..."
    ssh -o BatchMode=yes -o ConnectTimeout=5 "${USER}@${IP}" "exit" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSH Connection OK.${NC}"
        return 0
    else
        echo -e "${YELLOW}SSH failed. Initiating Setup Protocol...${NC}"
        # SELF-HEALING: Clear bad key before trying setup
        ssh-keygen -R "$IP" &>/dev/null
        install_ssh_key "$USER" "$IP"

        ssh -o BatchMode=yes "${USER}@${IP}" "exit"
        if [ $? -eq 0 ]; then echo -e "${GREEN}Setup Successful!${NC}"; return 0; else error_exit "Setup appeared to finish, but Root login still failed."; fi
    fi
}