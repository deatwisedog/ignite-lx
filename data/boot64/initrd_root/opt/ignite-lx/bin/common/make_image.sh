#!/bin/bash

# make_image.sh
# 
#
# Created by Daniel Faltin on 14.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

# 
# Globals of make_image.sh
#
IGX_IMAGE=""
IGX_IMAGE_DIR=""
IGX_IMAGE_NAME=""
IGX_INCLUDE=""
IGX_EXCLUDE=""
IGX_BACKEND=""
IGX_BACKEND_LOADED=0
IGX_BACKEND_CONF_DIR=""
IGX_COMMON_INCL="bin/common/ignite_common.inc"

#
# Setup script environment and include common functions.
#
if [ -z "$IGX_BASE" ]; then
    IGX_BASE="/opt/ignite-lx"
    export IGX_BASE
fi

if [ -f "$IGX_BASE/$IGX_COMMON_INCL" ]; then
    . "$IGX_BASE/$IGX_COMMON_INCL"
    igx_setenv || exit 1
else
    echo 1>&2 "FATAL: Cannot found major ignite functions $IGX_BASE/$IGX_COMMON_INCL, ABORT!"
    exit 1
fi

#
# Simply cleanup a failed ignite run.
# Arguments: noexit (means that script go ahead)
#
cleanup()
{
    retval=$?
    
    igx_log "ERROR: Failed to create disaster image $IGX_IMAGE!"
    
    if [ -f "$IGX_BACKEND_CONF_DIR/backend.conf" ]; then
        mod="$(awk -F '#' '/MOD/ { print $2; }' $IGX_BACKEND_CONF_DIR/backend.conf)"
        url="$(awk -F '#' '/URL/ { print $2; }' $IGX_BACKEND_CONF_DIR/backend.conf)"
        img="$(awk -F '#' '/IMG/ { print $2; }' $IGX_BACKEND_CONF_DIR/backend.conf)"
        
        if [ "$mod" = "none" -a -f "$url/$img" ]; then
            igx_verbose "Deleting failed image $url/$img"
            rm -f "$url/$img"
        fi
        
        igx_verbose "Deleting $IGX_BACKEND_CONF_DIR/backend.conf"
        rm -f "$IGX_BACKEND_CONF_DIR/backend.conf"
    fi
    
    if [ $IGX_BACKEND_LOADED -eq 1 ]; then
        igx_end_backup_backend "$IGX_BACKEND" "$IGX_IMAGE" && IGX_BACKEND_LOADED=0 
    fi
        
    case "$1" in
    
        noexit)
            return $retval
        ;;        
        
    esac
    
    exit $retval
}

