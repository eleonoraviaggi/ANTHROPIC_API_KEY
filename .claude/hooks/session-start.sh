#!/bin/bash
# Prepares Claude Code cloud sessions for video work:
# Remotion deps, HyperFrames render browser, whisper.cpp + a Whisper model.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

export HYPERFRAMES_NO_TELEMETRY=1
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
WHISPER_SRC="$HOME/.local/src/whisper.cpp"
WHISPER_MODEL="${WHISPER_MODEL:-small.en}"
MODELS_DIR="$HOME/.cache/hyperframes/whisper/models"

log() { echo "[session-start] $*" >&2; }

# Remotion project dependencies
if [ -f "$PROJECT_DIR/my-video/package.json" ]; then
  log "Installing Remotion dependencies"
  (cd "$PROJECT_DIR/my-video" && npm install --no-audit --no-fund --loglevel=error)
  # Remotion downloads its own Chrome from remotion.media; skip if the network blocks it.
  (cd "$PROJECT_DIR/my-video" && npx remotion browser ensure >/dev/null 2>&1) \
    || log "WARN: Remotion browser download failed (is remotion.media allowed?)"
fi

# HyperFrames headless Chrome for local rendering
log "Ensuring HyperFrames render browser"
npx --yes hyperframes browser ensure >/dev/null 2>&1 \
  || log "WARN: hyperframes browser ensure failed"

# whisper.cpp, built from source and put on PATH
if ! command -v whisper-cli >/dev/null 2>&1; then
  if [ ! -x "$WHISPER_SRC/build/bin/whisper-cli" ]; then
    log "Building whisper.cpp"
    if [ ! -d "$WHISPER_SRC/.git" ]; then
      mkdir -p "$(dirname "$WHISPER_SRC")"
      git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_SRC"
    fi
    cmake -S "$WHISPER_SRC" -B "$WHISPER_SRC/build" \
      -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_TESTS=OFF >/dev/null
    cmake --build "$WHISPER_SRC/build" -j"$(nproc)" --config Release >/dev/null
  fi
  ln -sf "$WHISPER_SRC/build/bin/whisper-cli" /usr/local/bin/whisper-cli
fi

# Whisper model where the HyperFrames CLI looks for it; needs huggingface.co allowed.
MODEL_FILE="$MODELS_DIR/ggml-$WHISPER_MODEL.bin"
if [ ! -s "$MODEL_FILE" ]; then
  log "Downloading Whisper model $WHISPER_MODEL"
  mkdir -p "$MODELS_DIR"
  if curl -fsSL --retry 3 -o "$MODEL_FILE.part" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$WHISPER_MODEL.bin"; then
    mv "$MODEL_FILE.part" "$MODEL_FILE"
  else
    rm -f "$MODEL_FILE.part"
    log "WARN: Whisper model download failed (is huggingface.co allowed?)"
  fi
fi

log "Done"
