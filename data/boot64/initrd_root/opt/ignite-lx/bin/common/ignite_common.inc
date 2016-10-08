# ignite_common.inc
# 
#
# Created by Daniel Faltin on 14.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

#
# Globals
#
IGX_VERSION="IGNITE-LX VERSION 0.5"
IGX_VERBOSE=0
IGX_LOG="ignite_$(uname -n).log"

#
# Setup the Ignite-LX environment
# 
igx_setenv()
{
    if [ -z "$IGX_BASE" ]; then
        IGX_BASE="/opt/ignite-lx"
        export IGX_BASE
    fi
    
    if [ ! -f "$IGX_BASE/etc/ignite.conf" ]; then
        igx_stderr "ERROR: Cannot find/access $IGX_BASE/etc/ignite.conf, please check environment variable \$IGX_BASE"
        return 1
    else
        . $IGX_BASE/etc/ignite.conf
        export IGX_BASE
        export IGX_BIN_DIR
        export IGX_COMMON_DIR
        export IGX_LOG_DIR
        export IGX_BOOT64_DIR
        export IGX_CONFIG_DIR
        export IGX_MAX_IMAGES
    fi
    
    for dir in "$IGX_BASE" "$IGX_BIN_DIR" "$IGX_COMMON_DIR" "$IGX_LOG_DIR" "$IGX_BOOT64_DIR"; do
               
        if [ ! -d "$dir" ]; then
            igx_stderr "ERROR: Cannot find mandatory directory $dir, ABORT!"
            return 2
        fi
        
    done
    
    PATH=$PATH:/sbin:/usr/sbin:$IGX_BIN_DIR
    export PATH
    
    return 0
}

#
# Print defined string to stderr
#
igx_stderr()
{
    echo 1>&2 "$@"
}

#
# Print defined string to stderr
#
igx_stdout()
{
    echo "$@"
}

#
# Function try to resolve the given hostname and print the ip to stdout.
# Arguments: hostname
# Return 0 on success otherwise a value greater 0
#
igx_gethostbyname()
{
    to_resolv="$@"
    
    if [ -z "$to_resolv" ]; then
        igx_log "ERROR: igx_gethostbyname() Missing function argument, ABORT!"
        return 1
    fi
    
    echo "$to_resolv" | egrep '^[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}$' > /dev/null
    if [ $? -eq 0 ]; then
        echo "$to_resolv"
        return 0
    fi
    
    host -4 -t A "$to_resolv" 2> /dev/null | awk 'BEGIN { retval = 1; } 
    { 
        if($0 ~ /has address/) { 
            print $NF; 
            retval = 0; 
            exit(retval); 
        } 
    } END { exit(retval); }'
    res_ret=$?
    
    if [ $res_ret -ne 0 ]; then
        igx_verbose "WARNING: Cannot resolv IP4Addr of $to_resolv!"
        echo "$to_resolv"
    fi
    
    return $?
}

#
# Print argument string or stuff from stdin to stderr and into logfile ($IGX_LOG)
#
igx_log()
{
    retval=$?
    log_string="$@"
    
    if [ ! -z "$log_string" ]; then
        igx_stderr "$log_string"
        echo "$log_string" >> $IGX_LOG_DIR/$IGX_LOG
    else
        while read log_string; do
            igx_stderr "$log_string"
            echo "$log_string" >> $IGX_LOG_DIR/$IGX_LOG
        done
    fi
    
    return $retval
}

#
# Simply retun the default Ignite-LX date string
#
igx_date()
{
    date "+%Y-%m-%d_%H:%M:%S"
}

