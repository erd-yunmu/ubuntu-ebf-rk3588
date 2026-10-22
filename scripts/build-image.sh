#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

cleanup_loopdev() {
    local loop="$1"

    sync --file-system
    sync

    sleep 1

    if [ -b "${loop}" ]; then
        for part in "${loop}"p*; do
            if mnt=$(findmnt -n -o target -S "$part"); then
                umount "${mnt}"
            fi
        done
        losetup -d "${loop}"
    fi
}

wait_loopdev() {
    local loop="$1"
    local seconds="$2"

    until test $((seconds--)) -eq 0 -o -b "${loop}"; do sleep 1; done

    ((++seconds))

    ls -l "${loop}" &> /dev/null
}

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 filename.rootfs.tar"
    exit 1
fi

rootfs="$(readlink -f "$1")"
if [[ "$(basename "${rootfs}")" != *".rootfs.tar" || ! -e "${rootfs}" ]]; then
    echo "Error: $(basename "${rootfs}") must be a rootfs tarfile"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p images build && cd build

if [[ -z ${BOARD} ]]; then
    echo "Error: BOARD is not set"
    exit 1
fi

# Create an empty disk image
img="../images/$(basename "${rootfs}" .rootfs.tar).img"
size="$(( $(wc -c < "${rootfs}" ) / 1024 / 1024 ))"
truncate -s "$(( size + 1024 + 512 ))M" "${img}"

# Create loop device for disk image
loop="$(losetup -f)"
losetup -P "${loop}" "${img}"
disk="${loop}"

# Cleanup loopdev on early exit
trap 'cleanup_loopdev ${loop}' EXIT

# Ensure disk is not mounted
mount_point=/tmp/mnt
umount "${disk}"* 2> /dev/null || true
umount ${mount_point}/* 2> /dev/null || true
mkdir -p ${mount_point}

# Setup partition table
dd if=/dev/zero of="${disk}" count=4096 bs=512
parted --script "${disk}" \
mklabel gpt \
mkpart primary ext4 16MiB 528MiB \
mkpart primary ext4 528MiB 100%

# Create partitions
{
    echo "t"
    echo "1"
    echo "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
    echo "t"
    echo "2"
    echo "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
    echo "w"
} | fdisk "${disk}" &> /dev/null || true

parted --script "${disk}" set 1 legacy_boot on

partprobe "${disk}"

partition_char="$(if [[ ${disk: -1} == [0-9] ]]; then echo p; fi)"

sleep 1

wait_loopdev "${disk}${partition_char}2" 60 || {
    echo "Failure to create ${disk}${partition_char}2 in time"
    exit 1
}

sleep 1

wait_loopdev "${disk}${partition_char}1" 60 || {
    echo "Failure to create ${disk}${partition_char}1 in time"
    exit 1
}

sleep 1

# Generate random uuid for bootfs
boot_uuid=$(uuidgen)

# Generate random uuid for rootfs
root_uuid=$(uuidgen)

# Create filesystems on partitions
dd if=/dev/zero of="${disk}${partition_char}1" bs=1KB count=10 > /dev/null
mkfs.ext4 -U "${boot_uuid}" -L system-boot "${disk}${partition_char}1"
dd if=/dev/zero of="${disk}${partition_char}2" bs=1KB count=10 > /dev/null
mkfs.ext4 -U "${root_uuid}" -L writable "${disk}${partition_char}2"

# Mount partitions
mkdir -p ${mount_point}/{system-boot,writable} 
mount "${disk}${partition_char}1" ${mount_point}/system-boot
mount "${disk}${partition_char}2" ${mount_point}/writable

# Copy the rootfs to root partition
tar -xpf "${rootfs}" -C ${mount_point}/writable

# Set boot args for the splash screen
[ -z "${img##*desktop*}" ] && bootargs="splash plymouth.ignore-serial-consoles" || bootargs=""

# Create fstab entries
mkdir -p ${mount_point}/writable/boot/firmware
cat > ${mount_point}/writable/etc/fstab << EOF
# <file system>       <mount point>  <type>  <options>                    <dump>  <fsck>
UUID=${root_uuid}     /              ext4    defaults,x-systemd.growfs    0       1
/swapfile             none           swap    sw                           0       0
EOF

# Uboot script
cat > ${mount_point}/system-boot/boot.cmd << 'EOF'
# This is a boot script for U-Boot
#
# Recompile with:
# mkimage -A arm64 -O linux -T script -C none -n "Boot Script" -d boot.cmd boot.scr

setenv load_addr "${kernel_addr_r}"
setenv ubuntu_env_size 0

echo "Boot script loaded from ${devtype} ${devnum}"

# Board uEnv first; ubuntuEnv.txt only as fallback.
if test -n "${lubancat_uenv}"; then
	if test -e ${devtype} ${devnum}:${distro_bootpart} /uEnv/uEnv-${lubancat_uenv}.txt; then
		load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} /uEnv/uEnv-${lubancat_uenv}.txt
		env import -t ${load_addr} ${filesize}
		setenv ubuntu_env_size ${filesize}
		echo "Config: /uEnv/uEnv-${lubancat_uenv}.txt"
	fi
fi

if test "${ubuntu_env_size}" = "0"; then
	if test -e ${devtype} ${devnum}:${distro_bootpart} /ubuntuEnv.txt; then
		load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} /ubuntuEnv.txt
		env import -t ${load_addr} ${filesize}
		setenv ubuntu_env_size ${filesize}
		echo "Config: /ubuntuEnv.txt (fallback)"
	fi
fi

# U-Boot's dtb choice wins.
if test -n "${lubancat_fdtfile}"; then
	setenv fdtfile "${lubancat_fdtfile}"
fi

if test "${devtype}" = "mmc"; then
	setenv rootdev "/dev/mmcblk${devnum}p2"
	setenv bootpart "/dev/mmcblk${devnum}p1"
elif test "${devtype}" = "nvme"; then
	setenv rootdev "/dev/nvme${devnum}n1p2"
	setenv bootpart "/dev/nvme${devnum}n1p1"
else
	setenv rootdev "LABEL=writable"
	setenv bootpart ""
fi

setenv bootargs "${bootargs} root=${rootdev}"
if test -n "${bootpart}"; then
	setenv bootargs "${bootargs} lubancat.bootdev=${bootpart}"
fi
printenv bootargs

load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /dtbs/rockchip/${fdtfile}
fdt addr ${fdt_addr_r} && fdt resize 0x40000

if dtoverlay ${load_addr} ${ubuntu_env_size} ${devtype} ${devnum}:${distro_bootpart}; then
    echo "Device tree overlays applied"
else
    echo "Error applying device tree overlays, restoring original device tree"
    load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /dtbs/rockchip/${fdtfile}
fi

# Pass what was used to the OS.
fdt set /chosen lubancat,dtb "${fdtfile}"
fdt set /chosen lubancat,uenv "${lubancat_uenv}"

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /vmlinuz
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /initrd.img

booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
EOF
mkimage -A arm64 -O linux -T script -C none -n "Boot Script" -d ${mount_point}/system-boot/boot.cmd ${mount_point}/system-boot/boot.scr

# dtb name used by the sanity check below.
FDTFILE_NAME="${OVERLAY_PREFIX}-lubancat-generic.dtb"

# uEnv = common bootargs + per-board dtb/overlay list.
mkdir -p ${mount_point}/system-boot/uEnv
for uenv in ../config/uEnv/*.uEnv; do
    uenv_name="$(basename "${uenv}" .uEnv)"
    {
        printf '# Kernel parameters for system boot configuration.\n'
        printf 'bootargs=rootfstype=ext4 rootwait rw console=ttyS2,1500000 console=tty1 console=ttyFIQ0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1 systemd.unified_cgroup_hierarchy=0 %s\n\n' "${bootargs}"
        cat "${uenv}"
    } > "${mount_point}/system-boot/uEnv/uEnv-${uenv_name}.txt"
done

uenv_file="../config/uEnv/${BOARD}.uEnv"
overlay_list=""
if [ -f "${uenv_file}" ]; then
    overlay_list="$(tr -d '\r' < "${uenv_file}" \
        | sed -e 's/#.*//' \
        | sed -n -e 's|^[[:space:]]*dtoverlay=[[:space:]]*||p' \
                 -e 's|^[[:space:]]*\([A-Za-z0-9][A-Za-z0-9._-]*-ove[rt]*lay\)[[:space:]]*$|\1|p' \
        | sed -e 's|[[:space:]]*$||' -e 's|.*/||' -e 's|\.dtbo$||' \
        | grep -v '^$' \
        | awk '!seen[$0]++' \
        | tr '\n' ' ')"
