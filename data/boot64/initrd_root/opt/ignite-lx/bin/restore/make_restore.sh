#!/bin/sh

# make_restore.sh
# 
#
# Created by Daniel Faltin on 25.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

# 
# Globals of make_restore.sh
#
PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/opt/ignite-lx/bin"
export PATH

IGX_BACKEND_MOD=""
IGX_BACKEND_URL=""
IGX_BACKEND_IMG=""
IGX_CONFIGSET_NAME=""
IGX_SYSCONF_FILE=""
IGX_COMMON_INCL="bin/common/ignite_common.inc"
IGX_START_POINT="udev"
IGX_RECOVERY_STEPS="udev modules hostname network init_backend bind_backend mbr raid lvm mkfs mount_fs extract grub"

#
# Panic function start shell in case of error, that means if prev. retval is not equal zero
#
panic()
{
    assert_retval=$?
    
    if [ $assert_retval -ne 0 ]; then
        igx_log " "
        igx_log " "
        igx_log "****************************************************************************"
        igx_log "ERROR: Ignite Step: $1 FAIL!"
        igx_log "Please execute the step manually!"
        igx_log "RUN: \"exit\" to continue with next step of restore!"
        igx_log "Running Recovery Shell!"
        igx_log "****************************************************************************"
        igx_shell
    fi
    
    return $assert_retval
}

#
# Setup script environment and include common functions.
#
if [ -z "$IGX_BASE" ]; then
    IGX_BASE="/opt/ignite-lx"
    export IGX_BASE
fi

if [ -f "$IGX_BASE/$IGX_COMMON_INCL" ]; then
    . "$IGX_BASE/$IGX_COMMON_INCL"
    igx_setenv
    panic "Environment"
    IGX_LOG="ignite_restore.log"
    export IGX_LOG
else
    echo 1>&2 "FATAL: Cannot found major ignite functions $IGX_BASE/$IGX_COMMON_INCL, ABORT!"
    echo 1>&2 "Restore cannot continued with a damaged boot image, calling poweroff!"
    sleep 5
    poweroff -f 
fi

#
# Usage function parse and check script arguments.
#
usage() 
{
    while getopts "dhvs:" opt; do
        case "$opt" in
            d)
                set -x
            ;;
                        
            s)
                IGX_START_POINT="$OPTARG"
            ;;
            
            v)
                IGX_VERBOSE=1
            ;;
            
            h|*)
                igx_stderr "$IGX_VERSION"
                igx_stderr "usage: make_restore.sh [-dhv -s <start point>] <restore config name>"
                igx_stderr "-h print this screen"
                igx_stderr "-d enable script debug"
                igx_stderr "-v verbose"
                igx_stderr "-s <start point> define the activity point for recovery start"
                igx_stderr ""
                return 1
            ;;
        esac
    done
    
    shift $((OPTIND - 1))
    
    IGX_CONFIGSET_NAME="$@"
    IGX_SYSCONF_FILE="$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/sysconfig.info"
    
    if [ -z "$IGX_CONFIGSET_NAME" ]; then
        igx_stderr "ERROR: Missing recovery configuration set name as argument, ABORT!"
        return 1
    fi
    
    if [ ! -d "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME" ]; then
        igx_stderr "ERROR: Recovery configuration set $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME does not exists, ABORT!"
        return 2
    fi
    
    if [ ! -r "$IGX_SYSCONF_FILE" ]; then
        igx_stderr "ERROR: Cannot access file $IGX_SYSCONF_FILE, ABORT!"
        return 3
    fi
    
    enabled=""
    for step in $IGX_RECOVERY_STEPS; do
        if [ "$IGX_START_POINT" = "$step" ]; then
            enabled="$step"
            continue
        fi
        if [ ! -z "$enabled" ]; then
            enabled="$enabled $step"
        fi
    done
    
    if [ -z "$enabled" ]; then
        igx_stderr "ERROR: The ignite start point $IGX_START_POINT does not exists, ABORT!"
        return 4
    else
        IGX_RECOVERY_STEPS="$enabled"
    fi 
    
    return 0
}

