#!/bin/bash

# make_config.sh
# 
#
# Created by Daniel Faltin on 18.10.10.
# Copyright 2010 D.F. Consulting. All rights reserved.


# 
# Globals of make_config.sh
#
IGX_COMMON_INCL="bin/common/ignite_common.inc"
IGX_DEVICES=""
IGX_CONFGSET_NAME=""
IGX_CONFGSET_FILE=""

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
    while getopts "dhv" opt; do
        case "$opt" in
            d)
                set -x
            ;;
            
            v)
                IGX_VERBOSE=1
            ;;
            
            h|*)
                igx_stderr "$IGX_VERSION"
                igx_stderr "usage: make_config.sh [-dhv] <device/vg, ...> <config name>"
                igx_stderr "-h print this screen"
                igx_stderr "-d enable script debug"
                igx_stderr "-v verbose"
                igx_stderr ""
                igx_stderr "Example:"
                igx_stderr "make_config.sh /dev/md0 vg00 myhost_20100901"
                return 1
            ;;
        esac
    done
    
    shift $((OPTIND - 1))
    
    ARGV="$@"
    ARGC=$#

    if [ -z "$ARGV" ]; then
        igx_stderr "ERROR: Missing arguments, ABORT!"
        usage -h
        return 1
    fi

    i=0
    for arg in $ARGV; do
        if [ $i -eq $((ARGC - 1)) ]; then
            IGX_CONFGSET_NAME="$arg"
            break
        else
            IGX_DEVICES="$IGX_DEVICES $arg"
        fi
        i=$((i + 1))
    done
    
    if [ -z "$IGX_DEVICES" -o -z "$IGX_CONFGSET_NAME" ]; then
        igx_stderr "ERROR: Argument <device/vg, ...> <config name> is required!"
        return 1
    fi
    
    if [ ! -d "$IGX_CONFIG_DIR" ]; then
        igx_stderr "ERROR: Directory \"$IGX_CONFIG_DIR\" where current system configuration should located does not exists!"
        return 2
    fi
    
    if [ -d "$IGX_CONFIG_DIR/$IGX_CONFGSET_NAME" ]; then
        igx_stderr "ERROR: Configuration set $IGX_CONFGSET_NAME already exists, ABORT!"
        return 3
    else
        mkdir -p "$IGX_CONFIG_DIR/$IGX_CONFGSET_NAME"
    fi
    
    IGX_CONFGSET_FILE="$IGX_CONFIG_DIR/$IGX_CONFGSET_NAME/sysconfig.info"
    
    return 0
}

