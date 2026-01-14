#!/bin/bash

edit_remote_file() {
    local REMOTE_USER=$1
    local TARGET_IP=$2
    local FILE_PATH=$3
    local HISTORY_FILE="$HOME/.t_edit_history"

    # === CONFIGURATION ===
    local TAG_MISSING=" [NOT FOUND]"
    local GRAY='\033[90m'

    # Load IDE Path from Config (Fallback to previous default if unset)
    local IDEA_PATH="${LOCAL_IDE_PATH:-$HOME/.local/share/JetBrains/Toolbox/scripts/idea}"

    # ================= 1. HISTORY & INTERACTIVE SELECTION =================
    if [ -z "$FILE_PATH" ]; then
        echo -e "${YELLOW}No file specified.${NC}"

        # Load History
        local -a HISTORY_ITEMS
        if [ -f "$HISTORY_FILE" ]; then
            mapfile -t HISTORY_ITEMS < <(head -n 12 "$HISTORY_FILE")
        fi

        echo -e "${YELLOW}Select a file to edit:${NC}"

        # 1. LIST HISTORY (Color Logic)
        local COUNT=1
        for item in "${HISTORY_ITEMS[@]}"; do
            if [[ "$item" == *"$TAG_MISSING"* ]]; then
                # INVALID: Dark Gray (Not obvious)
                echo -e "  ${YELLOW}${COUNT}) ${item}${NC}"
            else
                # VALID: Green (Obvious)
                echo -e "  ${GREEN}${COUNT}) ${item}${NC}"
            fi
            ((COUNT++))
        done

        # 2. SHOW NEW FILE OPTION
        echo -e "  ${GREEN}n)${NC} Enter new file path..."

        local MAX_OPT=$((COUNT - 1))

        # === PROMPT ===
        if [ "$MAX_OPT" -eq 0 ]; then
            read -p "Select [n]: " SEL_CHOICE
        else
            read -p "Select [1-${MAX_OPT}] or 'n': " SEL_CHOICE
        fi

        if [ -z "$SEL_CHOICE" ]; then
            if [ "$MAX_OPT" -gt 0 ]; then SEL_CHOICE="1"; else SEL_CHOICE="n"; fi
        fi

        # === SELECTION LOGIC ===
        if [[ "$SEL_CHOICE" =~ ^[Nn]$ ]]; then
            read -p "Enter Full File Path: " FILE_PATH
        elif [[ "$SEL_CHOICE" =~ ^[0-9]+$ ]]; then
            local IDX=$((SEL_CHOICE - 1))
            if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#HISTORY_ITEMS[@]}" ]; then
                FILE_PATH="${HISTORY_ITEMS[$IDX]}"
                # STRIP THE TAG to retry the raw path
                FILE_PATH="${FILE_PATH%${TAG_MISSING}}"
            else
                echo -e "${RED}Invalid selection number.${NC}"
                exit 1
            fi
        else
            FILE_PATH="$SEL_CHOICE"
        fi
    fi

    # Final Check
    if [ -z "$FILE_PATH" ]; then
        echo -e "${RED}Error: No path provided. Aborting.${NC}"
        exit 1
    fi

    # Helper function
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
        echo -e "${RED}Warning: Remote file '${FILE_PATH}' does not exist.${NC}"
        read -p "Do you want to create a NEW file? (y/N): " CREATE_CONFIRM

        if [[ ! "$CREATE_CONFIRM" =~ ^[Yy]$ ]]; then
            clean_history_entry "$FILE_PATH"
            echo "${FILE_PATH}${TAG_MISSING}" >> "$HISTORY_FILE"
            echo -e "${YELLOW}Marked as missing and moved to bottom of list.${NC}"
            exit 1
        fi
        echo -e "${BLUE}Proceeding to create new file...${NC}"
    fi

    # ================= 2. UPDATE HISTORY (SUCCESS) =================
    if [ ! -f "$HISTORY_FILE" ]; then touch "$HISTORY_FILE"; fi

    clean_history_entry "$FILE_PATH"

    # Prepend Clean Path to TOP
    echo "$FILE_PATH" | cat - "$HISTORY_FILE" > "${HISTORY_FILE}.new"
    head -n 12 "${HISTORY_FILE}.new" > "$HISTORY_FILE"
    rm -f "${HISTORY_FILE}.new"

    # ================= 3. EDITOR LOGIC =================
    log_step "EDIT" "Target: ${YELLOW}${FILE_PATH}${NC} on ${TARGET_IP}"

    local HAS_IDEA=false
    if [ -f "$IDEA_PATH" ]; then HAS_IDEA=true; fi

    echo -e "${YELLOW}Select Editor:${NC}"

    if [ "$HAS_IDEA" = true ]; then
        echo -e "  ${GREEN}1)${NC} IntelliJ Ultimate (WSL via SSHFS)"
    else
        echo -e "  ${BLACK}1) IntelliJ Ultimate (Not detected at configured path)${NC}"
    fi
    echo -e "  ${GREEN}2)${NC} Vim (Terminal)"
    echo -e "  ${GREEN}3)${NC} Nano (Terminal)"

    read -p "Select option [1]: " EDITOR_CHOICE
    EDITOR_CHOICE=${EDITOR_CHOICE:-1}

    case "$EDITOR_CHOICE" in
        1)
            if [ "$HAS_IDEA" = true ]; then
                if ! command -v sshfs &> /dev/null; then
                    echo -e "${RED}Error: 'sshfs' is not installed.${NC} Run: sudo apt install sshfs"
                    exit 1
                fi

                local MNT_DIR="/tmp/t_mnt_${TARGET_IP}"
                mkdir -p "$MNT_DIR"

                if grep -qs "$MNT_DIR" /proc/mounts; then
                    echo -e "${BLUE}Mount point active. Reusing...${NC}"
                else
                    echo -e "${BLUE}Mounting ${TARGET_IP} via SSHFS...${NC}"
                    sshfs -o reconnect,ServerAliveInterval=15 "${REMOTE_USER}@${TARGET_IP}:/" "$MNT_DIR"
                    if [ $? -ne 0 ]; then echo -e "${RED}Mount failed.${NC}"; exit 1; fi
                fi

                echo -e "${YELLOW}Launching IntelliJ...${NC} (Ctrl+S to save remote)"

                local IDEA_LOG="/tmp/t_idea_launch.log"
                "$IDEA_PATH" "${MNT_DIR}${FILE_PATH}" > "$IDEA_LOG" 2>&1 &
                local PID=$!

                sleep 2

                if ps -p $PID > /dev/null; then
                    echo -e "${GREEN}IntelliJ started (PID $PID).${NC}"
                else
                    if grep -qi "error" "$IDEA_LOG" && [ -s "$IDEA_LOG" ]; then
                         echo -e "${YELLOW}Process ended (Check /tmp/t_idea_launch.log).${NC}"
                    else
                         echo -e "${GREEN}Request sent to running IntelliJ instance.${NC}"
                    fi
                fi

                echo -e ""
                echo -e "${GREEN}Session Active.${NC} Press ${YELLOW}[ENTER]${NC} here when finished to Unmount."
                read -p ""

                echo -e "Unmounting..."
                fusermount -u "$MNT_DIR" && rmdir "$MNT_DIR"
            else
                echo -e "${RED}IntelliJ path invalid.${NC} Check LOCAL_IDE_PATH in .t_config."
                exit 1
            fi
            ;;
        2) ssh -t "${REMOTE_USER}@${TARGET_IP}" "vim ${FILE_PATH}" ;;
        3) ssh -t "${REMOTE_USER}@${TARGET_IP}" "nano ${FILE_PATH}" ;;
        *) echo "Invalid choice." ;;
    esac
}