#
# This function load all listed modules in sysconfig.info
#
load_modules()
{
    igx_log "Loading kernel modules..."
    
    awk -F ";" '/^module/ { print $NF; }' "$IGX_SYSCONF_FILE" | while read module; do
        modprobe $module 2> /dev/null && igx_log "Module $module successfuly loaded" || igx_log "Error while loading module $module"
    done
    
    igx_log "Loading of kernel modules done."
    igx_log "Trigger udev..."

    udevadm trigger
    if [ -d /sys/kernel ]; then
        udevadm settle
    fi

    return 0
}

#
# Start/Restart the udev daemon an trigger device scan
#
start_udev()
{
    igx_log "Starting udev daemon"
    
    if [ -d /sys/kernel ]; then
        echo > /sys/kernel/uevent_helper
    else
        igx_log "WARNING: Kernel $(uname -r) does not support inotify, udev will not work!"
        if [ -d /dev_old ]; then
            igx_log "Applying old device nodes (from backup) to /dev mountpoint"
            cd /dev_old && find . -xdev | /bin/cpio -pmdu /dev/
            if [ $? -ne 0 ]; then
                igx_log "ERROR: Failed to copy /dev_old to /dev device root, ABORT!"
                return 1
            fi
        else
            igx_log "FATAL: Cannot applying /dev_old as device root, directory is missing, ABORT!"
            return 2
        fi
    fi
    
    mkdir -p /dev/.udev/db /dev/.udev/queue /dev/.udev/rules.d
    killall udevd 2> /dev/null
    udevd --daemon 
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot run udev daemon, ABORT!"
        return 3
    fi
    
    sleep 1
    udevadm trigger
    if [ -d /sys/kernel ]; then
        udevadm settle
    fi

    if [ -d /sys/bus/scsi ]; then
        modprobe -q scsi_wait_scan && modprobe -r scsi_wait_scan || true
        if [ -d /sys/kernel ]; then
            udevadm settle
        fi
    fi
        
    igx_log "Start of udev daemon done"
        
    return 0
}

#
# Set the local hostname by using $IGX_SYSCONF_FILE
#
restore_hostname()
{
    igx_log "Setting up hostname"
    name="$(awk -F ';' '/^hostname/ { print $NF; }' $IGX_SYSCONF_FILE)"

    if [ -z "$name" ]; then
        igx_log "ERROR: Cannot find hostname in $IGX_SYSCONF_FILE!"
        return 1
    fi
    
    igx_log "Setting hostname to $name"
    hostname "$name"

    return $?
}