#
# This function return disks devices where a boot sector is installed
# written in $IGX_CONFGSET_FILE: boot;<disk>;<boot dump file>;<fdisk file>;<disk id by-path>
#
get_boot_disks()
{
    disk="$1"
    disks=""
    disk_masters="$(echo $disk | sed 's/[[:digit:]]\{1,\}$//g')"
    disk_masters="$disk_masters $(echo $disk | sed 's/[a-z][[:digit:]]\{1,\}$//g')"
    
    igx_verbose "Searching for boot sector on device: $disk"
    
    if [ -z "$disk" ]; then
        igx_log "ERROR: Function Argument <disk device> is missing"
    fi
    
    if [ ! -b "$disk" ]; then
        igx_verbose "Device $disk is not a valid disk device and is ignored!"
        return 0
    fi
    
    for mdisk in $disk_masters; do
        if [ -b "$mdisk" ]; then
            igx_verbose "Disk $mdisk (parent of $disk) will be checked as well for boot sectors."
            disks="$disks $mdisk"
        fi
    done

    if [ -z "$disks" ]; then
        if [ -b "$disk" ]; then
            disks="$disk"
        fi
    else
        if [ -b "$disk" ]; then
            disks="$disks $disk"
        fi
    fi

    for bdev in $disks; do
    
        dd 2> /dev/null if=$bdev bs=512 count=1 | file 2> /dev/null - | grep -i 'boot sector' > /dev/null
        if [ $? -eq 0 ]; then
            igx_verbose "Device $bdev contains a boot sector, a backup will created."
            boot_dump="$IGX_CONFIG_DIR/$IGX_CONFGSET_NAME/boot.$(basename $bdev)"
            fdisk_dump="$IGX_CONFIG_DIR/$IGX_CONFGSET_NAME/fdisk.$(basename $bdev)"
            
            grep "boot;$bdev;boot.$(basename $bdev);fdisk.$(basename $bdev)" $IGX_CONFGSET_FILE > /dev/null
            if [ $? -eq 0 ]; then
                igx_verbose "Device $bdev already listed in $(basename $IGX_CONFGSET_FILE), no activities are required."
                continue
            fi
            
            dd if=$bdev of="$boot_dump" bs=512 count=1 > /dev/null 2> /dev/null
            if [ $? -ne 0 ]; then
                igx_log "ERROR: Cannot read from device $bdev, ABORT!"
                return 1
            fi 
            
            fdisk -l $bdev | egrep "^$bdev" > "$fdisk_dump"
            if [ $? -ne 0 ]; then
                echo "$bdev" | egrep '.*[[:digit:]]$' > /dev/null
                if [ $? -ne 0 ]; then
                   igx_log "ERROR: Cannot get partition table from device $bdev, ABORT!"
                   return 2
                fi 
            fi 
            
            echo "boot;$bdev;boot.$(basename $bdev);fdisk.$(basename $bdev);$(igx_disk_bypath $bdev)" >> $IGX_CONFGSET_FILE

            if [ "$(fdisk -l $bdev 2> /dev/null | awk '/Extended/ { print $NF }')" = "Extended" ]; then
                ebdev="$(fdisk -l $bdev | awk '/Extended/ { print $1 }')"
                igx_verbose "Device $bdev has a extended DOS partion ($ebdev), additional boot sector added..."
                get_boot_disks "$ebdev"
            fi
        
        else
            igx_verbose "Device $disk does not contain a boot sector and is ignored!"
        fi

    done
    
    return 0
}

#
# This function get all phyiscal disks used by a Volume Group
# written in $IGX_CONFGSET_FILE: pv;<vg>;<disk>;<pvid>
#
get_vg_disks() 
{
    vg="$1"
    
    igx_verbose "Trying to inquire volume group devices for $vg..."
    
    if [ -z "$vg" ]; then
        igx_log "ERROR: Function Argument <vg> is missing"
    fi
    
    igx_is_vg "$vg"
    if [ $? -ne 0 ]; then
        igx_verbose "Device $vg is not a volume group and is ignored!"
        return 0
    fi
    
    test -f /var/tmp/pvs && rm -f /var/tmp/pvs
    
    vgdisplay 2> /dev/null --partial --verbose "$vg" | awk '
    BEGIN { 
    
        idx          = 0; 
        vg           = ""; 
        pv[idx]      = ""; 
        pv_uuid[idx] = ""; 
        
    } 
    {
    
        if($0 ~ /VG Name/)
            vg = $NF;
            
        if($0 ~ /PV Name/)
            pv[idx] = $NF;
            
        if($0 ~ /PV UUID/) 
            pv_uuid[idx++] = $NF;

    } 
    END { 
    
        for(i = 0; i < idx; i++)
            printf("pv;%s;%s;%s\n", vg, pv[i], pv_uuid[i]);
            
        for(i = 0; i < idx; i++)
            print pv[i] >> "/var/tmp/pvs";
            
        if(idx == 0) 
            exit(1);

        close("/var/tmp/pvs");
            
        exit(0); 
    
    }' >> $IGX_CONFGSET_FILE
    
    if [ $? -eq 0 ]; then
        igx_verbose "Infos for $vg successfuly inquired."
        igx_verbose "Calling vgcfgbackup $vg"
        vgcfgbackup 2>&1 "$vg" | igx_log
    else
        igx_log "ERROR: Failed to get infos for $vg, ABORT!"
        return 2
    fi
    
    if [ -f "/var/tmp/pvs" ]; then
        while read dev; do
            get_boot_disks "$dev"
            get_md_disks "$dev"
        done < /var/tmp/pvs
        rm -f /var/tmp/pvs
    fi
        
    return 0
}

