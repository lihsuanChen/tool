#!/bin/bash

# ================= 1. INITIALIZATION =================
# Calculate the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ================= 2. DEFAULT CONFIGURATION =================
# These values are used if .t_config is missing.
# ------------------------------------------------------------
REMOTE_USER="root"
BRIDGE_USER="sunbird"
AUTH_FILE="$HOME/.sunbird_auth"
CMD_LIBRARY="$HOME/scripts/m3_my_commands.txt"
BASE_IP="192.168"
DEFAULT_SUBNET="78"
LOCAL_DNF_SCRIPT="$HOME/projects/test_automation/dnfupdate.sh"
DEFAULT_SEARCH_LIMIT="8"

# ================= 3. USER OVERRIDES =================
# Load external configuration from the same directory as the script
# ------------------------------------------------------------
USER_CONFIG="$SCRIPT_DIR/.t_config"

if [ -f "$USER_CONFIG" ]; then
    # We source this file, so it can overwrite the variables above
    source "$USER_CONFIG"
fi

# ================= 4. EXPORT GLOBAL STATE =================
export REMOTE_USER
export BRIDGE_USER
export AUTH_FILE
export CMD_LIBRARY
export BASE_IP
export DEFAULT_SUBNET
export LOCAL_DNF_SCRIPT
export DEFAULT_SEARCH_LIMIT

# ================= 5. LOAD MODULES =================
source "$SCRIPT_DIR/m1_lib_ssh.sh"
source "$SCRIPT_DIR/m3_tool_cheatsheet.sh"
source "$SCRIPT_DIR/tool_help.sh"
source "$SCRIPT_DIR/m4_tool_postgres.sh"
source "$SCRIPT_DIR/tool_readme.sh"
source "$SCRIPT_DIR/m4_tool_tomcat.sh"
source "$SCRIPT_DIR/m4_tool_init_vm.sh"
source "$SCRIPT_DIR/tool_viewlog.sh"
source "$SCRIPT_DIR/m4_tool_edit.sh"
# ================================================

# ================= ARGUMENT PARSING =================
MODE=""
IP_SUFFIX=""
export TARGET_VERSION=""
export SEARCH_LIMIT="$DEFAULT_SEARCH_LIMIT"

while [[ $# -gt 0 ]]; do
  if [ -n "$MODE" ]; then
      case $1 in
        -f|-v|--version) export TARGET_VERSION="$2"; shift 2 ;;
        -l|--limit) export SEARCH_LIMIT="$2"; shift 2 ;;
        *) if [[ -z "$IP_SUFFIX" ]]; then IP_SUFFIX="$1"; else IP_SUFFIX="$IP_SUFFIX $1"; fi; shift ;;
      esac
  else
      case $1 in
        deploy|dnfupdate|ssh|setpass|find|readme|rootsetup|pgtrust|tomcatsetup|initvm|viewlog|logview|log|setlogviewer|edit) MODE="$1"; shift ;;
        -f|-v|--version) export TARGET_VERSION="$2"; shift 2 ;;
        -l|--limit) export SEARCH_LIMIT="$2"; shift 2 ;;
        -h|--help|--h|-help) print_help; exit 0 ;;
        *) if [[ -z "$IP_SUFFIX" ]]; then IP_SUFFIX="$1"; else IP_SUFFIX="$IP_SUFFIX $1"; fi; shift ;;
      esac
  fi
done

if [ -z "$MODE" ]; then echo -e "${RED}Error: Missing arguments.${NC}"; print_help; exit 1; fi

# ================= NORMALIZE VERSION =================
# Standardize version formats so sub-scripts don't have to parse them.
# -----------------------------------------------------
export VERSION_WITH_DOTS=""
export VERSION_NO_DOTS=""

