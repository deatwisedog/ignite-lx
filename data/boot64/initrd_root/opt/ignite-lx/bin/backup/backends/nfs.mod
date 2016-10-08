# nfs.mod
# 
#
# Created by Daniel Faltin on 29.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

#
# Module implements Ignite-LX NFS Backup
#
# This functions are include / loaded from make_image.sh
# Each backend must define the major functions below (igx_backup_backend_xxxxx)
#

#
# Function is used to identify the backend
# Arguments: none
# Return: print the backendname to stdout
#
igx_backup_backend_name()
{
    echo "nfs.mod"
    return $?
}

#
# Function init the backend usage
# Arguments: </path/imagename>
# Return: Zero on success otherwise an non zero value is returned
#
igx_backup_backend_init()
{
    return 0
}

#
# Function bind the backend resource like mount, etc.
# Arguments: </path/imagename>
# Return: Zero on success otherwise an non zero value is returned
#
igx_backup_backend_bind()
{
    igx_verbose "Mounting NFS Image share ($IGX_NFS_URL) on $IGX_NFS_MOUNTPOINT ..."
    
    if [ ! -d "$IGX_NFS_MOUNTPOINT" ]; then
        igx_log "ERROR: Directory / Mountpoint $IGX_NFS_MOUNTPOINT does not exists, ABORT!"
        return 1
    fi
    
    mount 2>&1 -t nfs "$IGX_NFS_URL" "$IGX_NFS_MOUNTPOINT"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot mount archive directory $IGX_NFS_URL, ABORT!"
        return 2
    fi
    
    igx_verbose "Mount of archive directory successful!"
    
    touch 2> /dev/null "$IGX_NFS_MOUNTPOINT/igx_write.tmp"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot write on mounted share $IGX_NFS_MOUNTPOINT, ABORT!"
        umount "$IGX_NFS_MOUNTPOINT"
        return 4
    else
        rm -f "$IGX_NFS_MOUNTPOINT/igx_write.tmp"
    fi
    
    return 0
}

#
# Read a gzip cpio content from "stdin" and handel the output of this content
# Arguments: </path/imagename>
# Return: Zero on success otherwise an non zero value is returned
#
igx_backup_backend_run()
{
    IMG_NAME="$(basename $1)"
    
    if [ -z "$IMG_NAME" ]; then
        igx_log "ERROR: Backend run() function missing arguments, ABORT!"
        return 1
    fi
    
    igx_verbose "Start of NFS backend, reading data stream from stdin (using cat as reader), output file is $IGX_NFS_MOUNTPOINT/$IMG_NAME"
    
    cat > "$IGX_NFS_MOUNTPOINT/$IMG_NAME"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Redirect of input stream using \"cat\" as stdin failed!"
        igx_log "Backend NFS failed to create file $IGX_NFS_MOUNTPOINT/$IMG_NAME, ABORT!"
        test -f "$IGX_NFS_MOUNTPOINT/$IMG_NAME" && rm -f "$IGX_NFS_MOUNTPOINT/$IMG_NAME"
        return 2
    fi
    
    igx_log "File $IGX_NFS_MOUNTPOINT/$IMG_NAME successfully created!"
    
    return 0
}

#
# Function copy the defined "configset" and "image" directory to bind()'ed resource
# Arguments: </path/configset> </path/image_iso_dir>
# Return: Zero on success otherwise an non zero value is returned
#
igx_backup_backend_copy()
{
    config_set="$1"
    image_set="$2"
    
    igx_verbose "Copying config set $config_set to NFS share Mountpoint $IGX_NFS_MOUNTPOINT"
    cp -R "$config_set" "$IGX_NFS_MOUNTPOINT"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot copy $config_set to $IGX_NFS_MOUNTPOINT, ABORT!"
        return 1
    fi
        
    igx_verbose "Copying $image_set to NFS Mountpoint $IGX_NFS_MOUNTPOINT/$(basename $config_set)"
    cp -R "$image_set" "$IGX_NFS_MOUNTPOINT/$(basename $config_set)"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot copy $image_set to $IGX_NFS_MOUNTPOINT/$(basename $config_set), ABORT!"
        return 2
    fi
    
    igx_log "Config set $(basename $config_set) (incl. iso/boot files) successfully copied to NFS Mountpoint $IGX_NFS_MOUNTPOINT!"

    return 0
}

#
# Function rotates stored "image" and "configset" directories"
# Arguments: <config set ids to remove> (if argument is "0" no rotation is required!)
# Return: Zero on success otherwise an non zero value is returned
#
igx_backup_backend_rotate()
{
    ids_to_remove="$@"
    
    igx_verbose "Rotating NFS config sets and images"
    
    if [ "$ids_to_remove" = "0" ]; then
        igx_verbose "No ids to remove deliverd for NFS config set rotation"
        return 0
    fi 

    igx_verbose "Config sets with following ids are marked for removed: $ids_to_remove"

    for setid in "$IGX_NFS_MOUNTPOINT"/*/set.id; do
        test -r "$setid" || continue
        cur_setid="$(cat $setid)"

        for rm_id in $ids_to_remove; do
            if [ "$cur_setid" = "$rm_id" ]; then
                mod="$(awk -F '#' '/MOD/ { print $2; }' $(dirname $setid)/backend.conf)"
                url="$(awk -F '#' '/URL/ { print $2; }' $(dirname $setid)/backend.conf)"
                img="$(awk -F '#' '/IMG/ { print $2; }' $(dirname $setid)/backend.conf)"
                
                if [ "$mod" = "$(igx_backup_backend_name)" -a  -f "$IGX_NFS_MOUNTPOINT/$img" ]; then
                    igx_verbose "Removing old NFS stored image file $IGX_NFS_MOUNTPOINT/$img from config set $(dirname $setid)"
                    rm -f "$IGX_NFS_MOUNTPOINT/$img"
                fi
                
                igx_log "Removing old NFS stored config set (set id: $cur_setid) $(dirname $setid)!"
                rm -rf "$(dirname $setid)"
            fi
        done 
    done
    
    return 0
}

#
# Function finish usage of backup backend
# Arguments: </path/imagename>
# Return: Zero on success otherwise an non zero value is returned
#
igx_backup_backend_end()
{
    igx_verbose "Unmounting NFS Image share ($IGX_NFS_URL) on $IGX_NFS_MOUNTPOINT ..."
    
    if [ ! -d "$IGX_NFS_MOUNTPOINT" ]; then
        igx_log "ERROR: Directory / Mountpoint $IGX_NFS_MOUNTPOINT does not exists, ABORT!"
        return 1
    fi
    
    igx_verbose "Unmounting $IGX_NFS_MOUNTPOINT"
    umount 2> /dev/null "$IGX_NFS_MOUNTPOINT" || igx_log "WARNING: Cannot umount $IGX_NFS_MOUNTPOINT"
        
    return $?
}

#
# Function print to stdout 
# Arguments: </path/imagename>
# Return: print MOD#<module name>, URL#<url/src>, IMG#<image name/path>
#

igx_backup_backend_getconf()
{
    IMG_NAME="$(basename $1)"
    
    url_host="$(echo $IGX_NFS_URL | awk -F ':' '{ print $1; }')"
    url_path="$(echo $IGX_NFS_URL | awk -F ':' '{ print $2; }')"

    echo "MOD#$(igx_backup_backend_name)"
    echo "URL#$(igx_gethostbyname $url_host):$url_path"
    echo "IMG#$IMG_NAME"
    
    return $?
}
