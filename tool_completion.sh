#!/bin/bash

# Autocomplete function for the 't' tool
_t_completion() {
    local cur prev words cword
    _init_completion || return

    # 1. Main Commands
    local commands="deploy ssh find dnfupdate setpass rootsetup pgtrust pgbackup tomcatsetup initvm jprofiler viewlog logview log setlogviewer readme edit docker rpm build"

    # 2. Context-Aware Completion
    local main_cmd="${COMP_WORDS[1]}"

    case "$main_cmd" in
        docker)
            if [[ $COMP_CWORD -eq 3 ]]; then
                 local docker_subs="install deploy db ps optimize"
                 COMPREPLY=( $(compgen -W "$docker_subs" -- "$cur") )
                 return 0
            fi
            ;;
        rpm)
            # t rpm [TAB] -> build / install
            if [[ $COMP_CWORD -eq 2 ]]; then
                 local rpm_subs="build install"
                 COMPREPLY=( $(compgen -W "$rpm_subs" -- "$cur") )
                 return 0
            fi
            ;;
        jprofiler)
            if [[ $COMP_CWORD -eq 3 ]]; then
                 local profiler_opts="off detach"
                 COMPREPLY=( $(compgen -W "$profiler_opts" -- "$cur") )
                 return 0
            fi
            ;;
    esac

    # 3. Standard Completion
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
}

complete -F _t_completion -o default t