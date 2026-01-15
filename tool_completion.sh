#!/bin/bash

# Autocomplete function for the 't' tool
_t_completion() {
    local cur prev words cword
    _init_completion || return

    local commands="deploy ssh find dnfupdate setpass rootsetup pgtrust tomcatsetup initvm viewlog logview log setlogviewer readme edit docker"

    # Check if the previous word was "docker"
    # COMP_WORDS contains the array of words
    # COMP_CWORD is the index of the current cursor

    # Handle subcommand completion for 'docker'
    # If the word BEFORE the current cursor was "docker"
    if [[ "${COMP_WORDS[COMP_CWORD-1]}" == "docker" ]]; then
         local docker_subs="install deploy db ps"
         COMPREPLY=( $(compgen -W "$docker_subs" -- "$cur") )
         return 0
    fi

    # Standard command completion (First Argument)
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
}

# The '-o default' option falls back to filename completion if no match is found
complete -F _t_completion -o default t