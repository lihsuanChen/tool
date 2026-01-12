#!/bin/bash

VIEWER_CONFIG="$HOME/.t_viewer_pref"

# ================= SWITCH FUNCTION =================
switch_log_viewer() {
    echo -e "${YELLOW}Current Log Viewer Configuration:${NC}"
    if [ -f "$VIEWER_CONFIG" ]; then
        CURRENT=$(cat "$VIEWER_CONFIG")
        echo -e "  Current: ${GREEN}${CURRENT}${NC}"
    else
        echo -e "  Current: ${GREEN}lnav (Default)${NC}"
    fi

    echo -e ""
    echo -e "Select your preferred viewer:"
    echo -e "  ${GREEN}1)${NC} lnav  (Terminal-based, Fast, No Config)"
    echo -e "  ${GREEN}2)${NC} glogg (GUI Window, Requires X-Server/WSLg)"
    echo -e "  ${GREEN}0)${NC} Cancel"

    read -p "Enter choice: " V_CHOICE

    case "$V_CHOICE" in
        1) echo "lnav" > "$VIEWER_CONFIG"; echo -e "${GREEN}Switched to 'lnav'.${NC}" ;;
        2) echo "glogg" > "$VIEWER_CONFIG"; echo -e "${GREEN}Switched to 'glogg'.${NC}" ;;
        0) echo "Cancelled."; ;;
        *) echo "Invalid choice."; ;;
    esac
}