#
# Setup network by using IGX_SYSCONF_FILE
#
restore_network()
{
    igx_log "Configuring network interface(s)"
    
    awk -F ';' '/^net/ { gsub(" ", ";", $5); if($3) print $2 " " $3 " " $4 " " $5; }' "$IGX_SYSCONF_FILE" | while read dev ip mask flags; do
        echo "$dev" | egrep 'bond[0-9]{1,}$' > /dev/null
        if [ $? -eq 0 ]; then
            igx_log "Device $dev identified as bonding interface, rebuilding device."
            bond_mode="$(echo $flags | awk -F ':' '{ print $1; }')"
            slaves="$(echo $flags | awk -F ':' '{ gsub(";", " ", $2); print $2; }')"
            
            if [ -z "$bond_mode" -o -z "$slaves" ]; then
                igx_log "SUSPECT/BUG: Cannot configure bonding interface $dev, missing flags in $IGX_SYSCONF_FILE, device is ignored!"
                continue
            fi

            if [ ! -f "/sys/class/net/$dev/bonding/mode" ]; then
                igx_log "ERROR: Cannot access /sys/class/net/$dev/bonding/mode, KERNEL Module bonding loaded?"
                igx_log "       Try: modprobe bonding miimon=100"
                return 1
            else
                igx_log "Configuring bonding mode for interface $dev (mode: $bond_mode)"
                echo "$bond_mode" > "/sys/class/net/$dev/bonding/mode"
            fi

            ifconfig $dev up > /dev/null 2> /dev/null
            if [ $? -ne 0 ]; then
                igx_log "ERROR: Cannot bring up bonding interface $dev without address, ABORT!"
                return 2
            else
                igx_log "Bonding interface $dev started without address!"
            fi
 
            ifenslave $dev $slaves
            if [ $? -ne 0 ]; then
                igx_log "ERROR: Cannot add slave devices $slaves to bonding interface, ABORT!"
                return 3
            else
                igx_log "Slave devices $slaves for bonding interface $dev successfully added!"
            fi
        fi

        awk -F ';' '/^vlan/ { print $2 " " $3 " " $4; }' "$IGX_SYSCONF_FILE" | while read v_dev v_dev_real vlanid; do
            if [ "$v_dev" != "$dev" ]; then
               continue
            fi

            igx_log "Creating vlan $vlanid on device $v_dev_real..."
            vconfig add $v_dev_real $vlanid

            if [ $? -ne 0 ]; then
               igx_log "Device $v_dev now available and successfully created with vlan-id $vlanid"
            else
               igx_log "ERROR: Cannot create device $v_dev (on $v_dev_real) with vlan-id $vlanid, ABORT!"
               return 3
            fi
        done

        if [ $? -ne 0 ]; then
            return 3
        fi
        
        ifconfig $dev $ip netmask $mask up
        if [ $? -ne 0 ]; then
            igx_log "WARNING: Cannot configure device $dev with ip $ip!"
        else
            igx_log "Device $dev with ip $ip/$mask successfully configured!"
        fi
    done

    if [ $? -ne 0 ]; then
        igx_log "ERROR: Some essential network devices cannot be created, ABORT!"
        return 4
    fi

    up_devs="$(ifconfig | awk '/^eth/ || /^bond/ { print $1; }')"
    
    if [ -z "$up_devs" ]; then
        igx_log "ERROR: No interface is configured, ABORT!"
        return 5
    fi
    
    sleep 1
    
    igx_log "Setting up network routing"
    
    for dev in $up_devs; do
    
        igx_log "Setting up routing for configured device $dev"
        
        awk -F ';' '/^route/ { if("'$dev'" == $NF) print $2 " " $3 " " $4; }' "$IGX_SYSCONF_FILE" | while read net mask gw; do
            if [ "$gw" = "0.0.0.0" ]; then
                igx_log "SKIP: $net/$mask with gw $gw is identified as internal network route."
                continue
            elif [ "$net" = "0.0.0.0" ]; then
                route add default gw $gw
            else
                route add $net netmask $mask gw $gw dev $dev
            fi
            if [ $? -ne 0 ]; then
                igx_log "WARNING: Route $net/$mask gw $gw dev $dev cannot install!"
            else
                igx_log "Route $net/$mask gw $gw dev $dev successfully installed!"
            fi
        done
        
        igx_log "Checking Linkspeed of Device $dev"
        ethtool $dev | awk 'BEGIN { flag = 0; }
        {
            if($0 ~ /Speed: 100M/)
                flag++;
                
            if($0 ~ /Duplex: Half/)
                flag++;
        }
        END { if(flag == 2) exit(1); exit(0); }'
        
        if [ $? -ne 0 ]; then
            igx_log "Device $dev operates with 100Mb/s Half Duplex, forcing $dev to 100Mb/s Full Duplex"
            ethtool --change $dev speed 100 duplex full autoneg off
            if [ $? -ne 0 ]; then
                igx_log "WARNING: Unable to change the speed to 100Mb/s FD on device $dev"
            fi
        else
            igx_log "Network device speed setting for $dev seems to be ok."
        fi
        
    done
    
    return 0
}

