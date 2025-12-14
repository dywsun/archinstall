#!/bin/sh

set -e

MIRROR_GITHUB_URL_PREFIX="https://ghproxy.cn"

read -p"please input your name: " name
export name
while true; do
  read -s -p"please input your password: " password
  echo
  read -s -p"please input your password again: " repassword
  echo
  [ "$password" == "$repassword" ] && break
done
export password

echo -e "There are some devices, please choice one of below:\n"
eval $(sudo fdisk -l | awk 'BEGIN {i=0} /^Disk \/dev/ { printf("ALL_DEVS[%s]=%s;",i++,$2 $3 $4)}')

while true; do
  for ((i=0; i < ${#ALL_DEVS[*]}; ++i)); do
    echo "$i ${ALL_DEVS[$i]}"
  done
  read -p"please select one option: " option
  DEV=${ALL_DEVS[$option]}
  if [ -n "$DEV" ]; then
    break
  fi
  echo -e "option $option not found!\n"
done

echo -e "you choice device: $DEV\n\n"
DEV=$(echo $DEV | awk -F: '{print $1}')

cat <<EOF
please choice your GPU driver:
  1) Intel integrated video card
  2) Amd integrated video card
  3) Nivdia external video card
EOF
read -p"(default=1): " driver
export driver

read -p"your hostname: " HOSTNAME

# installing
timedatectl set-ntp true

cat <<EOF | fdisk $DEV
g
n


+512M
t
1
n


+8G
t

19
n



t

23
w
p
EOF

DEV_NAME=$(echo $DEV | awk -F"/" '{print $3}')
eval $(sudo fdisk -l | awk 'BEGIN {i=0} /^\/dev\/'"$DEV_NAME"'/ {printf("PARTITION[%s]=%s;",i++,$1)}')

partprobe $DEV

mkfs.fat -F 32 ${PARTITION[0]}
yes | mkfs.ext4 ${PARTITION[2]}
mkswap ${PARTITION[1]}
swapon ${PARTITION[1]}

mount ${PARTITION[2]} /mnt
mkdir /mnt/boot
mount ${PARTITION[0]} /mnt/boot

# reflector --country China --latest 5 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist > /dev/null 2>&1
cat <<EOF > /etc/pacman.d/mirrorlist
Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch
Server = http://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch
EOF

echo -e "[archlinuxcn]\nServer = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch" >> /etc/pacman.conf

pacman -Sy --noconfirm archlinux-keyring archlinuxcn-keyring

pacstrap /mnt linux linux-firmware base base-devel vi dhcpcd reflector
genfstab -U /mnt >> /mnt/etc/fstab

echo $HOSTNAME >> /mnt/etc/hostname

# arch-chroot /mnt
curl -fsL "$MIRROR_GITHUB_URL_PREFIX/https://raw.github.com/dywsun/archinstall/master/chroot.sh" > /mnt/chroot.sh && \
arch-chroot /mnt bash chroot.sh && rm /mnt/chroot.sh

umount -R /mnt

read -p"Are you reboot? yes/no: " isreboot
if [ $isreboot == "yes" ]; then
  reboot
fi