#
# This function get all physical md device disks
# written in $IGX_CONFGSET_FILE: md;<md>;<disk>;<level>;<num of devs>;<size>;<uuid>
#
get_md_disks()
{
    md="$1"
    
    igx_verbose "Trying to get md infos for device $md..."
    
    if [ -z "$md" ]; then
        igx_log "ERROR: Function Argument <md device> is missing"
    fi
    
    valid=0
    for dev in $md; do
        if [ -b "$md" ]; then
            valid=1
            break
        fi
        if [ -b "/dev/$md" ]; then
            md="/dev/$md"
            valid=1
            break
        fi
    done
    
    if [ $valid -eq 0 ]; then
        igx_verbose "Device $md is not a valid block device and is ignored!"
        return 0
    fi 
    
    test -f /var/tmp/pvs2 && rm -f /var/tmp/pvs2
    
    mdadm 2> /dev/null --misc -D $md | awk '
    BEGIN { 

        idx       = 0;     
        md        = ""; 
        level     = ""; 
        num       = "";
        size      = ""; 
        uuid      = ""; 
        disk[idx] = ""; 
        
    } 
    {

        if($0 ~ /^\/dev\/md/) {
            gsub(":", "", $0);
            md = $NF;
        }
            
        if($0 ~ /Raid Level/)
            level = $NF;
            
        if($0 ~ /Raid Devices/)
            num = $NF;
            
        if($0 ~ /Array Size/)
            size = $4;
            
        if($0 ~ /UUID/)
            uuid = $NF;

        if($0 ~ /[[:digit:]].*dev/)
            disk[idx++] = $NF;
            
    } END { 
    
        for(i = 0; i < idx; i++)
            printf("md;%s;%s;%s;%s;%s;%s\n", md, disk[i], level, num, size, uuid);

        for(i = 0; i < idx; i++)
            print disk[i] >> "/var/tmp/pvs2";
                        
        if(idx == 0) 
            exit(1); 
            
        close("/var/tmp/pvs2");
            
        exit(0); 
        
    }' >> $IGX_CONFGSET_FILE
    
    if [ $? -ne 0 ]; then
        igx_verbose "Device $md is not a valid md device, is ignored!"
    fi
    
    if [ -f "/var/tmp/pvs2" ]; then
        while read dev; do
            get_boot_disks "$dev"
        done < /var/tmp/pvs2
        rm -f /var/tmp/pvs2
    fi
    
    igx_verbose "Infos for md device $md successfuly inquired."

    return 0
}

