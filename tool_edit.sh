#!/bin/bash

edit_remote_file() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    local FILE_PATH=$3
    local HISTORY_FILE="$HOME/.t_edit_history"

    # === CONFIGURATION ===
    local IDEA_PATH="${LOCAL_IDE_PATH:-$HOME/.local/share/JetBrains/Toolbox/scripts/idea}"

    # ================= 1. HISTORY SELECTION (UI FILTER) =================
    if [ -z "$FILE_PATH" ]; then
        # Load History
        local -a HISTORY_ITEMS
        if [ -f "$HISTORY_FILE" ]; then
            mapfile -t HISTORY_ITEMS < <(head -n 20 "$HISTORY_FILE")
        fi

        # Prepend "New File" option
        local OPTIONS=("+ New File...")
        OPTIONS+=("${HISTORY_ITEMS[@]}")

        echo -e "${YELLOW}Select file to edit:${NC}"

        # UI: Filter/Search
        SELECTED=$(printf "%s\n" "${OPTIONS[@]}" | ui_filter "Select or Search file...")

        if [[ "$SELECTED" == "+ New File..." ]]; then
            FILE_PATH=$(ui_input "/path/to/remote/file.txt")
        elif [ -n "$SELECTED" ]; then
            # Strip any status tags if we had them (legacy compatibility)
            FILE_PATH="${SELECTED% \[*}"
        else
            echo "No file selected."
            exit 0
        fi
    fi

    # Final Check
    if [ -z "$FILE_PATH" ]; then
        error_exit "No path provided."
    fi

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
        if ! ui_confirm "File '${FILE_PATH}' does not exist. Create it?"; then
            exit 1
        fi
    fi

    # ================= 2. UPDATE HISTORY =================
    if [ ! -f "$HISTORY_FILE" ]; then touch "$HISTORY_FILE"; fi
    clean_history_entry "$FILE_PATH"
    # Prepend
    echo "$FILE_PATH" | cat - "$HISTORY_FILE" > "${HISTORY_FILE}.new"
    head -n 20 "${HISTORY_FILE}.new" > "$HISTORY_FILE"
    rm -f "${HISTORY_FILE}.new"

    # ================= 3. EDITOR SELECTION =================
    log_step "EDIT" "Target: ${YELLOW}${FILE_PATH}${NC} on ${TARGET_IP}"

    local HAS_IDEA=false
    if [ -f "$IDEA_PATH" ]; then HAS_IDEA=true; fi

    local EDIT_TOOL=""
    local E_OPTS=()
    if [ "$HAS_IDEA" = true ]; then E_OPTS+=("IntelliJ Ultimate (SSHFS)"); fi
    E_OPTS+=("Vim (Terminal)" "Nano (Terminal)")

    CHOSEN_TOOL=$(ui_choose "${E_OPTS[@]}")

    if [[ "$CHOSEN_TOOL" == "IntelliJ"* ]]; then EDIT_TOOL="1"; fi
    if [[ "$CHOSEN_TOOL" == "Vim"* ]]; then EDIT_TOOL="2"; fi
    if [[ "$CHOSEN_TOOL" == "Nano"* ]]; then EDIT_TOOL="3"; fi

    case "$EDIT_TOOL" in
        1)
            # SSHFS Logic
            if ! command -v sshfs &> /dev/null; then error_exit "'sshfs' missing."; fi
            local MNT_DIR="/tmp/t_mnt_${TARGET_IP}"
            mkdir -p "$MNT_DIR"

            if ! grep -qs "$MNT_DIR" /proc/mounts; then
                sshfs -o reconnect,ServerAliveInterval=15 "${REMOTE_USER}@${TARGET_IP}:/" "$MNT_DIR"
            fi

            echo -e "${YELLOW}Launching IntelliJ...${NC}"
            "$IDEA_PATH" "${MNT_DIR}${FILE_PATH}" > /dev/null 2>&1 &

            echo -e "${GREEN}Session Active.${NC}"
            ui_input "Press Enter to unmount and finish..." "false" "Press Enter..." > /dev/null

            fusermount -u "$MNT_DIR" && rmdir "$MNT_DIR"
            ;;
        2) ssh -t "${REMOTE_USER}@${TARGET_IP}" "vim ${FILE_PATH}" ;;
        3) ssh -t "${REMOTE_USER}@${TARGET_IP}" "nano ${FILE_PATH}" ;;
    esac
}