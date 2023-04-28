#!/bin/bash

## George Law
## wrapper around seetting up crc for use with odf-nano
## spins up the crc vm with the suppllied parameters, then will
## ssh into crc to create 2 lvs for use with odf, and set up a systemd
## unit to mount those at boottime. finally, will reboot to make sure those
## lvs activate properly after a reboot


function usage() {
    echo "Usage: $0 -m MEMORY -s SIZE -p <kubeadmin  password>"
    echo "Setup crc with supplied parameters.  Will also create and attach 3 10GB disks"
    echo
}

if [ -z $1 ]; then
	usage
	exit;
fi
# get the options - watch for -p for the pod name and -o for output directory

which crc > /dev/null
if [ "$?" == "1" ]; then
    echo "Please download and copy crc executable to somewhere on your \$PATH: $PATH"
    exit;
fi
if [ -z ~/.crc/pass-secret.txt ]; then
    echo "Please  place the pull-secret file in ~/.crc/pull-secret.txt"
    exit;
fi

until [[ -z $1  ]]; do
    case $1 in
        -m)  mem=$2; shift ;;
        -s)  size=$2; shift ;;
        -p)  kubepass="$2"; shift ;;    # add the -p to the passed value
    esac
    shift
done

if [ "$size" == "" ]; then
    # default size 50 GB
    size=50
fi
if [ "$mem" == "" ]; then
    # default memory 16GB
    mem=16
fi
if [ "$kubepass" == "" ]; then
    # default password
    kubepass="password"
fi
echo "Ready to configure crc - using the following base values"
echo "crc vm memory : $mem GB"
echo "crc disk space : $size GB"
echo "crc kubeadmin password : $kubepass"


crc config set consent-telemetry no
crc config set enable-cluster-monitoring false # Enable only if you have enough memory, needs ~4G extra
crc config set cpus 4 #Change as per your HW config
mem_x=$(echo "${mem}*1024"|bc);
crc config set memory $mem_x  #Change as per your HW config
crc config set pull-secret-file ~/.crc/pull-secret.txt
crc config set disk-size 50
crc config set enable-shared-dirs true
crc config set kubeadmin-password password
crc config view
crc setup

echo "Starting crc vm"
crc start


# on mac os, do not use external disk images, use an internal image with 2 lvs
# https://github.com/ksingh7/odf-nano

# build a script locally
# scp to the vm
# then ssh vm sudo script to run it.
cat <<EOF > mkdisk.sh
#!/usr/bin/bash
mkdir -p /var/lib/storage
truncate --size 220G /var/lib/storage/disk1
losetup -P /dev/loop1 /var/lib/storage/disk1
pvcreate /dev/loop1
vgcreate odf /dev/loop1
lvcreate -n disk1 -L 105G odf
lvcreate -n disk2 -L 105G odf
EOF
chmod +x mkdisk.sh
scp -P 2222 -i ~/.crc/machines/crc/id_ecdsa mkdisk.sh core@"$(crc ip)":
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa  core@"$(crc ip)" sudo ./mkdisk.sh
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa  core@"$(crc ip)" lsblk

cat << EOF > lvm-odf-losetup.service
[Unit]
Description=LVM ODF loopback device setup
DefaultDependencies=no
Conflicts=umount.target
Requires=lvm2-lvmetad.service systemd-udev-settle.service
Before=local-fs.target umount.target
After=lvm2-lvmetad.service systemd-udev-settle.service
[Service]
Type=oneshot
ExecStart=/sbin/losetup -P /dev/loop1 /var/lib/storage/disk1
ExecStop=/sbin/losetup -d /dev/loop1
RemainAfterExit=yes
[Install]
WantedBy=local-fs-pre.target
EOF
scp -P 2222 -i ~/.crc/machines/crc/id_ecdsa lvm-odf-losetup.service core@"$(crc ip)":
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa  core@"$(crc ip)" sudo mv lvm-odf-losetup.service /etc/systemd/system
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa  core@"$(crc ip)" sudo restorecon /etc/systemd/system/lvm-odf-losetup.service
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa  core@"$(crc ip)" sudo systemctl enable lvm-odf-losetup
echo "Restarting crc to finish adding odf lvs"
crc stop
sleep 30
crc start
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)" uptime
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)" lsblk
ssh -p 2222 -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)" sudo lvs
crc console --credentials  > crc-creds.txt
echo "Setup complete.  As long as you can see loop1,odf-disk1, and odf-disk2 after the reboot above, you should be good to continue running the mac os deploy script"