#
# Check the source and if exists the function creates a symbolic link
# Arguments: src dst
#
igx_symlink()
{
    src_obj="$1"
    dst_obj="$2"
    
    if [ -z "$src_obj" -o -z "$dst_obj" ]; then
        igx_verbose "ERROR: igx_symlink() Missing function arguments, ABORT!"
        return 1
    fi
    
    if [ "$src_obj" = "$dst_obj" ]; then
        igx_log "ERROR: Cannot SymLink $src_obj, source and target is the same, ABORT!"
        return 2
    fi

    if [ "$(basename $src_obj)" = "$(basename $dst_obj)" ]; then
        if [ -d "$dst_obj" -o -f "$dst_obj" ]; then
            igx_log "ERROR: The target $dst_obj already exists and is not a file or directory, ABORT!"
            return 3
        fi
        if [ -h "$dst_obj" ]; then
            igx_verbose "The target symbolic link $dst_obj already exists and will replaced!"
            rm -f "$dst_obj"
        fi
    fi

    if [ ! -d "$(dirname $dst_obj)" ]; then
        igx_log "ERROR: Target directory for SymLink $dst_obj does not exists, ABORT!"
        return 4
    fi

    ln -s "$src_obj" "$dst_obj" 2> /dev/null
    if [ $? -ne 0 ]; then
        igx_log "ERROR: SymLink of $src_obj to $dst_obj failed, ABORT!"
        return 5
    else
        igx_verbose "SymLink of $src_obj to $dst_obj successful!"
    fi

    return 0
}

#
# Check and validate item to copy for sense and perform the activity.
# Attention function does force the deletion of target also if an error occur
# Agruments: src dst
#
igx_copy()
{
    src_obj="$1"
    dst_obj="$2"
    is_dir=0
    do_copy=0
    
    if [ -z "$src_obj" -o -z "$dst_obj" ]; then
        igx_verbose "ERROR: igx_copy() Missing function arguments, ABORT!"
        return 1
    fi
    
    if [ "$src_obj" = "$dst_obj" ]; then
        igx_log "ERROR: Cannot copy $src_obj, source and target is the same, ABORT!"
        return 2
    fi
    
    if [ "$(basename $src_obj)" = "$(basename $dst_obj)" ]; then
        if [ -d "$dst_obj" -o -f "$dst_obj" ]; then
            igx_verbose "The target $dst_obj allready exists and will be deleted."
            rm -rf "$dst_obj"
        fi
    fi
    
    test -d "$src_obj" && is_dir=1
    test -f "$src_obj" && do_copy=1
    
    if [ $is_dir -eq 1 ]; then
        for x in "$src_obj"/*; do
            test -f "$x" && do_copy=1 && break
            test -d "$x" && do_copy=1 && break
        done
    fi
        
    if [ $do_copy -eq 0 ]; then
        igx_verbose "Source $src_obj not marked for copy, no copy required!"
        return 0
    fi
        
    if [ ! -d "$(dirname $dst_obj)" ]; then
        igx_verbose "ERROR: Target directory $(dirname $dst_obj) does not exists, ABORT!"
        return 3
    fi
    
    cp -Rp "$src_obj" "$dst_obj"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Copy of $src_obj to $dst_obj failed, ABORT!"
        return 4
    else
        igx_verbose "Copy of $src_obj to $dst_obj successful!"
    fi
    
    return 0
}

#
# Function check for a valid IPv4 network address
# Arguments: IPv4addr
# Return 0 if address is valid otherwise 1
#
igx_is_ip()
{
    ip_addr="$@"
    
    if [ -z "$ip_addr" ]; then
        igx_log "ERROR: igx_is_ip() missing function argument!"
    fi
    
    digits="$(echo $ip_addr | awk -F '.' '{ for(i = 1; i <= NF; i++) printf("%s ", $i); exit(NF); }')"
    if [ $? -ne 4 ]; then
        return 1
    fi
    
    ip_chk=0
    for oct in $digits; do
        echo $oct | egrep '^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-5][0-5])$' > /dev/null || ip_chk=1
    done
    
    return $ip_chk
}

#
# Print out the abosolut path of directory or file!
# Return zero on success otherwise a non zero value
#
igx_dirname()
{
    dir_ret=0
    dir_path=""
    file_path="$@"
    
    if [ -z "$file_path" ]; then
        igx_stderr "igx_dirname() missing function argument"
        return 1
    fi

    if [ -d "$file_path" ]; then
        cd 2> /dev/null "$file_path"
        dir_ret=$?
        dir_path="$file_path"
    else
        cd 2>  /dev/null "$(dirname $file_path)"
        dir_ret=$?
        dir_path="$(dirname $file_path)"
    fi

    if [ $dir_ret -ne 0 ]; then
        igx_stderr "ERROR: Directory $dir_path does not exists!"
        return 2
    fi

    echo "$PWD"
    cd "$OLDPWD"

    return 0
}

#
# Function return the first "image config id"
# Arguments: <full path to config base directory>
# Return Value is the next first number, on error 0 is returned
#
igx_get_first_imgid()
{
    conf_dir="$1"
    
    if [ ! -d "$conf_dir" ]; then
        igx_log "ERROR: Cannot open/access directory $conf_dir where the system image informations are located, ABORT!"
        return 0
    fi
        
    first=$(for conf_id in $conf_dir/*/set.id; do test -f $conf_id && cat $conf_id; done | sort -nr | tail -1)
    
    if [ -z "$first" ]; then
        return 0
    fi
    
    return $first    
}

