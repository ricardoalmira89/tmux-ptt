#!/usr/bin/env bash
# tmux-ptt: shared helpers
# https://github.com/azcro/tmux-ptt

get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local option_value
  option_value="$(tmux show-option -gqv "$option")"
  if [ -z "$option_value" ]; then
    echo "$default_value"
  else
    echo "$option_value"
  fi
}

set_tmux_option() {
  tmux set-option -gq "$1" "$2"
}

is_macos() {
  [ "$(uname -s)" = "Darwin" ]
}

is_linux() {
  [ "$(uname -s)" = "Linux" ]
}

ptt_state_dir() {
  local dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-ptt-${USER:-$(id -un)}"
  mkdir -p "$dir"
  echo "$dir"
}

ptt_pidfile()   { echo "$(ptt_state_dir)/rec.pid"; }
ptt_busyfile()  { echo "$(ptt_state_dir)/busy"; }
ptt_wavfile()   { echo "$(ptt_state_dir)/rec.wav"; }
ptt_outbase()   { echo "$(ptt_state_dir)/out"; }
ptt_txtfile()   { echo "$(ptt_state_dir)/out.txt"; }
ptt_statefile() { echo "$(ptt_state_dir)/state"; }
