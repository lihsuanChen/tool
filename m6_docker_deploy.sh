#!/bin/bash

# ==============================================================================
# MODULE: Docker Deployment Router
# DESCRIPTION: Orchestrates deployments by routing to specific sub-modules.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load Libraries ---
source "$SCRIPT_DIR/m1_lib_ssh.sh"
source "$SCRIPT_DIR/m1_lib_ui.sh"

# --- Load Sub-Modules ---
source "$SCRIPT_DIR/m6_docker_deploy_env.sh"
source "$SCRIPT_DIR/m6_docker_deploy_server.sh"
source "$SCRIPT_DIR/m6_docker_deploy_client.sh"
source "$SCRIPT_DIR/m6_docker_deploy_database.sh" # <--- NEW

# ==============================================================================
# ROUTER FUNCTION
# ==============================================================================
deploy_app_code() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    log_step "DEPLOY-ROUTER" "Select Component to Deploy"

    local APP_TYPE
    APP_TYPE=$(ui_choose "Server (Java/Tomcat)" "Client (Angular/Node)" "Database (Liquibase)" "Cancel")

    case "$APP_TYPE" in
        "Server"*)
            deploy_server_container "$REMOTE_USER" "$TARGET_IP"
            ;;
        "Client"*)
            deploy_client_container "$REMOTE_USER" "$TARGET_IP"
            ;;
        "Database"*)
            deploy_database_container "$REMOTE_USER" "$TARGET_IP"
            ;;
        *)
            echo -e "${YELLOW}Deployment cancelled.${NC}"
            ;;
    esac
}