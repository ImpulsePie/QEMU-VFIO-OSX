#!/bin/bash

## Check if the script was executed as root
[[ "$EUID" -ne 0 ]] && echo "Please run as root" && exit 1

## Load the config file
source "${BASH_SOURCE%/*}/configmacamd"

## Check libvirtd
[[ $(systemctl status libvirtd | grep running) ]] || systemctl start libvirtd && sleep 1 && LIBVIRTD=STOPPED

## Memory lock limit
[[ $ULIMIT != $ULIMIT_TARGET ]] && ulimit -l $ULIMIT_TARGET

## Kill the Display Manager
#systemctl stop sddm
#sleep 1

## Kill the console
#echo 0 > /sys/class/vtconsole/vtcon0/bind
#echo 0 > /sys/class/vtconsole/vtcon1/bind
#echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

## Detach the GPU
virsh nodedev-detach $VIRSH_USB > /dev/null 2>&1
virsh nodedev-detach $VIRSH_SATA > /dev/null 2>&1
virsh nodedev-detach $VIRSH_GPU2 > /dev/null 2>&1
virsh nodedev-detach $VIRSH_GPU_AUDIO2 > /dev/null 2>&1


## Load vfio
modprobe vfio-pci
      
MY_OPTIONS="+pcid,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"

qemu-system-x86_64 -enable-kvm \
      -nographic -vga none \
      -m $MACOS_RAM \
      -cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,$MY_OPTIONS\
      -machine pc-q35-2.11 \
      -smp $MACOS_CORES,sockets=1,cores=$(( $MACOS_CORES / 2 )),threads=2 \
      -device vfio-pci,host=$IOMMU_GPU2,multifunction=on,x-vga=on \
      -device vfio-pci,host=$IOMMU_GPU_AUDIO2 \
      -device vfio-pci,host=$IOMMU_USB \
      -device vfio-pci,host=$IOMMU_SATA \
      -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc" \
      -netdev user,id=net0 \
      -device e1000-82545em,netdev=net0,id=net0,mac=52:54:00:c9:18:27 \
      -drive if=pflash,format=raw,readonly,file=$MACOS_OVMF \
      -drive if=pflash,format=raw,file=$MACOS_OVMF_VARS \
	  -smbios type=2 \
      -device ide-drive,bus=ide.2,drive=Clover \
      -drive id=Clover,if=none,snapshot=on,format=qcow2,file=$MACOS_CLOVER \
      -device ide-drive,bus=ide.1,drive=HDD \
      -drive id=HDD,file=$MACOS_IMG,media=disk,format=qcow2,if=none >> $LOG 2>&1 &

## Wait for QEMU
wait

## Unload vfio
modprobe -r vfio-pci
modprobe -r vfio_iommu_type1
modprobe -r vfio

## Reattach the GPU
virsh nodedev-reattach $VIRSH_SATA > /dev/null 2>&1
virsh nodedev-reattach $VIRSH_USB > /dev/null 2>&1
virsh nodedev-reattach $VIRSH_GPU_AUDIO2 > /dev/null 2>&1
virsh nodedev-reattach $VIRSH_GPU2 > /dev/null 2>&1


## Reload the framebuffer and console
#echo 1 > /sys/class/vtconsole/vtcon0/bind
#nvidia-xconfig --query-gpu-info > /dev/null 2>&1
#echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind

## Reload the Display Manager
#systemctl start sddm

## If libvirtd was stopped then stop it
[[ $LIBVIRTD == "STOPPED" ]] && systemctl stop libvirtd

## Restore ulimit
ulimit -l $ULIMIT
