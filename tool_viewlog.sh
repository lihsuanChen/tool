#!/bin/bash

# ==============================================================================
# MODULE: Log Viewing Utilities
# DESCRIPTION: Handles log viewer preferences and remote log viewing (GUI/CLI)
# DEPENDENCIES: gum, ssh, lnav/glogg (remote)
# ==============================================================================

VIEWER_CONFIG="$HOME/.t_viewer_pref"

# ================= SWITCH FUNCTION =================
switch_log_viewer() {
    # 1. Determine Current State
    local CURRENT="lnav"
    if [ -f "$VIEWER_CONFIG" ]; then
        CURRENT=$(cat "$VIEWER_CONFIG")
    fi

    # 2. Display Status
    echo -e "${YELLOW}Log Viewer Configuration${NC}"
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "Current Viewer: $CURRENT"

    # 3. Interactive Selection
    echo -e "Select your preferred viewer:"
    local V_CHOICE
    V_CHOICE=$(gum choose --cursor.foreground="212" --header "Choose Viewer Mode" \
        "lnav  (Terminal-based, Fast, No Config)" \
        "glogg (GUI Window, Requires X-Server/WSLg)" \
        "Cancel")

    # 4. Handle Selection
    case "$V_CHOICE" in
        "lnav"*)
            echo "lnav" > "$VIEWER_CONFIG"
            gum style --foreground 212 "Switched to 'lnav'. Future logs will open in terminal."
            ;;
        "glogg"*)
            echo "glogg" > "$VIEWER_CONFIG"
            gum style --foreground 212 "Switched to 'glogg'. Future logs will open in X11 window."
            ;;
        *)
            echo -e "${YELLOW}Operation cancelled.${NC}"
            ;;
    esac
}

