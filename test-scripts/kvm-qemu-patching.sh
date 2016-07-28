#!/bin/bash
# https://doomedraven.github.io/2016/01/23/KVM-QEMU.html

function usage() 
{
    echo 'Usage: $0 <func_name>'
    echo
    echo 'Func:'
    echo '    All'
    echo '    KVM'
    echo '    QEMU'
    echo '    SeaBios'
    exit
}

function install_kvm() 
{
    apt-get install build-essential gcc pkg-config glib-2.0 libglib2.0-dev libsdl1.2-dev libaio-dev libcap-dev libattr1-dev libpixman-1-dev -y
    apt-get build-dep qemu
    apt-get install lvm2 ubuntu-virt-server python-vm-builder qemu-kvm qemu-system libvirt-bin ubuntu-vm-builder kvm-ipxe bridge-utils -y
    apt-get install virtinst python-libvirt virt-viewer virt-manager -y # Virtual Machine Manager
	kvm-ok
}

function qemu_func() 
{
    #Download code
    echo '[+] Downloading QEMU source code'
    apt-get source qemu > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo '[+] Patching QEMU clues'
        sed -i 's/QEMU HARDDISK/WDC WD20EARS/g' qemu*/hw/ide/core.c
        if [ $? -ne 0 ]; then
            echo 'QEMU HARDDISK was not replaced in core.c'
        fi
        sed -i 's/QEMU HARDDISK/WDC WD20EARS/g' qemu*/hw/scsi/scsi-disk.c > /dev/null 2>&1
            if [ $? -eq 0 ]; then
            echo 'QEMU HARDDISK was not replaced in scsi-disk.c'
        fi
        sed -i 's/QEMU DVD-ROM/DVD-ROM/g' qemu*/hw/ide/core.c > /dev/null 2>&1
            if [ $? -eq 0 ]; then
            echo 'QEMU DVD-ROM was not replaced in core.c'
        fi
        sed -i 's/QEMU DVD-ROM/DVD-ROM/g' qemu*/hw/ide/atapi.c > /dev/null 2>&1
            if [ $? -eq 0 ]; then
            echo 'QEMU DVD-ROM was not replaced in atapi.c'
        fi
        sed -i 's/s->vendor = g_strdup("QEMU");/s->vendor = g_strdup("DELL");/g' qemu*/hw/scsi/scsi-disk.c
            if [ $? -eq 0 ]; then
            echo 'Vendor string was not replaced in scsi-disk.c'
        fi
        sed -i 's/QEMU CD-ROM/CD-ROM/g' qemu*/hw/scsi/scsi-disk.c > /dev/null 2>&1
            if [ $? -eq 0 ]; then
            echo 'QEMU CD-ROM was not patched in scsi-disk.c'
        fi
        sed -i 's/padstr8(buf + 8, 8, "QEMU");/padstr8(buf + 8, 8, "DELL");/g' qemu*/hw/ide/atapi.c > /dev/null 2>&1
            if [ $? -eq 0 ]; then
            echo 'padstr was not replaced in atapi.c'
        fi
        sed -i 's/QEMU MICRODRIVE/DELL MICRODRIVE/g' qemu*/hw/ide/core.c > /dev/null 2>&1
            if [ $? -eq 0 ]; then
            echo 'QEMU MICRODRIVE was not replaced in core.c'
        fi

        echo '[+] Starting to compile code'
        # not make sense compile if was not patched
        apt-get source --compile qemu > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            dpkg -i qemu*.deb
            if [ $? -eq 0 ]; then
                echo '[+] Patched, compiled and installed'
            else
                echo '[-] Install failed'
            fi
        else
            echo '[-] Compilling failed'
        fi
        echo '[+] Starting Installation'
        dpkg -i qemu*.deb

    else
        echo '[-] Download of QEMU source was not possible'
    fi
}

function seabios_func 
{
    echo '[+] Installing SeaBios dependencies'
    apt-get install git iasl > /dev/null 2>&1
    git clone git://git.seabios.org/seabios.git > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        cd seabios
        sed -i 's/Bochs/DELL/g' src/config.h > /dev/null 2>&1
        sed -i 's/BOCHSCPU/DELLCPU/g' src/config.h > /dev/null 2>&1
        sed -i 's/BOCHS/DELL/g' src/config.h > /dev/null 2>&1
        sed -i 's/BXPC/DELLS/g' src/config.h > /dev/null 2>&1
        make
        if [ $? -eq 0 ]; then
            echo '[+] Compiled SeaBios, bios file located in -> out/bios.bin'
            echo '[+] Replacing old bios.bin to new one, with backup'
            cp /usr/share/qemu/bios.bin /usr/share/qemu/bios.bin_back
            if [ $? == 0 ]; then
                echo '[+] Original bios.bin file backuped to /usr/share/qemu/bios.bin_back'
                cp out/bios.bin /usr/share/qemu/bios.bin
                if [ $? -eq 0 ]; then
                    echo '[+] Patched bios.bin placed correctly'
                else:
                    echo '[-] Bios patching failed'
                fi
            else:
                echo '[-] Bios backup failed'
            fi

        fi
    else
        echo '[-] Check if git installed or network connection is OK'
    fi
}

#check if start with root
if [ $EUID -ne 0 ]; then
   echo 'This script must be run as root'
   exit 1
fi

if [ $# -eq 0 ]; then
    usage
fi

if [ "$1" = '-h' ]; then
    usage
fi


if [ "$1" = 'All' ]; then
    install_kvm
    qemu_func
    seabios_func
fi

if [ "$1" = 'QEMU' ]; then
    qemu_func
fi

if [ "$1" = 'SeaBios' ]; then
    seabios_func
fi

if [ "$1" = 'KVM' ]; then
    install_kvm
fi
