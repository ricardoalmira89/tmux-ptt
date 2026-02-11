# tmux-ptt

Push To Talk for tmux. Record your voice, transcribe it, and paste the text directly into your terminal.

tmux-ptt is a tmux plugin that adds voice-to-text input. Press a key to start recording, press it again to stop. The audio is transcribed using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (local, offline) or the [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text) (cloud), and the resulting text is pasted into your active pane.

## Features

- **Push-to-talk toggle** &mdash; single key to start/stop recording
- **Auto-stop mode** &mdash; automatically stops recording when you stop speaking (voice activity detection via ffmpeg)
- **Instant status badge** &mdash; colored indicator in the status bar (red = recording, orange = transcribing)
- **Two transcription backends** &mdash; local whisper.cpp or OpenAI API
- **Cross-platform audio** &mdash; Linux (PulseAudio, ALSA) and macOS (AVFoundation)
- **Configurable** &mdash; keybinding, language, backend, badge text, model path
- **Auto-detection** &mdash; finds whisper-cli binary and models automatically
- **TPM compatible** &mdash; standard tmux plugin manager installation

## Requirements

### Required

- **tmux** 3.2+
- **ffmpeg** (recording) &mdash; or **SoX** (`rec`) as fallback
- **bash** 4+

### Audio (one of)

| Platform | Source | Command |
|----------|--------|---------|
| Linux | PulseAudio / PipeWire | `ffmpeg -f pulse` |
| Linux | ALSA | `ffmpeg -f alsa` |
| macOS | AVFoundation | `ffmpeg -f avfoundation` |
| Any | SoX | `rec` |

Install ffmpeg on your system:

```bash
# Debian/Ubuntu
sudo apt install ffmpeg

# Fedora
sudo dnf install ffmpeg

# macOS
brew install ffmpeg
```

### Transcription (one of)

#### Option A: whisper.cpp (local, offline)

Build from source:

```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build
cmake --build build --config Release
```

Download a model:

```bash
# English only (fast, ~142 MB)
./models/download-ggml-model.sh base.en

# Multilingual (slower, ~466 MB) — required for non-English languages
./models/download-ggml-model.sh small
```

The plugin auto-detects `whisper-cli` in these locations:

1. System `$PATH`
2. `~/apps/whisper.cpp/build/bin/whisper-cli`
3. `/usr/local/bin/whisper-cli`
4. `/opt/homebrew/bin/whisper-cli`

Models are searched relative to the binary, plus:

- `~/.local/share/whisper.cpp/models/`
- `~/apps/whisper.cpp/models/`

#### Option B: OpenAI API (cloud)

Set your API key:

```bash
# Environment variable
export OPENAI_API_KEY="sk-..."

# Or tmux option
set -g @ptt-openai-key "sk-..."
```

Requires `curl`. Uses the `whisper-1` model via the `/v1/audio/transcriptions` endpoint.

## Installation

### With TPM

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'azcro/tmux-ptt'
```

Press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/azcro/tmux-ptt.git ~/tmux-ptt
```

Add to your `~/.tmux.conf`:

```tmux
run-shell '~/tmux-ptt/ptt.tmux'
```

Reload: `tmux source-file ~/.tmux.conf`

## Changing the PTT key

By default, the plugin uses `F9` to toggle recording. To use a different key, add this to your `~/.tmux.conf` **before** the plugin is loaded:

```tmux
set -g @ptt-key 'C-p'       # Ctrl+P
```

Common key formats: `F1`&ndash;`F12`, `C-x` (Ctrl+x), `M-x` (Alt+x), `C-M-x` (Ctrl+Alt+x).

Reload after changing: `tmux source-file ~/.tmux.conf`

## Status bar setup

Add `#{E:@ptt_badge}` to your `status-right` (or `status-left`) where you want the badge to appear:

```tmux
set -g status-right "#{E:@ptt_badge} | %H:%M | %d-%b"
```

For **Oh my tmux** users, add it to `tmux_conf_theme_status_right` in `.tmux.conf.local`:

```tmux
tmux_conf_theme_status_right="#{E:@ptt_badge} #{prefix}#{mouse}#{pairing}#{synchronized} ..."
```

The badge shows nothing when idle, so it takes no space when you are not using PTT.

## Configuration

All options are set via tmux's `set -g @option value` syntax.

