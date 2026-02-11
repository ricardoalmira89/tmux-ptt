#!/usr/bin/env bash
# tmux-ptt: cross-platform audio source detection
# Outputs the ffmpeg/rec arguments needed to record audio.
# https://github.com/azcro/tmux-ptt

detect_audio_source() {
  if [ "$(uname -s)" = "Darwin" ]; then
    if command -v ffmpeg >/dev/null 2>&1; then
      echo "ffmpeg -f avfoundation -i :0"
    elif command -v rec >/dev/null 2>&1; then
      echo "rec"
    else
      echo "error:no_recorder"
    fi
    return
  fi

  # Linux: PulseAudio/PipeWire > ALSA > SOX
  if command -v ffmpeg >/dev/null 2>&1; then
    if pactl info >/dev/null 2>&1; then
      echo "ffmpeg -f pulse -i default"
      return
    fi
    if arecord -l >/dev/null 2>&1; then
      echo "ffmpeg -f alsa -i default"
      return
    fi
    echo "error:no_audio_source"
    return
  fi

  if command -v rec >/dev/null 2>&1; then
    echo "rec"
    return
  fi

  echo "error:no_recorder"
}
