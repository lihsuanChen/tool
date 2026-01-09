#!/bin/bash

# Autocomplete function for the 't' tool
_t_completion() {
    local cur commands
    cur="${COMP_WORDS[COMP_CWORD]}"

    # List of all subcommands supported by 't'
    # Added 'rootsetup' here so Tab knows about it
    commands="deploy ssh find dnfupdate setpass rootsetup pgtrust readme"

    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
}

complete -F _t_completion t