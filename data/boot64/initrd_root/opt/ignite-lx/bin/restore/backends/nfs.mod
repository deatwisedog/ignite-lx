# nfs.mod
# 
#
# Created by Daniel Faltin on 29.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

#
# Module implements Ignite-LX NFS Restore
#
# This functions are include / loaded from make_restore.sh
# Each backend must define the three major restore functions
#

#
# Run some pre- required activities like service start etc. 
# Arguments: none
# Return zero on success otherwise a non zero value
#
igx_restore_backend_init() 
{
    igx_log "Starting portmap daemon"
    
    /sbin/portmap
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot startup portmap daemon, ABORT!"
        igx_log "Please try to start /sbin/portmap manually and mount nfs share!"
        return 1
    else
        igx_log "Portmap daemon successfully started!"
    fi

    return 0
}

#
# Function bind the image location (if required) like mount etc.
# Arguments: <string> typical a url and image name to use internal in this function
# Return zero on success otherwise a non zero value
#
igx_restore_backend_bind() 
{
    URL="$@"

    igx_log "Mounting NFS Image share (from: $URL to: $IGX_NFS_MOUNTPOINT)"
    
    if [ -z "$URL" ]; then
        igx_log "ERROR: Cannot find URL as argument, ABORT!"
        return 1
    fi
    
    if [ -z "$IGX_NFS_MOUNTPOINT" ]; then
        IGX_NFS_MOUNTPOINT="/opt/ignite-lx/mnt/arch_mnt"
    fi
        
    if [ ! -d "$IGX_NFS_MOUNTPOINT" ]; then
        igx_log "Creating archive mountpoint $IGX_NFS_MOUNTPOINT"
        mkdir -p "$IGX_NFS_MOUNTPOINT"
        if [ ! -d "$IGX_NFS_MOUNTPOINT" ]; then
            igx_log "ERROR: Cannot create directory $IGX_NFS_MOUNTPOINT, ABORT!"
            igx_log "Create $IGX_NFS_MOUNTPOINT manually and mount nfs share!"
            return 2
        else
            igx_log "Archive mountpoint $IGX_NFS_MOUNTPOINT successfully created!"
        fi
    fi
    
    igx_log "Trying mount of $URL on $IGX_NFS_MOUNTPOINT ..."
    
    mount.nfs "$URL" "$IGX_NFS_MOUNTPOINT" -w -v -o nolock,soft
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Mount of $URL on $IGX_NFS_MOUNTPOINT failure, ABORT!"
        igx_log "Please mount nfs share on $IGX_NFS_MOUNTPOINT manually!"
        return 2
    fi
    
    igx_log "Mount of $URL on $IGX_NFS_MOUNTPOINT successfully!"
    
    return 0
}

#
# Function print to stdout the plain cpio archive content
# Arguments: <string> image url (path, link, etc.) to get
# Return zero on success otherwise a non zero value
#
igx_restore_backend_run()
{
    IMG="$@"

    if [ -z "$IGX_NFS_MOUNTPOINT" ]; then
        IGX_NFS_MOUNTPOINT="/opt/ignite-lx/mnt/arch_mnt"
    fi

    if [ ! -r "$IMG" ]; then
        if [ ! -r "$IGX_NFS_MOUNTPOINT/$IMG" ]; then
            igx_log "ERROR: Cannot find/read image file $IMG for restore, ABORT!"
            return 1
        else
            IMG_FILE="$IGX_NFS_MOUNTPOINT/$IMG"
        fi
    else
        IMG_FILE="$IMG"
    fi
    
    gzip -cd "$IMG_FILE"
    
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Unzip of file $IMG_FILE failed, ABORT!"
        return 2
    fi

    igx_log "Unzip of $IMG_FILE successful!"
    
    return 0
}

#
# Function move or copy the logfile on the same location where image is located.
# Arguments: <string> typical a logfile to move
# Return zero on success otherwise a non zero value
#
igx_restore_backend_log()
{
    move_log="$@"
    
    igx_log "Copying logfile $move_log to NFS share $IGX_NFS_MOUNTPOINT"
    cp "$move_log" "$IGX_NFS_MOUNTPOINT"
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot copy logfile, please do this manual, ABORT!"
        return 1
    fi
    
    return 0
}

#
# Function finish / cleanup the usage of this backend.
# Arguments: <string> typical a url to use internal in this function
# Return zero on success otherwise a non zero value
#
igx_restore_backend_end()
{
    URL="$@"
    
    if [ -z "$IGX_NFS_MOUNTPOINT" ]; then
        IGX_NFS_MOUNTPOINT="/opt/ignite-lx/mnt/arch_mnt"
    fi

    igx_log "Unmounting $IGX_NFS_MOUNTPOINT (from: $URL)"
 
    umount "$IGX_NFS_MOUNTPOINT"
    
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Unmount of $IGX_NFS_MOUNTPOINT failed, ABORT!"
        return 1
    fi
    
    igx_log "Unmount of $IGX_NFS_MOUNTPOINT successful!"
    
    return 0
}
