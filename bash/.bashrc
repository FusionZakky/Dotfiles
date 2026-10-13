#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return
# ble.sh (fish-style highlighting/autosuggest)
[[ $- == *i* ]] && source /usr/share/blesh/ble.sh --noattach

alias ls='ls --color=auto'
alias grep='grep --color=auto'
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