#
# This function get the current filesystem used on deliverd device 
# written in $IGX_CONFGSET_FILE: fs;<device>;<fstype>;<mountpoint>;<fs options, ...;...>
#
get_fs()
{
    blk="$1"
    
    igx_verbose "Getting filesystem for device $blk..."
    
    igx_is_disk "$blk"
    if [ $? -eq 0 ]; then
        fsopt="$(get_fs_options $blk)"
        igx_verbose "Looking up for mounted disk $blk using /proc/mounts and mount command"
        echo "$(mount; cat /proc/mounts)" | awk 'BEGIN { flag = 0; } 
        { 
            gsub(" on ", " ", $0);
            gsub(" type ", " ", $0);
            
            if($1 == "'$blk'") { 
                flag  = 1;
                printf("fs;%s;%s;%s;%s\n", "'$blk'", $3, $2, "'$fsopt'");
                exit(0);
            }
        } END { if(flag) exit(0); exit(1); }' >> $IGX_CONFGSET_FILE
        
        if [ $? -ne 0 ]; then
            igx_verbose "Device $blk currently not mounted, looking if device is a swap device"
            grep "^$blk" /proc/swaps > /dev/null
            if [ $? -eq 0 ]; then
                igx_verbose "Device $blk found as swap device!"
                echo "fs;$blk;swap;none" >> $IGX_CONFGSET_FILE
                return 0
            else
                igx_verbose "No filesystem or swap on $blk found!"
            fi
        else
            get_boot_disks "$blk"
        fi
    fi
    
    igx_is_vg "$blk"
    if [ $? -eq 0 ]; then
        for lv in /dev/mapper/$(basename $blk)*; do
            fsopt="$(get_fs_options $lv)"
            igx_verbose "Looking up for mounted logical volume $lv using /proc/mounts and mount command"
            echo "$(mount; cat /proc/mounts)" | awk 'BEGIN { flag = 0; } 
            { 
                gsub(" on ", " ", $0);
                gsub(" type ", " ", $0);
                
                if($1 == "'$lv'") { 
                    flag  = 1;
                    printf("fs;%s;%s;%s;%s\n", "'$lv'", $3, $2, "'$fsopt'");
                    exit(0); 
                }
            } END { if(flag) exit(0); exit(1); }' >> $IGX_CONFGSET_FILE
            
            if [ $? -ne 0 ]; then
                igx_verbose "Device $lv currently not mounted, looking if device is a swap device"
                grep "^$lv" /proc/swaps > /dev/null
                if [ $? -eq 0 ]; then
                    igx_verbose "Device $lv found as swap device!"
                    echo "fs;$lv;swap;none" >> $IGX_CONFGSET_FILE
                else
                    igx_verbose "No filesystem or swap on $lv found!"
                fi
            else
                igx_verbose "Logical Volume $lv found and successfully inquired"
            fi
        done
    fi

    return 0
}

