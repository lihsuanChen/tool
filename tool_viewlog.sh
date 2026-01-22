#!/bin/bash

VIEWER_CONFIG="$HOME/.t_viewer_pref"

# ================= SWITCH FUNCTION =================
switch_log_viewer() {
    echo -e "${YELLOW}Current Viewer:${NC}"
    if [ -f "$VIEWER_CONFIG" ]; then cat "$VIEWER_CONFIG"; else echo "lnav"; fi

    if command -v gum &> /dev/null; then
        CHOICE=$(gum choose "lnav (Terminal)" "glogg (GUI/X11)" "Cancel")
        if [[ "$CHOICE" == "lnav"* ]]; then
            echo "lnav" > "$VIEWER_CONFIG"
            echo -e "${GREEN}Set to lnav.${NC}"
        elif [[ "$CHOICE" == "glogg"* ]]; then
            echo "glogg" > "$VIEWER_CONFIG"
            echo -e "${GREEN}Set to glogg.${NC}"
        fi
    else
        # Legacy
        echo "1) lnav"
        echo "2) glogg"
        read -p "Choice: " C
        if [ "$C" == "1" ]; then echo "lnav" > "$VIEWER_CONFIG"; fi
        if [ "$C" == "2" ]; then echo "glogg" > "$VIEWER_CONFIG"; fi
    fi
}

# ================= VIEW FUNCTION =================
view_remote_log_gui() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # Configs
    local T_LOG="${TOMCAT_LOG_BASE:-/var/log/tomcat10}"
    local O_LOG="${OCULAN_LOG_BASE:-/var/log/oculan}"
    local PG_LOG="${POSTGRES_LOG_DIR:-/var/lib/pgsql/data/log}"

    local USE_VIEWER="lnav"
    if [ -f "$VIEWER_CONFIG" ]; then USE_VIEWER=$(cat "$VIEWER_CONFIG"); fi

    log_step "VIEWLOG" "Fetching log list from ${TARGET_IP}..."

    # 1. BUILD LOG LIST (Standard + Dynamic Postgres)
    declare -a LOG_OPTIONS

    # Standard Logs
    LOG_OPTIONS+=("${T_LOG}/dcTrackServer.log")
    LOG_OPTIONS+=("${T_LOG}/catalina.out")
    LOG_OPTIONS+=("${T_LOG}/access_logs.out")
    LOG_OPTIONS+=("${T_LOG}/floorMapsService.log")
    LOG_OPTIONS+=("${O_LOG}/backup-restore.log")
    LOG_OPTIONS+=("${O_LOG}/database-init.log")
    LOG_OPTIONS+=("${O_LOG}/upgrade.log")
    LOG_OPTIONS+=("/var/oculan/activemq/data/activemq.log")

    # Dynamic Postgres Logs (Newest First)
    # We fetch them and append to the array
    REMOTE_CMD="find ${PG_LOG}/ -maxdepth 1 -name 'postgresql-*.log' -printf '%p\n' 2>/dev/null | sort -r"
    mapfile -t PG_LOGS < <(ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMD")

    # Combine
    LOG_OPTIONS+=("${PG_LOGS[@]}")
    LOG_OPTIONS+=("+ Custom Path...")

    local TARGET_LOG=""

    if command -v gum &> /dev/null; then
        # === GUM FILTER ===
        echo -e "${YELLOW}Select Log File (Type to filter):${NC}"
        TARGET_LOG=$(printf "%s\n" "${LOG_OPTIONS[@]}" | gum filter --height 15 --placeholder "Search logs...")

        if [[ "$TARGET_LOG" == "+ Custom Path..." ]]; then
            TARGET_LOG=$(gum input --placeholder "/path/to/log.log")
        fi
    else
        # === LEGACY LIST ===
        echo "GUM not found. Using simple list."
        local I=1
        for L in "${LOG_OPTIONS[@]}"; do
            echo "$I) $L"
            ((I++))
        done
        read -p "Select: " IDX
        IDX=$((IDX-1))
        TARGET_LOG="${LOG_OPTIONS[$IDX]}"
    fi

    if [ -z "$TARGET_LOG" ]; then echo "Cancelled."; return; fi

    # 2. EXECUTE VIEWER
    if [ "$USE_VIEWER" == "glogg" ]; then
        echo -e "${YELLOW}Opening glogg (X11)...${NC}"
        ssh -X "${REMOTE_USER}@${TARGET_IP}" "glogg '${TARGET_LOG}'" 2>/dev/null
    else
        echo -e "${YELLOW}Opening lnav...${NC}"
        ssh -t "${REMOTE_USER}@${TARGET_IP}" "lnav '${TARGET_LOG}'"
    fi
}