#
# Restoring MBR on disk by using $IGX_SYSCONF_FILE
#
restore_mbr()
{
    igx_log "Restoring Master Boot Record(s)"
    
    bootdevs="$(awk -F ';' '/^boot/ { print $2 ";" $3 " "; }' $IGX_SYSCONF_FILE)"
    if [ -z "$bootdevs" ]; then
        igx_log "SUSPECT: Cannot found any devices containing MBR, step is skipped!"
        return 0
    fi
    
    for devmbr in $bootdevs; do
    
        dev="$(echo $devmbr | awk -F ';' '{ print $1; }')"
        mbr_file="$(echo $devmbr | awk -F ';' '{ print $2; }')"

        igx_log "Checking MBR from device $dev"
        if [ ! -b "$dev" ]; then
            igx_log "ERROR: Cannot find disk device $dev, ABORT!"
            return 1
        fi
        
        dd 2>/dev/null if="$dev" of="/tmp/mbr" bs=512 count=1
        cur_cksum="$(cksum /tmp/mbr | awk '{ print $1 }')"
        old_cksum="$(cksum $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/$mbr_file | awk '{ print $1 }')"
        
        if [ $cur_cksum -eq $old_cksum ]; then
            igx_log "MBR from disk $dev needs no restore (cksum is $cur_cksum)"
        else
            igx_log "Restoring MBR from disk $dev"
            dd 2>/dev/null if="$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/$mbr_file" of="$dev" count=1 bs=512
            if [ $? -ne 0 ]; then
                igx_log "ERROR: Cannot restore MBR for disk $dev, ABORT!"
                return 2
            else
                igx_log "Re- reading partition table on $(echo $dev | sed 's/[[:digit:]]*$//g') (using fdisk)"
                echo "w" | fdisk 2>&1 "$(echo $dev | sed 's/[[:digit:]]*$//g')"
                igx_log "Waiting 5 seconds before we go ahead (udev needs that)..."
                sleep 5
            fi
        fi

    done
    
    return 0
}

#
# Set up md software raid by using $IGX_SYSCONF_FILE
#
restore_raid()
{
    igx_log "Re- creating software raid (md) devices"
    grep -e "^md;" "$IGX_SYSCONF_FILE" > /dev/null
    if [ $? -ne 0 ]; then
        igx_log "No software raid needs to be setup, skipped!"
        return 0
    fi
        
    md_devices="$(awk -F ';' '/^md/ { print $2; }' $IGX_SYSCONF_FILE | sort -u)"
    
    for md_dev in $md_devices; do
    
        if [ -b $md_dev ]; then
            igx_log "Raid device $md_dev allready exists, testing if device is up"
            mdadm -D $md_dev
            if [ $? -eq 0 ]; then
                igx_log "Raid device $md_dev is up"
                continue
            fi
            igx_log "Raid device $md_dev is not running, trying startup"
        fi
    
        md_disks="$(awk -F ';' '/^md/ { if($2 == "'$md_dev'") print $3; }' $IGX_SYSCONF_FILE | sort | tr '\n' ' ')"
        md_level="$(awk -F ';' '/^md/ { if($2 == "'$md_dev'") { gsub("raid", "", $4); print $4; } }' $IGX_SYSCONF_FILE | sort -u)"
        md_devs="$(echo $md_disks | wc -w)"
        
        igx_log "Bringing up raid device $md_dev (level=$md_level, disks=$md_disks)"
        igx_log "Testing if we can assemble raid without re-creation"
        
        mdadm --assemble --run $md_dev $md_disks
        if [ $? -eq 0 ]; then
            igx_log "Raid$md_level on device $md_dev successfuly assembled."
            continue
        fi
        
        igx_log "Assemble of raid device $md_dev failed, no old superblock found!"
        igx_log "We need to create a new raid$md_level on device $md_dev"
        
        mdadm --create --assume-clean --run --level=$md_level --raid-devices=$md_devs $md_dev $md_disks
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot re- create raid$md_level on device $md_dev, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 1
        fi

        igx_log "Raid$md_level on device $md_dev created!"
        IGX_GEN_MD_CONF=1
      
    done
    
    return 0
}

