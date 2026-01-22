#!/bin/bash

# ================= UI INTERACTION LIBRARY =================
# Standardizes user input with 'gum' support and legacy fallbacks.
# ==========================================================

has_gum() {
    command -v gum &> /dev/null
}

# --- CONFIRMATION ---
# Usage: if ui_confirm "Proceed?"; then ...
# Returns 0 (true) for Yes, 1 (false) for No
ui_confirm() {
    local PROMPT="$1"

    if has_gum; then
        # Use Red background for critical confirmations to grab attention
        gum confirm --selected.background=196 "$PROMPT"
    else
        read -p "$PROMPT (y/N): " REPLY
        [[ "$REPLY" =~ ^[Yy]$ ]]
    fi
}

# --- INPUT (TEXT/PASSWORD) ---
# Usage: VAR=$(ui_input "Prompt Text" [masked=true|false] [placeholder])
ui_input() {
    local PROMPT="$1"
    local MASKED="${2:-false}"
    local PLACEHOLDER="${3:-}"

    if has_gum; then
        if [ "$MASKED" == "true" ]; then
            gum input --password --placeholder "$PROMPT..."
        else
            gum input --placeholder "${PLACEHOLDER:-$PROMPT...}"
        fi
    else
        # Fallback: prompt to stderr to avoid capturing prompt in variable
        if [ "$MASKED" == "true" ]; then
            read -sp "$PROMPT: " VAL >&2
            echo "" >&2
        else
            read -p "$PROMPT: " VAL >&2
        fi
        echo "$VAL"
    fi
}

# --- CHOICE ---
# Usage: VAR=$(ui_choose "Option 1" "Option 2" ...)
ui_choose() {
    local OPTIONS=("$@")

    if has_gum; then
        gum choose "${OPTIONS[@]}"
    else
        # Legacy select menu using stderr for menu display
        >&2 echo "Select Option:"
        local i=1
        for opt in "${OPTIONS[@]}"; do
            >&2 echo "  $i) $opt"
            ((i++))
        done
        read -p "Choice: " IDX >&2

        # Return the value corresponding to the index
        local REAL_IDX=$((IDX-1))
        if [ "$REAL_IDX" -ge 0 ] && [ "$REAL_IDX" -lt "${#OPTIONS[@]}" ]; then
            echo "${OPTIONS[$REAL_IDX]}"
        else
            echo ""
        fi
    fi
}

# --- FILTER (SEARCH) ---
# Usage: VAR=$(printf "%s\n" "${ARRAY[@]}" | ui_filter "Placeholder")
ui_filter() {
    local PLACEHOLDER="$1"
    local HEIGHT="${2:-10}"

    if has_gum; then
        gum filter --height "$HEIGHT" --placeholder "$PLACEHOLDER"
    else
        # Fallback: Since we can't do fuzzy search easily in pure bash,
        # we display the list and ask for manual input.
        >&2 echo "--- Available Options ---"
        cat -n >&2
        >&2 echo "-------------------------"
        read -p "Enter full path or selection: " SELECTION >&2
        echo "$SELECTION"
    fi
}