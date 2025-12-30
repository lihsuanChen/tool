#!/bin/bash

# =================CONFIGURATION =================
export REMOTE_USER="root"
export BRIDGE_USER="sunbird"
export AUTH_FILE="$HOME/.sunbird_auth"
export BASE_IP="192.168"
export DEFAULT_SUBNET="78"
export LOCAL_DNF_SCRIPT="$HOME/projects/test_automation/dnfupdate.sh"
# ================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

# ================= HELP FUNCTION =================
print_help() {
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}  CUSTOM DEPLOYMENT & AUTOMATION TOOL${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "Usage: t [COMMAND] [IP_SUFFIX] [FLAGS]"
    echo -e ""
    echo -e "${YELLOW}COMMANDS:${NC}"
    echo -e "  ${GREEN}deploy <IP>${NC}      Smart Build & Deploy."
    echo -e "  ${GREEN}dnfupdate <IP>${NC}   Run dnfupdate.sh."
    echo -e "  ${GREEN}ssh <IP>${NC}         Setup keys & Login as root."
    echo -e "  ${GREEN}setpass [IP]${NC}     Force update 'sunbird' password (Optional IP to verify)."
    echo -e ""
    echo -e "${YELLOW}FLAGS:${NC}"
    echo -e "  -v <ver>     Version for DB/Client (e.g., 9.3.5)"
}

# ================= ARGUMENT PARSING =================
MODE=""
IP_SUFFIX=""
export TARGET_VERSION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    deploy|dnfupdate|ssh|setpass) MODE="$1"; shift ;;
    -f|-v|--version) export TARGET_VERSION="$2"; shift 2 ;;
    -h|--help|--h|-help) print_help; exit 0 ;;
    *) if [[ -z "$IP_SUFFIX" ]]; then IP_SUFFIX="$1"; fi; shift ;;
  esac
done

if [ -z "$MODE" ]; then echo -e "${RED}Error: Missing arguments.${NC}"; print_help; exit 1; fi

# CALCULATE IP (If provided)
TARGET_IP=""
if [ -n "$IP_SUFFIX" ]; then
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
        # Pass FORCE=true, and pass TARGET_IP (if it exists) to allow validation
        ensure_bridge_password "true" "$TARGET_IP"
        exit 0
        ;;
    *) echo -e "${RED}Error: Unknown command '$MODE'${NC}"; exit 1 ;;
esac