#
# Extend and print the filesystem options for creation (mkfs)
# Arguments: <dev>
# Print out on stdout: <block size>;<inode size>;<uuid>;<label>
#
get_fs_options()
{
    fs_opt_dev="$1"
    fs_opt_type=""
    fso_retv=0
    
    if [ -z "$fs_opt_dev" ]; then
        igx_log "ERROR: get_fs_options() missing arguments, ABORT!"
        return 1
    fi
    
    igx_verbose "Requesting filesystem details for $fs_opt_dev..."
    
    echo "$(mount; cat /proc/mounts)" | awk 'BEGIN { flag = 0; } 
    { 
        gsub(" on ", " ", $0);
        gsub(" type ", " ", $0);
                
        if($1 == "'$fs_opt_dev'") { 
            flag = 1;
            printf("%s\n", $3);
            exit(0); 
        }
    } END { if(flag) exit(0); exit(1); }' > /tmp/fsopt.tmp
    
    if [ $? -ne 0 ]; then
        igx_log "WARNING: Cannot get FSType of $fs_opt_dev, assuming device as swap!"
        fs_opt_type="swap"
    else
        fs_opt_type="$(cat /tmp/fsopt.tmp)"
        rm -f /tmp/fsopt.tmp
    fi
    
    case "$fs_opt_type" in
    
            xfs)
                if [ ! -x /usr/sbin/xfs_info -o ! -x /usr/sbin/xfs_admin ]; then
                    igx_log "ERROR: Cannot find/execute /usr/sbin/xfs_info or /usr/sbin/xfs_admin, ABORT!"
                    return 2
                fi
                                
                xfs_info "$fs_opt_dev" | awk '{
                    gsub(",", " ", $0);
                    if($0 ~ /data.*bsize=/)
                        for(n = 1; n < NF; n++)
                            if($n ~ /bsize=/) {
                                split($n, v, "=");
                                printf("%s;", v[2]);
                                break;
                            }
                }'

                xfs_info "$fs_opt_dev" | awk '{
                    gsub(",", " ", $0);
                    if($0 ~ /isize=/)
                        for(n = 1; n < NF; n++)
                            if($n ~ /isize=/) {
                                split($n, v, "=");
                                printf("%s;", v[2]);
                                break;
                            }
                }'
                
                xfs_admin -u "$fs_opt_dev" | awk '/=/ { gsub("\"", "", $0); printf("%s;", $NF);  }'
                xfs_admin -l "$fs_opt_dev" | awk '/=/ { label = $NF; gsub("\"", "", label); printf("%s", label); }'
                fso_retv=$?
            ;;
            
            ext|ext2|ext3|ext4)
                if [ ! -x /sbin/dumpe2fs -o ! -x /sbin/dumpe2fs ]; then
                    igx_log "ERROR: Cannot find/execute /sbin/dumpe2fs, ABORT!"
                    return 2
                fi
                
                dumpe2fs 2> /dev/null "$fs_opt_dev" | awk '/Block size:/             { printf("%s;", $NF); }'
                dumpe2fs 2> /dev/null "$fs_opt_dev" | awk '/Inode size:/             { printf("%s;", $NF); }'
                dumpe2fs 2> /dev/null "$fs_opt_dev" | awk '/Filesystem UUID:/        { printf("%s;", $NF); }'
                dumpe2fs 2> /dev/null "$fs_opt_dev" | awk '/Filesystem volume name:/ { if($0 !~ /</) printf("%s", $NF); }'
                fso_retv=$?
            ;;

            reiserfs)
                if [ ! -x /sbin/reiserfstune ]; then
                    igx_log "ERROR: Cannot find/execute /sbin/reiserfstune, ABORT!"
                    return 2
                fi
                
                reiserfstune "$fs_opt_dev" | awk '/Blocksize:/ { printf("%s;", $NF); }'
                printf ";"                
                reiserfstune "$fs_opt_dev" | awk '/UUID:/ { printf("%s;", $NF); }'
                reiserfstune "$fs_opt_dev" | awk '/LABEL:/ { printf("%s", $NF); }'
                fso_retv=$?
            ;;
            
            swap)
                igx_log "No filesystem detailes for $fs_opt_dev, devices is ignored!"
                echo ";;;"
            ;;
            
            *)
                igx_log "ERROR: Support for FS $fs_opt_type is not available, ABORT!"
                return 1
            ;;
            
    esac
    
    if [ $fso_retv -ne 0 ]; then
        igx_log "ERROR: A error is occurred while requesting FS options, ABORT!"
    else
        igx_verbose "Filesystem details for $fs_opt_dev (type $fs_opt_type) successfully requested."
    fi
    
    return $fso_retv
}

#
# Function print on stdout a classic subnet mask in oct. style
# Argument <network prefix>
# Return: 0 on success otherwise a not 0 value
#
get_subnetmask()
{
    bit=$1
    pos=7
    oct=0
    idx=0

    subnetmask[0]=0
    subnetmask[1]=0
    subnetmask[2]=0
    subnetmask[3]=0

    if [ -z "$bit" ]; then
        igx_log "ERROR: get_subnetmask() missing function argument, ABORT!"
        return 1
    fi

    echo $bit | egrep '[[:digit:]]{1}' > /dev/null
    if [ $? -ne 0 ]; then
        igx_log "ERROR: get_subnetmask() invalid function argument, ABORT!"
        return 1
    fi
    
    if [ $bit -lt 0 -o $bit -gt 32 ]; then
        igx_log "ERROR: get_subnetmask() invalid function argument, ABORT!"
        return 1
    fi

    while [[ $bit -gt 0 ]]; do
        oct=$(( oct + (1 <<  $pos) ))
        if [ $pos -eq 0 ]; then
            subnetmask[$idx]=$oct
            oct=0
            pos=8
            idx=$((idx + 1))
        fi
        pos=$((pos - 1))
        bit=$((bit - 1))
    done

    subnetmask[$idx]=$oct
    echo "${subnetmask[0]}.${subnetmask[1]}.${subnetmask[2]}.${subnetmask[3]}"

    return 0
}

