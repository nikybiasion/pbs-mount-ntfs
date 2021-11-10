#!/bin/bash
declare -a snapshots
declare -a drivenames
declare snapsel
declare drivesel
declare partsel
declare loopid
USER=root@pam
PBS=192.168.0.3
DATASTORE=backup

function list_snapshots(){
   i=1
   while read snapshot; do
      if [ "z${snapshot}" == "z" ] || [ "${snapshot}" == "snapshot" ]; then continue; fi
      snapshots[$i]="${snapshot} ${snapshot}"
      ((i=i+1))
   done < <(proxmox-backup-client snapshot list | awk '{print $2}')

   snapsel=$(dialog --ascii-lines --no-tags --menu "Select snapshot:" 0 0 5 ${snapshots[@]} 2>&1 >/dev/tty )
}

function list_drives(){
   i=1
   while read drivename; do
     if [ "z${drivename}" == "z" ] || [ "${drivename}" == "filename" ] || [[ "${drivename}" =~ "blob" ]]; then continue; fi
     drivenames[$i]="${drivename%.fidx} ${drivename%.fidx}"
     ((i=i+1))
   done < <(proxmox-backup-client snapshot files ${snapsel} | awk '{print $2}')

   drivesel=$(dialog --ascii-lines --no-tags --menu "Select drive:" 0 0 5 ${drivenames[@]} 2>&1 >/dev/tty )
}

function map_backup(){
   loopid=$(proxmox-backup-client map ${snapsel} ${drivesel} --repository $USER@$PBS:8007:$DATASTORE | awk '{print $NF}')
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
   mkdir /mnt/restorewin
   mount.ntfs /dev/$partsel /mnt/restorewin/ -o ro
   rodee=$(dialog --ascii-lines --title "Restore data" --msgbox "Partition mounted on /mnt/sdc, press ok when finished restore" 0 0 2>&1 >/dev/tty)
   umount /mnt/restorewin
}

function exit_restore(){
   proxmox-backup-client unmap $loopid
   exit
}

while true
do
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
           mount_partition
           exit_restore ;;
      esac
    ;;
  esac
done