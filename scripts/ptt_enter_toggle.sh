#!/usr/bin/env bash
# tmux-ptt: toggle auto-enter on/off
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

current="$(get_tmux_option "@ptt-auto-enter" "off")"

if [ "$current" = "on" ]; then
  tmux set -g @ptt-auto-enter "off"
  tmux set -gq @ptt_badge "#[fg=black,bg=white,bold] PTT #[fg=#cccccc]⏎ #[fg=default,bg=default,none]"
else
  tmux set -g @ptt-auto-enter "on"
  tmux set -gq @ptt_badge "#[fg=black,bg=white,bold] PTT ⏎ #[fg=default,bg=default,none]"
fi
tmux refresh-client -S
