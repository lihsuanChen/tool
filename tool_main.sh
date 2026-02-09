#!/bin/bash

# ================= 1. INITIALIZATION =================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ================= 2. DEFAULT CONFIGURATION =================
# These act as fallbacks. The primary config is in .t_config
REMOTE_USER="root"
BRIDGE_USER="sunbird"
AUTH_FILE="$HOME/.sunbird_auth"
CMD_LIBRARY="$HOME/scripts/m3_my_commands.txt"
BASE_IP="192.168"
DEFAULT_SUBNET="78"
DEFAULT_SEARCH_LIMIT="8"

# ================= 3. USER OVERRIDES =================
USER_CONFIG="$SCRIPT_DIR/.t_config"
if [ -f "$USER_CONFIG" ]; then source "$USER_CONFIG"; fi

# ================= 4. EXPORT GLOBAL STATE =================
# Core Variables
export REMOTE_USER BRIDGE_USER AUTH_FILE CMD_LIBRARY BASE_IP DEFAULT_SUBNET LOCAL_DNF_SCRIPT DEFAULT_SEARCH_LIMIT

# System Services & Names (Centralized)
export TOMCAT_SERVICE TOMCAT_APP_NAME PG_SERVICE

# Remote Paths: Tomcat
export TOMCAT_HOME TOMCAT_WEBAPPS TOMCAT_LOG_BASE

# Remote Paths: Postgres
export PG_DATA_DIR PG_HBA_CONF POSTGRES_LOG_DIR

# Remote Paths: App & Docker
export OCULAN_ROOT OCULAN_LOG_BASE DOCKER_DATA_DEST

# ================= 5. LOAD MODULES =================
# Core Libraries
source "$SCRIPT_DIR/m1_lib_ssh.sh"
source "$SCRIPT_DIR/m1_lib_ui.sh"
source "$SCRIPT_DIR/tool_help.sh"
source "$SCRIPT_DIR/m3_tool_cheatsheet.sh"

# Feature Modules
source "$SCRIPT_DIR/m4_tool_postgres.sh"
source "$SCRIPT_DIR/m4_tool_tomcat.sh"
source "$SCRIPT_DIR/m4_tool_init_vm.sh"
source "$SCRIPT_DIR/m4_tool_jprofiler.sh"
source "$SCRIPT_DIR/tool_readme.sh"
source "$SCRIPT_DIR/tool_viewlog.sh"
source "$SCRIPT_DIR/tool_edit.sh"
source "$SCRIPT_DIR/m6_tool_docker_main.sh"
source "$SCRIPT_DIR/m7_tool_build.sh"  # <--- NEW MODULE

# ================= HELPER: IP RESOLUTION =================
resolve_target_ip() {
    local INPUT=$1
    if [ -z "$INPUT" ]; then echo ""; return; fi

    if [[ "$INPUT" =~ ^[0-9.]+$ ]] && [[ "$INPUT" =~ [0-9] ]]; then
        if [[ "$INPUT" == *.* ]]; then
            echo "$INPUT"
        else
            echo "${BASE_IP}.${DEFAULT_SUBNET}.${INPUT}"
        fi
    else
        echo ""
    fi
}

# ================= ARGUMENT PARSING =================
MODE=""
IP_SUFFIX=""
export TARGET_VERSION=""
export SEARCH_LIMIT="$DEFAULT_SEARCH_LIMIT"

while [[ $# -gt 0 ]]; do
  case $1 in
    # Core Commands
    deploy|dnfupdate|ssh|docker|find|readme|edit|rpm|build) MODE="$1"; shift ;;
    # Admin & Setup Commands
    setpass|rootsetup|pgtrust|pgbackup|tomcatsetup|initvm|jprofiler) MODE="$1"; shift ;;
    # Logging Commands
    viewlog|logview|log|setlogviewer) MODE="$1"; shift ;;

    # Flags
    -f|-v|--version) export TARGET_VERSION="$2"; shift 2 ;;
    -l|--limit) export SEARCH_LIMIT="$2"; shift 2 ;;
    -h|--help|--h|-help) print_help; exit 0 ;;

    # Default: Treat as IP part
    *) if [[ -z "$IP_SUFFIX" ]]; then IP_SUFFIX="$1"; else IP_SUFFIX="$IP_SUFFIX $1"; fi; shift ;;
  esac
done

# ================= INTERACTIVE MODE (GUM) =================
# If no command is provided, launch the Interactive Main Menu
if [ -z "$MODE" ]; then
    if command -v gum &> /dev/null; then
        echo -e "${BLUE}:: t Automation Suite ::${NC}"
        MODE=$(gum choose --header "Select Operation" \
            "deploy" "ssh" "docker" "rpm" "edit" "viewlog" \
            "find" "initvm" "pgbackup" "jprofiler" "dnfupdate" "readme")

        if [ -z "$MODE" ]; then echo "Cancelled."; exit 0; fi
    else
        echo -e "${RED}Error: Missing arguments.${NC}"; print_help; exit 1;
    fi
fi

# ================= IP RESOLUTION & PROMPT =================
# 1. Try to resolve from arguments
TARGET_IP=$(resolve_target_ip "$IP_SUFFIX")
EXTRA_ARGS="$IP_SUFFIX" # Fallback if not an IP