| Option | Default | Description |
|--------|---------|-------------|
| `@ptt-key` | `F9` | Key to toggle recording |
| `@ptt-lang` | `en` | Transcription language (ISO 639-1 code) |
| `@ptt-backend` | `auto` | Backend: `whisper-cpp`, `openai-api`, or `auto` |
| `@ptt-whisper-path` | *(auto)* | Path to `whisper-cli` binary |
| `@ptt-model` | *(auto)* | Path to GGML model file |
| `@ptt-openai-key` | `$OPENAI_API_KEY` | OpenAI API key |
| `@ptt-recording-text` | `Recording` | Badge text while recording |
| `@ptt-transcribing-text` | `Transcribing` | Badge text while transcribing |
| `@ptt-auto-stop` | `off` | `on` to auto-stop when you stop speaking |
| `@ptt-silence-duration` | `2` | Seconds of silence before auto-stop triggers |
| `@ptt-silence-threshold` | `-30` | Noise threshold in dB for silence detection |

### Example

```tmux
# Use Ctrl+P as the PTT key
set -g @ptt-key 'C-p'

# Transcribe in Spanish using local whisper
set -g @ptt-lang 'es'
set -g @ptt-backend 'whisper-cpp'

# Custom model path
set -g @ptt-model '~/models/ggml-small.bin'

# Custom badge text
set -g @ptt-recording-text 'REC'
set -g @ptt-transcribing-text '...'
```

### Auto-stop mode

Enable auto-stop to let the plugin detect when you finish speaking. The recording stops automatically after a period of silence, so you only need to press the key once to start:

```tmux
set -g @ptt-auto-stop 'on'

# Optional: adjust silence sensitivity
set -g @ptt-silence-duration '3'    # wait 3 seconds of silence (default: 2)
set -g @ptt-silence-threshold '-25' # less sensitive to quiet sounds (default: -30)
```

Auto-stop requires ffmpeg as the audio recorder. If you use SoX (`rec`), auto-stop is not available and the plugin falls back to manual toggle mode.

You can still press the key during recording to stop it manually, overriding auto-stop.

## How it works

### Manual mode (default)

1. **Press the PTT key** &mdash; ffmpeg starts recording audio (16 kHz, mono, 16-bit WAV)
2. **Status badge turns red** &mdash; shows "Recording" in the status bar
3. **Press the key again** &mdash; recording stops, badge turns orange ("Transcribing")
4. **Transcription runs** &mdash; whisper.cpp or OpenAI API processes the audio
5. **Text is pasted** &mdash; transcribed text goes directly into the active pane
6. **Badge disappears** &mdash; status bar returns to normal

### Auto-stop mode

1. **Press the PTT key** &mdash; recording starts with voice activity detection enabled
2. **Speak normally** &mdash; the plugin listens for your voice
3. **Stop speaking** &mdash; after the configured silence duration (default: 2 seconds), recording stops automatically
4. **Transcription runs** &mdash; same as manual mode
5. **Text is pasted** &mdash; no second keypress needed

## Troubleshooting

### No audio recorded

- Check that ffmpeg is installed: `ffmpeg -version`
- On Linux, verify PulseAudio/PipeWire is running: `pactl info`
- Try recording manually: `ffmpeg -f pulse -i default -ac 1 -ar 16000 -t 3 /tmp/test.wav`

### Transcription fails

- Verify whisper-cli is found: `which whisper-cli`
- Set the path explicitly: `set -g @ptt-whisper-path '/path/to/whisper-cli'`
- Check that a model exists: `ls ~/apps/whisper.cpp/models/ggml-*.bin`
- For non-English languages, use a multilingual model (`ggml-small.bin`, not `ggml-base.en.bin`)

### Badge not showing

- Make sure `#{E:@ptt_badge}` is in your `status-right` or `status-left`
- Reload config: `tmux source-file ~/.tmux.conf`
- Test manually: `tmux set -gq @ptt_badge "#[bg=red,bold] TEST #[none]"`

### OpenAI API errors

- Verify your key: `echo $OPENAI_API_KEY`
- Check connectivity: `curl -s https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY" | head -c 100`
- Set the key in tmux: `set -g @ptt-openai-key "sk-..."`

## Disclaimer

This project was entirely written by AI using [Claude Code](https://claude.ai/), Anthropic's CLI coding agent. No line of code was manually written by a human. While it has been tested and works as intended, please review the code before using it in your workflow. AI-generated code may contain subtle bugs or edge cases that were not caught during development. Use at your own risk.

## License

[MIT](LICENSE)
