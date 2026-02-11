#!/usr/bin/env bash
set -euo pipefail
# tmux-ptt: main toggle script
# Called via run-shell -b when the user presses the PTT key.
# https://github.com/azcro/tmux-ptt

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/detect_audio.sh"

# --- Read config ---
PTT_LANG="$(get_tmux_option "@ptt-lang" "en")"
PTT_BACKEND="$(get_tmux_option "@ptt-backend" "auto")"

# --- State files ---
PIDFILE="$(ptt_pidfile)"
BUSYFILE="$(ptt_busyfile)"
WAV="$(ptt_wavfile)"
OUTBASE="$(ptt_outbase)"
TXT="$(ptt_txtfile)"

# --- Guard: ignore keypress during transcription ---
if [ -f "$BUSYFILE" ]; then
  exit 0
fi

# --- Badge helpers ---
set_badge() {
  local text="$1" bg="$2"
  tmux set -gq @ptt_badge "#[fg=white,bg=$bg,bold] $text #[fg=default,bg=default,none]"
  tmux refresh-client -S
}

clear_badge() {
  tmux set -gq @ptt_badge ""
  tmux refresh-client -S 2>/dev/null || true
}

# --- Cleanup on exit ---
cleanup() {
  rm -f "$BUSYFILE"
  clear_badge
}

# --- Start recording ---
start_recording() {
  rm -f "$WAV" "$TXT"

  local audio_cmd
  audio_cmd="$(detect_audio_source)"

  case "$audio_cmd" in
    error:*)
      tmux display-message "PTT: No audio source found (${audio_cmd#error:})"
      exit 1
      ;;
    rec)
      rec -q -c 1 -r 16000 -b 16 "$WAV" >/dev/null 2>&1 &
      ;;
    ffmpeg*)
      $audio_cmd -hide_banner -loglevel error \
        -ac 1 -ar 16000 -y "$WAV" >/dev/null 2>&1 &
      ;;
  esac

  echo $! > "$PIDFILE"
  local rec_text
  rec_text="$(get_tmux_option "@ptt-recording-text" "Recording")"
  set_badge "$rec_text" "red"
}

# --- Stop recording and transcribe ---
stop_and_transcribe() {
  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  rm -f "$PIDFILE"

  touch "$BUSYFILE"
  trap cleanup EXIT TERM INT

  # Gracefully stop recorder
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null || true
    local i=0
    while [ $i -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
      sleep 0.1
      i=$((i + 1))
    done
    kill -9 "$pid" 2>/dev/null || true
  fi

  if [ ! -s "$WAV" ]; then
    exit 0
  fi

  # Update indicator
  local trans_text
  trans_text="$(get_tmux_option "@ptt-transcribing-text" "Transcribing")"
  set_badge "$trans_text" "#d75f00"

  # Transcribe
  "$CURRENT_DIR/transcribe.sh" "$WAV" "$OUTBASE" "$PTT_LANG" "$PTT_BACKEND"

  if [ ! -s "$TXT" ]; then
    exit 0
  fi

  # Clean timestamps, normalize whitespace
  local text
  text="$(sed -E 's/\[[0-9:. -]+\]//g' "$TXT" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')"

  if [ -z "$text" ]; then
    exit 0
  fi

  # Paste into active pane
  tmux set-buffer -- "$text"
  tmux paste-buffer -d
}

# --- Main toggle ---
if [ -f "$PIDFILE" ]; then
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    stop_and_transcribe
  else
    rm -f "$PIDFILE"
    clear_badge
    start_recording
  fi
else
  start_recording
fi
