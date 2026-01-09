#!/bin/bash

# Function to handle README display and viewer installation
show_readme() {
    local BASE_DIR=$1
    local README_PATH="$BASE_DIR/README.md"

    if [ ! -f "$README_PATH" ]; then
        echo -e "${RED}Error: README.md not found at $README_PATH${NC}"
        exit 1
    fi

    # ================= 1. AUTO-INSTALL LOGIC =================
    # If 'glow' is missing, offer to install it
    if ! command -v glow &> /dev/null; then
        echo -e "${YELLOW}Better Reader 'glow' is missing.${NC}"
        read -p "Auto-install 'glow' now? (y/N): " INSTALL_CONFIRM

        if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Installing Glow... (Sudo password may be required)${NC}"

            if command -v apt &> /dev/null; then
                # Debian/Ubuntu Installation
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
                sudo apt update && sudo apt install -y glow

            elif command -v dnf &> /dev/null; then
                # RHEL/Fedora Installation
                echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
                sudo dnf install -y glow

            else
                echo -e "${RED}Could not detect apt or dnf. Skipping install.${NC}"
            fi
            echo ""
        fi
    fi

    # ================= 2. VIEWING LOGIC =================
    if command -v glow &> /dev/null; then
        # BEST: Render Markdown like a webpage
        glow -p "$README_PATH"

    elif command -v bat &> /dev/null; then
        # GOOD: Syntax Highlighting
        bat --style=plain --language=md "$README_PATH"

    elif command -v batcat &> /dev/null; then
        # GOOD: Ubuntu sometimes calls it 'batcat'
        batcat --style=plain --language=md "$README_PATH"

    else
        # FALLBACK: Standard text
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}  DISPLAYING README: $README_PATH${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}(Tip: Install 'glow' or 'bat' for a better reading experience)${NC}"
        echo ""
        cat "$README_PATH"
    fi
}