#
# Function return the next free "image config id"
# Arguments: <full path to config base directory>
# Return Value is the next free number, on error 0 is returned
#
igx_get_imgid()
{
    conf_dir="$1"
    
    if [ ! -d "$conf_dir" ]; then
        igx_log "ERROR: Cannot open/access directory $conf_dir where the system image informations are located, ABORT!"
        return 0
    fi
        
    next=$(for conf_id in $conf_dir/*/set.id; do test -f $conf_id && cat $conf_id; done | sort -n | tail -1)
    
    if [ -z "$next" ]; then
        return 1
    fi
    
    return $((next + 1))    
}

#
# Function set the next free "image config id" in $conf_dir/config_id
# Arguments: <full path to system config directory>
# Return Value is the next free number, on error 0 is returned
#
igx_set_imgid()
{
    confsys_dir="$1"
    
    if [ ! -d "$confsys_dir" ]; then
        igx_log "ERROR: Cannot open/access directory $conf_dir where the system image informations are located, ABORT!"
        return 0
    fi
    
    igx_get_imgid $(dirname $confsys_dir)
    setn=$?
    
    echo "$setn" > "$confsys_dir/set.id"
    
    return $setn    
}

#
# Check if required environment contains all Tools
#
igx_chkenv()
{
    TOOLS="cpio find file id dd cat echo printf awk sed gzip date"
    
    if [ ! -f /tmp/run_igx_resotre.tmp ]; then
        TOOLS="$TOOLS ip ifconfig route host"
    else
        TOOLS="cpio poweroff nfsmount mount"
    fi
    
    IFS_OLD="$IFS"
    
    found=0
    
    for bin in $TOOLS; do
        IFS=":"
        for dir in $PATH; do
            test -x $dir/$bin && found=1
        done
        IFS="$IFS_OLD"
        if [ $found -eq 0 ]; then
            igx_stderr "FATAL: Cannot find/execute program $bin, please check that it is installed and in \$PATH, ABORT!"
            return 1
        else
            found=0
        fi
    done
    
    if [ "`id -u`" != "0" ]; then
        igx_stderr "ERROR: Insufficient permissions, run this script as root. ABORT!"
        return 2
    fi
    
    if [ ! -f /proc/mounts ]; then
        igx_stderr "ERROR: Cannot access /proc/mounts, seems that proc is not available, ABORT!"
        return 3
    fi
    
    return 0
}

#
# If argument is a valid Volume Group zero is returned.
#
igx_is_vg()
{
    if [ -z "$1" ]; then
        igx_stderr "ERROR: Unable to check for valid Volume Group, function argument missing!"
        return 2
    fi
    
    vg_prefix="/dev/mapper/`basename $1`"

    test -b "$vg_prefix" && return 0
        
    for lv in ${vg_prefix}*; do
        test -b "$lv" && return 0
    done
    
    return 1
}

#
# If argument is a valid disk device zero is returned.
#
igx_is_disk()
{
    if [ -z "$1" ]; then
        igx_stderr "ERROR: Unable to check for valid Volume Group, function argument missing!"
        return 2
    fi

    test -b "$1" && return 0
    
    for dev in /dev /dev/mapper; do
        test -b "$dev/`basename $1`" && return 0
    done
    
    return 1
}

#
# If IGX_VERBOSE is true the string as argument is written to stdout.
#
igx_verbose()
{
    if [ $IGX_VERBOSE -eq 1 ]; then
        igx_log "verbose: $@"
    fi
    
    return 0
}

#
# Resolve all block devices and return the full path
#
igx_resolve_devices() 
{
    if [ -z "$1" ]; then
        igx_stderr "ERROR: Unable resolve devices, function argument missing!"
        return 2
    fi
    
    for dev in $@; do
        test -b $dev && echo $dev && continue
        dev_base="`basename $dev`"
        
        for dir in /dev /dev/mapper; do
            test -b "$dir/$dev_base" && echo $dir/$dev_base && break
        done
        
        for lv in /dev/mapper/${dev_base}*; do
            test -b "$lv" && echo $lv
        done
    done

    return 0
}

#
# Simply print a yes/no request
# Return: 0 (yes) or 1 (no)
#
igx_yesno()
{
    yesno_ret=1

    while true; do 

        yesno="n"
        printf "Are you sure [$yesno]?: "
        read buf
        
        if [ -z "$buf" ]; then
            buf="$yesno"
        fi

        case "$buf" in
            yes|y)
                yesno_ret=0
                break
            ;;

            no|n)
                yesno_ret=1
                break
            ;;

            *)
                igx_stderr "ERROR: Invalid entry, please enter \"yes\" or \"no\"!"
            ;;
        esac

    done

    return $yesno_ret
}

#
# Function start shell
#
igx_shell()
{
    if [ -x /sbin/usplash_write ]; then
        /sbin/usplash_write "QUIT"
    fi
    
    modprobe i8042 2> /dev/null
    modprobe atkbd 2> /dev/null

    cd /
    PS1='(IGNITE-LX SHELL)# ' /bin/sh -i </dev/console >/dev/console 2>&1
    
    return $?
}

#
# Use dialog to gen. a start menu.
# Return: 1 default, 2 advanced, 3 shell otherwise 0
#
igx_menu_start()
{
    tmp_out="/tmp/select"

    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Select your action" \
                --cancel-label "PowerOff" \
                --menu "Choose one of the menu points" 10 50 8 \
                        1 "Ignite-LX System Recovery (Default)" \
                        2 "Ignite-LX System Recovery (Advanced)" \
                        3 "Ignite-LX Recovery Shell" > $tmp_out

    item="$(cat $tmp_out)"
    rm -f $tmp_out

    if [ -z "$item" ]; then
        return 0
    fi
    
    return $item
}

#
# Use dialog to gen. a the advanced edit menu
# Return: Value 1 - 5 for menus, otherwise 0 (for back)
#
igx_menu_advance()
{
    tmp_out="/tmp/select"

    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit Restore Informations" \
                --cancel-label "Back" \
                --menu "Choose one of the menu points" 12 50 8 \
                        1 "Edit Network Settings" \
                        2 "Edit Disk Settings" \
                        3 "Edit LVM Settings" \
                        4 "Edit Raid (md) Settings" \
                        5 "Run Recovery" > $tmp_out

    item="$(cat $tmp_out)"
    rm -f $tmp_out

    if [ -z "$item" ]; then
        return 0
    fi
    
    return $item
}

#
# Simply display YES/NO DIALOG with defined message as argument
#
igx_menu_yesno()
{
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Select yes/no" \
                --yesno "$@" 5 30
                
    return $?
}

#
# Simply display MSG DIALOG with defined message as argument
#
igx_menu_errmsg()
{
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "A ERROR IS OCCURRED" \
                --msgbox "$@" 5 33

    return $?
}

#
# Use dialog to gen. a select configuration menu
# Arguments: <IGX_CONFIG_DIR>
# Return: As string the selected item
#
igx_menu_select_config()
{
    dir="$1"
    tmp_out="/tmp/select"
    
    if [ -z "$dir" ]; then
        igx_log "ERROR: Cannot generate menu, directory for config select is missing as function argument!"
        return 1
    fi 

    cnt=0
    for item in $(find $dir -type d -exec basename {} \;); do
        if [ $cnt -gt 0 ]; then
            menuitems="$menuitems $cnt $item"
        fi
        cnt=$((cnt + 1))
    done

    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Select a Backup for Restore" \
                --menu "Choose one of the menu points" 16 50 8 $menuitems > $tmp_out

    flag=0
    for item in $menuitems; do
        if [ $flag -eq 1 ]; then
            echo "$item"
            break
        fi

        if [ "$item" = "$(cat $tmp_out)" ]; then
            flag=1
        fi
    done

    rm -f $tmp_out
    menuitems=""
    
    if [ $flag -eq 0 ]; then
        return 1
    fi

    return 0
}

#
# Init the backup backend for usage
# Arguments <backend name> </path/imagename>
# Return: 0 on success, 100 if no backend is used, all other is treated as error
#
igx_init_backup_backend()
{
    IMAGE_NAME="$2"
    BACKEND_NAME="$1"
    BACKEND_DIR="$IGX_BIN_DIR/backup/backends"
    
    if [ -z "$BACKEND_NAME" -o $# -ne 2 ]; then
        igx_verbose "No backup backend defined, normal mode is used for image creation"
        return 100
    fi
    
    igx_verbose "Trying to find backup backend \"$BACKEND_NAME\" ..."
    
    if [ ! -d $BACKEND_DIR ]; then
        igx_log "ERROR: Cannot open/access backend directory $BACKEND_DIR, ABORT!"
        return 1
    fi
    
    backend_found=0
    for backend in $BACKEND_DIR/*; do
        if [ ! -r "$backend" ]; then
            igx_log "ERROR: Cannot read/access backend $backend, ABORT!"
            return 2
        fi
        igx_verbose "Loading backend $backend ..."
        . "$backend"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Load of backend $backend failure, ABORT!"
            return 3
        fi
        if [ "$(igx_backup_backend_name)" = "${BACKEND_NAME}.mod" ]; then
            backend_found=1
            break
        else
            igx_verbose "Backend $backend ignored and will unloaded."
        fi
    done
    
    if [ $backend_found -eq 0 ]; then
        igx_log "ERROR: Cannot find backend $BACKEND_NAME for backup usage, ABORT!"
        return 4
    fi
    
    igx_verbose "Backend $BACKEND_NAME successfuly loaded."
    igx_verbose "Initialize backend $BACKEND_NAME, running init()"
    
    igx_backup_backend_init "$IMAGE_NAME"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot initialize backend $BACKEND_NAME, ABORT!"
        return 5
    fi
    
    igx_verbose "Backend $BACKEND_NAME successfuly initialized!"
    igx_verbose "Trying to bind backend $BACKEND_NAME resource ... "
    
    igx_backup_backend_bind "$IMAGE_NAME"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot bind backend $BACKEND_NAME resource, ABORT!"
        return 6
    fi
    
    igx_verbose "Backend $BACKEND_NAME resource successfuly binded."
    
    return 0
}

#
# Function finish the usage of backup backend $IGX_BACKEND
# Arguments <backend name> </path/imagename>
# Return: 0 on success, 100 if no backend is used, all other is treated as error
#
igx_end_backup_backend()
{
    IMAGE_NAME="$2"
    BACKEND_NAME="$1"

    if [ -z "$BACKEND_NAME" -o $# -ne 2 ]; then
        igx_verbose "No backup backend defined, no end() function is called"
        return 100
    fi
    
    igx_verbose "Finishing usage of backend $BACKEND_NAME."

    igx_backup_backend_end "$IMAGE_NAME"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: End of backend $BACKEND_NAME usage failed, ABORT!"
        return 1
    fi
    
    igx_verbose "Usage of backend $BACKEND_NAME successfuly ended."
    
    return 0
}
