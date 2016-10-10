#!/bin/bash

# make_recovery.sh
# 
#
# Created by Daniel Faltin on 20.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

# 
# Globals of make_recovery.sh
#
IGX_INCLUDE=""
IGX_EXCLUDE=""
IGX_BACKEND=""
IGX_BACKEND_LOADED=0
IGX_IMAGE_NAME=""
IGX_CONFIGSET_NAME=""
IGX_KERN=0
IGX_ARCH="$(uname -m)"
IGX_BOOT_DIR=""
IGX_COMMON_INCL="bin/common/ignite_common.inc"
IGX_MOUNTED=0


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
    echo 1>&2 "FATAL: Cannot found major ignite functions $IGX_BASE/$IGX_COMMON_INCL, ABORT! Ignite-lx placed in /opt/ignite-lx ?"
    exit 1
fi

#
# Simply cleanup a failed ignite run.
# Arguments: noexit (means that script go ahead)
#
cleanup()
{
    retval=$?
    
    igx_log "ERROR: Failed to create a complete disaster recovery image set! # end of ignite at $(igx_date)"
    
    igx_verbose "Deleting failed image set ($IGX_CONFIGSET_NAME) files"
    test -d "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME" && rm -rf "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME"
    
    if [ $IGX_BACKEND_LOADED -eq 1 ]; then
        igx_end_backup_backend "$IGX_BACKEND" "$IGX_IMAGE_NAME"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Failed to end() usage of backup backend $IGX_BACKEND, ABORT!"
        fi
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
    IGX_CONFIGSET_NAME="recovery-$(igx_date)"
    IGX_IMAGE_NAME="$(igx_date).igx"

    while getopts "dhvki:x:a:b:" opt; do
    
        case "$opt" in
            d)
                set -x
            ;;
            
            i)
                IGX_INCLUDE="$IGX_INCLUDE $OPTARG"
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
                IGX_EXCLUDE="$IGX_EXCLUDE $OPTARG"
            ;;
            
            b)
                IGX_BACKEND="$OPTARG"
            ;;
            
            v)
                IGX_VERBOSE=1
            ;;
            
            k)
                IGX_KERN=1
            ;;
            
            a)
                IGX_ARCH="$OPTARG"
            ;;
            
            h|*)
                igx_stderr "$IGX_VERSION"
                igx_stderr "usage: make_recovery.sh [-dhvk -x <directory> -a <32/64> -b <backend>] -i <dev/vg>"
                igx_stderr "-h print this screen"
                igx_stderr "-a <32/64> force the usage of arch, default autodetected. Now supported only 32 arch"
                igx_stderr "-b <backend> define the backend to use for image creation (exp.: nfs)"
                igx_stderr "-d enable script debug"
                igx_stderr "-k include the current running kernel and modules in restore boot image"
                igx_stderr "-i <dev/vg> disk or vg to backup, typical only system root vg/disk"
                igx_stderr "-x <directory> defined directory will be exclude from backup"
                igx_stderr "-v verbose"
                igx_stderr ""
                igx_stderr "Examples:"
                igx_stderr "make_recovery.sh -b nfs -i vg00 -i /dev/md0 -x /tmp -x /var/tmp"
                igx_stderr "make_recovery.sh -i vg00 -i /dev/md0 -x /tmp -x /var/tmp"
                igx_stderr ""
                igx_stderr "Note: Without -b <backend> recovery archvie image + configset is created"
                igx_stderr "      in the current working directory! Be carefull when calling this variant,"
                igx_stderr "      and keep attention on your current working directory!"
                return 1
            ;;
        esac
        
    done
    
    if [ -z "$IGX_INCLUDE" ]; then
        igx_stderr "ERROR: Argument(s) -i <dev/vg> required!"
        return 2
    fi

    case $IGX_ARCH in
        x86_64|64|ia64)
            IGX_BOOT_DIR="$IGX_BOOT64_DIR"
        ;;
        
        *)
            igx_stderr "Arch. $IGX_ARCH is not supported yet, ABORT! We sorry, but now supported only x86_64 architecture."
            return 20
        ;;
    esac
    
    return 0
}

