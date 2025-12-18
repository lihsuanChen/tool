#!/bin/bash

# =================CONFIGURATION =================
# Global Config
export REMOTE_USER="root"
export BASE_IP="192.168"
export DEFAULT_SUBNET="78"

# Path to the source of the DNF update script (Local)
export LOCAL_DNF_SCRIPT="$HOME/projects/test_automation/dnfupdate.sh"
# ================================================

# Get the directory where this script is located to find the other files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import SSH Utilities (which also contains colors and logging)
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
    echo -e "                     ${RED}* Must be run from the project '.../server' folder.${NC}"
    echo -e "  ${GREEN}--dnfupdate <IP>${NC}   Transfers local 'dnfupdate.sh' to remote /opt and runs it."
    echo -e "  ${GREEN}--help, -h${NC}         Show this help message."
    echo -e ""
    echo -e "${YELLOW}IP FORMAT:${NC}"
    echo -e "  You can enter just the host number or the subnet+host."
    echo -e "  (Base Config: ${BASE_IP}.${DEFAULT_SUBNET}.x)"
    echo -e ""
    echo -e "  Ex: ${GREEN}tool --deploy 11${NC}      -> Connects to ${BASE_IP}.${DEFAULT_SUBNET}.11"
    echo -e "  Ex: ${GREEN}tool --deploy 99.11${NC}   -> Connects to ${BASE_IP}.99.11"
    echo -e ""
}

# 1. PARSE ARGUMENTS
MODE=$1
IP_SUFFIX=$2

# Check for Help Flag immediately (No IP required)
if [[ "$MODE" == "--help" || "$MODE" == "-h" ]]; then
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

# 3. CHECK SSH CONNECTION (Common to all processes)
check_and_setup_ssh "${REMOTE_USER}" "${TARGET_IP}"

# 4. EXECUTE REQUESTED PROCESS
case "$MODE" in
    --deploy)
        log_step "MAIN" "Starting Deployment Process..."
        bash "$SCRIPT_DIR/process_deploy.sh"
        ;;
    --dnfupdate)
        log_step "MAIN" "Starting DNF Update Process..."
        bash "$SCRIPT_DIR/process_dnfupdate.sh"
        ;;
    *)
        error_exit "Unknown mode: $MODE. Run 'tool --help' for usage."
        ;;
esac