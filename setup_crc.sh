#!/bin/bash

## George Law
## wrapper around seetting up crc for use with odf-nano
## spins up the crc vm with the suppllied parameters, then will
## shut down, create 3 10Gi disk images and then attach them to the vm, the restarts the vm


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
crc config set enable-cluster-monitoring true # Enable only if you have enough memory, needs ~4G extra
crc config set cpus 4 #Change as per your HW config
mem=$(echo "16*1024"|bc);
crc config set memory $mem  #Change as per your HW config
crc config set pull-secret-file ~/.crc/pull-secret.txt
crc config set disk-size 50
crc config set enable-shared-dirs true
crc config set kubeadmin-password password
crc config view
crc setup


#sudo virsh attach-disk crc --source ~/.crc/vdb --target vdb --persistent
#sudo virsh attach-disk crc --source ~/.crc/vdc --target vdc --persistent
#sudo virsh attach-disk crc --source ~/.crc/vdd --target vdd --persistent
alias crcssh='ssh -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)"'
echo "Starting crc vm"
crc start
echo "Shutting down to attach disks"
crc stop

echo "Creating 3 10 GB disk images for osds"
sudo -S qemu-img create -f raw ~/.crc/vdb 10G
sudo -S qemu-img create -f raw ~/.crc/vdc 10G
sudo -S qemu-img create -f raw ~/.crc/vdd 10G
echo "Attaching the disks to the crc vm"
index1=3
index2=1
for i in vdb vdc vdd; do
echo "<disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='/home/glaw/.crc/${i}' index='${index1}'/>
      <backingStore/>
      <target dev='${i}' bus='virtio'/>
      <alias name='virtio-disk${index2}'/>
    </disk>" > disk_${index2}.xml
#      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    virsh attach-device crc --file  disk_${index2}.xml --config
   # --config

    ((index1+=1))
    ((index2+=1))
done
rm disk*.xml
crc start
ssh -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)" uptime
ssh -i ~/.crc/machines/crc/id_ecdsa core@"$(crc ip)" lsblk
crc console --credentials  > crc-creds.txt
