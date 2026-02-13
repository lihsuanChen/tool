#!/bin/bash

# ==============================================================================
# MODULE: Docker Deploy - ENVIRONMENT
# DESCRIPTION: Sets up the base platform, pulls images, and starts containers.
# ==============================================================================

# Ensure execution abstraction is loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/m1_lib_exec.sh"

deploy_docker_env() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- Local Paths ---
    local PROJECT_ROOT="$HOME/projects/dctrack_app"
    local LOCAL_PLATFORM_DIR="${PROJECT_ROOT}/platform"
    local LOCAL_ENV_DIR="$HOME/env/docker-dev"

    # --- Remote Paths ---
    local REMOTE_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"
    local REMOTE_CONFIG_DIR="${REMOTE_ROOT}/platform/Docker/Dev"
    local REMOTE_APP_BASE="${DOCKER_APP_MOUNT:-/dct_builds/dctrack_app}"

    log_step "ENV-DEPLOY" "Setting up Environment on ${TARGET_IP} (Local Mode: ${IS_LOCAL_MODE})..."

    # 1. Validation
    if [ ! -d "$LOCAL_PLATFORM_DIR" ]; then error_exit "Platform dir missing: $LOCAL_PLATFORM_DIR"; fi
    if [ ! -f "$LOCAL_ENV_DIR/env.dev" ]; then error_exit "Missing env.dev in: $LOCAL_ENV_DIR"; fi

    # ==========================
    # STEP 1: Choose Version
    # ==========================
    echo -e "${YELLOW}Select dcTrackVersion:${NC}"
    local SELECTED_VER
    SELECTED_VER=$(ui_choose "9.4.0" "9.3.5" "9.3.0" "9.2.0")
    echo -e "Selected: ${GREEN}${SELECTED_VER}${NC}"

    # ==========================
    # STEP 2: Choose Release
    # ==========================
    local USE_LATEST="true"
    local MANUAL_REL=""

    echo -e "\n${YELLOW}Select Release Strategy:${NC}"
    local REL_STRATEGY
    REL_STRATEGY=$(ui_choose "Latest (Auto-detect from Nexus)" "Manual Input")

    if [[ "$REL_STRATEGY" == "Manual"* ]]; then
        USE_LATEST="false"
        MANUAL_REL=$(ui_input "Enter Release Number (e.g. 362)")
    fi

    if [ "$USE_LATEST" == "false" ]; then
        if [ -z "$MANUAL_REL" ]; then error_exit "Release number cannot be empty."; fi
        echo -e "Target: ${GREEN}${SELECTED_VER}-${MANUAL_REL}${NC}"
    else
        echo -e "Target: ${GREEN}${SELECTED_VER} (Latest)${NC}"
    fi

    # 3. Prepare Remote
    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo mkdir -p ${REMOTE_ROOT} ${REMOTE_APP_BASE}" "false"

    # 4. Sync Platform
    echo "Uploading Platform folder..."
    sync_to_target "${LOCAL_PLATFORM_DIR}" "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_ROOT}/" "--delete"

    # 5. Inject env.dev
    echo "Injecting env.dev..."
    sync_to_target "${LOCAL_ENV_DIR}/env.dev" "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_CONFIG_DIR}/env.dev"

    # ==============================================================================
    # [FIX] Local Mode Permission Patch (Robust Version)
    # ==============================================================================
    if [ "$IS_LOCAL_MODE" == "true" ]; then
        log_step "FIX-PERMS" "Fixing ownership for Local Mode access..."

        # 1. Refresh sudo credentials
        if command -v sudo &> /dev/null; then
            echo -e "${YELLOW}[Local] Refreshing sudo credentials...${NC}"
            sudo -v
        fi

        # 2. Resolve IDs
        local MY_UID=$(id -u)
        local MY_GID=$(id -g)

        # 3. Optimization: Only chown if owner is different
        # This avoids running a heavy sudo command if not needed
        local CURRENT_OWNER
        CURRENT_OWNER=$(stat -c '%u:%g' "${REMOTE_ROOT}" 2>/dev/null)

        if [ "$CURRENT_OWNER" != "${MY_UID}:${MY_GID}" ]; then
            echo "Ownership mismatch ($CURRENT_OWNER vs ${MY_UID}:${MY_GID}). Applying fix..."
            run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "sudo chown -R ${MY_UID}:${MY_GID} ${REMOTE_ROOT}" "false"
        else
            echo "Ownership is correct. Skipping chown."
        fi
    fi

    # 6. Remote Execution
    local REMOTE_CMDS="
        export BUILDKIT_PROGRESS=plain
        set -e
        cd ${REMOTE_CONFIG_DIR}

        # --- CLEANUP ---
        echo '[Remote] Stopping containers...'
        sudo docker rm -f redis activemq nginx_request_router nginx_web_assets puma queue_classic queue_classic_tile_nodes cronjobs docker-tomcat-1 docker-db-1 2>/dev/null || true
        sudo docker compose down --remove-orphans 2>/dev/null || true

        # --- CONFIGURATION ---
        echo '[Remote] Configuring docker-compose.yml...'
        sed -i '/tomcat_asset_service/s/^ *# *image/    image/' docker-compose.yml
        sed -i '\|/dct_builds/dctrack_app/server/dcTrackApp/target/dcTrackApp|s/^\( *\)- /\1# - /' docker-compose.yml
        sed -i '\|/dct_builds/dctrack_app_client/dist|s/^\( *\)- /\1# - /' docker-compose.yml

        # Symlink if needed
        if [ ! -L /platform ] && [ ! -d /platform ]; then sudo ln -sfn ${REMOTE_ROOT}/platform /platform; fi

        # Ensure permissions for mapped volumes
        sudo chown -R 1000:1000 ${REMOTE_APP_BASE}
        sudo chmod -R 755 ${REMOTE_APP_BASE}

        # --- UPDATE .ENV ---
        sed -i 's/^dcTrackVersion=.*/dcTrackVersion=${SELECTED_VER}/' .env

        if [ \"$USE_LATEST\" == \"true\" ]; then
            sed -i 's/^getLatestRelease=.*/getLatestRelease=true/' .env

            if ! command -v jq &> /dev/null; then
                if command -v dnf &> /dev/null; then sudo dnf install -y jq;
                elif command -v apt-get &> /dev/null; then sudo apt-get install -y jq; fi
            fi

            chmod +x pullLatestDockerVersion
            ./pullLatestDockerVersion
        else
            sed -i 's/^getLatestRelease=.*/getLatestRelease=false/' .env
            sed -i 's/^dcTrackRelease=.*/dcTrackRelease=${MANUAL_REL}/' .env
            sudo docker compose pull
        fi

        echo '[Remote] Starting Environment...'
        sudo docker compose up -d
    "

    run_remote_cmd "${REMOTE_USER}" "${TARGET_IP}" "${REMOTE_CMDS}" "true"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Environment Deployed!${NC}"
    else
        error_exit "Environment deployment failed."
    fi
}