#
# Creating system system recovery informations
#
make_config()
{
    FLAGS=""
    
    if [ $IGX_VERBOSE -eq 1 ]; then
        FLAGS="-v"
    fi
    igx_verbose "Calling script $IGX_COMMON_DIR/make_config.sh for recovery info creation."
    $IGX_COMMON_DIR/make_config.sh $FLAGS $IGX_INCLUDE "$IGX_CONFIGSET_NAME"
    
    return $?
}

#
# Creating new initrd and bootable ISO file
#
make_boot()
{
    FLAGS=""
    
    if [ $IGX_VERBOSE -eq 1 ]; then
        FLAGS="-v"
    fi
    
    if [ $IGX_KERN -eq 1 ]; then
        FLAGS="$FLAGS -k"
    fi
    
    if [ ! -z "$IGX_ARCH" ]; then
        FLAGS="$FLAGS -a $IGX_ARCH"
    fi
    
    igx_verbose "Calling script $IGX_COMMON_DIR/make_boot.sh"
    $IGX_COMMON_DIR/make_boot.sh $FLAGS

    return $?
}

#
# Creating disaster recovery image file
#
make_image()
{
    FLAGS=""
    
    if [ $IGX_VERBOSE -eq 1 ]; then
        FLAGS="-v"
    fi
    
    if [ ! -z "$IGX_BACKEND" ]; then
        FLAGS="$FLAGS -b $IGX_BACKEND"
    else
        IGX_IMAGE_NAME="$PWD/$IGX_IMAGE_NAME"
    fi
    
    for arg in $IGX_INCLUDE; do
        FLAGS="$FLAGS -i $arg"
    done
    
    for arg in $IGX_EXCLUDE; do
        FLAGS="$FLAGS -x $arg"
    done
        
    igx_verbose "Calling script $IGX_COMMON_DIR/make_image.sh"
    $IGX_COMMON_DIR/make_image.sh -o "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME" $FLAGS "$IGX_IMAGE_NAME" || return $?
    
    return 0
}

