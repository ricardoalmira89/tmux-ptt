#!/usr/bin/env bash
# tmux-ptt: Push To Talk for tmux
# TPM entry point
# https://github.com/azcro/tmux-ptt

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CURRENT_DIR/scripts/helpers.sh"

# --- Keybinding ---
ptt_key="$(get_tmux_option "@ptt-key" "F9")"
tmux bind-key -T root "$ptt_key" run-shell -b "$CURRENT_DIR/scripts/ptt_toggle.sh"

# --- Initialize badge variable ---
tmux set -gq @ptt_badge ""
