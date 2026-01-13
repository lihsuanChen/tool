#!/bin/bash

show_readme() {
    local TOOL_DIR=$1
    local USER_TARGET=$2
    local FINAL_PATH=""

    # 1. RESOLVE TARGET
    if [ -z "$USER_TARGET" ]; then
        # Default: Tool's own README
        FINAL_PATH="$TOOL_DIR/README.md"
    else
        if [ -f "$USER_TARGET" ]; then
            # User pointed to a specific file
            FINAL_PATH="$USER_TARGET"
        elif [ -d "$USER_TARGET" ]; then
            # User pointed to a directory (e.g. ".")
            # Find any variation of README starting with r/R and containing e/E...
            # This is safer than -iname on some older 'find' versions
            local FOUND=$(find "$USER_TARGET" -maxdepth 1 -name "[rR][eE][aA][dD][mM][eE]*" | head -n 1)

            if [ -n "$FOUND" ]; then
                FINAL_PATH="$FOUND"
            else
                echo -e "\033[1;33mNo README found in: ${USER_TARGET}\033[0m"
                return 1
            fi
        else
            echo -e "\033[0;31mError: Path not found: $USER_TARGET\033[0m"
            return 1
        fi
    fi

    # 2. DISPLAY
    echo -e "\033[0;34m==================================================\033[0m"
    echo -e "  READING: \033[1;33m$FINAL_PATH\033[0m"
    echo -e "\033[0;34m==================================================\033[0m"

    if command -v glow &> /dev/null; then
        glow -p "$FINAL_PATH"
    elif command -v bat &> /dev/null; then
        bat --style=plain --language=md "$FINAL_PATH"
    elif command -v batcat &> /dev/null; then
        batcat --style=plain --language=md "$FINAL_PATH"
    else
        cat "$FINAL_PATH"
    fi
}