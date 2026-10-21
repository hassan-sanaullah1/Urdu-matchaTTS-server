# kaani male+female Urdu TTS server.
# The cu124 torch wheels bundle the CUDA runtime, so this one image runs on a GPU
# host (with `--gpus all` + the NVIDIA container toolkit) and falls back to CPU on a
# host without a GPU — no change needed. The engine auto-detects CUDA at startup.
FROM python:3.12-slim-bookworm

# espeak-ng: the English g2p front end calls libespeak-ng.so.1 in-process (needs the
#   ur / en-us / en-gb-x-rp voices, all in the espeak-ng-data package).
# libsndfile1: soundfile reads/writes the WAV audio. libgomp1: OpenMP for torch/librosa.
RUN apt-get update && apt-get install -y --no-install-recommends \
        espeak-ng espeak-ng-data libsndfile1 libgomp1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HF_HUB_OFFLINE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install Python deps first so the big torch layer is cached across code changes.
# build-essential + python3-dev are needed to compile a couple of C-extension deps
# (e.g. cdifflib, pulled in by nemo_text_processing); they are purged in the same
# layer afterwards so they add nothing to the final image.
COPY requirements-server.txt .
RUN apt-get update && apt-get install -y --no-install-recommends build-essential python3-dev \
    && pip install --upgrade pip \
    && pip install --extra-index-url https://download.pytorch.org/whl/cu124 -r requirements-server.txt \
    && pip install --no-deps diffusers==0.25.0 conformer==0.3.2 \
    && apt-get purge -y build-essential python3-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# App code + bundled weights/assets (the whole deploy folder, see .dockerignore).
COPY . .

EXPOSE 8030

# Container-internal health check (no curl in the slim image).
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python -c "import urllib.request,sys,json; sys.exit(0 if json.load(urllib.request.urlopen('http://127.0.0.1:8030/healthz')).get('ready') else 1)"

# 0.0.0.0 so the port is reachable from outside the container.
CMD ["python", "server/app.py", "--host", "0.0.0.0", "--port", "8030"]
