#!/bin/bash

# Master function to initialize a new DC Track VM
run_init_vm_flow() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    local BRIDGE_USER=$3

    log_step "INIT-VM" "Starting Full VM Initialization on ${TARGET_IP}..."

    # ================= 1. ROOT SETUP =================
    # Syncs root password with bridge password
    log_step "INIT-VM" "${YELLOW}[1/3] Setting up Root Access...${NC}"
    ensure_bridge_password "false" "$TARGET_IP"
    setup_root_creds "$BRIDGE_USER" "$TARGET_IP"

    # ================= 1.5 SSH KEY SETUP (FIX) =======
    # Now that root is enabled, we MUST install the SSH key
    # so the next steps don't ask for a password.
    log_step "INIT-VM" "${YELLOW}[Key Sync] Installing SSH Key for Root...${NC}"
    check_and_setup_ssh "$REMOTE_USER" "$TARGET_IP"

    # ================= 2. POSTGRES TRUST =============
    # Whitelists your IP in pg_hba.conf
    log_step "INIT-VM" "${YELLOW}[2/3] Configuring PostgreSQL Whitelist...${NC}"
    pg_whitelist_ip "$REMOTE_USER" "$TARGET_IP"

    # ================= 3. TOMCAT DEBUG ===============
    # Enables JPDA on port 8000
    log_step "INIT-VM" "${YELLOW}[3/3] Enabling Tomcat Remote Debug...${NC}"
    enable_tomcat_debug "$REMOTE_USER" "$TARGET_IP"

    # ================= SUMMARY =======================
    echo -e ""
    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}  SUCCESS: VM ${TARGET_IP} Fully Initialized! ${NC}"
    echo -e "${GREEN}==============================================${NC}"
    echo -e "  1. Root Login:   ${GREEN}Enabled${NC}"
    echo -e "  2. SSH Key:      ${GREEN}Installed${NC}"
    echo -e "  3. Postgres:     ${GREEN}Trusted (${TARGET_IP})${NC}"
    echo -e "  4. Tomcat Debug: ${GREEN}Enabled (Port 8000)${NC}"
}