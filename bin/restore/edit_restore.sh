#!/bin/sh

# edit_restore.sh
# 
#
# Created by Daniel Faltin on 06.11.10.
# Copyright 2010 D.F. Consulting. All rights reserved.

# 
# Globals of edit_restore.sh
#
IGX_CONFIGSET_NAME="$1"
IGX_SYSCONF_FILE="$IGX_CONFIG_DIR/$IGX_CONFIGSET_NAME/sysconfig.info"
IGX_SYSCONF_DIR="$(dirname $IGX_SYSCONF_FILE)"
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
# Display the Advanced setting menu
#
menu_advance()
{
    tmp_out="/tmp/select"

    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit Restore Settings" \
                --cancel-label "Back" \
                --menu "Choose one of the menu points" 14 50 8 \
                        1 "Edit Network Interfaces" \
                        2 "Edit Network Routes" \
                        3 "Edit Boot Disks (restore MBR)" \
                        4 "Edit LVM (pv) Disks" \
                        5 "Edit Raid (md) Disks" \
                        6 "Edit FS & Devices" \
                        7 "GO! (start restore)" > $tmp_out

    item="$(cat $tmp_out)"
    rm -f $tmp_out

    if [ -z "$item" ]; then
        return 0
    fi
    
    return $item
}

#
# Display a dialog if invalid CHARS included
# On success 0 is returned otherwise 1
#
menu_check_char_invalid()
{
    echo "$@" | egrep '[ &_%"$§?:)(\\]' > /dev/null
    if [ $? -eq 0 ]; then
        igx_menu_errmsg "Chars in: \"$item\" not valid!"
        return 1
    fi

    return 0
}

#
# Edit the "net" lines in $IGX_SYSCONF_FILE
#
menu_edit_network()
{
    y=1
    tmp_out="/tmp/select"
    dialog_args=""
    IFSOLD="$IFS"

    IFS=";"
    while read kind dev ip mask flags; do
        
        if [ "$kind" != "net" ]; then
            continue
        fi
        
        if [ -z "$ip" -o -z "$mask" -o -z "$dev" ]; then
            continue
        fi
        
        if [ -z "$flags" ]; then
            flags="none"
        fi 
                
        dialog_args=''$dialog_args'
                     DEV    '$y'  2 '$dev'   '$y'  6  6 0
                     IP     '$y' 13 '$ip'    '$y' 16 16 0
                     MASK   '$y' 33 '$mask'  '$y' 38 16 0
                     FLAGS  '$y' 55 '$(echo $flags | sed -e 's/ $//g' -e 's/ /_/g')' '$y' 61 11 40'
        
        y=$((y + 2))
        
    done < "$IGX_SYSCONF_FILE"
    IFS="$IFSOLD"
    
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit Network Interfaces" \
                --form "Use [up] [down] to select input field " 15 80 8 \
                $dialog_args > $tmp_out

    if [ -z "$(cat $tmp_out)" ]; then
        rm -f $tmp_out
        return 0
    fi
    
    sed -e '/^net;/d' -e '/^$/d' "$IGX_SYSCONF_FILE" > "$IGX_SYSCONF_FILE.tmp"
    
    obj=1
    values_ok=1
    while read item; do
        
        case $obj in
            1)
                printf "net;$item"
            ;;
            
            4)
                obj=0
                if [ -z "$item" -o "$item" = "none" ]; then
                    printf ";\n"
                else
                    item="$(echo $item | sed -e 's/ $//g' -e 's/_/ /g')"
                    printf ";$item\n"
                fi
            ;;
            
            *)
                igx_is_ip "$item"
                if [ $? -ne 0 ]; then
                    values_ok=0
                    igx_menu_errmsg "Invalid: $item"
                    break
                fi
                printf ";$item"
            ;;
        esac
        
        obj=$((obj + 1))
    
    done < $tmp_out >> "$IGX_SYSCONF_FILE.tmp"
    
    if [ $values_ok -eq 1 ]; then
        mv "$IGX_SYSCONF_FILE.tmp" "$IGX_SYSCONF_FILE"
    fi
    
    rm -f $tmp_out

    return 0
}

