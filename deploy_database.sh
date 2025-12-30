#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

LOCAL_CHANGESETS="./src/files/opt/raritan/liquibase/changesets"
REMOTE_DB_DEST="/var/oculan/raritan/liquibase/changesets"

if [ ! -d "$LOCAL_CHANGESETS" ]; then
    error_exit "Directory '$LOCAL_CHANGESETS' not found.\nEnsure you are in the root of 'dctrack_database'."
fi

# 0. SAFETY CHECK
echo -e "\n${RED}!!! WARNING: DATABASE MIGRATION !!!${NC}"
echo -e "Target Server:  ${YELLOW}${TARGET_IP}${NC}"
if [ -n "$DB_VERSION" ]; then
    echo -e "Target Version: ${YELLOW}dctrack${DB_VERSION}${NC}"
else
    echo -e "Target Version: ${YELLOW}ALL CHANGESETS${NC}"
fi
echo -e "----------------------------------------"
read -p "Are you sure you want to execute this migration? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Operation Cancelled by user.${NC}"
    exit 0
fi

# 1. FORCE COPY FILES (SCP)
log_step "UPLOAD" "Force syncing files (SCP)..."

if [ -n "$DB_VERSION" ]; then
    # Case A: Specific Version (e.g., 940)
    TARGET_FOLDER="dctrack${DB_VERSION}"
    LOCAL_SRC="${LOCAL_CHANGESETS}/${TARGET_FOLDER}"

    if [ ! -d "$LOCAL_SRC" ]; then
        error_exit "Version folder '$TARGET_FOLDER' not found at:\n$LOCAL_SRC"
    fi

    echo -e "Source Path:  ${YELLOW}${LOCAL_SRC}${NC}"
    echo -e "Uploading:    ${YELLOW}${TARGET_FOLDER}${NC}..."

    # 1. Remove remote folder first to ensure clean state (optional but safer)
    ssh "${REMOTE_USER}@${TARGET_IP}" "rm -rf ${REMOTE_DB_DEST}/${TARGET_FOLDER}"

    # 2. Copy the folder fresh
    # Note: scp -r source dest_parent/ creates source inside dest_parent
    scp -r "${LOCAL_SRC}" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DB_DEST}/"

else
    # Case B: All Versions
    echo -e "Source Path:  ${YELLOW}${LOCAL_CHANGESETS}${NC}"
    echo -e "Uploading:    ${YELLOW}ALL changesets${NC}..."

    # Warning: syncing ALL changesets via SCP might be slow if there are many files
    scp -r "${LOCAL_CHANGESETS}/"* "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DB_DEST}/"
fi

if [ $? -ne 0 ]; then error_exit "SCP transfer failed."; fi

# 2. EXECUTE MIGRATION SCRIPT
log_step "REMOTE" "Executing Database Migration..."
REMOTE_CMD="/usr/local/sbin/database-migrate.sh"

echo -e "Running: ${YELLOW}${REMOTE_CMD}${NC}"
ssh "${REMOTE_USER}@${TARGET_IP}" "${REMOTE_CMD}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Database Migration complete!${NC}"
else
    error_exit "Remote migration script failed."
fi