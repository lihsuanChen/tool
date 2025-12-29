#!/bin/bash

# =================CONFIGURATION =================
export REMOTE_USER="root"
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
    echo -e "Usage: t [COMMAND] [IP_SUFFIX]"
    echo -e ""
    echo -e "${YELLOW}COMMANDS:${NC}"
    echo -e "  ${GREEN}deploy <IP>${NC}      Builds Maven project and deploys WAR to Tomcat."
    echo -e "  ${GREEN}dnfupdate <IP>${NC}   Transfers and runs dnfupdate.sh."
    echo -e "  ${GREEN}ssh <IP>${NC}         Exchanges SSH keys and logs in automatically."
    echo -e "  ${GREEN}--help, -help, --h, -h${NC}       Show this help message."
    echo -e ""
    echo -e "${YELLOW}IP FORMAT:${NC}"
    echo -e "  Ex: ${GREEN}t deploy 11${NC}      -> Connects to ${BASE_IP}.${DEFAULT_SUBNET}.11"
}

# 1. PARSE ARGUMENTS
MODE=$1
IP_SUFFIX=$2

# Check for Help Flag (Matches -h, --h, -help, --help)
if [[ "$MODE" =~ ^--?h(elp)?$ ]]; then
    print_help
    exit 0
fi

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
    deploy)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting Deployment Process..."
        bash "$SCRIPT_DIR/process_deploy.sh"
        ;;
    dnfupdate)
        check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"
        log_step "MAIN" "Starting DNF Update Process..."
        bash "$SCRIPT_DIR/process_dnfupdate.sh"
        ;;
    ssh)
        log_step "MAIN" "Starting SSH Key Exchange..."
        install_ssh_key "${REMOTE_USER}" "${TARGET_IP}"

        if [ $? -eq 0 ]; then
             log_step "MAIN" "Auto-logging into ${TARGET_IP}..."
             ssh "${REMOTE_USER}@${TARGET_IP}"
        else
             error_exit "Key exchange failed. Auto-login aborted."
        fi
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$MODE'${NC}"
        echo -e "Did you mean 't deploy', 't ssh', or 't dnfupdate'?"
        exit 1
        ;;
esac