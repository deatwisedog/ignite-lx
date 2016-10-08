#!/bin/bash

# make_boot.sh
# 
#
# Created by Daniel Faltin on 17.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.



# 
# Globals of make_boot.sh
#
IGX_ARCH="$(uname -m)"
IGX_BOOT_DIR=""
IGX_KERN=0
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
# Usage function parse and check script arguments.
#
usage() 
{
    while getopts "dhvka:" opt; do
        case "$opt" in
            d)
                set -x
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
                igx_stderr "usage: make_boot.sh [-dhvkb]"
                igx_stderr "-h print this screen"
                igx_stderr "-d enable script debug"
                igx_stderr "-a <arch> set current system bit arch. manual (example: 32 or 64)"
                igx_stderr "-k use current installed kernel and modules for disaster recovery boot (default disabled)"
                igx_stderr "-v verbose"
                igx_stderr ""
                igx_stderr "Example:"
                igx_stderr "make_boot.sh -v -k"
                return 1
            ;;
        esac
    done
    
    case $IGX_ARCH in
        x86_64|64|ia64)
            IGX_BOOT_DIR="$IGX_BOOT64_DIR"
        ;;
        
        *)
            igx_stderr "Arch. $IGX_ARCH is not supported yet, ABORT!"
            return 20
        ;;
    esac
    
    if [ ! -d "$IGX_BOOT_DIR/initrd_root" ]; then
        igx_stderr "ERROR: Cannot find/access $IGX_BOOT_DIR/initrd_root directory, ABORT!"
        return 1
    fi

    if [ ! -d "$IGX_BOOT_DIR/iso_root" ]; then
        igx_stderr "ERROR: Cannot find/access $IGX_BOOT_DIR/iso_root directory, ABORT!"
        return 2
    fi
    
    if [ ! -d "$IGX_BOOT_DIR/image" ]; then
        igx_stderr "ERROR: Cannot find/access $IGX_BOOT_DIR/image directory, ABORT!"
        return 3
    fi

    
    
    IFSOLD="$IFS"
    IFS=":"
    
    found=0    
    for dir in $PATH; do
        test -x "$dir/genisoimage" && found=1 && break
    done
    
    IFS="$IFSOLD"
    
    if [ $found -eq 0 ]; then
        igx_stderr "ERROR: Cannot find mandatory program \"genisoimage\" in \$PATH, ABORT!"
        return 4
    fi
    
    return 0
}

