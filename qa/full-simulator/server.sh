#!/usr/bin/env bash
set -euo pipefail
ROOT="$RUNNER_TEMP/fourier-backend"
mkdir -p "$ROOT/home" "$ROOT/data"
export UV_CACHE_DIR="$ROOT/cache"
uv python install 3.11
uv venv --python 3.11 "$ROOT/venv"
uv pip install --python "$ROOT/venv/bin/python" 'open-webui==0.13.4'
export DATA_DIR="$ROOT/data" HOME="$ROOT/home" WEBUI_SECRET_KEY="$(openssl rand -hex 32)"
export WEBUI_ADMIN_EMAIL=fourier-qa@example.test WEBUI_ADMIN_PASSWORD="$(cat "$RUNNER_TEMP/fourier-qa-password")" WEBUI_ADMIN_NAME="Fourier QA"
export WEBUI_AUTH=True ENABLE_SIGNUP=False ENABLE_OLLAMA_API=False ENABLE_OPENAI_API=False
export OFFLINE_MODE=True HF_HUB_OFFLINE=1 RAG_EMBEDDING_MODEL_AUTO_UPDATE=False RAG_RERANKING_MODEL_AUTO_UPDATE=False WHISPER_MODEL_AUTO_UPDATE=False
export ANONYMIZED_TELEMETRY=False DO_NOT_TRACK=True
exec "$ROOT/venv/bin/open-webui" serve --host 127.0.0.1 --port 8319
