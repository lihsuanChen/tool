#!/bin/bash

# ==============================================================================
# MODULE: Build Automation (RPM)
# DESCRIPTION: Automates RPM building inside a transient Rocky Linux 8 container.
# DEPENDENCIES: Docker
# ==============================================================================

build_rpm_in_container() {
    # --- 1. PRE-FLIGHT CHECKS ---
    # Ensure we are in a valid project root
    if [ ! -f "./Makefile" ]; then
        error_exit "No 'Makefile' found in $(pwd).\nThis command must be run from the project root."
    fi

    # Ensure Docker is running
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed or not in PATH."
    fi
    if ! docker info > /dev/null 2>&1; then
        error_exit "Docker daemon is not running."
    fi

    # --- 2. CONFIGURATION ---
    local DEFAULT_VER="9.3.5"
    local DEFAULT_REL="1"

    echo -e "${YELLOW}RPM Build Configuration:${NC}"
    local BUILD_VER=$(ui_input "Enter Version" "false" "$DEFAULT_VER")
    local BUILD_REL=$(ui_input "Enter Release" "false" "$DEFAULT_REL")

    # Apply defaults if empty
    BUILD_VER="${BUILD_VER:-$DEFAULT_VER}"
    BUILD_REL="${BUILD_REL:-$DEFAULT_REL}"

    # Container Config
    local CONTAINER_NAME="t_builder_$(date +%s)"
    local IMAGE="rockylinux:8" # Maps to docker.io/library/rockylinux:8
    local LOCAL_ARTIFACT_DIR="$HOME/tmp/rpms"

    # --- 3. START CONTAINER ---
    log_step "BUILD" "Starting Build Container (${IMAGE})..."

    # Check/Pull Image
    if [ -z "$(docker images -q $IMAGE 2> /dev/null)" ]; then
        echo -e "${YELLOW}Image '$IMAGE' not found locally. Pulling...${NC}"
        docker pull "$IMAGE"
    fi

    # Run detached, sleep infinity to keep alive
    docker run -d --name "$CONTAINER_NAME" --rm "$IMAGE" sleep infinity > /dev/null
    if [ $? -ne 0 ]; then error_exit "Failed to start container."; fi

    # Ensure cleanup on exit (trap)
    trap "echo -e '\n${BLUE}Stopping container...${NC}'; docker rm -f $CONTAINER_NAME >/dev/null" EXIT

    # --- 4. INSTALL TOOLS ---
    log_step "DEPS" "Installing Build Tools (make, rpm-build, rsync...)"

    # ADDED: libtool (required by dctrack_config rpmbuild)
    docker exec "$CONTAINER_NAME" bash -c "
        dnf install -y make rpm-build rsync gcc git tar diffutils epel-release libtool
    "
    if [ $? -ne 0 ]; then error_exit "Failed to install dependencies."; fi

    # --- 5. SYNC PROJECT ---
    log_step "SYNC" "Syncing project to container..."

    # Create build dir
    docker exec "$CONTAINER_NAME" mkdir -p /build

    # Use 'docker cp' to simulate rsyncing current folder (.) to container
    docker cp . "$CONTAINER_NAME":/build/

    # --- 6. EXECUTE MAKE ---
    log_step "MAKE" "Running: make VERSION=${BUILD_VER} RELEASE=${BUILD_REL} clean rpm"

    # ADDED: git safe.directory fix to prevent 'dubious ownership' errors
    docker exec -w /build "$CONTAINER_NAME" bash -c "
        git config --global --add safe.directory /build
        make VERSION=${BUILD_VER} RELEASE=${BUILD_REL} clean rpm
    "

    if [ $? -ne 0 ]; then
        error_exit "Build failed. Check output above."
    fi

    # --- 7. RETRIEVE ARTIFACTS ---
    log_step "RETRIEVE" "Collecting RPMs to ${LOCAL_ARTIFACT_DIR}..."
    mkdir -p "$LOCAL_ARTIFACT_DIR"

    # Find RPMs recursively in /build and copy them out
    local RPM_LIST
    RPM_LIST=$(docker exec "$CONTAINER_NAME" find /build -type f -name "*.rpm")

    if [ -z "$RPM_LIST" ]; then
        echo -e "${RED}No .rpm files found in container!${NC}"
    else
        for remote_file in $RPM_LIST; do
            local fname=$(basename "$remote_file")
            echo -e "  -> Pulling: ${fname}"
            docker cp "${CONTAINER_NAME}:${remote_file}" "${LOCAL_ARTIFACT_DIR}/"
        done
        echo -e "${GREEN}SUCCESS: RPMs saved to ${LOCAL_ARTIFACT_DIR}${NC}"
        ls -lh "${LOCAL_ARTIFACT_DIR}"/*.rpm 2>/dev/null
    fi
}