#
# Edit the "route" lines in $IGX_SYSCONF_FILE
#
menu_edit_routes()
{
    y=1
    tmp_out="/tmp/select"
    dialog_args=""
    IFSOLD="$IFS"

    IFS=";"
    while read kind route_arg; do
        
        if [ "$kind" != "route" ]; then
            continue
        fi

        net="$(echo $route_arg | awk '{ split($0, val, " "); print val[1]; }')"
        gw="$(echo $route_arg | awk '{ split($0, val, " "); print val[3]; }')"
        dev="$(echo $route_arg | awk '{ split($0, val, " "); print val[5]; }')"
        arg="$(echo $route_arg | awk '{ n = split($0, val, " "); for(i = 6; i <= n; i++) printf("%s ", val[i]); }')"
        
        if [ -z "$net" -o -z "$gw" -o -z "$dev" ]; then
            continue
        fi

        if [ -z "$arg" ]; then
            arg="none"
        else
            arg="$(echo $arg | sed -e 's/ $//g' -e 's/ /_/g')"
        fi
        
        dialog_args=''$dialog_args'
                     NET  '$y'  2 '$net'  '$y'  6 18 0
                     GW   '$y' 25 '$gw'   '$y' 28 16 0
                     DEV  '$y' 45 '$dev'  '$y' 49  5 10
                     ARG  '$y' 55 '$arg'  '$y' 59 16 50'
        
        y=$((y + 2))
        
    done < "$IGX_SYSCONF_FILE"
    IFS="$IFSOLD"
    
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit Network Routes" \
                --form "Use [up] [down] to select input field " 15 80 8 \
                $dialog_args > $tmp_out

    if [ -z "$(cat $tmp_out)" ]; then
        rm -f $tmp_out
        return 0
    fi
    
    sed -e '/^route;/d' -e '/^$/d' "$IGX_SYSCONF_FILE" > "$IGX_SYSCONF_FILE.tmp"
        
    obj=1
    values_ok=1
    while read item; do
        
        case $obj in
            1)
                igx_is_ip "$item"
                if [ $? -ne 0 -a "$item" != "default" ]; then
                    values_ok=0
                    igx_menu_errmsg "Invalid: $item"
                    break
                fi
                printf "route;$item"
            ;;
            
            2)
                igx_is_ip "$item"
                if [ $? -ne 0 ]; then
                    values_ok=0
                    igx_menu_errmsg "Invalid: $item!"
                    break
                fi
                printf " via $item"
            ;;

            3)
                printf " dev $item"
            ;;

            4)
                obj=0
                if [ -z "$item" -o "$item" = "none" ]; then
                    printf "\n"
                else
                    item="$(echo $item | sed -e 's/_$//g' -e 's/_/ /g')"
                    printf " $item\n"
                fi
            ;;
        esac
        
        obj=$((obj + 1))
    
    done < $tmp_out >> "$IGX_SYSCONF_FILE.tmp"
    
    if [ $values_ok -eq 1 ]; then
        mv "$IGX_SYSCONF_FILE.tmp" "$IGX_SYSCONF_FILE"
    fi
    
    rm -f $tmp_out

    return 0
}

