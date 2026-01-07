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
        # For full list, just cat the file
        MATCHES=$(cat "$CMD_LIBRARY")
    else
        echo -e "  ${C_TITLE}SEARCHING FOR: ${C_KEYWORD}'$RAW_INPUT'${C_RESET}"

        # === PHASE 1: STRICT SEARCH (AND) ===
        # Check if there are exact matches containing ALL words
        MATCHES=$(awk -v query="$RAW_INPUT" '
            BEGIN { split(tolower(query), words, " ") }
            /^#/ { head=$0; next }
            {
                line = tolower($0); all_found = 1;
                for (i in words) {
                    if (index(line, words[i]) == 0) { all_found = 0; break; }
                }
                if (all_found) {
                    if (head) print head;
                    print $0; head="" # Clear head so we do not duplicate it
                }
            }
        ' "$CMD_LIBRARY")

        # === PHASE 2: BEST MATCH (SCORING) ===
        if [ -z "$MATCHES" ]; then
            echo -e "${C_BORDER}--------------------------------------------------${C_RESET}"
            echo -e "  ${C_WARN}! No exact matches. Showing top 10 best matches:${C_RESET}"

            # 1. Score each line based on keyword hits
            # 2. Sort by Score (Desc) -> Header (Asc)
            # 3. Take Top 10
            # 4. Strip the score prefix to prep for display

            MATCHES=$(awk -v query="$RAW_INPUT" '
                BEGIN { split(tolower(query), words, " ") }
                /^#/ { head=$0; next }
                {
                    line = tolower($0)
                    score = 0
                    for (i in words) {
                        if (index(line, words[i]) > 0) score++
                    }
                    if (score > 0) {
                        # Output: Score @@@ Header @@@ Line content
                        print score "@@@" head "@@@" $0
                    }
                }
            ' "$CMD_LIBRARY" | sort -rn -t"@" -k1 | head -n 10 | awk -F"@@@" '{
                # Reconstruct output: Header \n Line
                # Only print header if it is different from the last one we printed
                if ($2 != last_head) { print $2; last_head=$2 }
                print $3
            }')
        fi
    fi
    echo -e "${C_BORDER}==================================================${C_RESET}"

    if [ -z "$MATCHES" ]; then
        echo -e "${C_KEYWORD}No matches found.${C_RESET}"
        return
    fi

    # 3. Parse and Print Loop
    # We use a temp file or process substitution to handle the reading
    echo "$MATCHES" | while IFS='|' read -r desc cmd; do
        desc=$(echo "$desc" | xargs)
        cmd=$(echo "$cmd" | xargs)

        # Handle Headers
        if [[ "$desc" == \#* ]]; then
            CLEAN_HEADER="${desc//# /}"
            echo -e "\n${C_HEADER}=== ${CLEAN_HEADER} ===${C_RESET}"
            continue
        fi

        # Handle Commands
        if [ -n "$desc" ] && [ -n "$cmd" ]; then
            echo -e "${C_DESC}${desc}${C_RESET}"
            echo -e "  ${C_CMD}> ${cmd}${C_RESET}"
        fi
    done
    echo ""
}