#
# Usage function parse and check script arguments.
#
usage() 
{
    while getopts "dhvi:x:b:o:" opt; do
        case "$opt" in
            d)
                set -x
            ;;
            
            b)
                IGX_BACKEND="$OPTARG"
            ;;
            
            i)
                IGX_INCLUDE="$IGX_INCLUDE $OPTARG"
            ;;
            
            o)
                IGX_BACKEND_CONF_DIR="$OPTARG"
            ;;
            
            x)
                echo "$OPTARG" | grep -e "^/" > /dev/null
                if [ $? -ne 0 ]; then
                    igx_stderr "ERROR: -x $OPTARG invalid, the path must be absolut!"
                    return 1
                fi
                
                if [ ! -d "$OPTARG" ]; then
                    igx_stderr "ERROR: -x $OPTARG, the defined directory does not exists!"
                    return 1
                fi
                IGX_EXCLUDE="$IGX_EXCLUDE $(echo $OPTARG | sed -e 's/^\/*/\//g' -e 's/\/$//g')"
            ;;
            
            v)
                IGX_VERBOSE=1
            ;;
            
            h|*)
                igx_stderr "$IGX_VERSION"
                igx_stderr "usage: make_image.sh [-dhv] [ -x <directory> -b <backend> -o <directory>] -i <dev/vg> <image name/output>"
                igx_stderr "-b <backend> define backend to handel archive output (exp.: nfs)"
                igx_stderr "-h print this screen"
                igx_stderr "-d enable script debug"
                igx_stderr "-v verbose"
                igx_stderr "-o <directory> output directory where backend.conf is written (default is image path)"
                igx_stderr "-i <dev/vg> disk or vg to backup, typical only system root vg/disk"
                igx_stderr "-x <directory/file> defined directory or file will be excluded from image"
                igx_stderr ""
                igx_stderr "Examples:"
                igx_stderr "make_image.sh -i vg00 -i /dev/md0 -x /tmp -x /var/tmp /mnt/external/ignite_image.igx"
                igx_stderr "make_image.sh -b nfs -o /opt/ignite-lx/data/config/mybackup -i vg00 -i /dev/md0 -x /tmp -x ignite_image.igx"
                return 1
            ;;
        esac
    done
    
    shift $((OPTIND - 1))
    
    IGX_IMAGE="$@"
    
    if [ -z "$IGX_INCLUDE" ]; then
        igx_stderr "ERROR: Argument -i <dev/vg> is required!"
        return 1
    fi
    
    if [ -z "$IGX_IMAGE" ]; then
        igx_stderr "ERROR: No output image defined!"
        return 2
    fi
    
    if [ -d "$IGX_IMAGE" ]; then
        igx_stderr "ERROR: Defined image output name is a directory!"
        return 3
    fi

    IGX_IMAGE_NAME="$(basename $IGX_IMAGE)"
    IGX_IMAGE_DIR="$(igx_dirname $IGX_IMAGE)"
    IGX_IMAGE="$IGX_IMAGE_DIR/$IGX_IMAGE_NAME"
    
    if [ ! -d "$IGX_IMAGE_DIR" ]; then
        igx_stderr "ERROR: Directory \"$IGX_IMAGE_DIR\" where image should located does not exists!"
        return 4
    fi

    if [ -z "$IGX_BACKEND_CONF_DIR" ]; then
        IGX_BACKEND_CONF_DIR="$IGX_IMAGE_DIR"
    else
        IGX_BACKEND_CONF_DIR="$(igx_dirname $IGX_BACKEND_CONF_DIR)" || return 5
    fi
        
    return 0
}

#
# Gather and return the basic mountpoints based on dev/vg provided as argument (typical $IGX_INCLUDE).
#
get_mountpoints()
{
    include="$@"
    igx_verbose "Resolving mountpoints for devices: $include"

    devices="`igx_resolve_devices $include`"
    if [ -z "$devices" ]; then
        igx_log "ERROR: Cannot resolve one or more devices of: $include, ABORT!"
        return 1
    fi
    
    igx_verbose "Following devices are resolved for mountpoints:"

    for dev1 in $devices; do
        
        igx_verbose "$dev1"
                
        echo "$(mount; cat /proc/mounts)" | awk 'BEGIN { flag = 0; } 
        { 
            gsub(" on ", " ", $0);
            gsub(" type ", " ", $0);
            
            if($1 == "'$dev1'") { 
                flag = 1;
                print $2;
                exit(0);
            }
        } END { if(flag) exit(0); exit(1); }'
                
        if [ $? -ne 0 ]; then
            while read dev2 args; do
                if [ "$dev1" = "$dev2" ]; then
                    found=1
                fi
            done < /proc/swaps

            blkid -o value $dev1 | grep swap > /dev/null 2> /dev/null
            if [ $? -eq 0 ]; then
                found=1
            fi
            
            if [ $found -eq 0 ]; then
                igx_log "ERROR: Device $dev1 not mounted and will not included in backup image, ABORT!"
                return 2
            fi
        fi
        
    done
    
    return 0
}

#
# Verify and print the hole content for each mountpoint provided provided as argument
#
get_fs_content()
{    
    mountpoints="$@"

    igx_verbose "Getting filesystem content for mountpoints..."
    
    if [ -z "$mountpoints" ]; then
        igx_log "ERROR: Cannot found any mounted filesystems for backup!"
        return 1
    fi
    
    for req in "/"; do 
    
        found=0
        
        for mp in $mountpoints; do
            if [ "$mp" = "$req" ]; then
                found=1
            fi
        done
        
        if [ $found -eq 0 ]; then
            igx_log "ERROR: The mandatory mountpoint \"/\" was not found so a image makes no sense, ABORT!"
            return 2
        fi
        
    done
    
    igx_verbose "Following mountpoints are include in image:"
    
    for mp in $mountpoints; do
        igx_verbose "$mp"
        find "$mp" -xdev 2> /dev/null
    done
        
    return 0
}

