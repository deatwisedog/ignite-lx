#!/bin/sh

# run_restore.sh
# 
#
# Created by Daniel Faltin on 26.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

# 
# Globals of run_restore.sh
#
PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/opt/ignite-lx/bin:/opt/ignite-lx/bin/restore"

IGX_IMAGE=""
IGX_SERVER=""
IGX_SYSCONF_NAME=""
IGX_COMMON_INCL="bin/common/ignite_common.inc"

export PATH

#
# Setup script environment and include common functions.
#
if [ -z "$IGX_BASE" ]; then
    IGX_BASE="/opt/ignite-lx"
    export IGX_BASE
fi

if [ -f "$IGX_BASE/$IGX_COMMON_INCL" ]; then
    . "$IGX_BASE/$IGX_COMMON_INCL"
    igx_setenv || igx_shell
else
    echo 1>&2 "FATAL: Cannot found major ignite functions $IGX_BASE/$IGX_COMMON_INCL, ABORT!"
    panic "Enviroment FAIL (fix and restart manual again)!"
fi

#
# Cleanup function for signal handling
#
cleanup()
{
    retval=$?
    exit $retval
}

#
# Select restore Mode
#
run_mode()
{
    igx_stdout "WELCOME TO IGNITE-LX $IGX_VERSION"
    igx_stdout "=========================================="
    igx_stdout ""
    igx_stdout "1.) Run Ignite-LX (GUI)"
    igx_stdout "2.) Run Ignite-LX (Failsave)"
    igx_stdout ""

    while true; do

        run_mode=1
        printf "Please select restore mode [default: $run_mode]: "
        read buf

        if [ -z "$buf" ]; then
            buf=$run_mode
        fi

        case "$buf" in
            1)
                run_mode=1
                break
            ;;

            2)
                run_mode=2
                break
            ;;

            *)
                igx_stderr "ERROR: Invalid entry $buf, please try again!"
            ;;
        esac

    done

    return $run_mode
}

#
# Select the configuration to restore
# Arguments: <IGX_CONFIG_DIR> ([auto] autoselect the latest, if empty user input is required)
#
failsave_select_config()
{
    dir="$1"
    auto="$2"
    failsave_idx=0
    failsave_conf=""

    for item in $(find $dir -type d -exec basename {} \;); do
        if [ $failsave_idx -gt 0 ]; then
            failsave_conf="$failsave_conf $item"
        fi
        failsave_idx=$((failsave_idx + 1))
    done

    if [ "$auto" = "auto" ]; then
        for set in $failsave_conf; do
            IGX_SYSCONF_NAME="$set"
            break
        done

        return 0
    fi

    while true; do

        igx_stdout "Please select a configuration:"
        igx_stdout "------------------------------"
        igx_stdout ""

        cnt=1
        for set in $failsave_conf; do
            igx_stdout "${cnt}.) ${set}"
            cnt=$((cnt + 1))
        done

        fs_set=1
        printf "Choose a configuration [$fs_set]: "
        read buf

        if [ -z "$buf" ]; then
            buf=$fs_set
        fi

        echo "$buf" | egrep "^[[:digit:]]{1,}$" > /dev/null
        if [ $? -ne 0 ]; then
            igx_stderr "ERROR: Invalid selection $buf (only numbers are allowed)!"
            continue
        fi

        if [ $buf -lt 1 -o $buf -ge $failsave_idx ]; then
            igx_stderr "ERROR: Invalid selection $buf!"
        else
            cnt=1
            for set in $failsave_conf; do
                if [ $cnt -eq $buf ]; then
                    IGX_SYSCONF_NAME="$set"
                    break
                fi
                cnt=$((cnt + 1))
            done
            break
        fi

    done

    return 0
}

#
# Main loop for Failsave
#
failsave_loop()
{
    failsave_select_config "$IGX_CONFIG_DIR" "auto"

    while true; do

        igx_stdout "FAILSAVE MODE - MENU"
        igx_stdout "===================="
        igx_stdout ""
        igx_stdout "1.) Ignite-LX Restore Image [$IGX_SYSCONF_NAME]"
        igx_stdout "2.) Ignite-LX Recovery Shell"
        igx_stdout "3.) Ignite-LX System Recovery (Default)"
        igx_stdout "4.) Exit (Reboot)"

        fs_select=3
        printf "Please choose [$fs_select]:"
        read buf

        if [ -z "$buf" ]; then
            buf=$fs_select
        fi

        case "$buf" in
            
            1)
                failsave_select_config "$IGX_CONFIG_DIR"
            ;;

            2)
                clear
                igx_shell
            ;;

            3)
                igx_yesno && make_restore.sh "$IGX_SYSCONF_NAME"
            ;;
            
            4)
                igx_yesno && reboot -f
            ;;

            *)
                igx_stderr "ERROR: Invalid selection $buf"
            ;;

        esac


    done
}


#
# Main loop for menu
#
menu_loop()
{

    while true; do
    
        igx_menu_start
        action=$?
        
        case $action in
        
            1)
                IGX_SYSCONF_NAME="$(igx_menu_select_config $IGX_CONFIG_DIR)"
                if [ $? -eq 0 ]; then
                    igx_menu_yesno "Start Restore now?" && make_restore.sh "$IGX_SYSCONF_NAME"
                fi
            ;;
            
            2)
                IGX_SYSCONF_NAME="$(igx_menu_select_config $IGX_CONFIG_DIR)"
                if [ $? -eq 0 ]; then
                    edit_restore.sh "$IGX_SYSCONF_NAME"
                fi

            ;;
            
            3)
                clear
                igx_shell
            ;;
            
            *)
                igx_menu_yesno "Reboot Machine?" && reboot -f
            ;;
            
        esac
        
    done

    return 0
}

#
# This function is execute if the script is called
#
main()
{
    igx_chkenv  || return 1

    if [ ! -f /tmp/run_igx_resotre.tmp ]; then
        igx_log "ABORT: It seems you want to restore on a running Operating System, ABORT!"
        return 100
    fi 

    run_mode

    case $? in

        1)
            menu_loop
        ;;

        2)
            failsave_loop
        ;;

    esac
    
    return $?    
}

#
# Execute the script by calling main()
#
main $@
exit $?
