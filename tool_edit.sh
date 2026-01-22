#!/bin/bash

edit_remote_file() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    local FILE_PATH=$3
    local HISTORY_FILE="$HOME/.t_edit_history"

    # === CONFIGURATION ===
    local IDEA_PATH="${LOCAL_IDE_PATH:-$HOME/.local/share/JetBrains/Toolbox/scripts/idea}"
    local MNT_DIR="/tmp/t_mnt_${TARGET_IP}"

    # ================= 1. HISTORY SELECTION (UI FILTER) =================
    if [ -z "$FILE_PATH" ]; then
        local -a HISTORY_ITEMS
        if [ -f "$HISTORY_FILE" ]; then
            mapfile -t HISTORY_ITEMS < <(head -n 20 "$HISTORY_FILE")
        fi
        local OPTIONS=("+ New File...")
        OPTIONS+=("${HISTORY_ITEMS[@]}")

        echo -e "${YELLOW}Select file to edit:${NC}"
        SELECTED=$(printf "%s\n" "${OPTIONS[@]}" | ui_filter "Select or Search file...")

        if [[ "$SELECTED" == "+ New File..." ]]; then
            FILE_PATH=$(ui_input "/path/to/remote/file.txt")
        elif [ -n "$SELECTED" ]; then
            FILE_PATH="${SELECTED% \[*}"
        else
            echo "No file selected."; exit 0
        fi
    fi

    if [ -z "$FILE_PATH" ]; then error_exit "No path provided."; fi

    # Helper to clean history
    clean_history_entry() {
        local P=$1
        if [ -f "$HISTORY_FILE" ]; then
            grep -vF "$P" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
            mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
        fi
    }

    # ================= 1.5 REMOTE VERIFICATION =================
    ssh -q "${REMOTE_USER}@${TARGET_IP}" "test -e \"${FILE_PATH}\""
    if [ $? -ne 0 ]; then
        if ! ui_confirm "File '${FILE_PATH}' does not exist. Create it?"; then exit 1; fi
    fi

    # ================= 2. UPDATE HISTORY =================
    if [ ! -f "$HISTORY_FILE" ]; then touch "$HISTORY_FILE"; fi
    clean_history_entry "$FILE_PATH"
    echo "$FILE_PATH" | cat - "$HISTORY_FILE" > "${HISTORY_FILE}.new"
    head -n 20 "${HISTORY_FILE}.new" > "$HISTORY_FILE"
    rm -f "${HISTORY_FILE}.new"

    # ================= 3. EDITOR SELECTION =================
    log_step "EDIT" "Target: ${YELLOW}${FILE_PATH}${NC} on ${TARGET_IP}"

    local HAS_IDEA=false; if [ -f "$IDEA_PATH" ]; then HAS_IDEA=true; fi
    local EDIT_TOOL=""; local E_OPTS=()
    if [ "$HAS_IDEA" = true ]; then E_OPTS+=("IntelliJ Ultimate (SSHFS)"); fi
    E_OPTS+=("Vim (Terminal)" "Nano (Terminal)")

    CHOSEN_TOOL=$(ui_choose "${E_OPTS[@]}")
    if [[ "$CHOSEN_TOOL" == "IntelliJ"* ]]; then EDIT_TOOL="1"; fi
    if [[ "$CHOSEN_TOOL" == "Vim"* ]]; then EDIT_TOOL="2"; fi
    if [[ "$CHOSEN_TOOL" == "Nano"* ]]; then EDIT_TOOL="3"; fi

    # ================= 4. SSHFS FUNCTIONS (ROBUST & FAST) =================
    mount_sshfs() {
        if ! command -v sshfs &> /dev/null; then error_exit "'sshfs' missing."; fi
        mkdir -p "$MNT_DIR"

        # Check Stale Mounts (Fast check)
        if grep -qs "$MNT_DIR" /proc/mounts; then
            if ! timeout 1s ls -d "$MNT_DIR" >/dev/null 2>&1; then
                echo -e "${YELLOW}Cleaning stale mount...${NC}"
                fusermount -u -z "$MNT_DIR"
            else
                echo -e "${BLUE}Reusing existing mount...${NC}"
                return 0
            fi
        fi

        # Mount with compression for speed
        echo -e "${BLUE}Mounting...${NC}"
        sshfs -o reconnect,ServerAliveInterval=15,compression=yes "${REMOTE_USER}@${TARGET_IP}:/" "$MNT_DIR"
        if [ $? -ne 0 ]; then error_exit "Mount failed."; fi
    }

    unmount_sshfs() {
        # Check if actually mounted
        if grep -qs "$MNT_DIR" /proc/mounts; then
            echo -e "${BLUE}Unmounting...${NC}"

            # FAST UNMOUNT STRATEGY:
            # 1. Try standard unmount with a short timeout (2s).
            # 2. If it blocks >2s, assume connection is stuck and force Lazy Unmount (-z).
            if ! timeout 2s fusermount -u "$MNT_DIR"; then
                echo -e "${YELLOW}Standard unmount stalled. Forcing detach...${NC}"
                fusermount -u -z "$MNT_DIR"
            fi
        fi

        # Always try to remove dir and RETURN TRUE (0)
        # This prevents the loop from thinking unmount failed just because dir wasn't empty or grep failed
        rmdir "$MNT_DIR" 2>/dev/null
        return 0
    }

    # ================= 5. EXECUTION =================
    case "$EDIT_TOOL" in
        1)
            trap "unmount_sshfs; exit" INT TERM
            mount_sshfs

            echo -e "${YELLOW}Launching IntelliJ...${NC}"
            "$IDEA_PATH" "${MNT_DIR}${FILE_PATH}" > /dev/null 2>&1 &

            while true; do
                echo -e "\n${GREEN}=== SESSION ACTIVE ===${NC}"
                echo -e "Remote: ${REMOTE_USER}@${TARGET_IP}:${FILE_PATH}"

                ACTION=$(ui_choose "Unmount & Exit" "Check File Timestamp" "Open Terminal")

                if [[ "$ACTION" == "Unmount"* ]]; then
                    # Unconditional break prevents double prompt
                    unmount_sshfs
                    break

                elif [[ "$ACTION" == "Check File"* ]]; then
                    stat -c "Modified: %y" "${MNT_DIR}${FILE_PATH}" 2>/dev/null || echo "File not accessible."

                elif [[ "$ACTION" == "Open Terminal"* ]]; then
                    ssh "${REMOTE_USER}@${TARGET_IP}"
                fi
            done
            trap - INT TERM
            ;;
        2) ssh -t "${REMOTE_USER}@${TARGET_IP}" "vim ${FILE_PATH}" ;;
        3) ssh -t "${REMOTE_USER}@${TARGET_IP}" "nano ${FILE_PATH}" ;;
    esac
}