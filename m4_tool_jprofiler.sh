#!/bin/bash

# ==============================================================================
# JPROFILER SETUP MODULE
# Adapts to JDK version:
#   - New dcTrack (>9.2 / Java 21+): Uses JProfiler 15 (Client-side SSH Attach)
#     * No server-side install/config required.
#   - Old dcTrack (<=9.2 / Java 17-): Uses JProfiler 12 (Agent Path)
#     * Requires server-side install & setenv.sh config.
# ==============================================================================

setup_jprofiler_remote() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # Load Vars from .t_config (with defaults for safety)
    local T_HOME="${TOMCAT_HOME:-/usr/share/tomcat10}"
    local SERVICE="${TOMCAT_SERVICE:-tomcat10}"

    # JProfiler Legacy Config (Defaults to v12.0.4 if not set in .t_config)
    local JP_VER="${JP_LEGACY_VER:-12.0.4}"
    local JP_URL="${JP_LEGACY_URL:-https://download.ej-technologies.com/jprofiler/jprofiler_agent_linux-x86_12_0_4.tar.gz}"
    local JP_HOME="${JP_LEGACY_HOME:-/opt/jprofiler12}"
    local JP_PORT="${JP_AGENT_PORT:-8849}"
    local JP_LIB="${JP_LIB_PATH:-bin/linux-x64/libjprofilerti.so}"

    log_step "JPROFILER" "Configuring JProfiler on ${TARGET_IP}..."

    # NOTE: The closing EOF must be flush left
    ssh "${REMOTE_USER}@${TARGET_IP}" "bash -s" << EOF
    set -e

    # --- 1. DETECT VERSION ---
    if rpm -q dctrack_config &>/dev/null; then
        VER_SCORE=\$(rpm -q --queryformat '%{version}' dctrack_config | awk -F. '{ print \$1 * 10 + \$2 * 1 }')
    else
        echo '[Remote] Warning: dctrack_config not found. Assuming modern approach.'
        VER_SCORE=99
    fi

    # --- 2. LOGIC BRANCH ---
    if [ "\$VER_SCORE" -gt 92 ]; then
        # ==========================================
        # MODERN: Java 21+ (JProfiler 15)
        # Strategy: Zero-Config SSH Attach (Client driven)
        # ==========================================
        echo -e "[Remote] Detected: \033[1;33mJava 21+ (Score: \$VER_SCORE)\033[0m"
        echo -e "[Remote] Strategy: \033[1;32mNo server-side installation required for v15.\033[0m"
        echo "[Remote] Please use 'Attach to Remote JVM' via SSH in your local JProfiler client."

        # We still clean up conflicts, but skip install/setenv edits.
        SKIP_INSTALL=true
    else
        # ==========================================
        # LEGACY: Java 17- (JProfiler 12)
        # Strategy: Agent Path (Requires Install + Config)
        # ==========================================
        echo -e "[Remote] Detected: \033[1;33mJava 17- (Score: \$VER_SCORE)\033[0m"
        echo -e "[Remote] Strategy: \033[1;32mInstalling JProfiler ${JP_VER} Agent...\033[0m"

        SKIP_INSTALL=false
    fi

    # --- 3. CLEANUP STARTUP.SH (Common Conflict) ---
    STARTUP="${T_HOME}/bin/startup.sh"
    if grep -q "jpda start" "\$STARTUP"; then
        echo "[Remote] Removing 'jpda' from startup.sh to prevent conflicts..."
        sed -i 's/jpda start/start/g' "\$STARTUP"
    fi

    # --- 4. FIREWALL (Common Pre-req) ---
    if command -v firewall-cmd &> /dev/null; then
        if ! firewall-cmd --list-ports | grep -q "${JP_PORT}/tcp"; then
            echo '[Remote] Opening Port ${JP_PORT}...'
            firewall-cmd --add-port=${JP_PORT}/tcp --permanent >/dev/null
            firewall-cmd --reload >/dev/null
        fi
    fi

    # --- 5. INSTALL & CONFIGURE (Legacy Only) ---
    if [ "\$SKIP_INSTALL" = false ]; then

        # A. Install
        if [ ! -d "${JP_HOME}" ]; then
            echo "[Remote] Downloading JProfiler Agent..."
            wget -q -O /tmp/jprofiler.tar.gz "${JP_URL}"

            echo "[Remote] Extracting to ${JP_HOME}..."
            # Create a temp dir to extract and find the root folder name
            mkdir -p /opt/jp_tmp
            tar xzf /tmp/jprofiler.tar.gz --directory /opt/jp_tmp

            # Move the extracted content (whatever the folder name is) to target HOME
            mv /opt/jp_tmp/* "${JP_HOME}"
            rm -rf /opt/jp_tmp
            rm -f /tmp/jprofiler.tar.gz
        fi

        # B. Configure setenv.sh
        echo "[Remote] Updating setenv.sh with Agent Path..."
        SETENV="${T_HOME}/bin/setenv.sh"

        # Construct the agent string using configured variables
        AGENT_STR="-agentpath:${JP_HOME}/${JP_LIB}=port=${JP_PORT},nowait"
        INJECT_LINE="CATALINA_OPTS=\"\$AGENT_STR \$CATALINA_OPTS\""

        if [ ! -f "\$SETENV" ]; then touch "\$SETENV"; chmod +x "\$SETENV"; fi

        if grep -Fq "libjprofilerti.so" "\$SETENV"; then
            echo "[Remote] setenv.sh already configured. Skipping edit."
        else
            sed -i "1i \$INJECT_LINE" "\$SETENV"
            echo "[Remote] Restarting ${SERVICE}..."
            if command -v systemctl &> /dev/null; then systemctl restart ${SERVICE}; else service ${SERVICE} restart; fi
        fi
    fi
EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: JProfiler Remote Setup Complete.${NC}"
    else
        error_exit "JProfiler setup failed."
    fi
}

disable_jprofiler_remote() {
    local REMOTE_USER=$1
    local TARGET_IP=$2

    # Load Vars from .t_config
    local T_HOME="${TOMCAT_HOME:-/usr/share/tomcat10}"
    local SERVICE="${TOMCAT_SERVICE:-tomcat10}"
    local SETENV="${T_HOME}/bin/setenv.sh"

    log_step "JPROFILER" "Detaching JProfiler and Restarting ${SERVICE} on ${TARGET_IP}..."

    # NOTE: The closing EOF must be flush left
    ssh "${REMOTE_USER}@${TARGET_IP}" "bash -s" << EOF
    set -e

    # 1. CLEANUP CONFIGURATION
    if [ -f "${SETENV}" ]; then
        if grep -q "libjprofilerti.so" "${SETENV}"; then
            echo "[Remote] Removing JProfiler config from setenv.sh..."
            sed -i '/libjprofilerti.so/d' "${SETENV}"

            # 2. RESTART SERVICE (Only needed if we actually removed config)
            echo "[Remote] Restarting ${SERVICE} to unload agents..."
            if command -v systemctl &> /dev/null; then
                systemctl restart ${SERVICE}
            else
                service ${SERVICE} restart
            fi
        else
            echo "[Remote] No JProfiler config found. No restart needed."
        fi
    fi
EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: JProfiler detached.${NC}"
    else
        error_exit "Failed to detach JProfiler."
    fi
}