if [ -n "$TARGET_VERSION" ]; then
    # 1. Sanitize: Remove 'v' prefix if present (e.g. v9.3.5 -> 9.3.5)
    CLEAN_VER="${TARGET_VERSION#v}"

    if [[ "$CLEAN_VER" == *"."* ]]; then
        # Input has dots (e.g. 9.3.5)
        VERSION_WITH_DOTS="$CLEAN_VER"
        VERSION_NO_DOTS="${CLEAN_VER//./}"
    else
        # Input has NO dots (e.g. 935)
        VERSION_NO_DOTS="$CLEAN_VER"

        # Smart Infer: 3 digits (935) -> 9.3.5
        if [[ "$CLEAN_VER" =~ ^[0-9]{3}$ ]]; then
            VERSION_WITH_DOTS="${CLEAN_VER:0:1}.${CLEAN_VER:1:1}.${CLEAN_VER:2:1}"
        else
            # Fallback for non-standard lengths (e.g. 1001)
            VERSION_WITH_DOTS="$CLEAN_VER"
        fi
    fi
    export VERSION_WITH_DOTS
    export VERSION_NO_DOTS
fi

# ================= CALCULATE IP & ARGS =================
# Split IP_SUFFIX into the IP component and the rest (Extra Args)
# This allows commands like: 't edit 105 /etc/hosts'
# -------------------------------------------------------
TARGET_IP=""
EXTRA_ARGS=""

if [ -n "$IP_SUFFIX" ]; then
    # Extract the first word as the potential IP/ID
    read -r POTENTIAL_ID REMAINDER <<< "$IP_SUFFIX"

    if [[ "$POTENTIAL_ID" =~ ^[0-9.]+$ ]]; then
        # It is a valid IP syntax
        if [[ "$POTENTIAL_ID" == *.* ]]; then
            TARGET_IP="${BASE_IP}.${POTENTIAL_ID}"
        else
            TARGET_IP="${BASE_IP}.${DEFAULT_SUBNET}.${POTENTIAL_ID}"
        fi

        export TARGET_IP
        # The rest of the string becomes arguments for the command (e.g. filename)
        EXTRA_ARGS="$REMAINDER"

        echo -e "Target defined as: ${YELLOW}${TARGET_IP}${NC}"
    else
        # Fallback: The user might have typed 't find some query' (no IP)
        # So we keep the whole string as args for commands that don't need IPs
        EXTRA_ARGS="$IP_SUFFIX"
    fi
fi

case "$MODE" in
    deploy)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for deploy."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting Deployment Process..."
        bash "$SCRIPT_DIR/m5_process_deploy.sh"
        ;;
    dnfupdate)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for dnfupdate."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting DNF Update Process..."
        bash "$SCRIPT_DIR/m2_process_dnfupdate.sh"
        ;;
    ssh)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for ssh."; fi
        log_step "MAIN" "Checking Connection..."
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        ssh "${REMOTE_USER}@${TARGET_IP}"
        ;;
    setpass)
        ensure_bridge_password "true" "$TARGET_IP"
        exit 0
        ;;
    rootsetup)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for rootsetup."; fi
        ensure_bridge_password "false" "$TARGET_IP"
        setup_root_creds "${BRIDGE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    pgtrust)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for pgtrust."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        pg_whitelist_ip "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    tomcatsetup)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for tomcatsetup."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        enable_tomcat_debug "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    initvm)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for initvm."; fi
        run_init_vm_flow "${REMOTE_USER}" "${TARGET_IP}" "${BRIDGE_USER}"
        exit 0
        ;;
    viewlog|logview|log)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for viewlog."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        view_remote_log_gui "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    setlogviewer)
        switch_log_viewer
        exit 0
        ;;
    edit)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for edit."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"

        FINAL_PATH="${EXTRA_ARGS}"
        if [ -z "$FINAL_PATH" ]; then FINAL_PATH="$TARGET_VERSION"; fi

        edit_remote_file "${REMOTE_USER}" "${TARGET_IP}" "${FINAL_PATH}"
        exit 0
        ;;
    find)
        # Pass the full argument string, not split by IP
        cmd_search "$IP_SUFFIX"
        exit 0
        ;;
    readme)
        show_readme "$SCRIPT_DIR"
        exit 0
        ;;
    *) echo -e "${RED}Error: Unknown command '$MODE'${NC}"; exit 1 ;;
esac