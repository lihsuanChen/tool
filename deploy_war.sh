#!/bin/bash

# =================CONFIGURATION =================
# Default remote username (Change this if not root)
# Note: Writing to /var/lib/tomcat10 usually requires root or a specific tomcat user
REMOTE_USER="root"
# Base IP prefix
BASE_IP="192.168"
# Default Subnet if only host number is provided
DEFAULT_SUBNET="78"
# Relative path to the app source from the 'server' folder
APP_DIR="dcTrackApp"
# Target directory on Rocky Linux
REMOTE_DEST="/var/lib/tomcat10/webapps"
# ================================================

# ANSI Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper function for logging
log_step() {
    echo -e "\n${BLUE}==================================================${NC}"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

error_exit() {
    echo -e "${RED}ERROR: $1${NC}"
    exit 1
}

# 0. INPUT VALIDATION
if [ -z "$1" ]; then
    error_exit "Please provide an IP suffix (e.g., 188 or 78.188)"
fi

INPUT=$1
TARGET_IP=""

# Logic to determine IP
if [[ "$INPUT" == *.* ]]; then
    # Input has a dot (e.g., 78.188)
    TARGET_IP="${BASE_IP}.${INPUT}"
else
    # Input is just a number (e.g., 188)
    TARGET_IP="${BASE_IP}.${DEFAULT_SUBNET}.${INPUT}"
fi

echo -e "Target defined as: ${YELLOW}${TARGET_IP}${NC}"


# 1. CONFIRM LOCATION
log_step "1" "Checking Working Directory"
CURRENT_DIR=$(pwd)
BASENAME=$(basename "$CURRENT_DIR")

echo "Current directory: $CURRENT_DIR"

if [ "$BASENAME" != "server" ]; then
    error_exit "You are not in a '.../server' folder. Please move to the correct directory."
else
    echo -e "${GREEN}Directory confirmed: server${NC}"
fi

# Check for dcTrackApp folder existence
if [ ! -d "./dcTrackApp" ]; then
    error_exit "Folder 'dcTrackApp' not found in current directory. Expected structure: .../server/dcTrackApp"
else
    echo -e "${GREEN}Subfolder confirmed: dcTrackApp${NC}"
fi


# 2. CONFIRM SSH/SCP CONNECTION
log_step "2" "Verifying SSH Connection to ${REMOTE_USER}@${TARGET_IP}"

# Check connectivity using batch mode (checks if keys are set up)
if ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${TARGET_IP}" "echo Connection Success" 2>/dev/null; then
    echo -e "${GREEN}SSH Key already configured. Connection valid.${NC}"
else
    echo -e "${YELLOW}SSH Key not detected or connection failed.${NC}"
    echo -e "We need to set up the SSH key for passwordless SCP (or enter password for this session)."
    read -p "Do you want to run ssh-copy-id to save your key now? (y/n): " SETUP_KEY
    
    if [[ "$SETUP_KEY" =~ ^[Yy]$ ]]; then
        echo "Running ssh-copy-id. Please enter your password when prompted..."
        ssh-copy-id "${REMOTE_USER}@${TARGET_IP}"
        if [ $? -eq 0 ]; then
             echo -e "${GREEN}SSH Key saved successfully.${NC}"
        else
             echo -e "${RED}Failed to save SSH key. You may need to enter password manually for SCP steps.${NC}"
        fi
    else
        echo "Skipping key save. You will be prompted for a password during transfer."
    fi
fi


# 3. BUILD WAR FILE
log_step "3" "Building WAR with Maven"

# Check if the app directory exists
if [ ! -d "./$APP_DIR" ]; then
    error_exit "Directory ./$APP_DIR not found inside $(pwd)."
fi

# Store root server dir to return later if needed, though we run mvn here
# We assume the pom.xml is in the server folder or we need to go into dcTrackApp?
# Based on prompt "scp the war which is in .../server/dcTrackApp/target/", 
# usually mvn is run from the project root.
# Assuming we need to run mvn inside dcTrackApp or from server? 
# Standard is usually root, but let's assume we run it from current dir or check for pom.

if [ -f "./pom.xml" ]; then
    echo "pom.xml found in current directory. Building..."
    mvn clean install -DskipTests -T 1C
elif [ -f "./$APP_DIR/pom.xml" ]; then
    echo "pom.xml found in $APP_DIR. Entering directory..."
    cd "$APP_DIR"
    mvn clean install -DskipTests -T 1C
    cd .. # Return to server folder
else
    error_exit "No pom.xml found in current dir or $APP_DIR."
fi

if [ $? -ne 0 ]; then
    error_exit "Maven build failed."
fi


# 4. SCP TO REMOTE
log_step "4" "Deploying WAR to Remote Server"

# Locate the WAR file
# Note: This finds the most recently modified WAR file in the target directory
WAR_FILE=$(find ./$APP_DIR/target -name "*.war" -type f | head -n 1)

if [ -z "$WAR_FILE" ]; then
    error_exit "No WAR file found in ./$APP_DIR/target/"
fi

echo -e "Found WAR file: ${YELLOW}$WAR_FILE${NC}"
echo -e "Destination: ${YELLOW}${REMOTE_USER}@${TARGET_IP}:${REMOTE_DEST}/dcTrackApp.war${NC}"

# Renaming to dcTrackApp.war during SCP to match your restart logic
scp "$WAR_FILE" "${REMOTE_USER}@${TARGET_IP}:${REMOTE_DEST}/dcTrackApp.war"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}File uploaded successfully.${NC}"
else
    error_exit "SCP transfer failed."
fi


# 5. REMOTE EXECUTION
log_step "5" "Restarting Remote Tomcat Service"

REMOTE_CMDS="
cd ${REMOTE_DEST} && \
echo 'Removing old application folder...' && \
rm -rf dcTrackApp && \
echo 'Setting permissions...' && \
chmod 777 dcTrackApp.war && \
echo 'Restarting Tomcat...' && \
systemctl restart tomcat10.service
"

echo -e "Executing remote commands on ${YELLOW}${TARGET_IP}${NC}..."

ssh "${REMOTE_USER}@${TARGET_IP}" "$REMOTE_CMDS"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}SUCCESS: Deployment and Restart complete!${NC}"
else
    error_exit "Remote command execution failed."
fi
