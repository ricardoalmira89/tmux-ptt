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
PTT_AUTO_STOP="$(get_tmux_option "@ptt-auto-stop" "off")"

# --- State files ---
PIDFILE="$(ptt_pidfile)"
BUSYFILE="$(ptt_busyfile)"
WAV="$(ptt_wavfile)"
OUTBASE="$(ptt_outbase)"
TXT="$(ptt_txtfile)"
LOGFILE="$(ptt_logfile)"

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
  if [ "$(get_tmux_option "@ptt-auto-enter" "off")" = "on" ]; then
    tmux set -gq @ptt_badge "#[fg=black,bg=white,bold] PTT ⏎ #[fg=default,bg=default,none]"
  else
    tmux set -gq @ptt_badge "#[fg=black,bg=white,bold] PTT #[fg=#cccccc]⏎ #[fg=default,bg=default,none]"
  fi
  tmux refresh-client -S 2>/dev/null || true
}

# --- Cleanup on exit ---
cleanup() {
  rm -f "$BUSYFILE" "$LOGFILE"
  clear_badge
}

# --- Wait for silence after speech (auto-stop mode) ---
# Monitors ffmpeg silencedetect output. Waits until silence_start appears
# and persists (no new silence_end after it) for at least 1 polling cycle.
# Skips initial silence by requiring silence_start timestamp > 0.5s.
wait_for_silence() {
  local ffmpeg_pid="$1"
  local confirmed_ts=""

  while kill -0 "$ffmpeg_pid" 2>/dev/null; do
    sleep 0.5

    # Get the last silence_start timestamp
    local last_start_ts
    last_start_ts=$(grep "silence_start" "$LOGFILE" 2>/dev/null | tail -1 \
      | sed -E 's/.*silence_start: ([0-9]+(\.[0-9]+)?).*/\1/')

    # Skip if no silence_start yet or if it's initial silence (~0)
    if [ -z "$last_start_ts" ]; then
      confirmed_ts=""
      continue
    fi
    if ! awk "BEGIN {exit !($last_start_ts > 0.5)}" 2>/dev/null; then
      confirmed_ts=""
      continue
    fi

    # Get the last silence_end timestamp (if any)
    local last_end_ts
    last_end_ts=$(grep "silence_end" "$LOGFILE" 2>/dev/null | tail -1 \
      | sed -E 's/.*silence_end: ([0-9]+(\.[0-9]+)?).*/\1/')

    # Check if silence_start is newer than silence_end (still in silence)
    local in_silence=false
    if [ -z "$last_end_ts" ]; then
      in_silence=true
    elif awk "BEGIN {exit !($last_start_ts > $last_end_ts)}" 2>/dev/null; then
      in_silence=true
    fi

    if $in_silence; then
      if [ "$confirmed_ts" = "$last_start_ts" ]; then
        # Same silence persisted across two polls — confirmed real silence
        return 0
      fi
      confirmed_ts="$last_start_ts"
    else
      confirmed_ts=""
    fi
  done

  return 1
}

# --- Start recording ---
start_recording() {
  rm -f "$WAV" "$TXT" "$LOGFILE"

  local audio_cmd
  audio_cmd="$(detect_audio_source)"

  local use_auto_stop=false
  if [ "$PTT_AUTO_STOP" = "on" ] && [[ "$audio_cmd" == ffmpeg* ]]; then
    use_auto_stop=true
  fi

  case "$audio_cmd" in
    error:*)
      tmux display-message "PTT: No audio source found (${audio_cmd#error:})"
      exit 1
      ;;
    rec)
      rec -q -c 1 -r 16000 -b 16 "$WAV" >/dev/null 2>&1 &
      ;;
    ffmpeg*)
      if $use_auto_stop; then
        local silence_dur silence_thresh silence_boost
        silence_dur="$(get_tmux_option "@ptt-silence-duration" "1")"
        silence_thresh="$(get_tmux_option "@ptt-silence-threshold" "-20")"
        silence_boost="$(get_tmux_option "@ptt-silence-boost" "0")"
        > "$LOGFILE"
        local af_filter="silencedetect=noise=${silence_thresh}dB:d=${silence_dur}"
        if [ "$silence_boost" != "0" ]; then
          af_filter="volume=${silence_boost}dB,${af_filter}"
        fi
        $audio_cmd -hide_banner -loglevel info \
          -af "$af_filter" \
          -ac 1 -ar 16000 -y "$WAV" 2>"$LOGFILE" &
      else
        $audio_cmd -hide_banner -loglevel error \
          -ac 1 -ar 16000 -y "$WAV" >/dev/null 2>&1 &
      fi
      ;;
  esac

  echo $! > "$PIDFILE"
  local rec_text
  rec_text="$(get_tmux_option "@ptt-recording-text" "Recording")"
  set_badge "🔴 $rec_text" "red"

  # Auto-stop: wait for silence, then transcribe
  if $use_auto_stop; then
    local ffmpeg_pid
    ffmpeg_pid="$(cat "$PIDFILE")"

    if wait_for_silence "$ffmpeg_pid"; then
      # Silence detected after speech — auto-stop
      if [ ! -f "$BUSYFILE" ] && [ -f "$PIDFILE" ]; then
        stop_and_transcribe
      fi
    fi
    # If ffmpeg died (manual override or error), just exit
  fi
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
  set_badge "✏️ $trans_text" "#d75f00"

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

  # Auto-enter: send Enter key after pasting
  if [ "$(get_tmux_option "@ptt-auto-enter" "off")" = "on" ]; then
    tmux send-keys Enter
  fi
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
