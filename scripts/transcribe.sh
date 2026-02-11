#!/usr/bin/env bash
set -euo pipefail
# tmux-ptt: whisper backend abstraction
# Usage: transcribe.sh <wav> <outbase> <lang> <backend>
# https://github.com/azcro/tmux-ptt

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

WAV="$1"
OUTBASE="$2"
LANG="$3"
BACKEND="$4"
TXT="${OUTBASE}.txt"

# --- Resolve whisper-cli path ---
resolve_whisper_path() {
  local explicit
  explicit="$(get_tmux_option "@ptt-whisper-path" "")"
  if [ -n "$explicit" ] && [ -x "$explicit" ]; then
    echo "$explicit"
    return
  fi

  local candidate
  for candidate in \
    "$(command -v whisper-cli 2>/dev/null || true)" \
    "$HOME/apps/whisper.cpp/build/bin/whisper-cli" \
    "/usr/local/bin/whisper-cli" \
    "/opt/homebrew/bin/whisper-cli"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
}

# --- Resolve whisper model path ---
resolve_model_path() {
  local explicit
  explicit="$(get_tmux_option "@ptt-model" "")"
  if [ -n "$explicit" ] && [ -f "$explicit" ]; then
    echo "$explicit"
    return
  fi

  local whisper_path
  whisper_path="$(resolve_whisper_path)"
  [ -z "$whisper_path" ] && return

  local whisper_dir
  whisper_dir="$(dirname "$whisper_path")"

  local preferred
  if [ "$LANG" = "en" ]; then
    preferred="ggml-base.en.bin"
  else
    preferred="ggml-small.bin"
  fi

  local dir
  for dir in \
    "$whisper_dir/../models" \
    "$whisper_dir/../../models" \
    "$HOME/.local/share/whisper.cpp/models" \
    "$HOME/apps/whisper.cpp/models"; do
    if [ -f "$dir/$preferred" ]; then
      echo "$dir/$preferred"
      return
    fi
  done

  # Fallback: any ggml model
  for dir in \
    "$whisper_dir/../models" \
    "$whisper_dir/../../models" \
    "$HOME/.local/share/whisper.cpp/models" \
    "$HOME/apps/whisper.cpp/models"; do
    local found
    found="$(find "$dir" -maxdepth 1 -name 'ggml-*.bin' 2>/dev/null | head -1)"
    if [ -n "$found" ]; then
      echo "$found"
      return
    fi
  done
}

# --- Auto-detect backend ---
resolve_backend() {
  if [ "$1" != "auto" ]; then
    echo "$1"
    return
  fi

  if [ -n "$(resolve_whisper_path)" ]; then
    echo "whisper-cpp"
    return
  fi

  local api_key
  api_key="$(get_tmux_option "@ptt-openai-key" "${OPENAI_API_KEY:-}")"
  if [ -n "$api_key" ] && command -v curl >/dev/null 2>&1; then
    echo "openai-api"
    return
  fi

  echo "none"
}

# --- Backend: whisper.cpp ---
transcribe_whisper_cpp() {
  local whisper_path model_path
  whisper_path="$(resolve_whisper_path)"
  model_path="$(resolve_model_path)"

  if [ -z "$whisper_path" ]; then
    tmux display-message "PTT: whisper-cli not found. Set @ptt-whisper-path"
    exit 1
  fi
  if [ -z "$model_path" ]; then
    tmux display-message "PTT: No whisper model found. Set @ptt-model"
    exit 1
  fi

  "$whisper_path" \
    -m "$model_path" \
    -l "$LANG" \
    -f "$WAV" \
    -of "$OUTBASE" \
    -otxt \
    >/dev/null 2>&1 || true
}

# --- Backend: OpenAI API ---
transcribe_openai_api() {
  local api_key
  api_key="$(get_tmux_option "@ptt-openai-key" "${OPENAI_API_KEY:-}")"

  if [ -z "$api_key" ]; then
    tmux display-message "PTT: No OpenAI API key. Set @ptt-openai-key or \$OPENAI_API_KEY"
    exit 1
  fi

  local response
  response="$(curl -s --max-time 30 \
    https://api.openai.com/v1/audio/transcriptions \
    -H "Authorization: Bearer $api_key" \
    -F "file=@$WAV" \
    -F "model=whisper-1" \
    -F "language=$LANG" \
    -F "response_format=text")" || {
    tmux display-message "PTT: OpenAI API request failed"
    exit 1
  }

  printf '%s\n' "$response" > "$TXT"
}

# --- Main ---
backend="$(resolve_backend "$BACKEND")"

case "$backend" in
  whisper-cpp)    transcribe_whisper_cpp ;;
  openai-api)     transcribe_openai_api ;;
  none)
    tmux display-message "PTT: No transcription backend found"
    exit 1
    ;;
  *)
    tmux display-message "PTT: Unknown backend '$backend'"
    exit 1
    ;;
esac