#
# This function gather the network configuration for all ethX interfaces
# written in $IGX_CONFGSET_FILE: net;<dev>;<ip>;<netmask>;<extended flags> and route;<ip route line with gateway>
#
get_network()
{
    igx_verbose "Getting network informations for configured ethernet (eth) and bonding (bond) devices"
    
    for sys_dev in /sys/class/net/eth* /sys/class/net/bond*; do
    
        if [ ! -d "$sys_dev" ]; then
            continue
        fi 
        
        dev="$(basename $sys_dev)"
        igx_verbose "Getting configuration for device $dev"
        
        ip addr show $dev | awk '{
        
            if($0 ~ /inet /)  {
                ip  = $2;
                net = $2;
                                
                gsub("/.*", "", ip);
                gsub(".*/", "", net);
                
                if(net ~ /\./)
                    net = 32;
                
                printf("%s %s\n", ip, net);
                exit(0);
            }
            
        }' | while read ip net_prefix; do
        
            netmask="$(get_subnetmask $net_prefix)"
            igx_verbose "Device $dev is configured with $ip/$netmask"
            printf "net;%s;%s;%s;" "$dev" "$ip" "$netmask" >> $IGX_CONFGSET_FILE
            
            echo "$dev" | egrep "bond[0-9]{1,}$" > /dev/null
            if [ $? -eq 0 ]; then
               mode="$(awk '{ print $NF; }' $sys_dev/bonding/mode)"
               slaves="$(cat $sys_dev/bonding/slaves)"
               igx_verbose "Device $dev is a bonding interface, with mode $mode (devices $slaves)"
               printf "%s:%s\n" "$mode" "$slaves" >> $IGX_CONFGSET_FILE
            else
                printf "\n" >> $IGX_CONFGSET_FILE
            fi

            echo "$dev" | egrep ".*\.[0-9]{1,}$" > /dev/null
            if [ $? -eq 0 ]; then
               vlan="$(echo $dev | awk -F. '{ print $NF; }')"
               sys_dev_new="$(echo $sys_dev | sed 's/\.[[:digit:]]\{1,\}//g')"
               igx_verbose "Device $dev is a vlan interface with vlan-id $vlan"
               printf "vlan;%s;%s;%s\n" "$dev" "$(echo $dev | sed 's/\.[[:digit:]]\{1,\}//g')" "$vlan" >> $IGX_CONFGSET_FILE
            fi
            
        done
        
    done
           
    igx_verbose "Getting routing table..."
    ip route list | awk '/via/ { printf("route;%s\n", $0); }' >> $IGX_CONFGSET_FILE
    if [ $? -ne 0 ]; then
        igx_log "ERROR: Cannot request routing table while using 'ip route list' command, ABORT!"
        return 1
    else
        igx_verbose "Routing table informations successfully requested."
    fi
    
    return 0
}

#
# Function simply get the hostname
# written in $IGX_CONFGSET_FILE: hostname;<hostname>
#
get_hostname()
{
    igx_verbose "Getting hostname"
    printf "hostname;%s\n" "$(hostname)" >> $IGX_CONFGSET_FILE
    return $?
}

#
# Function simply get all loaded kernel modules
# written in $IGX_CONFGSET_FILE: module;<mod>
#
get_kernmod()
{
    igx_verbose "Getting loaded kernel modules"
    lsmod | sort -n -k3 | awk '!/^Module/ { print "module;"$1; }' >> $IGX_CONFGSET_FILE
    return $?
}

#
# This function is execute if the script is called
#
main()
{
    usage $@   || return 1
    igx_chkenv || return 2
    
    for arg in $IGX_DEVICES; do
        get_vg_disks $arg || return 1
        get_md_disks $arg || return 2
        get_fs $arg       || return 3
    done
    
    get_hostname || return 5    
    get_network  || return 6
    get_kernmod  || return 7
    
    igx_set_imgid "$IGX_CONFIG_DIR/$IGX_CONFGSET_NAME"
    
    return 0
}

#
# Execute the script by calling main()
#
main $@
exit $?
