#!/bin/bash

# ALWAYS load the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_ssh.sh"

# Configuration
REMOTE_SCRIPT_DEST="/opt"
SCRIPT_NAME=$(basename "$LOCAL_DNF_SCRIPT")

log_step "DNF-UPDATE" "Preparing to run DNF Update"

# 1. VERIFY LOCAL FILE EXISTS
if [ ! -f "$LOCAL_DNF_SCRIPT" ]; then
    error_exit "Local script not found at: $LOCAL_DNF_SCRIPT"
fi

echo -e "Source: ${YELLOW}$LOCAL_DNF_SCRIPT${NC}"
echo -e "Destination: ${YELLOW}${REMOTE_USER}@${TARGET_IP}:${REMOTE_SCRIPT_DEST}/${SCRIPT_NAME}${NC}"

# 2. TRANSFER FILE
log_step "DNF-UPDATE" "Transferring Script to /opt"
scp "$LOCAL_DNF_SCRIPT" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_SCRIPT_DEST}/${SCRIPT_NAME}"

if [ $? -ne 0 ]; then
    error_exit "Failed to transfer script. (Note: Writing to /opt usually requires root)."
fi

# 3. EXECUTE REMOTE SCRIPT
log_step "DNF-UPDATE" "Executing Remote Script"

REMOTE_CMDS="
chmod +x ${REMOTE_SCRIPT_DEST}/${SCRIPT_NAME} && \
cd ${REMOTE_SCRIPT_DEST} && \
./${SCRIPT_NAME}
"

ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMDS"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Remote script executed successfully!${NC}"
else
    error_exit "Remote script execution failed."
fi