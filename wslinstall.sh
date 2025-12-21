#!/bin/sh

set -e

read -p"please input your name: " name

while true; do
  read -s -p"please input your password: " password
  echo
  read -s -p"please input your password again: " repassword
  echo
  [ "$password" == "$repassword" ] && break
done

read -p"your hostname: " HOSTNAME

USER_HOME="/home/$name"
USER_LOCAL_HOME="$USER_HOME/.local"
USER_CONFIG_HOME="$USER_HOME/.config"
MIRROR_GITHUB_URL_PREFIX="https://ghproxy.cn"
MIRROR_GITHUB_URL="$MIRROR_GITHUB_URL_PREFIX/https://github.com"
TEMP_PACKAGES_DIR="/tmp/packages"

echo $name $password $HOSTNAME

# change hostname
echo $HOSTNAME > /etc/hostname

echo "127.0.0.1	$HOSTNAME.localdomain	$HOSTNAME" >> /etc/hosts

cat <<EOF > /etc/pacman.d/mirrorlist
Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch
Server = http://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch
EOF

cat << EOF >> /etc/pacman.conf

[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch
EOF

pacman_install() {
  pacman --noconfirm --needed -S $@
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

pacman-key --init
pacman-key --populate
pacman -Sy --noconfirm archlinux-keyring archlinuxcn-keyring

pacman_install zsh git

# create user
useradd -m -g wheel -s /bin/zsh "$name"
echo "$name:$password" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/temp
chsh -s /bin/zsh "$name"

# set root password same with user's password
echo -e "$password\n$password" | passwd

pacman_install openssh && systemctl enable sshd

# install packages in packages.csv file
curl -fsL "$MIRROR_GITHUB_URL_PREFIX/https://raw.github.com/dywsun/archinstall/master/wslpackages.csv" > /tmp/packages.csv
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

# set dotfiles
sudo -u "$name" git clone "$MIRROR_GITHUB_URL/dywsun/dotfiles.git" "$USER_HOME/dotfiles"&& \
sudo -u "$name" cp -r "$USER_HOME/dotfiles/.config" "$USER_HOME/" && \
sudo -u "$name" cp -r "$USER_HOME/dotfiles/.local" "$USER_HOME/" && \
sudo -u "$name" cp -P "$USER_HOME/dotfiles/.zprofile" "$USER_HOME/" && \
sudo -u "$name" cp "$USER_CONFIG_HOME/npm/npmrc" "$USER_HOME/.npmrc" || echo -e "########## set dotfiles error! ##########\n"

# clean unused files
rm -rf $USER_HOME/{.bash_logout,.bash_profile,.bashrc,dotfiles}
