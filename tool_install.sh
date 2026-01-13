#!/bin/bash

# ================= CONFIGURATION =================
TARGET_SHELL_RC="$HOME/.bashrc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_TOOL_PATH="$SCRIPT_DIR/tool_main.sh"
COMPLETION_FILE="$SCRIPT_DIR/tool_completion.sh"
# =================================================

# 1. Verify the main tool exists
if [ ! -f "$MAIN_TOOL_PATH" ]; then
    echo -e "\033[0;31mERROR: Could not find tool_main.sh at: $MAIN_TOOL_PATH\033[0m"
    exit 1
fi

# 2. Verify the completion file exists
if [ ! -f "$COMPLETION_FILE" ]; then
    echo -e "\033[0;31mERROR: Could not find tool_completion.sh at: $COMPLETION_FILE\033[0m"
    exit 1
fi

# ================= ALIAS SETUP =================
add_alias() {
    local NAME=$1
    local COMMAND=$2
    echo "Configuring alias '$NAME'..."
    if grep -q "alias $NAME=" "$TARGET_SHELL_RC"; then
        echo -e "  \033[1;33mWARNING: Alias '$NAME' already exists in .bashrc. Skipping.\033[0m"
    else
        echo "alias $NAME='$COMMAND'" >> "$TARGET_SHELL_RC"
        echo -e "  \033[0;32mSUCCESS: Alias '$NAME' added.\033[0m"
    fi
}

echo "---------------------------------------------------"
echo "1. Setting up Custom Automation Tool Aliases"
echo "---------------------------------------------------"
add_alias "t" "$MAIN_TOOL_PATH"
add_alias "td" "$MAIN_TOOL_PATH deploy"
add_alias "tf" "$MAIN_TOOL_PATH find"
add_alias "te" "$MAIN_TOOL_PATH edit"

# ================= COMPLETION SETUP =================
echo ""
echo "---------------------------------------------------"
echo "2. Setting up Bash Autocompletion"
echo "---------------------------------------------------"

# Ensure the script is executable
chmod +x "$COMPLETION_FILE"

# Register in .bashrc if not already there
if grep -q "source $COMPLETION_FILE" "$TARGET_SHELL_RC"; then
    echo -e "  \033[1;33mWARNING: Completion script already sourced in .bashrc. Skipping.\033[0m"
else
    echo "source $COMPLETION_FILE" >> "$TARGET_SHELL_RC"
    echo -e "  \033[0;32mSUCCESS: Added completion sourcing to .bashrc.\033[0m"
fi

# ================= RELOAD CONFIGURATION =================
echo ""
echo "---------------------------------------------------"
echo "3. Reloading Shell Configuration"
echo "---------------------------------------------------"

# This reloads the config for the CURRENT window only
source "$TARGET_SHELL_RC"

if [ $? -eq 0 ]; then
    echo -e "\033[0;32mSUCCESS: Configuration reloaded.\033[0m"
else
    echo -e "\033[0;31mWARNING: Failed to reload configuration automatically.\033[0m"
fi

echo ""
echo "---------------------------------------------------"
echo -e "\033[1;32mSETUP COMPLETE!\033[0m"