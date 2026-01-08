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

# --- SMART SYNONYM EXPANSION ---
expand_concept() {
    local word=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$word" in
        find|search|grep|locate|look|query|where) echo "find|search|grep|locate|look|query|where" ;;
        text|string|pattern|content|code|line)    echo "text|string|pattern|content|code|line" ;;
        rm|remove|delete|del|purge|clean|trash)   echo "rm|remove|delete|del|purge|clean|trash" ;;
        cp|copy|backup|duplicate|clone)           echo "cp|copy|backup|duplicate|clone" ;;
        mv|move|rename)                           echo "mv|move|rename" ;;
        dir|directory|folder|path)                echo "dir|directory|folder|path" ;;
        file|files|doc)                           echo "file|files|doc" ;;
        ls|list|show|view|display|print|check)    echo "ls|list|show|view|display|print|check" ;;
        zip|tar|compress|pack|archive)            echo "zip|tar|compress|pack|archive" ;;
        unzip|untar|extract|unpack)               echo "unzip|untar|extract|unpack" ;;
        disk|space|usage|size|du|df)              echo "disk|space|usage|size|du|df" ;;
        mem|memory|ram|swap)                      echo "mem|memory|ram|swap" ;;
        net|network|ip|port|socket|tcp|udp)       echo "net|network|ip|port|socket|tcp|udp" ;;
        kill|stop|halt|pause)                     echo "kill|stop|halt|pause" ;;
        run|start|launch|exec)                    echo "run|start|launch|exec" ;;
        *) echo "$word" ;;
    esac
}

cmd_search() {
    local RAW_INPUT=$1

    # 1. Check Library
    if [ ! -f "$CMD_LIBRARY" ]; then
        echo -e "${C_CMD}Library file not found at: $CMD_LIBRARY${C_RESET}"
        return
    fi

    # 2. Setup Limits
    # Use environment variable if set, otherwise 0 (unlimited) for strict search
    local STRICT_LIMIT=${SEARCH_LIMIT:-0}
    # For fuzzy search fallback, default to 10 if not set
    local FUZZY_LIMIT=${SEARCH_LIMIT:-10}

    # 3. Print Header
    echo -e "${C_BORDER}==================================================${C_RESET}"
    if [ -z "$RAW_INPUT" ]; then
        echo -e "  ${C_TITLE}COMMAND CHEATSHEET: ${C_HEADER}FULL LIST${C_RESET}"
        MATCHES=$(cat "$CMD_LIBRARY")
    else
        if [ -n "$SEARCH_LIMIT" ]; then
            echo -e "  ${C_TITLE}SEARCHING FOR: ${C_KEYWORD}'$RAW_INPUT'${C_RESET} ${C_WARN}(Limit: $SEARCH_LIMIT)${C_RESET}"
        else
            echo -e "  ${C_TITLE}SEARCHING FOR: ${C_KEYWORD}'$RAW_INPUT'${C_RESET}"
        fi

        # === PRE-PROCESS: Build Concept Regexes ===
        local PATTERN_LIST=""
        for word in $RAW_INPUT; do
            local EXPANDED=$(expand_concept "$word")
            if [ -z "$PATTERN_LIST" ]; then PATTERN_LIST="$EXPANDED"; else PATTERN_LIST="${PATTERN_LIST}###${EXPANDED}"; fi
        done

        # === PHASE 1: CONCEPT SEARCH (Smart AND) ===
        # We pass 'limit' variable to awk.
        # Awk counts matches and exits ONLY when the command count hits the limit.
        MATCHES=$(awk -v patterns="$PATTERN_LIST" -v limit="$STRICT_LIMIT" '
            BEGIN { n = split(patterns, regex_list, "###") }
            /^#/ { head=$0; next }
            {
                line = tolower($0); match_all = 1;
                for (i = 1; i <= n; i++) { if (line !~ regex_list[i]) { match_all = 0; break } }

                if (match_all) {
                    if (head) print head;
                    print $0;
                    head=""

                    # Count matches and enforce limit
                    count++
                    if (limit > 0 && count >= limit) exit
                }
            }
        ' "$CMD_LIBRARY")

        # === PHASE 2: BEST MATCH (Scoring) ===
        if [ -z "$MATCHES" ]; then
            echo -e "${C_BORDER}--------------------------------------------------${C_RESET}"
            echo -e "  ${C_WARN}! No exact matches. Showing top $FUZZY_LIMIT concept matches:${C_RESET}"

            MATCHES=$(awk -v patterns="$PATTERN_LIST" '
                BEGIN { n = split(patterns, regex_list, "###") }
                /^#/ { head=$0; next }
                {
                    line = tolower($0); score = 0;
                    for (i = 1; i <= n; i++) { if (line ~ regex_list[i]) score++ }
                    if (score > 0) { print score "@@@" head "@@@" $0 }
                }
            ' "$CMD_LIBRARY" | sort -rn -t"@" -k1 | head -n "$FUZZY_LIMIT" | awk -F"@@@" '{
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

    # 4. Parse and Print
    echo "$MATCHES" | while IFS='|' read -r desc cmd; do
        desc=$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ "$desc" == \#* ]]; then
            CLEAN_HEADER="${desc//# /}"
            echo -e "\n${C_HEADER}=== ${CLEAN_HEADER} ===${C_RESET}"
            continue
        fi

        if [ -n "$desc" ] && [ -n "$cmd" ]; then
            echo -e "${C_DESC}${desc}${C_RESET}"
            echo -e "  ${C_CMD}> ${cmd}${C_RESET}"
        fi
    done
    echo ""
}