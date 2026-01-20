#!/bin/bash

# ================= CONFIGURATION =================
TARGET_SHELL_RC="$HOME/.bashrc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Core Paths
MAIN_TOOL_PATH="$SCRIPT_DIR/tool_main.sh"
COMPLETION_FILE="$SCRIPT_DIR/tool_completion.sh"

# Prompt Configuration
PROMPT_DIR="$HOME/env/resource"
PROMPT_FILE="$PROMPT_DIR/tool_prompt.sh"
# =================================================

# 1. Verify the main tool exists
if [ ! -f "$MAIN_TOOL_PATH" ]; then
    echo -e "\033[0;31mERROR: Could not find tool_main.sh at: $MAIN_TOOL_PATH\033[0m"
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

if [ -f "$COMPLETION_FILE" ]; then
    chmod +x "$COMPLETION_FILE"
    if grep -q "source $COMPLETION_FILE" "$TARGET_SHELL_RC"; then
        echo -e "  \033[1;33mWARNING: Completion script already sourced. Skipping.\033[0m"
    else
        echo "source $COMPLETION_FILE" >> "$TARGET_SHELL_RC"
        echo -e "  \033[0;32mSUCCESS: Added completion sourcing.\033[0m"
    fi
else
    echo -e "  \033[0;31mERROR: tool_completion.sh not found.\033[0m"
fi

# ================= PROMPT SETUP (NEW) =================
echo ""
echo "---------------------------------------------------"
echo "3. Generating & Registering Custom Prompt"
echo "---------------------------------------------------"

# Ensure target directory exists
if [ ! -d "$PROMPT_DIR" ]; then
    echo -e "  Directory '$PROMPT_DIR' missing. Creating..."
    mkdir -p "$PROMPT_DIR"
fi

# Write the prompt logic to ~/env/resource/tool_prompt.sh
cat <<'EOF' > "$PROMPT_FILE"
#!/bin/bash

# Custom Prompt for 't' Suite Users
# Features: Exit Code Status, 256-Colors, Git Branch Integration

_set_prompt() {
  local EXIT=$?
  local STATUS=""
  local BRANCH=""

  # 1. Exit Status Indicator
  if [ $EXIT -eq 0 ]; then
    # Success: Greenish-Blue (85)
    STATUS="\[\033[38;5;85m\][$EXIT] ⚑"
  else
    # Failure: Red/Magenta (162)
    STATUS="\[\033[38;5;162m\][$EXIT] ⚑"
  fi

  # 2. Git Branch Indicator
  if command -v git &> /dev/null; then
      BRANCH=$(git branch --show-current 2>/dev/null)
      if [ -n "$BRANCH" ]; then
        BRANCH=" - $BRANCH"
      fi
  fi

  # 3. Construct PS1
  # Structure: [Reset] Status [Time Color] Time [Dir Color] (Dir Branch) [Arrow Color] ▶ [Reset]
  export PS1="\[\033[0m\]$STATUS \[\033[38;5;149m\]\t\[\033[38;5;85m\] (\W$BRANCH)\[\033[38;5;177m\] ▶\[\033[0m\] "
}

# 4. Hook into PROMPT_COMMAND (Idempotent)
# Only add if not already present to prevent infinite recursion
if [[ "$PROMPT_COMMAND" != *"_set_prompt"* ]]; then
    PROMPT_COMMAND="_set_prompt; $PROMPT_COMMAND"
fi
EOF

chmod +x "$PROMPT_FILE"
echo -e "  \033[0;32mSUCCESS: Generated $PROMPT_FILE\033[0m"

# Register in .bashrc
if grep -q "source $PROMPT_FILE" "$TARGET_SHELL_RC"; then
    echo -e "  \033[1;33mWARNING: Prompt script already sourced in .bashrc. Skipping.\033[0m"
else
    echo "source $PROMPT_FILE" >> "$TARGET_SHELL_RC"
    echo -e "  \033[0;32mSUCCESS: Added prompt sourcing to .bashrc.\033[0m"
fi

# ================= RELOAD CONFIGURATION =================
echo ""
echo "---------------------------------------------------"
echo "4. Reloading Shell Configuration"
echo "---------------------------------------------------"

source "$TARGET_SHELL_RC"

if [ $? -eq 0 ]; then
    echo -e "\033[0;32mSUCCESS: Configuration reloaded.\033[0m"
else
    echo -e "\033[0;31mWARNING: Failed to reload configuration automatically.\033[0m"
fi

echo ""
echo "---------------------------------------------------"
echo -e "\033[1;32mSETUP COMPLETE!\033[0m"