fi

# Copy the device trees, kernel, and initrd to the boot partition
mv ${mount_point}/writable/boot/firmware/* ${mount_point}/system-boot/

if [ -d "${mount_point}/system-boot/dtbs/rockchip/overlay" ]; then
    rm -rf "${mount_point}/system-boot/dtb/overlay"
    mkdir -p "${mount_point}/system-boot/dtb"
    mv "${mount_point}/system-boot/dtbs/rockchip/overlay" "${mount_point}/system-boot/dtb/overlay"
fi

if [ ! -f "${mount_point}/system-boot/dtbs/rockchip/${FDTFILE_NAME}" ]; then
    echo "Error: dtb ${FDTFILE_NAME} not found in dtbs/rockchip"
    exit 1
fi

for overlay in ${overlay_list}; do
    if [ ! -f "${mount_point}/system-boot/dtb/overlay/${overlay}.dtbo" ]; then
        echo "Error: overlay ${overlay} not found in dtb/overlay"
        exit 1
    fi
done

# Write bootloader to disk image
if [ -f "${mount_point}/writable/usr/lib/u-boot/u-boot-rockchip.bin" ]; then
    dd if="${mount_point}/writable/usr/lib/u-boot/u-boot-rockchip.bin" of="${loop}" seek=1 bs=32k conv=fsync
else
    dd if="${mount_point}/writable/usr/lib/u-boot/idbloader.img" of="${loop}" seek=64 conv=notrunc
    dd if="${mount_point}/writable/usr/lib/u-boot/u-boot.itb" of="${loop}" seek=16384 conv=notrunc
fi

# Cloud init config for server image
if [ -z "${img##*server*}" ]; then
    cp ../overlay/boot/firmware/{meta-data,network-config} ${mount_point}/system-boot
fi

sync --file-system
sync

# Umount partitions
umount "${disk}${partition_char}1"
umount "${disk}${partition_char}2"

# Remove loop device
losetup -d "${loop}"

# Exit trap is no longer needed
trap '' EXIT

echo -e "\nCompressing $(basename "${img}.xz")\n"
xz -3 --force --keep --quiet --threads=0 "${img}"
rm -f "${img}"
cd ../images && sha256sum "$(basename "${img}.xz")" > "$(basename "${img}.xz.sha256")"
