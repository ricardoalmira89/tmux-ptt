#!/usr/bin/env bash
# tmux-ptt: status bar indicator
# Called by tmux via #() on every status-interval tick.
# Outputs styled badge or nothing. Must be fast.
# https://github.com/azcro/tmux-ptt

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

STATEFILE="$(ptt_statefile)"

if [ ! -f "$STATEFILE" ]; then
  exit 0
fi

state="$(cat "$STATEFILE" 2>/dev/null || true)"

case "$state" in
  recording)
    text="$(get_tmux_option "@ptt-recording-text" "REC")"
    printf '#[fg=white,bg=red,bold] %s #[fg=default,bg=default,none]' "$text"
    ;;
  transcribing)
    text="$(get_tmux_option "@ptt-transcribing-text" "...")"
    printf '#[fg=white,bg=#d75f00,bold] %s #[fg=default,bg=default,none]' "$text"
    ;;
  *)
    rm -f "$STATEFILE"
    ;;
esac
