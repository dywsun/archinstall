#!/bin/sh

remote_user="git@github.com:dywsun"
# personal_remote_repo="git@zwled.xyz:/srv/git"

ssh-keygen -t ed25519 -C "zdynstop@gmail.com"

cat "$HOME/.ssh/id_ed25519.pub" | xclip -i -selection clipboard
echo -e "\e[34mpublic-key:\e[33m"
cat "$HOME/.ssh/id_ed25519.pub"
echo -e "\e[0m"
echo -e "\e[32mssh-public-key was pasted! Add this to your github account and your owner remote repo(on vps)!\e[0m\n"

read -p "Are you continue clone repos? [yes/no]: " answer
[ -z "$answer" -o "$answer" == "yes" ] || exit 0

dir="$HOME/.local/src"
[ -d "$dir" ] || mkdir -p "$dir"
for repo in {archinstall,dotfiles,dwm,dwmblocks,dmenu,st,slock,notes}; do
  git -C "$dir" clone "$remote_user/$repo.git"
  # pushd "$dir/$repo" && git remote add personal "$personal_remote_repo/$repo.git" && popd
done