#
# Rotate and copy the system recovery information and image local and on/to nfs mount
#
update_configset()
{
    igx_verbose "Updateing config sets (copy and rotating sets and archives) ..."
    
    marked_set_ids=""
    
    igx_get_first_imgid "$IGX_CONFIG_DIR"
    first_setid=$?
        
    igx_get_imgid "$IGX_CONFIG_DIR"
    free_setid=$?
    
    too_many=$(( (free_setid - first_setid) - IGX_MAX_IMAGES ))
        
    if [ $too_many -gt 0 ]; then
        igx_verbose "Rotation of $too_many config sets in local directory $IGX_CONFIG_DIR required!"

        cnt=0
        while [[ $cnt -lt $too_many ]]; do
            igx_get_first_imgid "$IGX_CONFIG_DIR"
            now_first_id=$?
                        
            for setid in "$IGX_CONFIG_DIR"/*/set.id; do
                test -r "$setid" || continue
                cur_setid="$(cat $setid)"
                if [ "$cur_setid" = "$now_first_id" ]; then
                    marked_set_ids="$marked_set_ids $cur_setid"
                    mod="$(awk -F '#' '/MOD/ { print $2; }' $(dirname $setid)/backend.conf)"
                    url="$(awk -F '#' '/URL/ { print $2; }' $(dirname $setid)/backend.conf)"
                    img="$(awk -F '#' '/IMG/ { print $2; }' $(dirname $setid)/backend.conf)"
                    if [ "$mod" = "none" -a  -f "$url/$img" ]; then
                        igx_verbose "Removing old image file $url/$img from config set $(dirname $setid)"
                        rm -f "$url/$img"
                    fi
                    igx_log "Removing old config set (set id: $cur_setid) $(dirname $setid)!"
                    rm -rf "$(dirname $setid)"
                fi
            done 
            cnt=$((cnt + 1))
        done
    else
        igx_log "No config set rotation required."
        marked_set_ids="0"
    fi    
    
    if [ ! -z "$IGX_BACKEND" ]; then
        igx_verbose "Loading backend $IGX_BACKEND again to execute config set update!"
        igx_init_backup_backend "$IGX_BACKEND" "$IGX_IMAGE_NAME"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot init() backend $IGX_BACKEND, ABORT!"
            return 1
        else
            IGX_BACKEND_LOADED=1
        fi        
    
        igx_verbose "Running backend $IGX_BACKEND copy() config set function"
        igx_backup_backend_copy "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME" "$IGX_BOOT_DIR/image"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Copy() config set function from backend $IGX_BACKEND failure, ABORT!"
            return 2
        fi

        igx_verbose "Running backend $IGX_BACKEND config set rotate() function"
        igx_backup_backend_rotate $marked_set_ids
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Rotate() config set function from backend $IGX_BACKEND failure, ABORT!"
            return 3
        fi

        igx_verbose "Finishing usage of backup backend $IGX_BACKEND"
        igx_backup_backend_end "$IGX_IMAGE_NAME"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Failed to end() usage of backup backend $IGX_BACKEND, ABORT!"
            return 4
        else
            IGX_BACKEND_LOADED=0
        fi
    else
        igx_verbose "Copying config set $IGX_CONFIGSET_NAME to $(dirname $IGX_IMAGE_NAME)"
        cp -Rp "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME" "$(dirname $IGX_IMAGE_NAME)"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot copy $IGX_CONFIGSET_NAME to $(dirname $IGX_IMAGE_NAME), ABORT!"
            return 5
        fi
        
        igx_verbose "Copying image directory into $(dirname $IGX_IMAGE_NAME)/$IGX_CONFIGSET_NAME"
        igx_copy "$IGX_BOOT_DIR/image" "$(dirname $IGX_IMAGE_NAME)/$IGX_CONFIGSET_NAME"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot copy image directory to $(dirname $IGX_IMAGE_NAME)/$IGX_CONFIGSET_NAME, ABORT!"
            return 6
        fi
        
        igx_log "Config set IGX_CONFIGSET_NAME (incl. iso/boot files) successfully copied to $(dirname $IGX_IMAGE_NAME)!"
    fi
        
    return 0
}

#
# Run seq. all required steps for disaster recovery image creation
#
run()
{
    igx_log "***********************************************************************"
    igx_log "Step 1-4: Creating recovery system informations for restore"
    igx_log "***********************************************************************"
    make_config || return $?
    igx_log "System information for recovery successfully collected"
    igx_log " "
    
    igx_log "***********************************************************************"
    igx_log "Step 2-4: Creating disaster recovery image for filesystem restore"
    igx_log "***********************************************************************"
    make_image || return $?
    igx_log " "	
    
    igx_log "***********************************************************************"
    igx_log "Step 3-4: Creating boot image files and ISO for disaster restore boot"
    igx_log "***********************************************************************"
    make_boot || return $?
    igx_log " "
    
    igx_log "***********************************************************************"
    igx_log "Step 4-4: Moving & rotating disaster recovery images and config sets"
    igx_log "***********************************************************************"
    update_configset || return $?
    igx_log " "

    return 0
}

#
# This function is execute if the script is called
#
main()
{
    usage $@    || return 1
    igx_chkenv  || return 2
    
    test -f "$IGX_LOG_DIR/$IGX_LOG" && rm -f "$IGX_LOG_DIR/$IGX_LOG"
    trap cleanup 2 15
    
    igx_log "Starting creation of disaster recovery image at $(igx_date)"
    
    run
    if [ $? -eq 0 ]; then
        igx_log "Disaster recovery image set successfully created!"
        igx_log "End creation of disaster recovery image at $(igx_date)"        
    else
        igx_log "ERROR: Some errors are occurred, image set is not usable for restore and will deleted!"
        cleanup "noexit"
    fi
    
    return $?
}

#
# Execute the script by calling main()
#
main $@
exit $?
