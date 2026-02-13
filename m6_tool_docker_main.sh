#!/bin/bash

# Load the sub-modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m6_docker_install.sh"
source "$SCRIPT_DIR/m6_docker_deploy.sh"
source "$SCRIPT_DIR/m6_docker_optimize.sh"
source "$SCRIPT_DIR/m1_lib_exec.sh" # [NEW] Ensure exec lib is available

# ================= MENU FUNCTION =================
show_docker_menu() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    echo -e "${YELLOW}Docker Actions for ${TARGET_IP} (Local Mode: ${IS_LOCAL_MODE}):${NC}"

    # === GUM MENU ONLY ===
    ACTION=$(gum choose \
        "1. Install Docker Platform" \
        "2. Deploy Environment (Pull Images & Configs)" \
        "3. Deploy Server/Client/DB (Sync Repository & Restart)" \
        "4. Optimize Storage (Fix 'No Space')" \
        "0. Cancel")

    if [ -z "$ACTION" ]; then echo "Cancelled."; exit 0; fi

    ACTION_CHOICE="${ACTION:0:1}"

    case "$ACTION_CHOICE" in
        1) install_docker_remote "$REMOTE_USER" "$TARGET_IP" ;;
        2) deploy_docker_env "$REMOTE_USER" "$TARGET_IP" ;;     # Calls Function
        3) deploy_app_code "$REMOTE_USER" "$TARGET_IP" ;;       # Calls Router
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
            # [MODIFIED] Use run_remote_cmd abstraction
            run_remote_cmd "$REMOTE_USER" "$TARGET_IP" "sudo docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}'"
            ;;
        *)
            echo -e "${RED}Error: Unknown subcommand '$SUBCOMMAND'${NC}"
            echo "Available: install, deploy (env), code (update), optimize"
            exit 1
            ;;
    esac
}