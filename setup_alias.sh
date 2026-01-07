#!/bin/bash

# ================= CONFIGURATION =================
TARGET_SHELL_RC="$HOME/.bashrc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_TOOL_PATH="$SCRIPT_DIR/tool_main.sh"
# =================================================

# 1. Verify the main tool exists
if [ ! -f "$MAIN_TOOL_PATH" ]; then
    echo -e "\033[0;31mERROR: Could not find tool_main.sh at: $MAIN_TOOL_PATH\033[0m"
    echo "Please ensure this setup script is in the same folder as tool_main.sh"
    exit 1
fi

# Function to safely add an alias
add_alias() {
    local NAME=$1
    local COMMAND=$2

    echo "Configuring alias '$NAME'..."

    # Check for duplicate alias in .bashrc
    if grep -q "alias $NAME=" "$TARGET_SHELL_RC"; then
        echo -e "  \033[1;33mWARNING: Alias '$NAME' already exists in .bashrc. Skipping.\033[0m"
    else
        # Explicitly wrap the entire command in single quotes
        echo "alias $NAME='$COMMAND'" >> "$TARGET_SHELL_RC"
        echo -e "  \033[0;32mSUCCESS: Alias '$NAME' added.\033[0m"
    fi
}

echo "---------------------------------------------------"
echo "Setting up Custom Automation Tool Aliases"
echo "---------------------------------------------------"

# 1. Add 't'
add_alias "t" "$MAIN_TOOL_PATH"

# 2. Add 'td'
add_alias "td" "$MAIN_TOOL_PATH deploy"

# 3. Add 'tf' (NEW: Tool Find)
add_alias "tf" "$MAIN_TOOL_PATH find"

echo "---------------------------------------------------"
echo "To use the new commands immediately, run:"
echo -e "\033[1;34msource $TARGET_SHELL_RC\033[0m"