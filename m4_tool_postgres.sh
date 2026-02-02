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

# Function to Manage Local Data Backups (Backup/Restore)
pg_manage_backups() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # Config (Defaults from global or fallback)
    local SERVICE="${PG_SERVICE:-postgresql}"
    local DATA_DIR="${PG_DATA_DIR:-/var/lib/pgsql/data}"
    local BACKUP_DIR="/var/lib/pgsql/backups"

    log_step "PG-BACKUP" "Managing PostgreSQL Data on ${TARGET_IP}..."

    # 1. Select Action
    local ACTION
    ACTION=$(ui_choose "Create Backup" "Restore Backup" "Cancel")

    if [[ "$ACTION" == "Create Backup" ]]; then
        # === BACKUP LOGIC ===
        local TS=$(date +%Y%m%d_%H%M%S)
        local FNAME="pg_data_${TS}.tar.gz"

        echo -e "Target: ${YELLOW}${BACKUP_DIR}/${FNAME}${NC}"

        # We assume physical backup requires service stop to ensure consistency
        if ! ui_confirm "Stop ${SERVICE}, Backup Data, and Restart?"; then return; fi

        ssh "${REMOTE_USER}@${TARGET_IP}" "
            echo '[Remote] Preparing backup directory...'
            mkdir -p ${BACKUP_DIR}
            chown postgres:postgres ${BACKUP_DIR}

            echo '[Remote] Stopping ${SERVICE}...'
            if command -v systemctl &> /dev/null; then systemctl stop ${SERVICE}; else service ${SERVICE} stop; fi

            echo '[Remote] Archiving ${DATA_DIR}...'
            # Use dirname to tar the 'data' folder itself
            cd \$(dirname ${DATA_DIR})
            tar -czf ${BACKUP_DIR}/${FNAME} \$(basename ${DATA_DIR})

            echo '[Remote] Restarting ${SERVICE}...'
            if command -v systemctl &> /dev/null; then systemctl start ${SERVICE}; else service ${SERVICE} start; fi
        "

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}SUCCESS: Backup created at ${BACKUP_DIR}/${FNAME}${NC}"
        else
            error_exit "Backup operation failed."
        fi

    elif [[ "$ACTION" == "Restore Backup" ]]; then
        # === RESTORE LOGIC ===

        # 1. Fetch List
        echo "Fetching available backups..."
        local RAW_LIST
        RAW_LIST=$(ssh "${REMOTE_USER}@${TARGET_IP}" "ls -1 ${BACKUP_DIR}/*.tar.gz 2>/dev/null")

        if [ -z "$RAW_LIST" ]; then
            error_exit "No backups found in ${BACKUP_DIR}."
        fi

        # 2. Select Backup
        # We strip the path for the menu, then reconstruct it
        local FILES=$(echo "$RAW_LIST" | xargs -n1 basename)
        local SELECTED=$(echo "$FILES" | gum filter --placeholder "Select Backup to Restore...")

        if [ -z "$SELECTED" ]; then echo "Cancelled."; return; fi

        # 3. Warning
        echo -e "${RED}!!! WARNING: DESTRUCTIVE OPERATION !!!${NC}"
        echo -e "You are about to restore: ${YELLOW}${SELECTED}${NC}"
        echo -e "This will:"
        echo -e "  1. Stop ${SERVICE}"
        echo -e "  2. ${RED}DELETE ALL CURRENT DATA${NC} in ${DATA_DIR}"
        echo -e "  3. Extract contents from the backup"

        if ! ui_confirm "Are you ABSOLUTELY SURE?"; then
             echo "Operation cancelled."
             return
        fi

        # 4. Execute Restore
        ssh "${REMOTE_USER}@${TARGET_IP}" "
            set -e
            echo '[Remote] Stopping ${SERVICE}...'
            if command -v systemctl &> /dev/null; then systemctl stop ${SERVICE}; else service ${SERVICE} stop; fi

            echo '[Remote] Wiping current data directory...'
            # Safety check: Ensure we are deleting the right thing
            if [ \"${DATA_DIR}\" == \"/var/lib/pgsql/data\" ]; then
                rm -rf ${DATA_DIR:?}/*
            else
                echo 'Non-standard path detected. Aborting wipe for safety.'
                exit 1
            fi

            echo '[Remote] Extracting backup...'
            cd \$(dirname ${DATA_DIR})
            tar -xzf ${BACKUP_DIR}/${SELECTED}

            echo '[Remote] Fixing permissions...'
            chown -R postgres:postgres ${DATA_DIR}
            # Restore SELinux context if restorecon exists
            if command -v restorecon &> /dev/null; then restorecon -R ${DATA_DIR}; fi

            echo '[Remote] Restarting ${SERVICE}...'
            if command -v systemctl &> /dev/null; then systemctl start ${SERVICE}; else service ${SERVICE} start; fi
        "

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}SUCCESS: Database restored from ${SELECTED}.${NC}"
        else
            error_exit "Restore failed. Please check server status manually."
        fi
    fi
}