# ================= VIEW FUNCTION =================
view_remote_log_gui() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- 1. DETERMINE VIEWER ---
    local USE_VIEWER="lnav" # Default
    if [ -f "$VIEWER_CONFIG" ]; then
        USE_VIEWER=$(cat "$VIEWER_CONFIG")
    fi

    # --- 2. BUILD SELECTION MENU ---
    # We create a list for gum filter. Format: "Label | Path"
    # We will strip the label after selection.
    local OPTIONS=(
        "PostgreSQL Logs (Dynamic List)...|PG_DYN"
        "Tomcat: dcTrackServer.log|/var/log/tomcat10/dcTrackServer.log"
        "Tomcat: catalina.out|/var/log/tomcat10/catalina.out"
        "Tomcat: access_logs.out|/var/log/tomcat10/access_logs.out"
        "Tomcat: floorMapsService.log|/var/log/tomcat10/floorMapsService.log"
        "Tomcat: gc.log|/var/log/tomcat10/gc.log"
        "Tomcat: wfPluginsLog.log|/var/log/tomcat10/wfPluginsLog.log"
        "Oculan: backup-restore.log|/var/log/oculan/backup-restore.log"
        "Oculan: database-init.log|/var/log/oculan/database-init.log"
        "Oculan: upgrade.log|/var/log/oculan/upgrade.log"
        "ActiveMQ: activemq.log|/var/oculan/activemq/data/activemq.log"
        "Custom Path...|CUSTOM"
    )

    log_step "VIEWLOG" "Target: ${GREEN}${TARGET_IP}${NC} | Viewer: ${YELLOW}${USE_VIEWER}${NC}"

    local SELECTION
    SELECTION=$(printf "%s\n" "${OPTIONS[@]}" | gum filter --indicator=">" --placeholder="Search logs..." --height=15)

    if [ -z "$SELECTION" ]; then
        echo -e "${YELLOW}No log selected. Exiting.${NC}"
        return
    fi

    # Extract the Value (everything after the last pipe)
    local LOG_KEY="${SELECTION##*|}"
    local TARGET_LOG=""

    case "$LOG_KEY" in
        # === OPTION 1: DYNAMIC POSTGRES LIST ===
        "PG_DYN")
            echo -e "${YELLOW}Fetching PostgreSQL logs from remote...${NC}"

            # Find logs, print 'Timestamp|Date Time|Path', sort by timestamp desc
            # Using gum spin to indicate activity
            local REMOTE_CMD="find /var/lib/pgsql/data/log/ -maxdepth 1 -name 'postgresql-*.log' -printf '%T@|%Ty-%Tm-%Td %TH:%TM|%p\n' 2>/dev/null | sort -nr"

            mapfile -t PG_LOGS < <(gum spin --spinner dot --title "Scanning /var/lib/pgsql/data/log/..." -- ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMD")

            if [ ${#PG_LOGS[@]} -eq 0 ]; then
                gum style --foreground 196 "No PostgreSQL logs found."
                return
            fi

            # Format for gum filter: "Date | Filename | FullPath"
            declare -a CLEAN_LIST
            for line in "${PG_LOGS[@]}"; do
                IFS='|' read -r TS DATE PATH_VAL <<< "$line"
                local BASENAME=$(basename "$PATH_VAL")
                CLEAN_LIST+=("$DATE | $BASENAME | $PATH_VAL")
            done

            local PG_CHOICE
            PG_CHOICE=$(printf "%s\n" "${CLEAN_LIST[@]}" | gum filter --indicator=">" --placeholder="Select Postgres Log..." --height=10)

            if [ -n "$PG_CHOICE" ]; then
                # Extract full path (last field separated by " | ")
                TARGET_LOG=$(echo "$PG_CHOICE" | awk -F ' \\| ' '{print $3}')
            else
                echo "Cancelled."; return
            fi
            ;;

        # === OPTION: CUSTOM PATH ===
        "CUSTOM")
            TARGET_LOG=$(gum input --placeholder "/var/log/..." --header "Enter full absolute path to log file:")
            if [ -z "$TARGET_LOG" ]; then echo "Cancelled."; return; fi
            ;;

        # === OPTION: STANDARD LOGS ===
        *)
            TARGET_LOG="$LOG_KEY"
            ;;
    esac

    # 3. EXECUTE BASED ON PREFERENCE
    if [ "$USE_VIEWER" == "glogg" ]; then
        # === OPTION A: GLOGG (GUI) ===
        log_step "VIEWLOG" "Checking remote X11/glogg requirements..."

        # Using gum spin for the dependency check
        gum spin --spinner minidot --title "Verifying glogg installation on remote..." -- ssh "${REMOTE_USER}@${TARGET_IP}" "
            # A. Fix X11 Auth
            if ! rpm -q xorg-x11-xauth &> /dev/null; then
                if command -v dnf &> /dev/null; then sudo dnf install -y xorg-x11-xauth; else sudo yum install -y xorg-x11-xauth; fi
            fi
            # B. Install glogg
            if ! command -v glogg &> /dev/null; then
                if ! rpm -q epel-release &> /dev/null; then
                    if command -v dnf &> /dev/null; then sudo dnf install -y epel-release; else sudo yum install -y epel-release; fi
                fi
                if command -v dnf &> /dev/null; then sudo dnf install -y glogg; else sudo yum install -y glogg; fi
            fi
            # C. Ensure SSHD Config
            if grep -q '^X11Forwarding no' /etc/ssh/sshd_config; then
                sudo sed -i 's/^X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config
                sudo systemctl restart sshd
            fi
        "

        echo -e "${GREEN}Launching glogg... (Check your taskbar if window doesn't appear)${NC}"
        ssh -X "${REMOTE_USER}@${TARGET_IP}" "glogg '${TARGET_LOG}'" 2>/dev/null &

    else
        # === OPTION B: LNAV (TERMINAL) ===

        # Check lnav existence silently with gum spin
        gum spin --spinner minidot --title "Verifying lnav installation on remote..." -- ssh -t "${REMOTE_USER}@${TARGET_IP}" "
            if ! command -v lnav &> /dev/null; then
                if ! rpm -q epel-release &> /dev/null; then
                    if command -v dnf &> /dev/null; then sudo dnf install -y epel-release; else sudo yum install -y epel-release; fi
                fi
                if command -v dnf &> /dev/null; then sudo dnf install -y lnav; else sudo yum install -y lnav; fi
            fi
        "

        echo -e "${GREEN}Opening lnav session...${NC}"
        ssh -t "${REMOTE_USER}@${TARGET_IP}" "lnav '${TARGET_LOG}'"
    fi
}