#!/bin/bash

# ==============================================================================
# MODULE: RPM Installer
# DESCRIPTION: Syncs and installs local RPMs to remote targets.
# ==============================================================================

install_rpm_remote() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    local RPM_DIR="$HOME/tmp/rpms"

    # --- 1. PRE-FLIGHT CHECKS ---
    if [ ! -d "$RPM_DIR" ]; then
        error_exit "RPM directory '$RPM_DIR' not found.\nHave you run 't rpm build' yet?"
    fi

    # --- 2. SELECT RPM (Time Sorted) ---
    log_step "SELECT" "Scanning $RPM_DIR..."

    # List files sorted by time (newest first), take basename
    # We enter the dir to make the output clean for the menu
    local RPM_LIST
    RPM_LIST=$(cd "$RPM_DIR" && ls -1t *.rpm 2>/dev/null)

    if [ -z "$RPM_LIST" ]; then
        error_exit "No .rpm files found in $RPM_DIR."
    fi

    echo -e "${YELLOW}Select RPM to install (Newest First):${NC}"

    local SELECTED_RPM
    # Use ui_filter (gum filter) for selection
    SELECTED_RPM=$(echo "$RPM_LIST" | ui_filter "Select RPM file...")

    if [ -z "$SELECTED_RPM" ]; then
        echo "Cancelled."
        return
    fi

    local LOCAL_FILE="$RPM_DIR/$SELECTED_RPM"

    # --- 3. TARGET CONFIRMATION ---
    # If IP is missing (not passed from main), prompt for it now
    if [ -z "$TARGET_IP" ]; then
        echo -e "${YELLOW}Target IP required for installation.${NC}"
        local RAW_INPUT
        RAW_INPUT=$(ui_input "Enter Target IP" "false")
        # Access resolve helper via subshell or assume simple input
        if [[ "$RAW_INPUT" =~ ^[0-9.]+$ ]]; then
             if [[ "$RAW_INPUT" == *.* ]]; then TARGET_IP="$RAW_INPUT"; else TARGET_IP="${BASE_IP}.${DEFAULT_SUBNET}.${RAW_INPUT}"; fi
        else
             error_exit "Invalid IP."
        fi

        # Ensure SSH connection is valid before proceeding
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
    fi

    log_step "INSTALL" "Target: ${GREEN}${TARGET_IP}${NC} | Artifact: ${YELLOW}${SELECTED_RPM}${NC}"

    # --- 4. SYNC (Upload) ---
    echo -e "Uploading to /tmp/..."
    rsync -avz -e ssh --progress "$LOCAL_FILE" "${REMOTE_USER}@${TARGET_IP}:/tmp/"
    if [ $? -ne 0 ]; then error_exit "Upload failed."; fi

    # --- 5. REMOTE INSTALL ---
    echo -e "Installing via DNF..."

    # Using 'dnf install -y' allows it to handle dependencies automatically
    # We use sudo directly.
    ssh -t "${REMOTE_USER}@${TARGET_IP}" "
        echo '[Remote] Installing RPM...'
        sudo dnf install -y /tmp/${SELECTED_RPM}
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: ${SELECTED_RPM} installed on ${TARGET_IP}!${NC}"
    else
        error_exit "Remote installation failed."
    fi
}