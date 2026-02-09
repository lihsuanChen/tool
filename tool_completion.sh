#!/bin/bash

# Autocomplete function for the 't' tool
_t_completion() {
    local cur prev words cword
    _init_completion || return

    # 1. Main Commands
    # ADDED: rpm build
    local commands="deploy ssh find dnfupdate setpass rootsetup pgtrust pgbackup tomcatsetup initvm jprofiler viewlog logview log setlogviewer readme edit docker rpm build"

    # 2. Context-Aware Completion
    # Check the main command (always at index 1)
    local main_cmd="${COMP_WORDS[1]}"

    case "$main_cmd" in
        docker)
            # If we are looking for the subcommand (after the IP usually)
            # t docker 105 [TAB]
            if [[ $COMP_CWORD -eq 3 ]]; then
                 local docker_subs="install deploy db ps optimize"
                 COMPREPLY=( $(compgen -W "$docker_subs" -- "$cur") )
                 return 0
            fi
            ;;
        jprofiler)
            # t jprofiler 105 [TAB]
            if [[ $COMP_CWORD -eq 3 ]]; then
                 local profiler_opts="off detach"
                 COMPREPLY=( $(compgen -W "$profiler_opts" -- "$cur") )
                 return 0
            fi
            ;;
    esac

    # 3. Standard Completion (First Argument)
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
}

# The '-o default' option falls back to filename completion if no match is found
complete -F _t_completion -o default t