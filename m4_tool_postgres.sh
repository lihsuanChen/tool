#!/bin/bash

# Function to whitelist the current machine's IP in Postgres
pg_whitelist_ip() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # 1. Get Local IP (The machine running this script)
    local LOCAL_IP=$(hostname -I | awk '{print $1}')

    if [ -z "$LOCAL_IP" ]; then
        error_exit "Could not determine Local IP."
    fi

    log_step "POSTGRES" "Whitelisting Local IP (${YELLOW}${LOCAL_IP}${NC}) on Remote Host..."

    # 2. Define Configuration
    local PG_CONF="/var/lib/pgsql/data/pg_hba.conf"

    # UPDATED: Added /32 to the IP address
    local NEW_ENTRY="host    all             all             ${LOCAL_IP}/32            trust"

    # 3. Execute Remote Command
    # Note: We do NOT use ${GREEN} colors inside the remote block to prevent SSH syntax errors.
    ssh "${REMOTE_USER}@${TARGET_IP}" "
        # Check if the specific IP/32 entry already exists
        if grep -qF '${LOCAL_IP}/32' '${PG_CONF}'; then
            echo '[Remote] IP ${LOCAL_IP}/32 is already in pg_hba.conf. Skipping.'
        else
            echo '[Remote] Adding ${LOCAL_IP}/32 to whitelist...'
            echo '${NEW_ENTRY}' >> '${PG_CONF}'

            echo '[Remote] Restarting PostgreSQL Service...'
            if command -v systemctl &> /dev/null; then
                systemctl restart postgresql.service
            else
                service postgresql restart
            fi
        fi
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: PostgreSQL Access Enabled for ${LOCAL_IP}.${NC}"
    else
        error_exit "Failed to update PostgreSQL configuration."
    fi
}