# ================= VIEW FUNCTION =================
view_remote_log_gui() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # DETERMINE VIEWER
    local USE_VIEWER="lnav" # Default
    if [ -f "$VIEWER_CONFIG" ]; then
        USE_VIEWER=$(cat "$VIEWER_CONFIG")
    fi

    log_step "VIEWLOG" "Using viewer: ${YELLOW}${USE_VIEWER}${NC} on ${TARGET_IP}..."

    # 1. MAIN MENU
    echo -e "${YELLOW}Select a log file to open:${NC}"
    echo -e "  ${GREEN}1)${NC}  PostgreSQL Logs (Dynamic List)"
    echo -e "  ${GREEN}2)${NC}  /var/log/tomcat10/dcTrackServer.log"
    echo -e "  ${GREEN}3)${NC}  /var/log/tomcat10/catalina.out"
    echo -e "  ${GREEN}4)${NC}  /var/log/tomcat10/access_logs.out"
    echo -e "  ${GREEN}5)${NC}  /var/log/tomcat10/floorMapsService.log"
    echo -e "  ${GREEN}6)${NC}  /var/log/tomcat10/gc.log"
    echo -e "  ${GREEN}7)${NC}  /var/log/tomcat10/wfPluginsLog.log"
    echo -e "  ${GREEN}8)${NC}  /var/log/oculan/backup-restore.log"
    echo -e "  ${GREEN}9)${NC}  /var/log/oculan/database-init.log"
    echo -e "  ${GREEN}10)${NC} /var/log/oculan/upgrade.log"
    echo -e "  ${GREEN}11)${NC} /var/oculan/activemq/data/activemq.log"
    echo -e "  ${GREEN}12)${NC} Custom Path..."
    echo -e "  ${GREEN}0)${NC}  Cancel"

    read -p "Enter choice [1-12]: " LOG_CHOICE

    TARGET_LOG=""
    case "$LOG_CHOICE" in
        # === OPTION 1: DYNAMIC POSTGRES LIST ===
        1)
            echo -e "${YELLOW}Fetching PostgreSQL logs list from remote...${NC}"
            # Find logs, print 'Timestamp|Date Time|Path', sort by timestamp desc (newest first)
            REMOTE_CMD="find /var/lib/pgsql/data/log/ -maxdepth 1 -name 'postgresql-*.log' -printf '%T@|%Ty-%Tm-%Td %TH:%TM|%p\n' 2>/dev/null | sort -nr"

            mapfile -t PG_LOGS < <(ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMD")

            if [ ${#PG_LOGS[@]} -eq 0 ]; then
                echo -e "${RED}No PostgreSQL logs found in /var/lib/pgsql/data/log/${NC}"
                return
            fi

            echo -e "${YELLOW}Available PostgreSQL Logs (Sorted by Date):${NC}"

            declare -a LOG_PATHS
            COUNT=1

            for line in "${PG_LOGS[@]}"; do
                IFS='|' read -r TS DATE PATH_VAL <<< "$line"
                LOG_PATHS[$COUNT]="$PATH_VAL"
                BASENAME=$(basename "$PATH_VAL")

                if [ $COUNT -eq 1 ]; then
                    echo -e "  ${GREEN}${COUNT})${NC} ${BLUE}${BASENAME}${NC}  ${BLUE}(Updated: ${DATE}) ${BLUE}[LATEST]${NC}"
                else
                    echo -e "  ${GREEN}${COUNT})${NC} ${BASENAME}  (Updated: ${DATE})"
                fi
                ((COUNT++))
            done

            echo -e "  ${GREEN}0)${NC} Cancel"
            read -p "Select Log [1-$((COUNT-1))]: " PG_CHOICE

            if [[ "$PG_CHOICE" =~ ^[0-9]+$ ]] && [ "$PG_CHOICE" -gt 0 ] && [ "$PG_CHOICE" -lt "$COUNT" ]; then
                TARGET_LOG="${LOG_PATHS[$PG_CHOICE]}"
            else
                echo "Cancelled or Invalid."; exit 0
            fi
            ;;

        # === STANDARD LOGS ===
        2) TARGET_LOG="/var/log/tomcat10/dcTrackServer.log" ;;
        3) TARGET_LOG="/var/log/tomcat10/catalina.out" ;;
        4) TARGET_LOG="/var/log/tomcat10/access_logs.out" ;;
        5) TARGET_LOG="/var/log/tomcat10/floorMapsService.log" ;;
        6) TARGET_LOG="/var/log/tomcat10/gc.log" ;;
        7) TARGET_LOG="/var/log/tomcat10/wfPluginsLog.log" ;;
        8) TARGET_LOG="/var/log/oculan/backup-restore.log" ;;
        9) TARGET_LOG="/var/log/oculan/database-init.log" ;;
        10) TARGET_LOG="/var/log/oculan/upgrade.log" ;;
        11) TARGET_LOG="/var/oculan/activemq/data/activemq.log" ;;
        12) read -p "Enter full path: " TARGET_LOG ;;
        0) echo "Cancelled."; exit 0 ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac

    if [ -z "$TARGET_LOG" ]; then return; fi

    # 2. EXECUTE BASED ON PREFERENCE
    if [ "$USE_VIEWER" == "glogg" ]; then
        # === OPTION A: GLOGG (GUI) ===
        echo -e "${YELLOW}Configuring X11 & Checking glogg on remote...${NC}"

        ssh "${REMOTE_USER}@${TARGET_IP}" "
            # A. Fix X11 Auth
            if ! rpm -q xorg-x11-xauth &> /dev/null; then
                if command -v dnf &> /dev/null; then dnf install -y xorg-x11-xauth; else yum install -y xorg-x11-xauth; fi
            fi
            # B. Install glogg
            if ! command -v glogg &> /dev/null; then
                if ! rpm -q epel-release &> /dev/null; then
                    if command -v dnf &> /dev/null; then dnf install -y epel-release; else yum install -y epel-release; fi
                fi
                if command -v dnf &> /dev/null; then dnf install -y glogg; else yum install -y glogg; fi
            fi
            # C. Ensure SSHD Config
            if grep -q '^X11Forwarding no' /etc/ssh/sshd_config; then
                sed -i 's/^X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config
                systemctl restart sshd
            fi
        "
        log_step "VIEWLOG" "Opening with glogg (X11)..."
        ssh -X "${REMOTE_USER}@${TARGET_IP}" "glogg '${TARGET_LOG}'" 2>/dev/null

    else
        # === OPTION B: LNAV (TERMINAL) ===
        echo -e "${YELLOW}Checking for lnav on remote...${NC}"
        ssh -t "${REMOTE_USER}@${TARGET_IP}" "
            if ! command -v lnav &> /dev/null; then
                echo '[Remote] lnav not found. Installing...'
                if ! rpm -q epel-release &> /dev/null; then
                    if command -v dnf &> /dev/null; then sudo dnf install -y epel-release; else sudo yum install -y epel-release; fi
                fi
                if command -v dnf &> /dev/null; then sudo dnf install -y lnav; else sudo yum install -y lnav; fi
            fi
        "
        log_step "VIEWLOG" "Opening with lnav..."
        ssh -t "${REMOTE_USER}@${TARGET_IP}" "lnav '${TARGET_LOG}'"
    fi
}