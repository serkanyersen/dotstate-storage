# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

eval "$(/opt/homebrew/bin/brew shellenv)"
fpath=(~/.zsh/completions $fpath)
source `brew --prefix`/share/antigen/antigen.zsh
source ~/.exportsrc

# Load the oh-my-zsh's library.
antigen use oh-my-zsh

antigen bundle git
antigen bundle atuinsh/atuin@main
# antigen bundle github
antigen bundle npm
antigen bundle sublime
antigen bundle brew
antigen bundle z
antigen bundle yarn
antigen bundle cp
# antigen bundle httpie
antigen bundle macos
antigen bundle nvm
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle andrewferrier/fzf-z
antigen theme romkatv/powerlevel10k

antigen bundle mafredri/zsh-async
# antigen bundle sindresorhus/pure

antigen apply

export EDITOR='nvim'

# Basic shortcuts
if command -v clear >/dev/null 2>&1; then
  alias c="clear; printf '\e[3J'"
fi

if command -v nvim >/dev/null 2>&1; then
  alias vi="nvim"
  alias vim="nvim"
fi

if command -v eza >/dev/null 2>&1; then
  alias lst="eza --tree --git-ignore -I node_modules"
  alias ls="eza -lah --icons=always --git"
fi

if command -v zsh >/dev/null 2>&1; then
  alias reload="exec zsh"
fi

if [[ -n "$EDITOR" ]]; then
  alias edit="$EDITOR ~/.zshrc"
fi

if command -v docker-compose >/dev/null 2>&1; then
  alias dc="docker-compose"
fi

if command -v bat >/dev/null 2>&1; then
  alias cat="bat"
fi

if command -v fzf >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
  alias preview="fzf --preview 'bat --color \"always\" {}'"
fi

# alias build="web && ./bin/build web --working $WORKING_DIR --output $OUTPUT_DIR"
if command -v powermetrics >/dev/null 2>&1 && command -v grep >/dev/null 2>&1; then
  alias cpu-temp="sudo powermetrics --samplers smc |grep -i \"CPU die temperature\""
  alias gpu-temp="sudo powermetrics --samplers smc |grep -i \"GPU die temperature\""
fi

# add support for ctrl+o to open selected file in VS Code
export FZF_DEFAULT_OPTS="--bind='ctrl-o:execute(code {})+abort'"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --git-ignore'
function gi() { curl -L -s https://www.gitignore.io/api/$@ ;}
function weather() { curl "http://wttr.in/$1?m";}

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

if [ -f '$(brew --prefix)/opt/nvm/nvm.sh' ]; then
export NVM_DIR="$HOME/.nvm"
. "$(brew --prefix)/opt/nvm/nvm.sh" --no-use
fi

to_mp4() {
  ffmpeg -i "$1" -vcodec h264 -acodec mp2 "${2:-output.mp4}"
  mv output.mp4 "output_$(date +%F-%H:%M).mp4"
}

unsymlink() {
  local dest="$1"
  local src="$2"
  [ -L "$dest" ] && rm "$dest"
  cp "$src" "$dest"
}

export PATH="$PATH:`npm -g bin`"

# added by setup_android_env_var.sh
export ANDROID_SDK="/Users/$USER/Library/Android/sdk"
export ANDROID_NDK_REPOSITORY=/opt/android_ndk
export ANDROID_HOME=${ANDROID_SDK}
export PATH=${PATH}:${ANDROID_SDK}/tools:${ANDROID_SDK}/tools/bin:${ANDROID_SDK}/platform-tools
alias emulator="/Users/$USER/Library/Android/sdk/emulator/emulator"
export PATH="$HOME/.local/bin:$PATH"
export PATH="/Users/$USER/.deno/bin:$PATH"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /usr/local/bin/bitcomplete bit

_build_yargs_completions()
{
  local reply
  local si=$IFS
  IFS=$'
' reply=($(COMP_CWORD="$((CURRENT-1))" COMP_LINE="$BUFFER" COMP_POINT="$CURSOR" /Users/seko/local/whatsapp/wajs/web/scripts/build/bin/build --get-yargs-completions "${words[@]}"))
  IFS=$si
  _describe 'values' reply
}
compdef _build_yargs_completions build
###-end-build-completions-###
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
. "/Users/serkan/.deno/env"
. "$HOME/.local/bin/env"

# bun completions
[ -s "/Users/serkan/.bun/_bun" ] && source "/Users/serkan/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Added by Antigravity
export PATH="/Users/serkan/.antigravity/antigravity/bin:$PATH"
export PATH="$(go env GOPATH)/bin:$PATH"

# opencode
export PATH=/Users/serkan/.opencode/bin:$PATH

# dotstate completions loaded via fpath (~/.zsh/completions/_dotstate)
