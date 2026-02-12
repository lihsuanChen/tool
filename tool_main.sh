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
source "$SCRIPT_DIR/m7_tool_build.sh"
source "$SCRIPT_DIR/m7_tool_rpm_install.sh"

# ================= 6. ARGUMENT PARSING VARS =================
COMMAND=""
TARGET_IP=""
declare -a COMMAND_ARGS=()
export TARGET_VERSION=""
export SEARCH_LIMIT="$DEFAULT_SEARCH_LIMIT"

# ================= 7. HELPER FUNCTIONS =================

# Checks if input looks like an IP or a subnet suffix (e.g., 103 or 192.168.1.1)
is_ip_or_suffix() {
    local input=$1
    if [[ "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$input" =~ ^[0-9]{1,3}$ ]]; then
        return 0 # True
    else
        return 1 # False
    fi
}

# Resolves partial IP (105) to full IP (192.168.78.105) based on config
resolve_target_ip() {
    local input=$1
    if [[ "$input" == *.* ]]; then
        echo "$input"
    else
        echo "${BASE_IP}.${DEFAULT_SUBNET}.${input}"
    fi
}

# Hook: Ensures TARGET_IP is set, prompts user via GUI if missing.
# This allows centralized IP handling for any module that needs it.
require_ip() {
    if [ -z "$TARGET_IP" ]; then
        local RAW_INPUT
        RAW_INPUT=$(ui_input "Enter Target IP (e.g., 105)" "false")
        if [ -z "$RAW_INPUT" ]; then
            error_exit "Target IP is required for this operation."
        fi
        TARGET_IP=$(resolve_target_ip "$RAW_INPUT")
    fi
    # Export for sub-modules to use
    export TARGET_IP
}

# ================= 8. MAIN PARSING LOOP =================
# Strategy: Consume global flags first, then identify Command,
# then consume IP if present, treating everything else as Args.

while [[ $# -gt 0 ]]; do
    case "$1" in
        # --- Global Flags ---
        -h|--help) print_help; exit 0 ;;
        -v|--version) export TARGET_VERSION="$2"; shift 2 ;;
        -l|--limit) export SEARCH_LIMIT="$2"; shift 2 ;;

        # --- Command Detection ---
        # List of known commands. If COMMAND is not set, the first match becomes the command.
        deploy|dnfupdate|ssh|docker|find|readme|edit|rpm|build|setpass|rootsetup|pgtrust|pgbackup|tomcatsetup|initvm|jprofiler|viewlog|logview|log|setlogviewer)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            else
                # If Command is already set (e.g. 't rpm install'), treat 'install' as an argument
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;

        # --- IP vs Argument Logic ---
        *)
            # logic: If TARGET_IP is not yet set, AND the arg looks like an IP/Suffix, consume it as IP.
            # This fixes 't edit 103' where 103 was previously treated as a file path.
            if [ -z "$TARGET_IP" ] && is_ip_or_suffix "$1"; then
                TARGET_IP=$(resolve_target_ip "$1")
            else
                # Otherwise, it's a generic argument (file path, search term, sub-command, etc.)
                COMMAND_ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

# ================= 9. NORMALIZE VERSION =================
# Helper to standardize version strings (e.g., v9.3.5 -> 9.3.5 and 935)
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

# ================= 10. INTERACTIVE MENU (If No Command) =================
if [ -z "$COMMAND" ]; then
    if command -v gum &> /dev/null; then
        echo -e "${BLUE}:: t Automation Suite ::${NC}"
        COMMAND=$(gum choose --header "Select Operation" \
            "deploy" "ssh" "docker" "rpm" "edit" "viewlog" \
            "find" "initvm" "pgbackup" "jprofiler" "dnfupdate" "readme")

        if [ -z "$COMMAND" ]; then echo "Cancelled."; exit 0; fi
    else
        echo -e "${RED}Error: Missing arguments.${NC}"; print_help; exit 1;
    fi
fi

# ================= 11. COMMAND DISPATCHER =================
# Join COMMAND_ARGS array into a string for passing to functions
FINAL_ARGS="${COMMAND_ARGS[*]}"

