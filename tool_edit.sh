#!/bin/bash

edit_remote_file() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    local FILE_PATH=$3
    local HISTORY_FILE="$HOME/.t_edit_history"

    # === CONFIGURATION ===
    local IDEA_PATH="${LOCAL_IDE_PATH:-$HOME/.local/share/JetBrains/Toolbox/scripts/idea}"

    # ================= 1. HISTORY SELECTION (GUM FILTER) =================
    if [ -z "$FILE_PATH" ]; then

        # Load History
        local -a HISTORY_ITEMS
        if [ -f "$HISTORY_FILE" ]; then
            mapfile -t HISTORY_ITEMS < <(head -n 20 "$HISTORY_FILE")
        fi

        if command -v gum &> /dev/null; then
            # --- GUM MODE ---
            # Add "New File" as the top option
            local OPTIONS=("+ New File...")
            OPTIONS+=("${HISTORY_ITEMS[@]}")

            echo -e "${YELLOW}Select file to edit (Type to filter):${NC}"
            # Pass the array to gum filter
            SELECTED=$(printf "%s\n" "${OPTIONS[@]}" | gum filter --height 10 --placeholder "Select file...")

            if [[ "$SELECTED" == "+ New File..." ]]; then
                FILE_PATH=$(gum input --placeholder "/path/to/remote/file.txt")
            elif [ -n "$SELECTED" ]; then
                # Strip any status tags if we had them (legacy compatibility)
                FILE_PATH="${SELECTED% \[*}"
            else
                echo "No file selected."
                exit 0
            fi
        else
            # --- LEGACY MODE (Fallback) ---
            echo -e "${YELLOW}Select a file to edit:${NC}"
            local COUNT=1
            for item in "${HISTORY_ITEMS[@]}"; do
                echo -e "  ${GREEN}${COUNT})${NC} ${item}"
                ((COUNT++))
            done
            echo -e "  ${GREEN}n)${NC} Enter new file path..."

            read -p "Select choice: " SEL_CHOICE
            if [[ "$SEL_CHOICE" =~ ^[Nn]$ ]]; then
                read -p "Enter Full File Path: " FILE_PATH
            elif [[ "$SEL_CHOICE" =~ ^[0-9]+$ ]]; then
                IDX=$((SEL_CHOICE - 1))
                FILE_PATH="${HISTORY_ITEMS[$IDX]}"
            fi
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
        if command -v gum &> /dev/null; then
             if ! gum confirm "File '${FILE_PATH}' does not exist. Create it?"; then
                 exit 1
             fi
        else
             echo -e "${RED}File '${FILE_PATH}' not found.${NC}"
             read -p "Create new? (y/N): " C
             if [[ ! "$C" =~ ^[Yy]$ ]]; then exit 1; fi
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

    if command -v gum &> /dev/null; then
        # Build Options array
        local E_OPTS=()
        if [ "$HAS_IDEA" = true ]; then E_OPTS+=("IntelliJ Ultimate (SSHFS)"); fi
        E_OPTS+=("Vim (Terminal)" "Nano (Terminal)")

        CHOSEN_TOOL=$(printf "%s\n" "${E_OPTS[@]}" | gum choose)

        if [[ "$CHOSEN_TOOL" == "IntelliJ"* ]]; then EDIT_TOOL="1"; fi
        if [[ "$CHOSEN_TOOL" == "Vim"* ]]; then EDIT_TOOL="2"; fi
        if [[ "$CHOSEN_TOOL" == "Nano"* ]]; then EDIT_TOOL="3"; fi
    else
        # Legacy
        echo -e "  1) IntelliJ"
        echo -e "  2) Vim"
        read -p "Select: " EDIT_TOOL
    fi

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

            echo -e "${GREEN}Session Active.${NC} Press Enter to Unmount."
            if command -v gum &> /dev/null; then gum input --placeholder "Press Enter to finish..."; else read -p ""; fi

            fusermount -u "$MNT_DIR" && rmdir "$MNT_DIR"
            ;;
        2) ssh -t "${REMOTE_USER}@${TARGET_IP}" "vim ${FILE_PATH}" ;;
        3) ssh -t "${REMOTE_USER}@${TARGET_IP}" "nano ${FILE_PATH}" ;;
    esac
}