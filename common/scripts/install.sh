#!/usr/bin/env bash

set -e
set -u



# Ensure script is run from its directory
cd "$(dirname "$0")" || { echo "Failed to change directory"; exit 1; }
DOTFILES_ROOT=$(pwd)

# Parse arguments
FORCE=0
for arg in "$@"; do
  if [[ "$arg" == "--force" ]]; then
    FORCE=1
  fi
done

# Check for required commands
for cmd in curl ln mv cp brew; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command '$cmd' not found. Please install it first." >&2
    exit 1
  fi
done

ST=0
FG_BLACK=30
FG_BLUE=34
FG_WHITE=97

BG_BLACK=40
BG_RED=41
BG_GREEN=42
BG_YELLOW=43
BG_BLUE=44
BG_CYAN=46

COLOR_ERR="\\e[$ST;$FG_WHITE;${BG_RED}m"
COLOR_WARN="\\e[$ST;$FG_BLACK;${BG_YELLOW}m"
COLOR_INFO="\\e[$ST;$FG_WHITE;${BG_BLUE}m"
COLOR_OKAY="\\e[$ST;$FG_BLACK;${BG_CYAN}m"
COLOR_DONE="\\e[$ST;$FG_BLACK;${BG_GREEN}m"
COLOR_DEBG="\\e[$ST;$FG_BLUE;${BG_BLACK}m"

RESET="\\e[0m"

echo ''

success () {
  printf "$COLOR_DONE DONE $RESET %s $RESET\\n" "$1"
}

info () {
  printf "$COLOR_INFO INFO $RESET %s$RESET\\n" "$1"
}

okay () {
  printf "$COLOR_OKAY OKAY $RESET %s$RESET\\n" "$1"
}

warn () {
  printf "$COLOR_WARN WARN $RESET %s$RESET\\n" "$1"
}

debg () {
  printf "$COLOR_DEBG DEBG $RESET %s$RESET\\n" "$1"
}

fail () {
  printf "$COLOR_ERR ERR! $RESET %s$RESET\\n" "$1"
  echo ''
  exit
}

error () {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"

  if [[ -n "$message" ]] ; then
    fail "Error on line ${parent_lineno}: ${message}; exit ${code}"
  else
    fail "Error on line ${parent_lineno}; exit ${code}"
  fi

  exit "${code}"
}
trap 'error ${LINENO}' ERR

# safe_run () {
#     set +e
#     local log="&>$LOGFILE"

#     eval "$1 $log"
#     if [[ $? -ne 0 ]]; then
#         if [[ -n "${2+x}" ]]; then
#             fail "$2"
#         else
#             fail "$1 failed, please check $LOGFILE"
#         fi
#         set -e
#         exit 1
#     fi
# }



if [[ -f $DOTFILES_ROOT/.install-done && $FORCE -ne 1 ]]; then
  fail "Dotfiles already installed. Use --force to reinstall."
  exit 1
fi


if [[ -d $HOME/.dotfiles-backup ]]; then
  DATE=$(date +%s)
  info "Old backup folder found. moving to .dotfiles-backup-$DATE"
  mv "$HOME/.dotfiles-backup" "$HOME/.dotfiles-backup-$DATE"
  success "Old backup moved"
fi


info "Backing up existing files."
mkdir -p "$HOME/.dotfiles-backup"

if [[ -d $HOME/.vim ]]; then
  cp -r "$HOME/.vim" "$HOME/.dotfiles-backup/" 2>/dev/null || true
fi

for f in .zshrc .gitconfig .tmux.conf; do
  if [[ -f "$HOME/$f" ]]; then
    cp "$HOME/$f" "$HOME/.dotfiles-backup/" 2>/dev/null || true
  fi
done
if [[ -f $HOME/.ssh/config ]]; then
  mkdir -p "$HOME/.dotfiles-backup/.ssh" && cp "$HOME/.ssh/config" "$HOME/.dotfiles-backup/.ssh/config" 2>/dev/null || true
fi
success "Backup done: $HOME/.dotfiles-backup"


info "Linking new dotfiles"
for file in .vimrc .zshrc .gitconfig .tmux.conf; do
  target="$DOTFILES_ROOT/config/$file"
  link="$HOME/$file"
  if [[ -e "$link" || -L "$link" ]]; then
    warn "$link already exists, skipping."
  else
    ln -s "$target" "$link"
    success "$file linked"
  fi
done

# Special path
if [[ ! -e "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" ]]; then
  ln -s "$DOTFILES_ROOT/config/.sshconfig" "$HOME/.ssh/config"
  success ".ssh/config linked"
else
  warn ".ssh/config already exists, skipping."
fi


touch ~/.exportsrc
success "exports file created"


# Check network before installing Homebrew/Linuxbrew
ping -c 1 github.com >/dev/null 2>&1 || { fail "Network unreachable. Cannot install Homebrew/Linuxbrew."; exit 1; }

if [[ "$OSTYPE" == "darwin"* ]]; then
  info "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail "Homebrew install failed."
  command -v brew >/dev/null 2>&1 && success "Homebrew installed." || fail "Homebrew not found after install."
elif [[ "$OSTYPE" == "linux"* ]]; then
  mv ~/.gitconfig ~/.gitconfig.tmp
  info "Installing Linuxbrew"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)" || fail "Linuxbrew install failed."

  test -d ~/.linuxbrew && PATH="$HOME/.linuxbrew/bin:$HOME/.linuxbrew/sbin:$PATH"
  test -d /home/linuxbrew/.linuxbrew && PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
  test -r ~/.bash_profile && echo "export PATH='$(brew --prefix)/bin:$(brew --prefix)/sbin'":'"$PATH"' >>~/.bash_profile
  echo "export PATH='$(brew --prefix)/bin:$(brew --prefix)/sbin'":'"$PATH"' >>~/.profile
  echo "export PATH='$(brew --prefix)/bin:$(brew --prefix)/sbin'":'"$PATH"' >> ~/.exportsrc

  sudo apt-get install build-essential -y
  brew install gcc -y

  mv ~/.gitconfig.tmp ~/.gitconfig
fi


info "Install brew packages"
BREW_PKGS="antigen httpie hub vim exa bat fzf nvm yarn fd jq tig tmux procs bottom htop stow delta"
for pkg in $BREW_PKGS; do
  if brew list "$pkg" >/dev/null 2>&1; then
    info "$pkg already installed."
  else
    brew install "$pkg" || warn "$pkg failed to install."
  fi
done
success "Packages are installed"


success "All dotfiles are linked"


touch ~/.exportsrc
success "Exports file created"


if [[ $SHELL != *"/zsh"* ]]; then
  if command -v zsh >/dev/null 2>&1; then
    info "Setting zsh as default for current user."
    sudo chsh -s "$(command -v zsh)" "$(whoami)"
    zsh # switch to zsh
    success "Done"
  else
    warn "zsh not found, cannot set as default shell."
  fi
fi


if [[ ! -d $HOME/bin/ ]]; then
  info "creating local bin folder"
  mkdir -p "$HOME/bin/"
  success "$HOME/bin/ Done"
fi

info "Files copied, enabling."
set +e
set +u
# shellcheck source=/dev/null
. "$HOME/.zshrc" >/dev/null 2>/dev/null
set -e
set -u

# put this file here so we know install was done before
touch "$DOTFILES_ROOT/.install-done"
success "Enabled"

echo ''
echo '  Install completed.'
