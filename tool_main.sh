#!/bin/bash

# =================CONFIGURATION =================
# Global Config
export REMOTE_USER="root"
export BASE_IP="192.168"
export DEFAULT_SUBNET="78"

# Path to the source of the DNF update script (Local)
export LOCAL_DNF_SCRIPT="$HOME/projects/test_automation/dnfupdate.sh"
# ================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import SSH Utilities
source "$SCRIPT_DIR/lib_ssh.sh"

# ================= HELP FUNCTION =================
print_help() {
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${YELLOW}  CUSTOM DEPLOYMENT & AUTOMATION TOOL${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "Usage: tool [COMMAND] [IP_SUFFIX]"
    echo -e ""
    echo -e "${YELLOW}COMMANDS:${NC}"
    echo -e "  ${GREEN}--deploy <IP>${NC}      Builds Maven project and deploys WAR to Tomcat."
    echo -e "  ${GREEN}--dnfupdate <IP>${NC}   Transfers and runs dnfupdate.sh."
    echo -e "  ${GREEN}--ssh <IP>${NC}         Exchanges SSH keys (ssh-copy-id) only."
    echo -e "  ${GREEN}--help, -h${NC}         Show this help message."
    echo -e ""
    echo -e "${YELLOW}IP FORMAT:${NC}"
    echo -e "  Ex: ${GREEN}tool --deploy 11${NC}      -> Connects to ${BASE_IP}.${DEFAULT_SUBNET}.11"
}

# 1. PARSE ARGUMENTS
MODE=$1
IP_SUFFIX=$2

# Check for Help Flag (Matches -h, --h, -help, --help)
if [[ "$MODE" =~ ^--?h(elp)?$ ]]; then
    print_help
    exit 0
fi

# Validate inputs for other modes
if [ -z "$MODE" ] || [ -z "$IP_SUFFIX" ]; then
    echo -e "${RED}Error: Missing arguments.${NC}"
    print_help
    exit 1
fi

# 2. CALCULATE TARGET IP
TARGET_IP=""
if [[ "$IP_SUFFIX" == *.* ]]; then
    TARGET_IP="${BASE_IP}.${IP_SUFFIX}"
else
    TARGET_IP="${BASE_IP}.${DEFAULT_SUBNET}.${IP_SUFFIX}"
fi

export TARGET_IP

echo -e "Target defined as: ${YELLOW}${TARGET_IP}${NC}"

# 3. EXECUTE REQUESTED PROCESS
case "$MODE" in
    --deploy)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting Deployment Process..."
        bash "$SCRIPT_DIR/process_deploy.sh"
        ;;
    --dnfupdate)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting DNF Update Process..."
        bash "$SCRIPT_DIR/process_dnfupdate.sh"
        ;;
    --ssh)
        log_step "MAIN" "Starting SSH Key Exchange..."
        install_ssh_key "${REMOTE_USER}" "${TARGET_IP}"
        ;;
    *)
        echo -e "${RED}Error: Unknown mode '$MODE'${NC}"
        print_help
        exit 1
        ;;
esac