#
# Restoring VolumeGroups by using $IGX_SYSCONF_FILE
#
restore_lvm()
{
    igx_log "Restoring VolumeGroup(s)"
    
    vgs="$(awk -F ';' '/^pv/ { print $2; } ' $IGX_SYSCONF_FILE | sort -u)"
    pvs="$(awk -F ';' '/^pv/ { print $3 ";" $4 " "; }' $IGX_SYSCONF_FILE)"

    if [ -z "$vgs" ]; then
        igx_log "No VolumeGroups to restore, step is skipped!"
        return 0
    fi

    for pvuuid in $pvs; do
    
        pv="$(echo $pvuuid | awk -F ';' '{ print $1; }')"
        uuid="$(echo $pvuuid | awk -F ';' '{ print $2; }')"

        igx_log "Running pvcreate on dev $pv (restoring uuid: $uuid)"
        pvcreate -y -ff --norestorefile --uuid "$uuid" "$pv"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot prepare PV $pv for LVM usage, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 1
        else
            igx_log "PV $pv successfully prepared for LVM usage!"
        fi
        
    done
        
    for vg in $vgs; do
    
        igx_log "Restoring VolumeGroup $vg"
        vgcfgrestore "$vg"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot restore VolumeGroup $vg, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 2
        else
            igx_log "VolumeGroup $vg successfully restored!"
        fi
        
        igx_log "Activating VolumeGroup $vg"
        vgchange -a y "$vg"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot activate VolumeGroup $vg, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 3
        else
            igx_log "VolumeGroup $vg successfully activated!"
        fi
        
    done

    return 0
}

#
# Creating filesystems on devices by using $IGX_SYSCONF_FILE
#
restore_mkfs()
{
    igx_log "Creating filesystem on devices (mkfs)"
    
    bdisks="$(egrep '^fs;' $IGX_SYSCONF_FILE)"
    if [ -z "$bdisks" ]; then
        igx_log "SUSPECT: No devices found where a filesystem should created, step is skipped!"
        return 0
    fi
    
    for fstypes in $bdisks; do
    
        flags=""
        uuid_cmd=""
        bdev="$(echo $fstypes | awk -F ';' '{ print $2; }')"
        fs="$(echo $fstypes | awk -F ';' '{ print $3; }')"
        bsize="$(echo $fstypes | awk -F ';' '{ print $5; }')"
        isize="$(echo $fstypes | awk -F ';' '{ print $6; }')"
        uuid="$(echo $fstypes | awk -F ';' '{ print $7; }')"
        label="$(echo $fstypes | awk -F ';' '{ print $8; }')"
        
        case $fs in
        
            xfs)
                flags="-f"
                test -z "$bsize" || flags="$flags -b size=$bsize"
                test -z "$isize" || flags="$flags -i size=$isize"
                test -z "$label" || flags="$flags -L $label"
                test -z "$uuid"  || uuid_cmd="xfs_admin -U $uuid $bdev"
            ;;
            
            ext2)
                flags="-F"
                test -z "$bsize" || flags="$flags -b $bsize"
                test -z "$isize" || flags="$flags -I $isize"
                test -z "$label" || flags="$flags -L $label"
                test -z "$uuid"  || uuid_cmd="tune2fs -U $uuid $bdev"
            ;;
            
            ext3)
                flags="-F"
                test -z "$bsize" || flags="$flags -b $bsize"
                test -z "$isize" || flags="$flags -I $isize"
                test -z "$label" || flags="$flags -L $label"
                test -z "$uuid"  || uuid_cmd="tune2fs -U $uuid $bdev"
            ;;

            ext4)
                flags="-F"
                test -z "$bsize" || flags="$flags -b $bsize"
                test -z "$isize" || flags="$flags -I $isize"
                test -z "$label" || flags="$flags -L $label"
                test -z "$uuid"  || uuid_cmd="tune2fs -U $uuid $bdev"
            ;;

            reiserfs)
                flags="-f"            
                test -z "$bsize" || flags="$flags -b $bsize"
                test -z "$uuid"  || flags="$flags -u $uuid"
                test -z "$label" || flags="$flags -l $label"
            ;;

            reiser4)
                flags="-fy"            
                test -z "$bsize" || flags="$flags -b $bsize"
                test -z "$uuid"  || flags="$flags -U $uuid"
                test -z "$label" || flags="$flags -L $label"
            ;;
            
            swap)
                igx_log "Swap Device $bdev is ignored!"
                continue
            ;;
            
            *)
                igx_log "ERROR: Support for FS $fs is not available, ABORT!"
                return 1
            ;;
            
        esac
        
        igx_log "Creating filesystem \"$fs\" on device $bdev"
        mkfs.${fs} $flags "$bdev"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot create $fs on $bdev, ABORT"
            igx_log "Please create manual and restart restore like described below!"
            return 1
        else
            igx_log "Filesystem $fs successully created on $bdev!"
        fi

        if [ ! -z "$uuid_cmd" ]; then
            $uuid_cmd
            if [ $? -ne 0 ]; then
                igx_log "ERROR: Cannot set UUID on $fs on $bdev, ABORT"
                igx_log "Please set the UUID=$uuid manual and restart restore like described below!"
                return 1
            else
                igx_log "Filesystem $fs successully created on $bdev!"
            fi
        fi
        
    done
    
    return 0
}

