#!/usr/bin/env bash
# tmux-ptt: Push To Talk for tmux
# TPM entry point
# https://github.com/azcro/tmux-ptt

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/scripts/helpers.sh"

# --- Keybinding ---
ptt_key="$(get_tmux_option "@ptt-key" "F9")"
tmux bind-key -T root "$ptt_key" run-shell -b "$CURRENT_DIR/scripts/ptt_toggle.sh"

# --- Auto-enter toggle keybinding ---
enter_key="$(get_tmux_option "@ptt-enter-key" "F9")"
tmux bind-key "$enter_key" run-shell -b "$CURRENT_DIR/scripts/ptt_enter_toggle.sh"

# --- Initialize badge variable ---
if [ "$(get_tmux_option "@ptt-auto-enter" "off")" = "on" ]; then
  tmux set -gq @ptt_badge "#[fg=black,bg=white,bold] PTT ⏎ #[fg=default,bg=default,none]"
else
  tmux set -gq @ptt_badge "#[fg=black,bg=white,bold] PTT #[fg=#cccccc]⏎ #[fg=default,bg=default,none]"
fi
