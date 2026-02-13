#!/bin/bash

# ==============================================================================
# MODULE: Execution Abstraction Layer
# DESCRIPTION: Handles command execution and file synchronization transparently
#              for both Remote (SSH) and Local (WSL2/Linux) targets.
# ==============================================================================

# Global State (Set by tool_main.sh)
IS_LOCAL_MODE="${IS_LOCAL_MODE:-false}"

# ------------------------------------------------------------------------------
# FUNCTION: run_remote_cmd
# DESCRIPTION: Executes a command string on the target.
# USAGE: run_remote_cmd "user" "ip" "command_string" [use_tty: true/false]
# ------------------------------------------------------------------------------
run_remote_cmd() {
    local R_USER=$1
    local R_IP=$2
    local CMD_STR=$3
    local USE_TTY="${4:-true}" # Default to true for interactive sudo prompts

    log_step "EXEC" "Target: ${R_IP} (Local Mode: ${IS_LOCAL_MODE})"

    if [ "$IS_LOCAL_MODE" == "true" ]; then
        # === LOCAL MODE ===
        echo -e "${YELLOW}[Local Execution]${NC} Running command locally..."

        # [FIX] Use Temporary Script Execution
        # Creating a physical script file avoids 'eval' quoting issues and
        # ensures 'sudo' has proper TTY access without subshell buffering.

        local TMP_SCRIPT
        TMP_SCRIPT=$(mktemp)

        # Write command to temp file
        echo "#!/bin/bash" > "$TMP_SCRIPT"
        echo "$CMD_STR" >> "$TMP_SCRIPT"

        chmod +x "$TMP_SCRIPT"

        # Execute the script
        bash "$TMP_SCRIPT"
        local RET=$?

        # Cleanup
        rm -f "$TMP_SCRIPT"

        return $RET
    else
        # === REMOTE MODE ===
        local SSH_OPTS=""
        if [ "$USE_TTY" == "true" ]; then
            SSH_OPTS="-t" # Allocate pseudo-terminal for interactive programs/sudo
        fi

        # Pass through to standard SSH
        ssh $SSH_OPTS "${R_USER}@${R_IP}" "$CMD_STR"
        return $?
    fi
}

# ------------------------------------------------------------------------------
# FUNCTION: sync_to_target
# DESCRIPTION: Syncs files from Local Source to Target Destination.
# USAGE: sync_to_target "source_path" "remote_user" "remote_ip" "dest_path" ["rsync_flags"]
# ------------------------------------------------------------------------------
sync_to_target() {
    local SRC_PATH=$1
    local R_USER=$2
    local R_IP=$3
    local DEST_PATH=$4
    local EXTRA_FLAGS="${5:-}" # e.g. "--delete --relative"

    # [FIX] Calculate Parent Directory to avoid creating file as dir
    local DEST_PARENT
    DEST_PARENT=$(dirname "$DEST_PATH")

    if [ "$IS_LOCAL_MODE" == "true" ]; then
        # === LOCAL MODE ===
        echo -e "${YELLOW}[Local Sync]${NC} ${SRC_PATH} -> ${DEST_PATH}"

        # 1. Ensure Destination PARENT Directory Exists
        if [ ! -d "$DEST_PARENT" ]; then
            mkdir -p "$DEST_PARENT" 2>/dev/null
            if [ $? -ne 0 ]; then
                sudo mkdir -p "$DEST_PARENT"
            fi
        fi

        # 2. Determine if we need SUDO for rsync
        local USE_SUDO="false"
        if [ ! -w "$DEST_PARENT" ]; then
            USE_SUDO="true"
        fi

        # 3. Execute Rsync
        if [ "$USE_SUDO" == "true" ]; then
            sudo rsync -avz $EXTRA_FLAGS "$SRC_PATH" "$DEST_PATH"
        else
            rsync -avz $EXTRA_FLAGS "$SRC_PATH" "$DEST_PATH"
        fi

        if [ $? -ne 0 ]; then
            error_exit "Local file sync failed. (Permission denied?)"
        fi

    else
        # === REMOTE MODE ===
        echo -e "${BLUE}[Remote Sync]${NC} ${SRC_PATH} -> ${R_USER}@${R_IP}:${DEST_PATH}"

        # Ensure remote PARENT directory exists
        ssh "${R_USER}@${R_IP}" "sudo mkdir -p ${DEST_PARENT}"

        # Execute Rsync with SSH
        rsync -avz -e ssh $EXTRA_FLAGS "$SRC_PATH" "${R_USER}@${R_IP}:${DEST_PATH}"

        if [ $? -ne 0 ]; then
            error_exit "Remote file sync failed."
        fi
    fi
}