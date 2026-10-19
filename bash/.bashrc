#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return
# ble.sh (fish-style highlighting/autosuggest)
[[ $- == *i* && -n ${BLESH-} ]] && source /usr/share/blesh/ble.sh --noattach

alias ls='ls --color=auto'
alias grep='grep --color=auto'
# --- bashpolish (managed by bashpolish.sh) ---
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize cdspell
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
alias pamcan=pacman
alias q='qs -c ii'
[[ $TERM != linux ]] && command -v eza >/dev/null && alias ls='eza --icons=auto'
# --- end bashpolish ---
PS1='[\u@\h \W]\$ '

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/zakkaria/y/google-cloud-sdk/path.bash.inc' ]; then . '/home/zakkaria/y/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/zakkaria/y/google-cloud-sdk/completion.bash.inc' ]; then . '/home/zakkaria/y/google-cloud-sdk/completion.bash.inc'; fi

# Starship (bash-specific config) + matugen terminal palette
if [[ $TERM != linux ]]; then
  export STARSHIP_CONFIG=~/.config/starship-bash.toml
  eval "$(starship init bash)"
  [[ -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt ]] && cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
fi
[[ ${BLE_VERSION-} ]] && ble-attach
[[ ${BLE_VERSION-} ]] && bleopt keymap_emacs_mode_string_multiline=''
[[ ${BLE_VERSION-} ]] && _ble_decode_show_progress_hook=
true