#
# This function reads stream form stdin and removes all leading '/' and the paths or files provided as argument
#
mangele_content()
{
    exclude="$@"
    sed_args=""
    
    if [ ! -z "$exclude" ]; then
        for e in $exclude; do
            if [ -f "$e" ]; then
                pattern=$(echo $e | sed -e 's/\//\\\//g')
                sed_args="-e /${pattern}$/d $sed_args"
            else
                pattern=$(echo $e | sed -e 's/\//\\\//g' -e 's/$/\\\//g')
                sed_args="-e /${pattern}/d $sed_args"
            fi
        done
    fi
    
    sed_args="$sed_args -e s/^\///g -e /^$/d"
    
    while read line; do
        echo "$line" | sed $sed_args
    done
    
    return $?
}

#
# Create the require image information (backend.conf) where path and name is listed
#
create_backend_conf()
{
    bconf_retval=0
    
    if [ $IGX_BACKEND_LOADED -eq 0 ]; then
        igx_verbose "Creating $IGX_BACKEND_CONF_DIR/backend.conf (with local informations)"
        echo "MOD#none"            >  "$IGX_BACKEND_CONF_DIR/backend.conf"
        echo "URL#$IGX_IMAGE_DIR"  >> "$IGX_BACKEND_CONF_DIR/backend.conf"
        echo "IMG#$IGX_IMAGE_NAME" >> "$IGX_BACKEND_CONF_DIR/backend.conf"
        bconf_retval=$?
    else
        igx_verbose "Creating $IGX_BACKEND_CONF_DIR/backend.conf from backend $IGX_BACKEND"
        igx_backup_backend_getconf "$IGX_IMAGE" > "$IGX_BACKEND_CONF_DIR/backend.conf"
        bconf_retval=$?
    fi

    if [ $bconf_retval -ne 0 ]; then
        igx_log "ERROR: Cannot create $IGX_BACKEND_CONF_DIR/backend.conf, ABORT"
        return 1
    fi
    
    return $bconf_retval
}

#
# Create the cpio archive from the provided devices or volume groups.
#
create_image()
{    
    igx_log "Creating System Recovery Archive # start $(igx_date)"

    targets="$@"
    cpio_cmd="cpio -o --format=crc"
    mounts="$(get_mountpoints $targets)"
    
    if [ -z "$mounts" ]; then
        igx_log "ERROR: Cannot create image, unable to resolved mountpoint correctly. ABORT!"
        return 1
    fi
    
    igx_init_backup_backend "$IGX_BACKEND" "$IGX_IMAGE"
    ibk_ret=$?
        
    if [ $ibk_ret -eq 100 ]; then
    
        create_backend_conf || return 2
        cd /
        get_fs_content $mounts | mangele_content $IGX_EXCLUDE | $cpio_cmd | gzip -v -9 - > $IGX_IMAGE
        arch_retval=$?
        cd $OLDPWD
        
        if [ $arch_retval -ne 0 ]; then
            igx_log "ERROR: The creation of image $IGX_IMAGE was not successful! # end $(igx_date)"
            return 1
        else
            igx_log "Archive successfully created! # end $(igx_date)"
        fi
        
    else
        if [ $ibk_ret -ne 0 ]; then
            igx_log "ERROR: Init() of backend $IGX_BACKEND failed, ABORT!"
            return 4
        else
            IGX_BACKEND_LOADED=1
            create_backend_conf || return 3
        fi
        
        igx_verbose "Starting archive creation and deliver compressed cpio to backend $IGX_BACKEND"
                
        cd /
        get_fs_content $mounts | mangele_content $IGX_EXCLUDE | $cpio_cmd | gzip -v -9 - | igx_backup_backend_run "$IGX_IMAGE"
        arch_retval=$?
        cd $OLDPWD
                
        if [ $arch_retval -ne 0 ]; then
            igx_stdout "ERROR: The creation of image $IGX_IMAGE using backend $IGX_BACKEND was not successful! # end $(igx_date)"
            return 6
        else
            igx_log "Archive by using backend $IGX_BACKEND successfully created! # end $(igx_date)"
            igx_end_backup_backend "$IGX_BACKEND" "$IGX_IMAGE" && IGX_BACKEND_LOADED=0 || return 5
        fi
    fi
        
    return 0
}


#
# This function is execute if the script is called
#
main()
{
    usage $@   || return 1
    igx_chkenv || return 2
    
    trap cleanup 2 15
    
    create_image $IGX_INCLUDE
    if [ $? -ne 0 ]; then
        cleanup "noexit"
        return 1
    fi
    
    return 0
}

#
# Execute the script by calling main()
#
main $@
exit $?
