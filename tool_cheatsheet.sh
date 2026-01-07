#!/bin/bash

# ================= COLOR PALETTE =================
C_HEADER='\033[1;35m'   # Bold Magenta (Sections)
C_DESC='\033[1;36m'     # Bold Cyan (Descriptions)
C_CMD='\033[0;33m'      # Yellow (Commands)
C_RESET='\033[0m'       # Reset
C_BORDER='\033[0;34m'   # Blue (Borders)
C_TITLE='\033[0;36m'    # Cyan (Title)
C_KEYWORD='\033[1;31m'  # Bold Red (Search Term)
C_WARN='\033[1;33m'     # Bold Yellow (Warning)
# =================================================

cmd_search() {
    local RAW_INPUT=$1

    # 1. Check Library
    if [ ! -f "$CMD_LIBRARY" ]; then
        echo -e "${C_CMD}Library file not found at: $CMD_LIBRARY${C_RESET}"
        return
    fi

    # 2. Print Header
    echo -e "${C_BORDER}==================================================${C_RESET}"
    if [ -z "$RAW_INPUT" ]; then
        echo -e "  ${C_TITLE}COMMAND CHEATSHEET: ${C_HEADER}FULL LIST${C_RESET}"
        MATCHES=$(cat "$CMD_LIBRARY")
    else
        echo -e "  ${C_TITLE}SEARCHING FOR: ${C_KEYWORD}'$RAW_INPUT'${C_RESET}"

        # === PHASE 1: STRICT SEARCH (AND) ===
        # We use awk to check if ALL words in input exist in the line
        # It also tracks the current section header

        # Convert input "find the file" -> "find" "the" "file"
        MATCHES=$(awk -v query="$RAW_INPUT" '
            BEGIN {
                split(tolower(query), words, " "); # Split query into array
            }
            /^#/ { head=$0; printed=0; next }      # Store header, don not print yet
            {
                line = tolower($0);
                all_found = 1;
                for (i in words) {
                    if (index(line, words[i]) == 0) { all_found = 0; break; }
                }
                if (all_found) {
                    if (head && !printed) { print head; printed=1 }
                    print $0
                }
            }
        ' "$CMD_LIBRARY")

        # === PHASE 2: FALLBACK TO PARTIAL (OR) ===
        if [ -z "$MATCHES" ]; then
            echo -e "${C_BORDER}--------------------------------------------------${C_RESET}"
            echo -e "  ${C_WARN}! No exact matches. Showing partials:${C_RESET}"

            # Regex for OR logic: "find the docker" -> "find|the|docker"
            OR_REGEX=$(echo "$RAW_INPUT" | tr -s ' ' '|' | tr '[:upper:]' '[:lower:]')

            MATCHES=$(awk -v regex="$OR_REGEX" '
                /^#/ { head=$0; printed=0; next }
                tolower($0) ~ regex {
                    if (head && !printed) { print head; printed=1 }
                    print $0
                }
            ' "$CMD_LIBRARY")
        fi
    fi
    echo -e "${C_BORDER}==================================================${C_RESET}"

    if [ -z "$MATCHES" ]; then
        echo -e "${C_KEYWORD}No matches found.${C_RESET}"
        return
    fi

    # 3. Parse and Print
    echo "$MATCHES" | while IFS='|' read -r desc cmd; do
        desc=$(echo "$desc" | xargs)
        cmd=$(echo "$cmd" | xargs)

        # Handle Headers (Lines starting with #)
        if [[ "$desc" == \#* ]]; then
            CLEAN_HEADER="${desc//# /}"
            echo -e "\n${C_HEADER}=== ${CLEAN_HEADER} ===${C_RESET}"
            continue
        fi

        # Handle Commands
        if [ -n "$desc" ] && [ -n "$cmd" ]; then
            echo -e "${C_DESC}${desc}${C_RESET}"
            echo -e "  ${C_CMD}> ${cmd}${C_RESET}"
            echo ""
        fi
    done
}