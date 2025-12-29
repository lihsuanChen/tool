#!/bin/bash

# ================= CONFIGURATION =================
ALIAS_NAME="t"  # Changed from 'tool' to 't'
TARGET_SHELL_RC="$HOME/.bashrc"
# Get the absolute path of the directory where THIS script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_TOOL_PATH="$SCRIPT_DIR/tool_main.sh"
# =================================================

echo "Setting up alias '$ALIAS_NAME'..."

# 1. Verify the main tool exists
if [ ! -f "$MAIN_TOOL_PATH" ]; then
    echo -e "\033[0;31mERROR: Could not find tool_main.sh at: $MAIN_TOOL_PATH\033[0m"
    echo "Please ensure this setup script is in the same folder as tool_main.sh"
    exit 1
fi

# 2. Check for duplicate alias in .bashrc
if grep -q "alias $ALIAS_NAME=" "$TARGET_SHELL_RC"; then
    echo -e "\033[1;33mWARNING: The alias '$ALIAS_NAME' is already defined in $TARGET_SHELL_RC.\033[0m"
    echo "No changes were made to avoid duplicates."
    echo "Current entry:"
    grep "alias $ALIAS_NAME=" "$TARGET_SHELL_RC"
    exit 0
fi

# 3. Append the alias if not found
echo "" >> "$TARGET_SHELL_RC"
echo "# Custom Automation Tool Alias" >> "$TARGET_SHELL_RC"
echo "alias $ALIAS_NAME='$MAIN_TOOL_PATH'" >> "$TARGET_SHELL_RC"

echo -e "\033[0;32mSUCCESS: Alias '$ALIAS_NAME' added to $TARGET_SHELL_RC\033[0m"
echo "---------------------------------------------------"
echo "To use the new command immediately, run this command:"
echo -e "\033[1;34msource $TARGET_SHELL_RC\033[0m"