# 2. If IP is invalid/missing but required, prompt for it
if [ -z "$TARGET_IP" ]; then
    # Commands that DO NOT require an IP
    case "$MODE" in
        find|readme|setlogviewer|setpass|rpm|build) ;;
        *)
            # Prompt user
            echo -e "${YELLOW}Target IP required for '$MODE'.${NC}"
            RAW_INPUT=$(ui_input "Enter IP (e.g. 105)" "false" "105")
            TARGET_IP=$(resolve_target_ip "$RAW_INPUT")

            if [ -z "$TARGET_IP" ]; then
                error_exit "Invalid or missing IP address."
            fi
            echo -e "Target defined as: ${YELLOW}${TARGET_IP}${NC}"
            ;;
    esac
fi

# Export for sub-modules
export TARGET_IP

# ================= NORMALIZE VERSION =================
export VERSION_WITH_DOTS=""
export VERSION_NO_DOTS=""
if [ -n "$TARGET_VERSION" ]; then
    CLEAN_VER="${TARGET_VERSION#v}"
    if [[ "$CLEAN_VER" == *"."* ]]; then
        VERSION_WITH_DOTS="$CLEAN_VER"
        VERSION_NO_DOTS="${CLEAN_VER//./}"
    else
        VERSION_NO_DOTS="$CLEAN_VER"
        if [[ "$CLEAN_VER" =~ ^[0-9]{3}$ ]]; then
            VERSION_WITH_DOTS="${CLEAN_VER:0:1}.${CLEAN_VER:1:1}.${CLEAN_VER:2:1}"
        else
            VERSION_WITH_DOTS="$CLEAN_VER"
        fi
    fi
    export VERSION_WITH_DOTS
    export VERSION_NO_DOTS
fi

# ================= MAIN SWITCH =================
case "$MODE" in
    deploy)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting Deployment Process..."
        bash "$SCRIPT_DIR/m5_process_deploy.sh"
        ;;
    dnfupdate)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting DNF Update Process..."
        bash "$SCRIPT_DIR/m2_process_dnfupdate.sh"
        ;;
    ssh)
        log_step "MAIN" "Checking Connection..."
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        ssh "${REMOTE_USER}@${TARGET_IP}"
        ;;
    docker)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        # Support subcommands like 't docker 105 ps'
        if [[ "$EXTRA_ARGS" == "$IP_SUFFIX" ]] && [ -n "$TARGET_IP" ]; then
             EXTRA_ARGS=""
        fi

        TRIMMED_ARGS=$(echo "$EXTRA_ARGS" | xargs)
        if [ -z "$TRIMMED_ARGS" ]; then
            show_docker_menu "${REMOTE_USER}" "${TARGET_IP}"
        else
            docker_router "$TRIMMED_ARGS" "${REMOTE_USER}" "${TARGET_IP}"
        fi
        exit 0
        ;;
    rpm|build)  # <--- NEW COMMAND
        build_rpm_in_container
        exit 0
        ;;
    setpass)
        ensure_bridge_password "true" "$TARGET_IP"
        exit 0
        ;;
    rootsetup)
        ensure_bridge_password "false" "$TARGET_IP"
        setup_root_creds "${BRIDGE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    pgtrust)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        pg_whitelist_ip "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    pgbackup)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        pg_manage_backups "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    tomcatsetup)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        enable_tomcat_debug "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    jprofiler)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        TRIMMED_ARGS=$(echo "$EXTRA_ARGS" | xargs)
        if [[ "$TRIMMED_ARGS" == "off" ]] || [[ "$TRIMMED_ARGS" == "detach" ]]; then
            disable_jprofiler_remote "${REMOTE_USER}" "${TARGET_IP}"
        else
            setup_jprofiler_remote "${REMOTE_USER}" "${TARGET_IP}"
        fi
        exit 0
        ;;
    initvm)
        run_init_vm_flow "${REMOTE_USER}" "${TARGET_IP}" "${BRIDGE_USER}"
        exit 0
        ;;
    viewlog|logview|log)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        view_remote_log_gui "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    setlogviewer)
        switch_log_viewer
        exit 0
        ;;
    edit)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"

        if [[ "$EXTRA_ARGS" == "$IP_SUFFIX" ]] && [ -n "$TARGET_IP" ]; then
             FINAL_PATH=""
        else
             FINAL_PATH="${EXTRA_ARGS}"
        fi

        # Allow version override to act as path if path is empty
        if [ -z "$FINAL_PATH" ] && [ -n "$TARGET_VERSION" ]; then FINAL_PATH="$TARGET_VERSION"; fi

        edit_remote_file "${REMOTE_USER}" "${TARGET_IP}" "${FINAL_PATH}"
        exit 0
        ;;
    find)
        cmd_search "$IP_SUFFIX"
        exit 0
        ;;
    readme)
        show_readme "$SCRIPT_DIR" "$IP_SUFFIX"
        exit 0
        ;;
    *) echo -e "${RED}Error: Unknown command '$MODE'${NC}"; exit 1 ;;
esac