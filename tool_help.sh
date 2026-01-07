#!/bin/bash

# ================= HELP FUNCTION =================
print_help() {
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${YELLOW}               CUSTOM AUTOMATION & DEPLOYMENT TOOL (t)${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "Usage: t [COMMAND] [IP_SUFFIX] [FLAGS]"
    echo -e ""
    echo -e "${YELLOW}COMMANDS:${NC}"
    echo -e "  ${GREEN}deploy <IP>${NC}      Smart Build & Deploy (Alias: ${GREEN}td${NC})"
    echo -e "  ${GREEN}ssh <IP>${NC}         Auto-Root Login."
    echo -e "  ${GREEN}find [query]${NC}     Search your personal cheatsheet (Alias: ${GREEN}tf${NC})"
    echo -e "      * ${GREEN}tf docker${NC}    -> Searches for 'docker'"
    echo -e "      * ${GREEN}tf${NC}           -> Lists all commands"
    echo -e "      ${WHITE}(Edit $CMD_LIBRARY manually to add items)${NC}"
    echo -e ""
    echo -e "${YELLOW}ARGUMENTS & FLAGS:${NC}"
    echo -e "  ${WHITE}<IP>${NC}                 Smart IP Expansion (Default Base: ${BASE_IP}.${DEFAULT_SUBNET})"
    echo -e "      * Type ${GREEN}11${NC}      -> ${BLUE}192.168.78.11${NC}"
    echo -e ""
    echo -e "  ${WHITE}-v <version>${NC}         Specific Version Control"
    echo -e "      * ${BLUE}Client:${NC} Sets build env (e.g., -v 9.3.5)"
    echo -e "      * ${BLUE}DB:${NC}     Syncs specific folder (e.g., -v 935)"
}