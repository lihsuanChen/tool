#!/bin/bash

# =================CONFIGURATION =================
export REMOTE_USER="root"
export BRIDGE_USER="sunbird"
export AUTH_FILE="$HOME/.sunbird_auth"
export CMD_LIBRARY="$HOME/scripts/my_commands.txt"
export BASE_IP="192.168"
export DEFAULT_SUBNET="78"
export LOCAL_DNF_SCRIPT="$HOME/projects/test_automation/dnfupdate.sh"
# ================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ================= LOAD MODULES =================
source "$SCRIPT_DIR/lib_ssh.sh"
source "$SCRIPT_DIR/tool_cheatsheet.sh"
source "$SCRIPT_DIR/tool_help.sh"
# ================================================

# ================= ARGUMENT PARSING =================
MODE=""
IP_SUFFIX=""
export TARGET_VERSION=""

while [[ $# -gt 0 ]]; do
  # CHECK 1: IF MODE IS ALREADY SET (e.g., 'find' was detected)
  # Treat everything else as arguments, ignoring reserved keywords.
  if [ -n "$MODE" ]; then
      case $1 in
        -f|-v|--version) export TARGET_VERSION="$2"; shift 2 ;;
        *)
           # Add word to suffix (Search Query or IP)
           if [[ -z "$IP_SUFFIX" ]]; then
               IP_SUFFIX="$1"
           else
               IP_SUFFIX="$IP_SUFFIX $1"
           fi
           shift
           ;;
      esac

  # CHECK 2: IF MODE IS NOT SET YET
  # Look for the command keyword.
  else
      case $1 in
        deploy|dnfupdate|ssh|setpass|find) MODE="$1"; shift ;;
        -f|-v|--version) export TARGET_VERSION="$2"; shift 2 ;;
        -h|--help|--h|-help) print_help; exit 0 ;;
        *)
           # Handle arguments that appear before the command (rare but possible)
           if [[ -z "$IP_SUFFIX" ]]; then
               IP_SUFFIX="$1"
           else
               IP_SUFFIX="$IP_SUFFIX $1"
           fi
           shift
           ;;
      esac
  fi
done

if [ -z "$MODE" ]; then echo -e "${RED}Error: Missing arguments.${NC}"; print_help; exit 1; fi

# CALCULATE IP (Only if input looks like a number/IP)
TARGET_IP=""
if [ -n "$IP_SUFFIX" ] && [[ "$IP_SUFFIX" =~ ^[0-9.]+$ ]]; then
    if [[ "$IP_SUFFIX" == *.* ]]; then TARGET_IP="${BASE_IP}.${IP_SUFFIX}"; else TARGET_IP="${BASE_IP}.${DEFAULT_SUBNET}.${IP_SUFFIX}"; fi
    export TARGET_IP
    echo -e "Target defined as: ${YELLOW}${TARGET_IP}${NC}"
fi

case "$MODE" in
    deploy)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for deploy."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting Deployment Process..."
        bash "$SCRIPT_DIR/process_deploy.sh"
        ;;
    dnfupdate)
        if [ -z "$TARGET_IP" ]; then error_exit "IP Required for dnfupdate."; fi
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting DNF Update Process..."
        bash "$SCRIPT_DIR/process_dnfupdate.sh"
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
    find)
        cmd_search "$IP_SUFFIX"
        exit 0
        ;;
    *) echo -e "${RED}Error: Unknown command '$MODE'${NC}"; exit 1 ;;
esac