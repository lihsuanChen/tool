#!/bin/bash

# ==============================================================================
# MODULE: Build Automation (Robust Docker Wrapper)
# DESCRIPTION: Runs builds with Hot-Patching for ODA install scripts.
# ==============================================================================

# ==============================================================================
# 1. GENERIC DOCKER RUNNER
# ==============================================================================
run_ephemeral_docker_build() {
    local IMAGE_NAME=$1
    local INSTALL_PKGS=$2
    local BUILD_CMD=$3
    local ARTIFACT_PATTERN=$4
    local OUTPUT_DIR=$5
    local EXTRA_MOUNTS=$6
    local EXTRA_ENVS=$7
    local PRE_BUILD_SETUP=$8

    # --- Container Config ---
    local CONTAINER_ID="t_builder_$(date +%s)"
    local DNF_CACHE_VOL="t_dnf_cache_r8"

    # --- A. Start Container ---
    log_step "DOCKER-INIT" "Starting container (${IMAGE_NAME})..."

    docker volume create "$DNF_CACHE_VOL" > /dev/null

    if [ -z "$(docker images -q "$IMAGE_NAME" 2> /dev/null)" ]; then
        echo -e "${YELLOW}Image '$IMAGE_NAME' not found. Pulling...${NC}"
        docker pull "$IMAGE_NAME"
    fi

    # Run Detached
    docker run -d \
        --name "$CONTAINER_ID" \
        --rm \
        -v "$DNF_CACHE_VOL:/var/cache/dnf" \
        -e http_proxy="$http_proxy" \
        -e https_proxy="$https_proxy" \
        -e no_proxy="$no_proxy" \
        $EXTRA_MOUNTS \
        $EXTRA_ENVS \
        "$IMAGE_NAME" sleep infinity > /dev/null

    if [ $? -ne 0 ]; then error_exit "Failed to start Docker container."; fi

    trap "echo -e '\n${BLUE}Stopping container...${NC}'; docker rm -f $CONTAINER_ID >/dev/null" EXIT

    # --- B. Install Dependencies ---
    log_step "DOCKER-DEPS" "Installing dependencies..."
    local BASE_PKGS="rsync git tar diffutils findutils which wget sed" # Added sed explicitly

    if [[ " $INSTALL_PKGS " == *" nodejs "* ]]; then
        echo -e "${YELLOW}  -> Detected Node.js request. Enabling stream: nodejs:20...${NC}"
        docker exec "$CONTAINER_ID" dnf module enable -y nodejs:20
    fi

    docker exec "$CONTAINER_ID" bash -c "
        dnf install -y --setopt=keepcache=1 $BASE_PKGS $INSTALL_PKGS
    "
    if [ $? -ne 0 ]; then error_exit "Failed to install dependencies."; fi

    # --- C. PRE-BUILD SETUP (Hot-Patching & SDK Prep) ---
    if [ -n "$PRE_BUILD_SETUP" ]; then
        log_step "DOCKER-SETUP" "Running pre-build setup..."
        docker exec "$CONTAINER_ID" bash -c "$PRE_BUILD_SETUP"
        if [ $? -ne 0 ]; then error_exit "Pre-build setup failed."; fi
    fi

    # --- D. Sync Source Code ---
    log_step "DOCKER-SYNC" "Syncing project to /build..."
    docker exec "$CONTAINER_ID" mkdir -p /build
    docker cp . "$CONTAINER_ID":/build/

    # --- E. Fix Git Worktree ---
    docker exec -w /build "$CONTAINER_ID" bash -c "
        if [ -f .git ] && grep -q '^gitdir: /' .git; then
            rm -f .git; git init > /dev/null
        fi
        git config --global --add safe.directory /build
    "

    # --- F. Execute Build ---
    log_step "DOCKER-RUN" "Executing Build..."
    docker exec -w /build "$CONTAINER_ID" bash -c "$BUILD_CMD"

    if [ $? -ne 0 ]; then error_exit "Build command failed."; fi

    # --- G. Retrieve Artifacts ---
    if [ -n "$ARTIFACT_PATTERN" ] && [ -n "$OUTPUT_DIR" ]; then
        log_step "DOCKER-PULL" "Retrieving artifacts ($ARTIFACT_PATTERN)..."
        mkdir -p "$OUTPUT_DIR"

        local FILES
        FILES=$(docker exec "$CONTAINER_ID" find /build -type f -name "$ARTIFACT_PATTERN")

        if [ -z "$FILES" ]; then
            echo -e "${YELLOW}No artifacts found matching '$ARTIFACT_PATTERN'.${NC}"
        else
            for remote_file in $FILES; do
                docker cp "${CONTAINER_ID}:${remote_file}" "${OUTPUT_DIR}/"
            done
            echo -e "${GREEN}Artifacts saved to: ${OUTPUT_DIR}${NC}"
            ls -lh "${OUTPUT_DIR}"/* 2>/dev/null | head -n 5
        fi
    fi
}

# ==============================================================================
# 2. HELPER: DEPENDENCY CONFIGURATION
# ==============================================================================
detect_build_dependencies() {
    if [ -f "./.t-deps" ]; then cat .t-deps | tr '\n' ' '; return; fi

    local PKGS="make rpm-build epel-release gcc"
    if [ -n "$(find . -maxdepth 3 -name pom.xml -print -quit)" ]; then PKGS+=" java-11-openjdk-devel maven"; fi
    if [ -n "$(find . -maxdepth 3 -name package.json -print -quit)" ]; then PKGS+=" nodejs"; fi
    if [ -f "./configure.ac" ] || [ -f "./configure" ]; then PKGS+=" automake autoconf libtool"; fi

    # C/C++ Headers Scanning
    if grep -r -q --include="*.c" --include="*.h" "gd.h" . 2>/dev/null; then PKGS+=" gd-devel libpng-devel libjpeg-devel"; fi
    if grep -r -q --include="*.c" --include="*.h" "png.h" . 2>/dev/null; then PKGS+=" libpng-devel"; fi
    if grep -r -q --include="*.c" --include="*.h" "jpeglib.h" . 2>/dev/null; then PKGS+=" libjpeg-devel"; fi

    # CMake / C++ / ODA Detection
    if [ -d "./server/dwgproc" ] || [ -d "./dwgproc" ] || [ -n "$(find . -maxdepth 3 -name CMakeLists.txt -print -quit)" ]; then
        echo -e "  -> Detected C++/CMake project... Adding ${GREEN}cmake gcc-c++ and Graphics Libs${NC}" >&2
        PKGS+=" cmake gcc-c++ libX11-devel libXt-devel libXext-devel mesa-libGL-devel mesa-libGLU-devel"
    fi

    echo "$PKGS"
}

configure_project_specifics() {
    RET_MOUNTS=""
    RET_ENVS=""
    RET_MAKE_VARS=""
    RET_SETUP_CMD=""

    # --- ODA / DWGPROC STRATEGY ---
    if [ -d "./server/dwgproc" ] || [ -d "./dwgproc" ]; then
        echo -e "${YELLOW}Detected 'dwgproc' module (Requires ODA SDK).${NC}"

        local ODA_ROOT="/opt/oda"
        local ODA_VER="23.12"
        # Since install_package uses ${ODA_PATH}/${VERSION}, we mount to /opt/oda/23.12
        local MOUNT_TARGET="${ODA_ROOT}/${ODA_VER}"
        local LOCAL_ODA_PATH="$HOME/tmp/ODA/23_12"

        if [ ! -d "$LOCAL_ODA_PATH" ]; then
            echo -e "${RED}WARNING: ODA SDK path not found at: ${LOCAL_ODA_PATH}${NC}"
            return
        fi

        echo -e "${GREEN}Found ODA SDK at ${LOCAL_ODA_PATH}. Auto-mounting.${NC}"

        # 1. Mount directly to where install_package expects the tarballs
        RET_MOUNTS="-v ${LOCAL_ODA_PATH}:${MOUNT_TARGET}:ro"

        # 2. Patching Logic
        # We assume install_package is in server/dwgproc/ or somewhere in src
        RET_SETUP_CMD="
            echo 'Searching for install_package script to patch...'

            # Find the script named 'install_package'
            SCRIPT_PATH=\$(find . -name install_package | head -n 1)

            if [ -n \"\$SCRIPT_PATH\" ]; then
                echo \" -> Patching \$SCRIPT_PATH (Uncommenting cp command)...\"
                # Use sed to uncomment the line starting with #cp
                sed -i 's/^#cp/cp/' \"\$SCRIPT_PATH\"

                # Double check if replacement worked
                if grep -q '^cp.*OdActivationInfo' \"\$SCRIPT_PATH\"; then
                     echo \" -> Patch success!\"
                else
                     echo \" -> WARNING: Patch may have failed or line is different.\"
                fi

                # 3. Ensure OdActivationInfo is available where install_package expects it
                # The script does: cp ../OdActivationInfo ThirdParty/activation
                # So we need OdActivationInfo in the PARENT directory of install_package.

                PARENT_DIR=\$(dirname \"\$SCRIPT_PATH\")
                TARGET_LOC=\"\$PARENT_DIR/../OdActivationInfo\"

                # Check if file exists in the mounted ODA folder
                SOURCE_ACT=\"${MOUNT_TARGET}/OdActivationInfo\"

                if [ -f \"\$SOURCE_ACT\" ]; then
                    echo \" -> Copying OdActivationInfo from ODA SDK to \$TARGET_LOC...\"
                    cp \"\$SOURCE_ACT\" \"\$TARGET_LOC\"
                else
                    echo \" -> WARNING: OdActivationInfo not found in mounted SDK (\$SOURCE_ACT).\"
                    echo \"    Please ensure it exists in your source code at \$TARGET_LOC\"
                fi

            else
                echo \" -> WARNING: 'install_package' script not found. Build may fail.\"
            fi
        "

        RET_ENVS="-e ODA_PATH=${ODA_ROOT} -e ODA_VERSION=${ODA_VER}"
        RET_MAKE_VARS="ODA_PATH=${ODA_ROOT} ODA_VERSION=${ODA_VER}"
    fi
}

# ==============================================================================
# 3. TASK: RPM BUILD
# ==============================================================================
build_rpm_in_container() {
    if [ ! -f "./Makefile" ]; then error_exit "No 'Makefile' found."; fi

    # 1. Config
    local DEFAULT_VER="9.3.5"
    local DEFAULT_REL="1"
    echo -e "${YELLOW}RPM Build Configuration:${NC}"
    local BUILD_VER=$(ui_input "Enter Version" "false" "$DEFAULT_VER")
    local BUILD_REL=$(ui_input "Enter Release" "false" "$DEFAULT_REL")
    BUILD_VER="${BUILD_VER:-$DEFAULT_VER}"
    BUILD_REL="${BUILD_REL:-$DEFAULT_REL}"

    # 2. Deps
    local DEPS
    DEPS=$(detect_build_dependencies)
    echo -e "${YELLOW}Dependencies:${NC} $DEPS"

    # 3. Project Specifics
    configure_project_specifics
    # Sets: RET_MOUNTS, RET_ENVS, RET_MAKE_VARS, RET_SETUP_CMD

    # 4. Command
    local CMD="make VERSION=${BUILD_VER} RELEASE=${BUILD_REL} ${RET_MAKE_VARS} clean rpm"
    local ARTIFACTS="$HOME/tmp/rpms"

    # 5. Execute
    run_ephemeral_docker_build \
        "rockylinux:8" \
        "$DEPS" \
        "$CMD" \
        "*.rpm" \
        "$ARTIFACTS" \
        "$RET_MOUNTS" \
        "$RET_ENVS" \
        "$RET_SETUP_CMD"
}