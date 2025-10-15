#!/bin/sh

set -e

USER_HOME="/home/$name"
USER_LOCAL_HOME="$USER_HOME/.local"
USER_CONFIG_HOME="$USER_HOME/.config"
MIRROR_GITHUB_URL_PREFIX="https://ghproxy.cn"
MIRROR_GITHUB_URL="$MIRROR_GITHUB_URL_PREFIX/https://github.com"
TEMP_PACKAGES_DIR="/tmp/packages"

pacman_install() {
  pacman --noconfirm --needed -S $@
}

aur_install() {
  [ -d "$TEMP_PACKAGES_DIR" ] || sudo -u "$name" mkdir -p "$TEMP_PACKAGES_DIR"
  for item in $@; do
    sudo -u "$name" git -C "$TEMP_PACKAGES_DIR" clone "https://aur.archlinux.org/${item}.git" && \
    sudo -u "$name" sed -iE 's#https://github\.com#https://ghproxy\.cn/&#g' "$TEMP_PACKAGES_DIR/$item/PKGBUILD" && \
    pushd "$TEMP_PACKAGES_DIR/$item" && \
    sudo -u "$name" GOPROXY="https://goproxy.cn" makepkg --noconfirm -si && \
    popd || echo -e "########## AUR: Install $item failed! ##########\n"
  done
}

yay_install() {
  sudo -u "$name" yay -S --noconfirm $@
}

git_install() {
  [ -d "$TEMP_PACKAGES_DIR" ] || sudo -u "$name" mkdir -p "$TEMP_PACKAGES_DIR"
  pushd "$TEMP_PACKAGES_DIR"
  for repo in $@; do
    git clone "$MIRROR_GITHUB_URL_PREFIX/$repo"
    repo_name=$(echo "$repo" | sed -E 's/.+\/(.+)\.git/\1/')
    pushd "$repo_name" && make clean install > /dev/null 2>&1 && popd
  done
  popd
}

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

echo -e "en_US.UTF-8 UTF-8\nzh_CN.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

HOSTNAME=$(cat /etc/hostname)
cat << EOF >> /etc/hosts
127.0.0.1 localhost
::1	localhost
127.0.0.1	$HOSTNAME.localdomain	$HOSTNAME
EOF
sh -c "$(curl -fsL $MIRROR_GITHUB_URL_PREFIX/https://raw.githubusercontent.com/dywsun/dotfiles/master/.local/bin/github_speed_up)"

# update mirror source
pacman_install reflector
reflector --country China --latest 5 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist > /dev/null 2>&1
cat << EOF >> /etc/pacman.conf
[archlinuxcn]
SigLevel = Optional TrustAll
Server = https://opentuna.cn/archlinuxcn/\$arch
EOF
pacman -Sy --noconfirm archlinux-keyring archlinuxcn-keyring

pacman_install zsh
# create user
useradd -m -g wheel -s /bin/zsh "$name"
echo "$name:$password" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/temp
chsh -s /bin/zsh "$name"

# set root password same with user's password
echo -e "$password\n$password" | passwd

pacman_install git
pacman_install networkmanager && systemctl enable NetworkManager && systemctl start NetworkManager

# ucode intel/amd
if [ -n "$(lscpu | awk '/Model name/' | grep AMD)" ]; then
  UCODE="amd-ucode"
else
  UCODE="intel-ucode"
fi
pacman_install grub efibootmgr $UCODE os-prober

grub-install --target="$(uname -m)-efi" --efi-directory=/boot --removable
grub-mkconfig -o /boot/grub/grub.cfg

if [ -z $driver ]; then driver="1"; fi
case $driver in
  "1")
    # for intel
    pacman_install mesa vulkan-intel xf86-video-intel;;
  "2")
    # for amd
    pacman_install mesa vulkan-radeon xf86-video-amdgpu;;
  "3")
    # for nvidia
    pacman_install linux-lts nvidia-lts nvidia-settings nvidia-utils;;
esac

pacman_install openssh && systemctl enable sshd
pacman_install cronie && systemctl enable cronie

# install input for chinese
pacman_install fcitx5-im fcitx5-chinese-addons fcitx5-lua fcitx5-pinyin-zhwiki
pacman_install adobe-source-han-sans-cn-fonts adobe-source-han-serif-cn-fonts
USER_FCITX_THEME_DIR="$USER_LOCAL_HOME/share/fcitx5/themes" 
[ -d "$USER_FCITX_THEME_DIR" ] || sudo -u "$name" mkdir -p "$USER_FCITX_THEME_DIR"
sudo -u "$name" git -C "$USER_FCITX_THEME_DIR" clone "$MIRROR_GITHUB_URL/sxqsfun/fcitx5-sogou-themes.git"
sudo -u "$name" cp -r "$USER_FCITX_THEME_DIR/fcitx5-sogou-themes/Alpha-black" "$USER_FCITX_THEME_DIR"

# install packages in packages.csv file
curl -fsL "$MIRROR_GITHUB_URL_PREFIX/https://raw.github.com/dywsun/archinstall/master/packages.csv" > /tmp/packages.csv
while IFS=',' read -a packs; do
  if [ -z "${packs[0]}" ]; then
    if pacman -Ss "${packs[1]}" >> /dev/null; then
      pacpackages="$pacpackages ${packs[1]}"
    fi
  elif [ "${packs[0]}" == "Y" ]; then
    yaypackages="$yaypackages ${packs[1]}"
  elif [ "${packs[0]}" == "A" ]; then
    aurpackages="$aurpackages ${packs[1]}"
  elif [ "${packs[0]}" == "G" ]; then
    gitpackages="$gitpackages ${packs[1]}"
  fi
done < /tmp/packages.csv

[ -z "$pacpackages" ] || pacman_install "$pacpackages"
aur_install yay
[ -z "$aurpackages" ] || aur_install "$aurpackages" 
[ -z "$yaypackages" ] || yay_install "$yaypackages"
[ -z "$gitpackages" ] || git_install "$gitpackages" 
[ -x /opt/YesPlayMusic/yesplaymusic ] && ln -sf /opt/YesPlayMusic/yesplaymusic /bin/yesplaymusic

# set dotfiles
sudo -u "$name" git clone "$MIRROR_GITHUB_URL/neverwaiting/dotfiles.git" "$USER_HOME/dotfiles"&& \
sudo -u "$name" cp -r "$USER_HOME/dotfiles/.config" "$USER_HOME/" && \
sudo -u "$name" cp -r "$USER_HOME/dotfiles/.local" "$USER_HOME/" && \
sudo -u "$name" cp -P "$USER_HOME/dotfiles/.zprofile" "$USER_HOME/" && \
sudo -u "$name" cp "$USER_CONFIG_HOME/npm/npmrc" "$USER_HOME/.npmrc" || echo -e "########## set dotfiles error! ##########\n"

# configuration for picom
sed -i "s/^fade-in-step = \S*/fade-in-step = 0.08;/; s/^fade-out-step = \S*/fade-out-step = 0.08;/; s/^backend = \S*/backend = \"glx\";/" /etc/xdg/picom.conf

# install grub-theme
git clone "$MIRROR_GITHUB_URL/vinceliuice/grub2-themes.git" && pushd grub2-themes && ./install.sh -b -t stylish -s 4k && popd && rm -rf grub2-themes

# clean unused files
rm -rf $USER_HOME/{.bash_logout,.bash_profile,.bashrc,dotfiles}