#
# Edit the "boot" lines in $IGX_SYSCONF_FILE
#
menu_edit_bootdisk()
{
    y=1
    tmp_out="/tmp/select"
    dialog_args=""
    org_disks=""
    IFSOLD="$IFS"

    IFS=";"
    while read kind disk mbr_file fdisk_file; do
        
        if [ "$kind" != "boot" ]; then
            continue
        fi
        
        if [ -z "$disk" -o -z "$mbr_file" -o -z "$fdisk_file" ]; then
            continue
        fi
        
        org_disks="$org_disks $(basename $disk)"
        
        dialog_args=''$dialog_args'
                     Disk '$y'  2 '$disk'  '$y'  10 30 50'        
        y=$((y + 2))
        
    done < "$IGX_SYSCONF_FILE"
    IFS="$IFSOLD"
    
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit Boot Disks" \
                --form "Use [up] [down] to select input field " 15 50 8 \
                $dialog_args > $tmp_out

    if [ -z "$(cat $tmp_out)" ]; then
        rm -f $tmp_out
        return 0
    fi
    
    sed -e '/^boot;/d' -e '/^$/d' "$IGX_SYSCONF_FILE" > "$IGX_SYSCONF_FILE.tmp"
    
    obj=1
    values_ok=1
    while read item; do
    
        menu_check_char_invalid "$item" || values_ok=0
        
        new_disk="$(basename $item)"
        old_disk=$(echo $org_disks | awk '{ print $'$obj'; }')
        
        echo "boot;$item;boot.$new_disk;fdisk.$new_disk"
        
        test -f "$IGX_SYSCONF_DIR/boot.$old_disk"  && cp "$IGX_SYSCONF_DIR/boot.$old_disk" "$IGX_SYSCONF_DIR/boot.$new_disk"
        test -f "$IGX_SYSCONF_DIR/fdisk.$old_disk" && cp "$IGX_SYSCONF_DIR/fdisk.$old_disk" "$IGX_SYSCONF_DIR/fdisk.$new_disk"
        
        obj=$((obj + 1))
        
    done < $tmp_out >> "$IGX_SYSCONF_FILE.tmp"
    
    if [ $values_ok -eq 1 ]; then
        mv "$IGX_SYSCONF_FILE.tmp" "$IGX_SYSCONF_FILE"
    fi
    
    rm -f $tmp_out

    return 0
}

#
# Edit the "pv" lines in $IGX_SYSCONF_FILE
#
menu_edit_pvdisk()
{
    y=1
    tmp_out="/tmp/select"
    vg_org=""
    uuid_org=""
    dialog_args=""
    IFSOLD="$IFS"

    IFS=";"
    while read kind vg disk uuid; do
        
        if [ "$kind" != "pv" ]; then
            continue
        fi
        
        if [ -z "$disk" -o -z "$vg" -o -z "$uuid" ]; then
            continue
        fi
        
        vg_org="$vg_org $vg"
        uuid_org="$uuid_org $uuid"
        
        dialog_args=''$dialog_args'
                     VolumeGroup '$y'  2 '$vg'    '$y' 14 -10 50       
                     Disk        '$y'  25 '$disk' '$y' 30  30 50'        

        y=$((y + 2))
        
    done < "$IGX_SYSCONF_FILE"
    IFS="$IFSOLD"
    
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit VolumeGroup Disks" \
                --form "Use [up] [down] to select input field " 15 70 8 \
                $dialog_args > $tmp_out

    if [ -z "$(cat $tmp_out)" ]; then
        rm -f $tmp_out
        return 0
    fi

    sed -e '/^pv;/d' -e '/^$/d' "$IGX_SYSCONF_FILE" > "$IGX_SYSCONF_FILE.tmp"
    
    cnt=1
    values_ok=1
    while read item; do
    
        menu_check_char_invalid "$item" || values_ok=0
        
        uuid=$(echo $uuid_org | awk '{ print $'$cnt'; }')
        vg=$(echo $vg_org | awk '{ print $'$cnt'; }')
        
        echo "pv;$vg;$item;$uuid"
        
        cnt=$((cnt + 1))
        
    done < $tmp_out >> "$IGX_SYSCONF_FILE.tmp"
        
    if [ $values_ok -eq 1 ]; then
        mv "$IGX_SYSCONF_FILE.tmp" "$IGX_SYSCONF_FILE"
    fi
    
    rm -f $tmp_out

    return 0
}

