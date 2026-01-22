#!/bin/bash

# Function to Enable Remote Debugging (JPDA) in Tomcat
enable_tomcat_debug() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # Load Paths from Config (Safe Defaults if missing)
    local SERVICE="${TOMCAT_SERVICE:-tomcat10}"
    local T_HOME="${TOMCAT_HOME:-/usr/share/tomcat10}"

    local CATALINA="${T_HOME}/bin/catalina.sh"
    local STARTUP="${T_HOME}/bin/startup.sh"

    log_step "TOMCAT" "Enabling Remote Debugging (JPDA) on ${TARGET_IP}..."

    # Remote Script
    ssh "${REMOTE_USER}@${TARGET_IP}" "
        # 1. Update catalina.sh: Change localhost -> 0.0.0.0
        if grep -q 'JPDA_ADDRESS=\"0.0.0.0:8000\"' '${CATALINA}'; then
            echo '[Remote] catalina.sh already listening on 0.0.0.0.'
        else
            echo '[Remote] Updating catalina.sh to allow remote connection...'
            sed -i 's/JPDA_ADDRESS=\"localhost:8000\"/JPDA_ADDRESS=\"0.0.0.0:8000\"/' '${CATALINA}'
        fi

        # 2. Update startup.sh: Add 'jpda' before 'start'
        if grep -q 'jpda start' '${STARTUP}'; then
            echo '[Remote] startup.sh already configured for JPDA.'
        else
            echo '[Remote] Updating startup.sh to enable JPDA mode...'
            sed -i '/^exec/ s/start \"\$@\"/jpda start \"\$@\"/' '${STARTUP}'
        fi

        # 3. Restart Tomcat Service
        echo '[Remote] Restarting Tomcat Service (${SERVICE})...'
        if command -v systemctl &> /dev/null; then
            systemctl restart ${SERVICE}.service
        else
            service ${SERVICE} restart
        fi
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Tomcat Debugging Enabled (Port 8000).${NC}"
    else
        error_exit "Failed to update Tomcat configuration."
    fi
}