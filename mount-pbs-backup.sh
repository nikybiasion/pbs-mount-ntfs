#!/bin/bash
declare -a groups
declare -a snapshots
declare -a drivenames
declare groupsel
declare snapsel
declare drivesel
declare partsel
declare loopid
USER=root@pam
PBS=192.168.0.3:8007
DATASTORE=backup
MOUNTDIR=/mnt/restorewin

function list_groups(){
        groups=()
        i=1
        while read group; do
                if [ "z${group}" == "z" ] || [ "${group}" == "group" ]; then continue; fi
                groups[$i]="${group} ${group}"
                ((i=i+1))
        done < <(proxmox-backup-client list | awk '{print $2}')

        groupsel=$(dialog --ascii-lines --no-tags --menu "Select backup group:" 0 0 5 ${groups[@]} 2>&1 >/dev/tty )
}

function list_snapshots(){
        snapshots=()
        i=1
        while read snapshot; do
                if [ "z${snapshot}" == "z" ] || [ "${snapshot}" == "snapshot" ]; then continue; fi
                snapshots[$i]="${snapshot} ${snapshot}"
                ((i=i+1))
        done < <(proxmox-backup-client snapshot list ${groupsel} | awk '{print $2}')

        snapsel=$(dialog --ascii-lines --no-tags --menu "Select snapshot:" 0 0 5 ${snapshots[@]} 2>&1 >/dev/tty )
}

function list_drives(){
        drivenames=()
        i=1
        while read drivename; do
                if [ "z${drivename}" == "z" ] || [ "${drivename}" == "filename" ] || [[ "${drivename}" =~ "blob" ]]; then continue; fi
                drivenames[$i]="${drivename%.fidx} ${drivename%.fidx}"
                ((i=i+1))
        done < <(proxmox-backup-client snapshot files ${snapsel} | awk '{print $2}')

        drivesel=$(dialog --ascii-lines --no-tags --menu "Select drive:" 0 0 5 ${drivenames[@]} 2>&1 >/dev/tty )
}


function map_backup(){
        loopid=$(proxmox-backup-client map ${snapsel} ${drivesel} --repository $USER@$PBS:$DATASTORE | awk '{print $NF}')
        partitions=($(lsblk $loopid -l | grep part | awk '{print $1"-"$4}'))
        declare -a menuparts
        i=1
        for partition in "${partitions[@]}"; do
                menuparts[i]="${partition%-*}"
                menuparts[i+1]="${partition%-*} - ${partition#*-}"
                ((i=i+2))
        done
        partsel=$(dialog --ascii-lines --no-tags --menu "Select partition:" 0 0 5 "${menuparts[@]}" 2>&1 >/dev/tty )
}

function mount_partition(){
        mkdir $MOUNTDIR
        mount.ntfs /dev/$partsel $MOUNTDIR -o ro
        if [ $? == 0 ]; then
                status=$(dialog --ascii-lines --title "Restore data" --msgbox "Partition mounted on $MOUNTDIR, press ok when the restore is finished" 0 0 2>&1 >/dev/tty)
                umount $MOUNTDIR
                else
                status=$(dialog --ascii-lines --title "Restore data error" --msgbox "Unable to mount partition" 0 0 2>&1 >/dev/tty)
        fi
}

function exit_restore(){
        proxmox-backup-client unmap $loopid
        exit
}

while true
do
        list_groups
        case $? in
                255) exit_restore ;;
                1) exit_restore ;;
                0)
                list_snapshots
                case $? in
                        255) exit_restore ;;
                        1) exit_restore ;;
                        0)
                        list_drives
                        case $? in
                                255) continue ;;
                                1) continue ;;
                                0) map_backup
                                case $? in
                                        255) continue ;;
                                        1) continue ;;
                                        0)
                                        mount_partition
                                        exit_restore ;;
                                esac
                        esac
                esac
        esac
done