#
# Copy kernel and modules (if IGX_KERN=1) to initrd, update scripts and create a new initrd
#
update_initrd()
{
    igx_log "Updating and creating new initrd for disaster recovery."
    
    if [ $IGX_KERN -eq 1 ]; then
        uname -r > $IGX_BOOT_DIR/version
    fi

    if [ ! -f "$IGX_BOOT_DIR/version" ]; then
        igx_log "WARNING: No default kernel found for Ignite-LX usage, assuming running kernel as default!"
        uname -r > $IGX_BOOT_DIR/version
        IGX_KERN=1
    fi
        
    kern_version="$(cat $IGX_BOOT_DIR/version)"

    igx_verbose "Copying Ignite-LX tools to initrd"
    rm    -rf "$IGX_BOOT_DIR/initrd_root/etc/udev"
    rm    -rf "$IGX_BOOT_DIR/initrd_root/lib/firmware"
    mkdir -p  "$IGX_BOOT_DIR/initrd_root/lib/firmware"
    mkdir -p  "$IGX_BOOT_DIR/initrd_root/opt/ignite-lx/log"
    mkdir -p  "$IGX_BOOT_DIR/initrd_root/opt/ignite-lx/data/boot32"
    mkdir -p  "$IGX_BOOT_DIR/initrd_root/opt/ignite-lx/data/boot64"
    igx_copy  "$IGX_BIN_DIR"    "$IGX_BOOT_DIR/initrd_root/opt/ignite-lx/bin"
    igx_copy  "$IGX_BASE/etc"   "$IGX_BOOT_DIR/initrd_root/opt/ignite-lx/etc"
    igx_copy  "$IGX_CONFIG_DIR" "$IGX_BOOT_DIR/initrd_root/opt/ignite-lx/data/config"
    
    igx_verbose "Copying required system configurations into initrd"
    igx_copy "/etc/lvm"            "$IGX_BOOT_DIR/initrd_root/etc/lvm"
    igx_copy "/etc/udev"           "$IGX_BOOT_DIR/initrd_root/etc/udev"
    igx_copy "/etc/mdadm"          "$IGX_BOOT_DIR/initrd_root/etc/mdadm"
    igx_copy "/etc/modprobe.d"     "$IGX_BOOT_DIR/initrd_root/etc/modprobe.d"
    igx_copy "/etc/scsi_id.config" "$IGX_BOOT_DIR/initrd_root/etc/scsi_id.config"
    igx_copy "/etc/hosts"          "$IGX_BOOT_DIR/initrd_root/etc/hosts"
    igx_copy "/etc/host.conf"      "$IGX_BOOT_DIR/initrd_root/etc/host.conf"
    igx_copy "/etc/services"       "$IGX_BOOT_DIR/initrd_root/etc/services"
    igx_copy "/etc/protocols"      "$IGX_BOOT_DIR/initrd_root/etc/protocols"
    igx_copy "/etc/resolv.conf"    "$IGX_BOOT_DIR/initrd_root/etc/resolv.conf"
    igx_copy "/etc/nsswitch.conf"  "$IGX_BOOT_DIR/initrd_root/etc/nsswitch.conf"
    
    for klib in /lib/klibc*; do
        igx_copy "$klib" "$IGX_BOOT_DIR/initrd_root/lib"
    done
    
    for fw in /lib/firmware/* /usr/lib/firmware/* /usr/lib/hotplug/firmware/*; do
        igx_copy "$fw" "$IGX_BOOT_DIR/initrd_root/lib/firmware"
    done
    
    igx_verbose "Adding udev default rules to initrd"
    if [ ! -d $IGX_BOOT_DIR/initrd_root/etc/udev ]; then
        cd $IGX_BOOT_DIR/initrd_root/etc
        ln -s udev_default udev
        cd $OLDPWD
    else
        mkdir -p $IGX_BOOT_DIR/initrd_root/etc/udev/rules.d
        cd $IGX_BOOT_DIR/initrd_root/etc/udev/rules.d
        for rule in ../../udev_default/rules.d/*; do
            ln -s $rule
        done
        cd $OLDPWD
        test -f $IGX_BOOT_DIR/initrd_root/etc/udev/udev.conf || \
        igx_copy "$IGX_BOOT_DIR/initrd_root/etc/udev_default/udev.conf" "$IGX_BOOT_DIR/initrd_root/etc/udev/udev.conf"
    fi
    
    if [ $IGX_KERN -eq 1 ]; then
        igx_verbose "Copying current module tree to initrd"
        
        if [ ! -d "/lib/modules/$kern_version/kernel" ]; then
            igx_log "ERROR: Cannot find/access modules directory /lib/modules/$kern_version/kernel, ABORT!"
            return 10
        fi
        
        if [ ! -f "/boot/System.map-$kern_version" ]; then
            igx_log "ERROR: Cannot find find/access /boot/System.map-$kern_version"
            return 20
        fi
    
        if [ ! -f "/boot/config-$kern_version" ]; then
            igx_log "ERROR: Cannot find find/access /boot/config-$kern_version"
            return 30
        fi

        if [ ! -f "/boot/vmlinuz-$kern_version" ]; then
            igx_log "ERROR: Cannot find find/access /boot/vmlinuz-$kern_version"
            return 40
        fi

        rm -rf $IGX_BOOT_DIR/initrd_root/lib/modules/*
        mkdir -p $IGX_BOOT_DIR/initrd_root/lib/modules/$kern_version
        igx_copy "/lib/modules/$kern_version/kernel" "$IGX_BOOT_DIR/initrd_root/lib/modules/$kern_version/kernel"
        igx_copy "/boot/System.map-$kern_version"    "$IGX_BOOT_DIR/image/System.map-$kern_version"
        igx_copy "/boot/config-$kern_version"        "$IGX_BOOT_DIR/image/config-$kern_version"
        igx_copy "/boot/symvers-${kern_version}.gz"  "$IGX_BOOT_DIR/image/symvers-${kern_version}.gz"
        igx_copy "/boot/vmlinuz-$kern_version"       "$IGX_BOOT_DIR/image/vmlinuz-$kern_version"
    fi
    
    igx_verbose "Creating a copy of /dev into initrd for kernel they not support inotify"
    test -d "$IGX_BOOT_DIR/initrd_root/dev_old" && rm -rf "$IGX_BOOT_DIR/initrd_root/dev_old"
    mkdir -p "$IGX_BOOT_DIR/initrd_root/dev_old"
    cd /dev
    find . -xdev | cpio -pmdu "$IGX_BOOT_DIR/initrd_root/dev_old" > /dev/null 2> /dev/null
    cd $OLDPWD

    igx_verbose "Creating new compressed initrd: $IGX_BOOT_DIR/image/initrd-$kern_version"    
    cd $IGX_BOOT_DIR/initrd_root
    find . | cpio -o --format=newc 2> /dev/null | gzip -9 - > $IGX_BOOT_DIR/image/initrd-$kern_version
        
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Failed to create initrd: $IGX_BOOT_DIR/image/initrd-$kern_version, ABORT!"
        cd $OLDPWD
        return 1
    fi
    
    cd $OLDPWD    
    igx_log "Initrd $IGX_BOOT_DIR/image/initrd-$kern_version successfuly created!"    
    
    return 0
}

#
# Creating a new disaster recovery bootable iso image
#
update_iso()
{
    kern_version="$(cat $IGX_BOOT_DIR/version)"

    igx_log "Creating new disaster recovery bootable ISO file"
    igx_verbose "Creating new isolinux.cfg bootloader configuration"
        
    if [ ! -d "$IGX_BOOT_DIR/iso_root/isolinux" ]; then
        igx_log "ERROR: Cannot find/access directory $IGX_BOOT_DIR/iso_root/isolinux, ABORT!"
        return 1
    fi

    echo "prompt 0"                                                                > $IGX_BOOT_DIR/iso_root/isolinux/isolinux.cfg
    echo "timeout 300"                                                            >> $IGX_BOOT_DIR/iso_root/isolinux/isolinux.cfg
    echo "default IGNITE-LX_RECOVERY_BOOT_$(uname -n)"                            >> $IGX_BOOT_DIR/iso_root/isolinux/isolinux.cfg
    echo "label IGNITE-LX_RECOVERY_BOOT_$(uname -n)"                              >> $IGX_BOOT_DIR/iso_root/isolinux/isolinux.cfg
    echo "kernel /kernel/vmlinuz-ignite_lx"                                       >> $IGX_BOOT_DIR/iso_root/isolinux/isolinux.cfg
    echo "append initrd=/images/initrd-ignite_lx load_ramdisk=1 prompt_ramdisk=0" >> $IGX_BOOT_DIR/iso_root/isolinux/isolinux.cfg
    
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Some errors are occurred while create isolinux.cfg, ABORT!"
        return 2
    fi
    
    igx_verbose "File $IGX_BOOT_DIR/iso_root/isolinux/isolinux.cfg successfuly created!"
    igx_verbose "Copying initrd & kernel into ISO boot directory"
    
    rm -f $IGX_BOOT_DIR/iso_root/images/* 2> /dev/null
    rm -f $IGX_BOOT_DIR/iso_root/kernel/* 2> /dev/null
    igx_copy "$IGX_BOOT_DIR/image/System.map-$kern_version"   "$IGX_BOOT_DIR/iso_root/kernel/System.map-$kern_version"
    igx_copy "$IGX_BOOT_DIR/image/symvers-${kern_version}.gz" "$IGX_BOOT_DIR/iso_root/kernel/symvers-${kern_version}.gz"
    igx_copy "$IGX_BOOT_DIR/image/config-$kern_version"       "$IGX_BOOT_DIR/iso_root/kernel/config-$kern_version"
    
    if [ ! -f "$IGX_BOOT_DIR/image/vmlinuz-$kern_version" ]; then
        igx_log "ERROR: Unable to find $IGX_BOOT_DIR/image/vmlinuz-$kern_version, ABORT!"
        return 3
    else
        igx_copy "$IGX_BOOT_DIR/image/vmlinuz-$kern_version" "$IGX_BOOT_DIR/iso_root/kernel/vmlinuz-ignite_lx"
    fi
    
    if [ ! -f "$IGX_BOOT_DIR/image/initrd-$kern_version" ]; then
        igx_log "ERROR: Unable to find $IGX_BOOT_DIR/image/initrd-$kern_version, ABORT!"
        return 4
    else
        igx_copy "$IGX_BOOT_DIR/image/initrd-$kern_version" "$IGX_BOOT_DIR/iso_root/images/initrd-ignite_lx"
    fi

    if [ $? -ne 0 ]; then
        igx_log "ERROR: Some errors are occurred while copying files to ISO boot directory, ABORT!"
        return 5
    fi
    
    igx_verbose "Required boot files successfuly copied to ISO boot directory."
    igx_verbose "Creating new ISO boot image $IGX_BOOT_DIR/image/$(uname -n)_recovery.iso"
    
    cd $IGX_BOOT_DIR/iso_root && rm -f isolinux/boot.cat && \
    genisoimage 2>&1 -input-charset iso8859-1 -U -r -o $IGX_BOOT_DIR/image/$(uname -n)_recovery.iso \
                     -b isolinux/isolinux.bin -c isolinux/boot.cat \
                     -no-emul-boot -boot-load-size 4 -boot-info-table "$IGX_BOOT_DIR/iso_root" 
            
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Some errors are occurred while creating ISO boot image, ABORT!"
        return 6
    fi

    igx_log "ISO image $IGX_BOOT_DIR/image/$(uname -n)_recovery.iso successfuly created!"
    
    return 0
}


#
# This function is execute if the script is called
#
main()
{
    usage $@                || return 1
    igx_chkenv              || return 2
    update_initrd           || return 3
    update_iso    | igx_log || return 4
    
    return 0
}

#
# Execute the script by calling main()
#
main $@
exit $?