case "$COMMAND" in
    deploy)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting Deployment Process..."
        bash "$SCRIPT_DIR/m5_process_deploy.sh"
        ;;

    dnfupdate)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting DNF Update Process..."
        bash "$SCRIPT_DIR/m2_process_dnfupdate.sh"
        ;;

    ssh)
        require_ip
        log_step "MAIN" "Checking Connection..."
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        ssh "${REMOTE_USER}@${TARGET_IP}"
        ;;

    docker)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"

        # If no sub-command passed in args, show interactive menu
        if [ -z "$FINAL_ARGS" ]; then
            show_docker_menu "${REMOTE_USER}" "${TARGET_IP}"
        else
            docker_router "$FINAL_ARGS" "${REMOTE_USER}" "${TARGET_IP}"
        fi
        exit 0
        ;;

    rpm|build)
        # --- RPM/Build Router ---
        SUB_CMD=""

        # Check args for explicit 'install' or 'build'
        if [[ "$FINAL_ARGS" == *"install"* ]]; then SUB_CMD="install"; fi
        if [[ "$FINAL_ARGS" == *"build"* ]]; then SUB_CMD="build"; fi

        # Handle alias 't build'
        if [[ "$COMMAND" == "build" ]]; then SUB_CMD="build"; fi

        # If undetermined, ask user
        if [ -z "$SUB_CMD" ]; then
            SUB_CMD=$(ui_choose "Build RPM (Container)" "Install RPM (Remote)" "Cancel")
        fi

        case "$SUB_CMD" in
            "build"|"Build"*)
                # Build happens locally/in-container, usually no IP needed
                build_rpm_in_container
                ;;
            "install"|"Install"*)
                # Install requires IP
                require_ip
                check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
                install_rpm_remote "${REMOTE_USER}" "${TARGET_IP}"
                ;;
            *)
                echo "Cancelled."
                ;;
        esac
        exit 0
        ;;

    edit)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        # FINAL_ARGS contains the file path (if any).
        # If 't edit 103' was used, 103 is consumed as TARGET_IP, so FINAL_ARGS is empty.
        # edit_remote_file handles empty args by showing the history menu.
        edit_remote_file "${REMOTE_USER}" "${TARGET_IP}" "$FINAL_ARGS"
        exit 0
        ;;

    viewlog|logview|log)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        view_remote_log_gui "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;

    find)
        # 'find' uses args as search query. No IP required.
        cmd_search "$FINAL_ARGS"
        exit 0
        ;;

    readme)
        # Display docs. No IP required.
        show_readme "$SCRIPT_DIR" "$FINAL_ARGS"
        exit 0
        ;;

    # --- Admin & Setup Commands ---
    setpass)
        require_ip
        ensure_bridge_password "true" "$TARGET_IP"
        exit 0
        ;;
    rootsetup)
        require_ip
        ensure_bridge_password "false" "$TARGET_IP"
        setup_root_creds "${BRIDGE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    pgtrust)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        pg_whitelist_ip "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    pgbackup)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        pg_manage_backups "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    tomcatsetup)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        enable_tomcat_debug "${REMOTE_USER}" "${TARGET_IP}"
        exit 0
        ;;
    jprofiler)
        require_ip
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        # Support sub-commands 'off' or 'detach'
        if [[ "$FINAL_ARGS" == "off" ]] || [[ "$FINAL_ARGS" == "detach" ]]; then
            disable_jprofiler_remote "${REMOTE_USER}" "${TARGET_IP}"
        else
            setup_jprofiler_remote "${REMOTE_USER}" "${TARGET_IP}"
        fi
        exit 0
        ;;
    initvm)
        require_ip
        run_init_vm_flow "${REMOTE_USER}" "${TARGET_IP}" "${BRIDGE_USER}"
        exit 0
        ;;
    setlogviewer)
        # Local preference config
        switch_log_viewer
        exit 0
        ;;

    *)
        echo -e "${RED}Error: Unknown command '$COMMAND'${NC}"
        print_help
        exit 1
        ;;
esac