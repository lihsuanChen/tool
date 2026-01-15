#!/bin/bash

# Load the sub-modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m6_docker_install.sh"
source "$SCRIPT_DIR/m6_docker_deploy.sh"
source "$SCRIPT_DIR/m6_docker_optimize.sh"

# ================= MENU FUNCTION =================
show_docker_menu() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    echo -e "${YELLOW}Docker Actions for ${TARGET_IP}:${NC}"
    echo -e "  ${GREEN}1)${NC} Install Docker Platform"
    echo -e "  ${GREEN}2)${NC} Deploy Environment (Pull Images & Configs)"
    echo -e "  ${GREEN}3)${NC} Deploy App Code (Sync WAR & Restart)"
    echo -e "  ${GREEN}4)${NC} Optimize Storage (Fix 'No Space')"
    echo -e "  ${GREEN}0)${NC} Cancel"

    echo ""
    read -p "Select action [1]: " ACTION_CHOICE
    ACTION_CHOICE=${ACTION_CHOICE:-1}

    case "$ACTION_CHOICE" in
        1) install_docker_remote "$REMOTE_USER" "$TARGET_IP" ;;
        2) deploy_docker_env "$REMOTE_USER" "$TARGET_IP" ;;     # Calls Function 1
        3) deploy_app_code "$REMOTE_USER" "$TARGET_IP" ;;       # Calls Function 2
        4) optimize_docker_storage "$REMOTE_USER" "$TARGET_IP" ;;
        0) echo "Cancelled."; exit 0 ;;
        *) echo -e "${RED}Invalid selection.${NC}"; exit 1 ;;
    esac
}

# ================= ROUTER =================
docker_router() {
    local SUBCOMMAND=$1
    local REMOTE_USER=$2
    local TARGET_IP=$3
    shift 3

    case "$SUBCOMMAND" in
        install|setup) install_docker_remote "$REMOTE_USER" "$TARGET_IP" ;;
        deploy|env)    deploy_docker_env "$REMOTE_USER" "$TARGET_IP" ;;
        code|update)   deploy_app_code "$REMOTE_USER" "$TARGET_IP" ;;
        optimize)      optimize_docker_storage "$REMOTE_USER" "$TARGET_IP" ;;
        ps|ls)
            log_step "DOCKER" "Checking running containers..."
            ssh "$REMOTE_USER@$TARGET_IP" "sudo docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'"
            ;;
        *)
            echo -e "${RED}Error: Unknown subcommand '$SUBCOMMAND'${NC}"
            echo "Available: install, deploy (env), code (update), optimize"
            exit 1
            ;;
    esac
}