#
# Edit the "md" lines in $IGX_SYSCONF_FILE
#
menu_edit_mddisk()
{
    y=1
    tmp_out="/tmp/select"
    type_org=""
    count_org=""
    size_org=""
    uuid_org=""
    dialog_args=""
    IFSOLD="$IFS"

    IFS=";"
    while read kind md disk type count size uuid; do
        
        if [ "$kind" != "md" ]; then
            continue
        fi
        
        if [ -z "$disk" -o -z "$md" -o -z "$uuid" -o z "$type" -o -z "$count" -o -z "$size" ]; then
            continue
        fi
        
        type_org="$type_org $type"
        count_org="$count_org $count"
        size_org="$size_org $size"
        uuid_org="$uuid_org $uuid"
        
        dialog_args=''$dialog_args'
                     Raid '$y'  2  '$md'    '$y'  7 20 50       
                     Disk '$y'  28 '$disk'  '$y' 33 20 50'        

        y=$((y + 2))
        
    done < "$IGX_SYSCONF_FILE"
    IFS="$IFSOLD"
    
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit Raid (md) Disks" \
                --form "Use [up] [down] to select input field " 15 60 8 \
                $dialog_args > $tmp_out

    if [ -z "$(cat $tmp_out)" ]; then
        rm -f $tmp_out
        return 0
    fi
    
    sed -e '/^md;/d' -e '/^$/d' "$IGX_SYSCONF_FILE" > "$IGX_SYSCONF_FILE.tmp"
    
    cnt=1
    obj=1
    values_ok=1
    while read item; do
    
        menu_check_char_invalid "$item" || values_ok=0
        
        case $obj in
        
            1)
                printf "md;$item"
            ;;
            
            2)
                uuid=$(echo $uuid_org   | awk '{ print $'$cnt'; }')
                type=$(echo $type_org   | awk '{ print $'$cnt'; }')
                count=$(echo $count_org | awk '{ print $'$cnt'; }')
                size=$(echo $size_org   | awk '{ print $'$cnt'; }')

                printf ";$item;$type;$count;$size;$uuid\n"
                cnt=$((cnt + 1))
                obj=0
            ;;
            
        esac
        
        obj=$((obj + 1))
        
    done < $tmp_out >> "$IGX_SYSCONF_FILE.tmp"

    if [ $values_ok -eq 1 ]; then
        mv "$IGX_SYSCONF_FILE.tmp" "$IGX_SYSCONF_FILE"
    fi
    
    rm -f $tmp_out

    return 0
}

#
# Edit the "fs" lines in $IGX_SYSCONF_FILE
#
menu_edit_fs()
{
    y=1
    tmp_out="/tmp/select"
    mp_org=""
    bsize_org=""
    isize_org=""
    uuid_org=""
    label_org=""
    dialog_args=""
    IFSOLD="$IFS"

    IFS=";"
    while read kind disk fs mp bsize isize uuid label; do
        
        if [ "$kind" != "fs" ]; then
            continue
        fi
        
        if [ -z "$disk" -o -z "$fs" -o -z "$mp" -o z "$bsize" -o -z "$isize" -o -z "$uuid" -o -z "$label" ]; then
            continue
        fi

        if [ "$fs" != "swap" ]; then
            mp_org="$mp_org $mp"        
            bsize_org="$bsize_org $bsize"
            isize_org="$isize_org $isize"
            uuid_org="$uuid_org $uuid"
            test -z "$label" && label_org="$label_org _" || label_org="$label_org $label"
        fi
        
        dialog_args=''$dialog_args'
                     Disk       '$y'  2  '$disk' '$y'  7  20 100       
                     FS         '$y'  28 '$fs'   '$y' 31   8 15
                     Mountpoint '$y'  40 '$mp'   '$y' 51 -20 100'        

        y=$((y + 2))
        
    done < "$IGX_SYSCONF_FILE"
    IFS="$IFSOLD"
    
    dialog 1>&2 --stdout --aspect 1 \
                --backtitle "$IGX_VERSION" \
                --title "Edit Filesystems" \
                --form "Use [up] [down] to select input field " 15 80 8 \
                $dialog_args > $tmp_out

    if [ -z "$(cat $tmp_out)" ]; then
        rm -f $tmp_out
        return 0
    fi
    
    sed -e '/^fs;/d' -e '/^$/d' "$IGX_SYSCONF_FILE" > "$IGX_SYSCONF_FILE.tmp"
    
    cnt=1
    obj=1
    values_ok=1
    while read item; do
    
        case $obj in
        
            1)
                printf "fs;$item"
            ;;
            
            2)
                if [ "$item" = "swap" ]; then
                    printf ";$item;none\n"
                else
                    mp=$(echo $mp_org       | awk '{ print $'$cnt'; }')
                    bsize=$(echo $bsize_org | awk '{ print $'$cnt'; }')
                    isize=$(echo $isize_org | awk '{ print $'$cnt'; }')
                    uuid=$(echo $uuid_org   | awk '{ print $'$cnt'; }')
                    label=$(echo $label_org | awk '{ gsub("_", "", $'$cnt'); print $'$cnt'; }')

                    printf ";$item;$mp;$bsize;$isize;$uuid;$label\n"
                    cnt=$((cnt + 1))
                fi
                obj=0
            ;;
                        
        esac
        
        obj=$((obj + 1))
        
    done < $tmp_out >> "$IGX_SYSCONF_FILE.tmp"
    
    if [ $values_ok -eq 1 ]; then
        mv "$IGX_SYSCONF_FILE.tmp" "$IGX_SYSCONF_FILE"
    fi
    
    rm -f $tmp_out

    return 0
}

