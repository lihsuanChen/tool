#!/bin/bash

# Function to Enable Remote Debugging (JPDA) in Tomcat
enable_tomcat_debug() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    log_step "TOMCAT" "Enabling Remote Debugging (JPDA) on ${TARGET_IP}..."

    # Define File Paths
    local CATALINA="/usr/share/tomcat10/bin/catalina.sh"
    local STARTUP="/usr/share/tomcat10/bin/startup.sh"

    # Remote Script
    # We use \" to escape double quotes inside the SSH command block
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

            # IMPROVED SED:
            # Instead of matching the whole complex line, we only find the 'exec' line
            # and replace 'start "$@"' with 'jpda start "$@"'
            sed -i '/^exec/ s/start \"\$@\"/jpda start \"\$@\"/' '${STARTUP}'
        fi

        # 3. Restart Tomcat Service
        echo '[Remote] Restarting Tomcat Service...'
        if command -v systemctl &> /dev/null; then
            systemctl restart tomcat10.service
        else
            service tomcat10 restart
        fi
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: Tomcat Debugging Enabled (Port 8000).${NC}"
    else
        error_exit "Failed to update Tomcat configuration."
    fi
}