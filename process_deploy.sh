#!/bin/bash

# ALWAYS load the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_ssh.sh"

# ================= DETECT CONTEXT =================
CURRENT_DIR=$(pwd)
BASENAME=$(basename "$CURRENT_DIR")

# Check 1: SERVER Mode
if [ "$BASENAME" == "server" ] && [ -d "./dcTrackApp" ]; then
    DEPLOY_TYPE="SERVER"
    APP_DIR="dcTrackApp"
    REMOTE_DEST="/var/lib/tomcat10/webapps"

# Check 2: CLIENT Mode
elif [[ "$CURRENT_DIR" == *"/dctrack_app_client" ]]; then
    DEPLOY_TYPE="CLIENT"
    REMOTE_CLIENT_DEST="/opt/raritan/dcTrack/appClient"
    if [ ! -f "./package.json" ]; then error_exit "Missing package.json"; fi

# Check 3: DB MIGRATION Mode
elif [[ "$CURRENT_DIR" == *"/dctrack_database" ]]; then
    DEPLOY_TYPE="DATABASE"
    LOCAL_CHANGESETS="./src/files/opt/raritan/liquibase/changesets"
    REMOTE_DB_DEST="/var/oculan/raritan/liquibase/changesets"

    if [ ! -d "$LOCAL_CHANGESETS" ]; then
        error_exit "Directory '$LOCAL_CHANGESETS' not found."
    fi

else
    echo -e "${RED}CRITICAL ERROR: Unknown Repository Context${NC}"
    echo "Current directory: $CURRENT_DIR"
    echo "To deploy, you must be in one of these locations:"
    echo -e "  1. .../server"
    echo -e "  2. .../dctrack_app_client"
    echo -e "  3. .../dctrack_database"
    exit 1
fi

log_step "DEPLOY" "Detected Repository Type: ${YELLOW}$DEPLOY_TYPE${NC}"

# ================= SERVER DEPLOYMENT FLOW =================
if [ "$DEPLOY_TYPE" == "SERVER" ]; then
    log_step "BUILD" "Building Server (Maven)..."
    if [ -f "./pom.xml" ]; then mvn clean install -DskipTests -T 1C; elif [ -f "./$APP_DIR/pom.xml" ]; then cd "$APP_DIR"; mvn clean install -DskipTests -T 1C; cd ..; else error_exit "No pom.xml found."; fi
    if [ $? -ne 0 ]; then error_exit "Maven build failed."; fi

    log_step "UPLOAD" "Uploading WAR..."
    WAR_FILE=$(find ./$APP_DIR/target -name "*.war" -type f | head -n 1)
    if [ -z "$WAR_FILE" ]; then error_exit "No WAR file found"; fi
    scp "$WAR_FILE" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DEST}/dcTrackApp.war"
    if [ $? -ne 0 ]; then error_exit "SCP failed."; fi

    log_step "REMOTE" "Restarting Tomcat..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "cd ${REMOTE_DEST} && rm -rf dcTrackApp && chmod 777 dcTrackApp.war && systemctl restart tomcat10.service"
    if [ $? -eq 0 ]; then echo -e "${GREEN}SUCCESS: Server Deployment complete!${NC}"; else error_exit "Restart failed."; fi

# ================= CLIENT DEPLOYMENT FLOW =================
elif [ "$DEPLOY_TYPE" == "CLIENT" ]; then
    log_step "BUILD" "Building Client (NPM)..."
    echo "Running npm install..." && npm install
    echo "Running npm rebuild node-sass..." && npm rebuild node-sass
    echo "Running npm run source-map..." && npm run source-map
    if [ ! -d "./dist" ]; then error_exit "Dist folder missing."; fi

    log_step "REMOTE" "Cleaning remote folder..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "mkdir -p ${REMOTE_CLIENT_DEST} && rm -rf ${REMOTE_CLIENT_DEST}/*"

    log_step "UPLOAD" "Syncing ./dist..."
    scp -r ./dist/* "${REMOTE_USER}@${TARGET_IP}:${REMOTE_CLIENT_DEST}/"

    log_step "REMOTE" "Setting Permissions..."
    ssh "${REMOTE_USER}@${TARGET_IP}" "chmod -R 777 ${REMOTE_CLIENT_DEST}/*"
    if [ $? -eq 0 ]; then echo -e "${GREEN}SUCCESS: Client Deployment complete!${NC}"; else error_exit "Client deploy failed."; fi

# ================= DATABASE DEPLOYMENT FLOW =================
elif [ "$DEPLOY_TYPE" == "DATABASE" ]; then

    # 0. SAFETY CHECK (CONFIRMATION)
    echo -e "\n${RED}!!! WARNING: DATABASE MIGRATION !!!${NC}"
    echo -e "Target Server:  ${YELLOW}${TARGET_IP}${NC}"
    if [ -n "$DB_VERSION" ]; then
        echo -e "Target Version: ${YELLOW}dctrack${DB_VERSION}${NC}"
    else
        echo -e "Target Version: ${YELLOW}ALL CHANGESETS${NC}"
    fi
    echo -e "----------------------------------------"
    read -p "Are you sure you want to execute this migration? (y/N): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Operation Cancelled by user.${NC}"
        exit 0
    fi

    # 1. DETERMINE SYNC SOURCE/TARGET
    log_step "RSYNC" "Syncing Migration Files..."

    if [ -n "$DB_VERSION" ]; then
        # Case A: Specific Version
        TARGET_FOLDER="dctrack${DB_VERSION}"
        LOCAL_SRC="${LOCAL_CHANGESETS}/${TARGET_FOLDER}"

        if [ ! -d "$LOCAL_SRC" ]; then
            error_exit "Version folder '$TARGET_FOLDER' not found in changesets."
        fi

        echo -e "Syncing ONLY: ${YELLOW}${TARGET_FOLDER}${NC}"
        rsync -av -e "ssh" "${LOCAL_SRC}" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DB_DEST}/"

    else
        # Case B: All Versions
        echo -e "Syncing ${YELLOW}ALL changesets${NC}..."
        rsync -av -e "ssh" "${LOCAL_CHANGESETS}/" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DB_DEST}/"
    fi

    if [ $? -ne 0 ]; then error_exit "Rsync failed."; fi

    # 2. EXECUTE MIGRATION SCRIPT
    log_step "REMOTE" "Executing Database Migration..."
    REMOTE_CMD="/usr/local/sbin/database-migrate.sh"

    echo -e "Running: ${YELLOW}${REMOTE_CMD}${NC}"
    ssh "${REMOTE_USER}@${TARGET_IP}" "${REMOTE_CMD}"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Database Migration complete!${NC}"
    else
        error_exit "Remote migration script failed."
    fi

fi