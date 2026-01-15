#!/bin/bash

# ==============================================================================
# FUNCTION 1: Deploy Environment (Pull Images & Configs)
# GOAL: 1. Select Version & Release Strategy
#       2. Sync Platform & Inject env.dev
#       3. CLEANUP Old Containers
#       4. Update .env based on selection
#       5. Pull & Start
# ==============================================================================
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

    log_step "ENV-DEPLOY" "Setting up Environment on ${TARGET_IP}..."

    # 1. Validation
    if [ ! -d "$LOCAL_PLATFORM_DIR" ]; then error_exit "Platform dir missing: $LOCAL_PLATFORM_DIR"; fi
    if [ ! -f "$LOCAL_ENV_DIR/env.dev" ]; then error_exit "Missing env.dev in: $LOCAL_ENV_DIR"; fi

    # ==========================
    # STEP 1: Choose Version
    # ==========================
    echo -e "${YELLOW}Choose dcTrackVersion:${NC}"
    echo "  1) 9.4.0"
    echo "  2) 9.3.5"
    echo "  3) 9.3.0"
    echo "  4) 9.2.0"
    read -p "Select [1-4]: " VER_OPT

    case $VER_OPT in
        1) SELECTED_VER="9.4.0" ;;
        2) SELECTED_VER="9.3.5" ;;
        3) SELECTED_VER="9.3.0" ;;
        4) SELECTED_VER="9.2.0" ;;
        *) echo -e "${RED}Invalid option. Defaulting to 9.3.0${NC}"; SELECTED_VER="9.3.0" ;;
    esac

    # ==========================
    # STEP 2: Choose Release
    # ==========================
    echo -e "\n${YELLOW}Choose dcTrackRelease for $SELECTED_VER:${NC}"
    echo "  1) Use Latest (Auto-detect from Nexus)"
    echo "  2) Input Release Manually"
    read -p "Select [1-2]: " REL_OPT
    REL_OPT=${REL_OPT:-1}

    local USE_LATEST="true"
    local MANUAL_REL=""

    if [ "$REL_OPT" == "2" ]; then
        USE_LATEST="false"
        read -p "Enter Release Number (e.g. 362): " MANUAL_REL
        if [ -z "$MANUAL_REL" ]; then error_exit "Release number cannot be empty."; fi
        echo -e "Target: ${GREEN}${SELECTED_VER}-${MANUAL_REL}${NC}"
    else
        echo -e "Target: ${GREEN}${SELECTED_VER} (Latest)${NC}"
    fi

    # 3. Prepare Remote
    echo "Preparing remote structure..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "sudo mkdir -p ${REMOTE_ROOT} ${REMOTE_APP_BASE}"

    # 4. Sync Platform
    echo "Uploading Platform folder..."
    rsync -avz -e ssh --delete "${LOCAL_PLATFORM_DIR}" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_ROOT}/"

    # 5. Inject env.dev
    echo "Injecting env.dev..."
    rsync -avz -e ssh "${LOCAL_ENV_DIR}/env.dev" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_CONFIG_DIR}/env.dev"

    # 6. Remote Execution
    ssh -t "${REMOTE_USER}@${TARGET_IP}" "
        set -e
        cd ${REMOTE_CONFIG_DIR}

        # --- CLEANUP (Stop old containers) ---
        echo '[Remote] Stopping all related containers...'
        CONTAINERS_TO_KILL='redis activemq nginx_request_router nginx_web_assets puma queue_classic queue_classic_tile_nodes cronjobs docker-tomcat-1 docker-db-1'
        sudo docker rm -f \$CONTAINERS_TO_KILL 2>/dev/null || true
        sudo docker compose down --remove-orphans 2>/dev/null || true

        # --- CONFIGURATION (Enable Image / Disable Volume) ---
        echo '[Remote] Configuring docker-compose.yml...'
        sed -i '/tomcat_asset_service/s/^ *# *image/    image/' docker-compose.yml
        sed -i '\|/dct_builds/dctrack_app/server/dcTrackApp/target/dcTrackApp|s/^\( *\)- /\1# - /' docker-compose.yml

        # Fix Symlinks & Perms
        if [ ! -L /platform ] && [ ! -d /platform ]; then sudo ln -sfn ${REMOTE_ROOT}/platform /platform
        elif [ -L /platform ]; then sudo ln -sfn ${REMOTE_ROOT}/platform /platform; fi

        sudo chown -R 1000:1000 ${REMOTE_APP_BASE}
        sudo chmod -R 755 ${REMOTE_APP_BASE}

        # --- UPDATE .ENV FILES ---
        echo '[Remote] Updating .env configuration...'

        sed -i 's/^dcTrackVersion=.*/dcTrackVersion=${SELECTED_VER}/' .env

        if [ \"$USE_LATEST\" == \"true\" ]; then
            # --- STRATEGY: USE LATEST ---
            echo '[Remote] Strategy: LATEST. Setting getLatestRelease=true...'
            sed -i 's/^getLatestRelease=.*/getLatestRelease=true/' .env

            if ! command -v jq &> /dev/null; then
                 if [ -f /etc/redhat-release ]; then sudo dnf install -y jq;
                 else sudo apt-get update && sudo apt-get install -y jq; fi
            fi
            chmod +x pullLatestDockerVersion
            ./pullLatestDockerVersion

        else
            # --- STRATEGY: MANUAL INPUT ---
            echo '[Remote] Strategy: MANUAL. Setting getLatestRelease=false...'
            sed -i 's/^getLatestRelease=.*/getLatestRelease=false/' .env
            sed -i 's/^dcTrackRelease=.*/dcTrackRelease=${MANUAL_REL}/' .env

            echo '[Remote] Pulling specific images (${SELECTED_VER}-${MANUAL_REL})...'
            sudo docker compose pull
        fi

        # --- STARTUP ---
        echo '[Remote] Starting Environment...'
        sudo docker compose up -d
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Environment Deployed!${NC}"
    else
        error_exit "Environment deployment failed."
    fi
}