#
# Mounting blank new disks in temporary mountpoint by using $IGX_SYSCONF_FILE
#
restore_mount()
{
    igx_log "Mounting all Filesystem in /mnt"
    
    mounts="$(awk -F ';' '/^fs/ { if($3 != "swap") print $2 ";/mnt" $4 " "; }' $IGX_SYSCONF_FILE | sort -t ';' -k 2)"
    if [ -z "$mounts" ]; then
        igx_log "ERROR: No devices found to mount!"
        return 1
    fi
    
    for mount in $mounts; do
    
        bdev="$(echo $mount | awk -F ';' '{ print $1; }')"
        mp="$(echo $mount | awk -F ';' '{ print $2; }')"
        
        igx_log "Creating mountpoint $mp"
        mkdir -p "$mp"
        
        igx_log "Mounting $bdev on $mp"
        mount "$bdev" "$mp"
        
        if [ $? -ne 0 ]; then
            igx_log "ERROR: Cannot mount $bdev on $mp, ABORT!"
            igx_log "Please create manual and restart restore like described below!"
            return 2
        else
            igx_log "Device $bdev successfully mounted on $mp! (go ahead in 4 sec.)"
            sleep 4
        fi

    done
    
    return 0
}

#
# Mount nfs filesystem to got recovery archive
#
init_backend()
{
    igx_log "Initializing restore backend"
    
    if [ ! -f "$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf" ]; then
        igx_log "ERROR: Cannot find $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 1
    fi
    
    IGX_BACKEND_MOD="$(awk -F '#' '/MOD/ { print $2; }' $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf)"
    IGX_BACKEND_URL="$(awk -F '#' '/URL/ { print $2; }' $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf)"
    IGX_BACKEND_IMG="$(awk -F '#' '/IMG/ { print $2; }' $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf)"

    if [ -z "$IGX_BACKEND_MOD" ]; then
        igx_log "ERROR: Cannot find backend module name in $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 2
    fi
    
    if [ -z "$IGX_BACKEND_URL" ]; then
        igx_log "ERROR: Cannot find backend url in $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 3
    fi
    
    if [ -z "$IGX_BACKEND_IMG" ]; then
        igx_log "ERROR: Cannot find backend image url/name in $IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/backend.conf, ABORT!"
        return 4
    fi
    
    igx_log "Restore backend is \"$IGX_BACKEND_MOD\" and will be used to get image content"
    igx_log "Trying to load backend $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD ..."
    
    if [ ! -f "$IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD" ]; then
        igx_log "ERROR: Cannot find/access restore module $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD, ABORT!"
        return 5
    fi
    
    . "$IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD"
    
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Load of $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD failure, ABORT!"
        return 6
    fi

    igx_log "Restore backend $IGX_BIN_DIR/restore/backends/$IGX_BACKEND_MOD successfully loaded!"
    igx_log "Running backend init() function"
    
    igx_restore_backend_init
    bret=$?
    
    if [ $bret -ne 0 ]; then
        igx_log "ERROR: Backend init() function exit with $bret, ABORT!"
        return 7
    fi
    
    return 0
}
#
# Function bind the backend by calling backend bind() function
#
bind_backend()
{
    igx_log "Executing backend $IGX_BACKEND_MOD bind() functions"
    
    igx_restore_backend_bind "$IGX_BACKEND_URL"
    bret=$?
    
    if [ $bret -ne 0 ]; then
        igx_log "ERROR: Backend bind() function exit with $bret, ABORT!"
        return 1
    fi
    
    return 0
}