#
# Menu loop function
#
menu_loop()
{
    menu_retval=0

    while true; do
        menu_advance && break
        menu_direct_call "$?"
        menu_retval=$?
        if [ $menu_retval -ne 0 ]; then
            break
        fi
    done

    return $menu_retval
}

#
# Direct menu call, allow to jump direct in the edit section
#
menu_direct_call()
{
    opt="$1"

    case "$opt" in
        
        1)
            menu_edit_network
        ;;
            
        2)
            menu_edit_routes
        ;;
            
        3)
            menu_edit_bootdisk
        ;;
            
        4)
            menu_edit_pvdisk
        ;;
            
        5)
            menu_edit_mddisk
        ;;
            
        6)
            menu_edit_fs
        ;;

        7)
            igx_menu_yesno "Start Restore now?" 
            if [ $? -eq 0 ]; then
                make_restore.sh "$IGX_CONFIGSET_NAME"
                return 100
            fi
        ;;
            
        *)
            igx_log "ERROR: Internal error, menu selection does not exists!"
            return 1
        ;;
            
    esac

    return 0
}

main()
{
    igx_chkenv  || return 1

    if [ ! -f /tmp/run_igx_resotre.tmp ]; then
        igx_log "ABORT: It seems you want to restore on a running Operating System, ABORT!"
        return 100
    fi 

    if [ -z "$IGX_SYSCONF_FILE" ]; then
        igx_log "ABORT: Missing sysconfig.info to edit as argument of script!"
        return 200
    fi

    if [ ! -f "$IGX_SYSCONF_FILE" ]; then
        igx_log "ABORT: Cannot read/find sysconfig.info to edit!"
        return 300
    fi

    cp "$IGX_SYSCONF_FILE" "$IGX_SYSCONF_FILE.save"

    if [ -z "$2" ]; then
        menu_loop
    else
        menu_direct_call "$2"
    fi

    if [ $? -ne 100 ]; then
        if [ "$(cksum $IGX_SYSCONF_FILE | awk '{ print $1 }')" != "$(cksum $IGX_SYSCONF_FILE.save | awk '{ print $1 }')" ]; then
            igx_menu_yesno "Discard Changes?" && mv "$IGX_SYSCONF_FILE.save" "$IGX_SYSCONF_FILE"
        fi
    fi

    rm -f "$IGX_SYSCONF_FILE.save"
    
    return $?    
}

#
# Execute the script by calling main()
#
main $@
exit $?