# ==============================================================================
# FUNCTION 2: Deploy App Code (Sync WAR & Restart)
# GOAL: 1. Build (Optional)
#       2. Sync Code
#       3. Config (Disable Image / Enable Volume)
#       4. Restart Tomcat
# ==============================================================================
deploy_app_code() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # --- Local Paths ---
    local PROJECT_ROOT="$HOME/projects/dctrack_app"
    local SERVER_ROOT="${PROJECT_ROOT}/server"
    local LOCAL_ARTIFACT_DIR="${SERVER_ROOT}/dcTrackApp/target/dcTrackApp"
    local LOCAL_ARTIFACT_WAR="${SERVER_ROOT}/dcTrackApp/target/dcTrackApp.war"

    # --- Remote Paths ---
    local REMOTE_ROOT="${DOCKER_PROJECT_ROOT:-/dct_builds/docker}"
    local REMOTE_CONFIG_DIR="${REMOTE_ROOT}/platform/Docker/Dev"
    local REMOTE_APP_BASE="${DOCKER_APP_MOUNT:-/dct_builds/dctrack_app}"
    local REMOTE_ARTIFACT_PATH="${REMOTE_APP_BASE}/server/dcTrackApp/target/dcTrackApp"

    log_step "CODE-DEPLOY" "Preparing to deploy to ${TARGET_IP}..."

    # ==========================
    # STEP 1: Choose Build Strategy
    # ==========================
    echo -e "${YELLOW}Choose Deployment Strategy:${NC}"
    echo "  1) Directly Deploy (Use existing WAR/Folder)"
    echo "  2) Build and Deploy (mvn clean install)"
    read -p "Select [1-2]: " BUILD_OPT
    BUILD_OPT=${BUILD_OPT:-1}

    if [ "$BUILD_OPT" == "2" ]; then
        echo -e "\n${BLUE}Starting Maven Build...${NC}"
        echo "Command: mvn clean install -DskipTests -T 1C"
        echo "Directory: ${SERVER_ROOT}"

        if [ -d "$SERVER_ROOT" ]; then
            cd "$SERVER_ROOT" || error_exit "Could not enter ${SERVER_ROOT}"
            mvn clean install -DskipTests -T 1C

            if [ $? -ne 0 ]; then
                error_exit "Maven build failed. Aborting deployment."
            fi
            echo -e "${GREEN}Build Successful! Proceeding to deploy...${NC}\n"
        else
            error_exit "Server directory not found: ${SERVER_ROOT}"
        fi
    fi

    # ==========================
    # STEP 2: Sync Code
    # ==========================
    echo "Syncing App Code..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "sudo mkdir -p ${REMOTE_ARTIFACT_PATH}"

    if [ -d "$LOCAL_ARTIFACT_DIR" ]; then
        echo -e "Syncing Exploded WAR from: ${YELLOW}${LOCAL_ARTIFACT_DIR}${NC}"
        rsync -avz -e ssh --delete "${LOCAL_ARTIFACT_DIR}/" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_ARTIFACT_PATH}/"

        # Cleanup root if it exists (safety check for container)
        ssh "${REMOTE_USER}@${TARGET_IP}" "
            if [ -d ${REMOTE_APP_BASE}/WEB-INF ]; then
                sudo rm -rf ${REMOTE_APP_BASE}/WEB-INF ${REMOTE_APP_BASE}/META-INF ${REMOTE_APP_BASE}/resources
            fi
        "
    elif [ -f "$LOCAL_ARTIFACT_WAR" ]; then
        echo -e "Syncing WAR file..."
        rsync -avz -e ssh "$LOCAL_ARTIFACT_WAR" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_ARTIFACT_PATH}/dcTrackApp.war"
    else
        echo -e "${YELLOW}No artifacts found in ${LOCAL_ARTIFACT_DIR}. Run 'mvn clean install' first.${NC}"
        return 1
    fi

    # ==========================
    # STEP 3: Config & Restart
    # ==========================
    ssh -t "${REMOTE_USER}@${TARGET_IP}" "
        cd ${REMOTE_CONFIG_DIR}

        # A) DISABLE IMAGE
        echo '[Remote] Commenting out Image definition...'
        sed -i '/tomcat_asset_service/s/^ *image:/    #image:/' docker-compose.yml

        # B) ENABLE VOLUME (Use Local Code)
        echo '[Remote] Enabling Local Code Volume (Removing #)...'
        sed -i '\|/dct_builds/dctrack_app/server/dcTrackApp/target/dcTrackApp|s/^\( *\)# - /\1- /' docker-compose.yml

        echo '[Remote] Fixing permissions...'
        sudo chown -R 1000:1000 ${REMOTE_APP_BASE}
        sudo chmod -R 755 ${REMOTE_APP_BASE}

        echo '[Remote] Restarting Tomcat Service...'
        sudo docker compose restart tomcat
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Code Deployed & Tomcat Restarted!${NC}"
        echo -e "App URL: http://${TARGET_IP}:8080/dcTrackApp"
    else
        error_exit "Code deployment failed."
    fi
}