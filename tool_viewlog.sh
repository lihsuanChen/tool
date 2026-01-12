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

    # 1. SELECT LOG FILE
    echo -e "${YELLOW}Select a log file to open:${NC}"
    echo -e "  ${GREEN}1)${NC} /var/log/tomcat10/dcTrackServer.log"
    echo -e "  ${GREEN}2)${NC} /var/log/tomcat10/catalina.out"
    echo -e "  ${GREEN}3)${NC} /var/log/tomcat10/access_logs.out"
    echo -e "  ${GREEN}4)${NC} Custom Path..."
    echo -e "  ${GREEN}0)${NC} Cancel"

    read -p "Enter choice [1-4]: " LOG_CHOICE

    TARGET_LOG=""
    case "$LOG_CHOICE" in
        1) TARGET_LOG="/var/log/tomcat10/dcTrackServer.log" ;;
        2) TARGET_LOG="/var/log/tomcat10/catalina.out" ;;
        3) TARGET_LOG="/var/log/tomcat10/access_logs.out" ;;
        4) read -p "Enter full path: " TARGET_LOG ;;
        0) echo "Cancelled."; exit 0 ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac

    if [ -z "$TARGET_LOG" ]; then return; fi

    # 2. EXECUTE BASED ON PREFERENCE
    if [ "$USE_VIEWER" == "glogg" ]; then
        # === OPTION A: GLOGG (GUI) ===
        echo -e "${YELLOW}Configuring X11 & Checking glogg on remote...${NC}"

        # SELF-HEALING X11 SCRIPT
        ssh "${REMOTE_USER}@${TARGET_IP}" "
            # A. Fix X11 Auth (Fixes 'request failed on channel 0')
            if ! rpm -q xorg-x11-xauth &> /dev/null; then
                echo '[Remote] Installing xauth (Required for X11)...'
                if command -v dnf &> /dev/null; then dnf install -y xorg-x11-xauth; else yum install -y xorg-x11-xauth; fi
            fi

            # B. Install glogg
            if ! command -v glogg &> /dev/null; then
                echo '[Remote] glogg not found. Installing...'
                if ! rpm -q epel-release &> /dev/null; then
                    if command -v dnf &> /dev/null; then dnf install -y epel-release; else yum install -y epel-release; fi
                fi
                if command -v dnf &> /dev/null; then dnf install -y glogg; else yum install -y glogg; fi
            fi

            # C. Ensure SSHD Config allows X11
            # If X11Forwarding is set to no, change it to yes and restart sshd
            if grep -q '^X11Forwarding no' /etc/ssh/sshd_config; then
                echo '[Remote] Enabling X11Forwarding in sshd_config...'
                sed -i 's/^X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config
                systemctl restart sshd
            fi
        "

        # Launch with X11 Forwarding (-X) and Redirect Stderr to suppress 'xauth' noise
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
        # Launch with Pseudo-Terminal (-t)
        log_step "VIEWLOG" "Opening with lnav..."
        ssh -t "${REMOTE_USER}@${TARGET_IP}" "lnav '${TARGET_LOG}'"
    fi
}