#
# Function extract content from $IGX_BACKEND_IMG file
#
restore_filesystems()
{
    igx_log "Restoreing filesystems (extracting backup archive content)"
        
    igx_log "Changing directory to /mnt"
    
    cd /mnt
    if [ "$(pwd)" != "/mnt" ]; then
        igx_log "ERROR: Cannot change to directory /mnt, ABORT!"
        cd $OLDPWD
        return 2
    fi
        
    igx_log "Using backend $IGX_BACKEND_MOD run() function to get plain archive content"
    igx_restore_backend_run "$IGX_BACKEND_IMG" | /bin/cpio -imduv 2>&1 | dialog --aspect 1 --backtitle "$IGX_VERSION" --title "Ignite-LX Filesystem Restore (Archive Extract)" --progressbox 20 60

    if [ $? -ne 0 ]; then
        igx_log "ERROR: Archive $IGX_BACKEND_IMG not successfully extracted, ABORT!"
        igx_log "       Possible that backend $IGX_BACKEND_MOD run() function failure!"
        cd $OLDPWD
        return 3
    else
        igx_log "Archvie $IGX_BACKEND_IMG successfully extarcted!"
    fi
    
    cd $OLDPWD
    
    igx_log "Backend $IGX_BACKEND_MOD end() function is called later if restore is fully complete!"
    
    return 0
}

#
# Fix grub installation on boot disks list in $IGX_SYSCONF_FILE
#
restore_grub()
{
    igx_log "Running grup-install on boot devices"

    if [ ! -x /mnt/sbin/grub-install -a ! -x /mnt/usr/sbin/grub-install ]; then
        igx_log "ERROR: grub-install not found, maybe that system cannot boot!"
        igx_log "Update boot loader manual or leave it!"
        return 1
    fi
    
    bdisks="$(awk -F ';' '/^boot/ { print $2 " "; }' $IGX_SYSCONF_FILE)"
    if [ -z "$bdisks" ]; then
        igx_log "SUSPECT: No boot devices are found, step is skipped!"
        return 0
    fi
    
    igx_log "Moving /dev temporary to /mnt/dev"
    mount -o move /dev /mnt/dev
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot move /dev mountpoint, ABORT!"
        return 3
    else
        igx_log "Mountpoint /dev successfully moved to /mnt/dev"
    fi
    
    for disk in $bdisks; do
        echo $disk | egrep '.*[[:digit:]]$' > /dev/null
        if [ $? -eq 0 ]; then
            igx_log "IGNORE: Device $disk is a partion and ignored!"
            continue
        fi

        igx_log "Calling grub-install (using chroot as wrapper) on device $disk"
        chroot /mnt sh -c "grub-install $disk"
        if [ $? -ne 0 ]; then
            igx_log "ERROR: grub-install $disk failed, ABORT"
            igx_log "Please install / update boot loader manually!"
            return 2
        else
            igx_log "Restore of boot loader on $disk successful!"
        fi
    done
    
    igx_log "Moving /mnt/dev back to /dev"
    mount -o move /mnt/dev /dev
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot move /mnt/dev mountpoint, ABORT!"
        return 4
    else
        igx_log "Mountpoint /mnt/dev successfully moved to /dev"
    fi
    
    return 0
}

#
# Function execute seq. all the recovery steps.
#
run()
{
    step_ret=0
    repeat_step=0
    
    for step in $IGX_RECOVERY_STEPS; do
    
        while true; do
        
            repeat_step=0
            
            igx_log "----------------------------------------------------------------------------"
            igx_log "RUN STEP: $step"
            igx_log "----------------------------------------------------------------------------"
            igx_log " "
        
            sleep 1
    
            case "$step" in
                                    
                modules)
                    load_modules
                    panic "modules"
                    step_ret=$?
                ;;
            
                udev)
                    start_udev
                    panic "udev"
                    step_ret=$?
                ;;
            
                hostname)
                    restore_hostname
                    panic "hostname"
                    step_ret=$?
                ;;
            
                network)
                    restore_network
                    panic "network"
                    step_ret=$?
                ;; 
            
                init_backend)
                    init_backend
                    panic "init_backend"
                    step_ret=$?
                ;; 

                bind_backend)
                    bind_backend
                    panic "bind_backend"
                    step_ret=$?
                ;; 
            
                mbr)
                    restore_mbr
                    panic "mbr"
                    step_ret=$?
                ;; 
            
                raid)
                    restore_raid
                    panic "raid"
                    step_ret=$?
                ;;
            
                lvm)
                    restore_lvm
                    panic "lvm"
                    step_ret=$?
                ;;
            
                mkfs)
                    restore_mkfs
                    panic "mkfs"
                    step_ret=$?
                ;;
            
                mount_fs)
                    restore_mount
                    panic "mount_fs"
                    step_ret=$?
                ;; 
            
                extract)
                    restore_filesystems
                    panic "extract"
                    step_ret=$?
                ;;

                grub)
                    restore_grub
                    panic "grub"
                    step_ret=$?
                ;;
            
                *)
                    igx_log "ERROR: Recovery step \"$step\" not implemented yet, ABORT!"
                    false
                    panic "$step"
                    return 1
                ;;
        
            esac
        
            if [ $step_ret -ne 0 ]; then
                igx_menu_yesno "Continue Restore?"   || break 2
                igx_menu_yesno "Repeat step: $step?" && repeat_step=1
            else
                igx_log "----------------------------------------------------------------------------"
                igx_log "END STEP: $step (go ahead in 3 secs.)"
                igx_log "----------------------------------------------------------------------------"
                igx_log " "
                sleep 3
            fi
            
            if [ $repeat_step -eq 0 ]; then
                break
            fi

        done
        
    done
    
    if [ $step_ret -eq 0 ]; then
        igx_menu_yesno "Ignite Finish! Quit?" || igx_shell
    else
        igx_menu_yesno "Ignite Errors! Quit?" || igx_shell
    fi
    
    return $ret
}

#
# Cleanup function for signal handling
#
cleanup()
{
    retval=$?
    exit $retval
}

#
# This function is execute if the script is called
#
main()
{
    usage $@    || return 1
    igx_chkenv  || return 2
    
    trap cleanup 2 15
    
    if [ ! -f /tmp/run_igx_resotre.tmp ]; then
        igx_log "ABORT: It seems you want to restore on a running Operating System, ABORT!"
        return 100
    fi 

    igx_log "Starting disaster recovery at $(igx_date)"
    
    run
    retval=$?
    
    igx_log "End of disaster recovery at $(igx_date)"
    
    if [ $retval -eq 0 ]; then
        igx_log "FINAL RESTORE STATUS: SUCCESS!"
    else
        igx_log "FINAL RESTORE STATUS: FAILED!"
    fi
    
    igx_restore_backend_log "$IGX_LOG_DIR/$IGX_LOG" || igx_shell
    igx_log "Calling backend $IGX_BACKEND end() function to finish backend usage"
    igx_restore_backend_end "$IGX_BACKEND_URL"      || igx_shell
        
    umount -a 2> /dev/null
    
    return $retval
}

#
# Execute the script by calling main() and poweroff afterwards
#
main $@
poweroff -f 
