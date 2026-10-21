# kaani male + female Urdu TTS — portable server

A self-contained package of the Urdu kiosk text-to-speech server. It speaks Urdu (with
English words, names and numbers mixed in) in **two voices from one checkpoint** —
`male` (speaker row 0) and `female` (speaker row 1) — over a simple HTTP API.

Everything the server needs is **inside this folder** — code, model checkpoint, vocoder,
vocabulary and lookup tables. It loads nothing from outside the folder and needs **no
internet at run time**. You run it in Docker, so the only things to install on the target
machine are Docker itself (and, for GPU, the NVIDIA toolkit).

---

## Table of contents

1. [What you need](#1-what-you-need)
2. [What's in this folder](#2-whats-in-this-folder)
3. [Step 1 — copy this folder to the target machine](#3-step-1--copy-this-folder-to-the-target-machine)
4. [Step 2 — install Docker](#4-step-2--install-docker)
5. [Step 3 — GPU only: install the NVIDIA Container Toolkit](#5-step-3--gpu-only-install-the-nvidia-container-toolkit)
6. [Step 4 — configure (port, default voice, CPU vs GPU)](#6-step-4--configure-port-default-voice-cpu-vs-gpu)
7. [Step 5 — build and start](#7-step-5--build-and-start)
8. [Step 6 — verify it works](#8-step-6--verify-it-works)
9. [Managing the service](#9-managing-the-service-logs-stop-restart-update)
10. [Configuration reference](#10-configuration-reference)
11. [HTTP API](#11-http-api)
12. [Connecting the kiosk (or any client)](#12-connecting-the-kiosk-or-any-client)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. What you need

**Hardware / OS**

- A **64-bit x86-64 Linux** machine (Ubuntu 22.04 / 24.04 or Debian 12 recommended).
  - *Windows:* works via **Docker Desktop + WSL2** — see the note in [Step 2](#4-step-2--install-docker). GPU needs WSL2 + a recent NVIDIA driver.
  - *macOS:* runs **CPU-only** (no NVIDIA GPU passthrough). Fine for testing, slower.
  - This package is built for x86-64; it will **not** run as-is on ARM (Apple Silicon, Raspberry Pi) because of a bundled compiled extension.
- **RAM:** 8 GB minimum, 16 GB comfortable.
- **Free disk:** **~15 GB** for the Docker image (torch + CUDA libraries are large). Check with `df -h /`.
- **GPU (optional but recommended):** any NVIDIA card with a current driver. Without a GPU the server runs on CPU automatically — the first word is slower, but it still works.

**Software (installed in the steps below)**

- Docker Engine + the Docker Compose plugin.
- *(GPU only)* NVIDIA driver + NVIDIA Container Toolkit.

You do **not** need Python, CUDA, espeak, or any of the model tooling on the host — all of
that lives inside the Docker image.

---

## 2. What's in this folder

```
kiosk-tts-server/
├── server/                     app.py (HTTP routes) + engine.py (the loaded, warm model)
├── src/
│   ├── paths.py                every file location the code uses
│   └── common/                 text front end + model-loading code
├── vendor/Matcha-TTS/          the Matcha-TTS engine (incl. a prebuilt CPython-3.12 x86-64 extension)
├── checkpoints/
│   └── kaani_male_female/       the male+female checkpoint (step=003999.ckpt)  ← the voices
├── models/
│   ├── base/vocab.json          the 350-symbol vocabulary the front end reads
│   └── vocoder/                 the Vocos 22 kHz vocoder (mel → audio)
├── assets/                     dict / NeMo number grammars / NLTK WordNet / transliteration pairs
├── requirements-server.txt     the serving-only Python dependencies (installed into the image)
├── Dockerfile                  how the image is built
├── docker-compose.yml          how the container is run  ← edit this to configure
├── .dockerignore
└── README.md                   this file
```

---

## 3. Step 1 — copy this folder to the target machine

This folder is a git repository. On another machine, just clone it:

```bash
git clone <this-repo-url> ~/kiosk-tts-server
cd ~/kiosk-tts-server
```

(rsync/scp/USB copy of the whole folder also still works if you don't want to use git.)

Two small cache folders are **not in git** — `assets/nemo_cache/` and `assets/nltk_data/`.
`assets/nemo_cache/` regenerates itself on first run (NeMo's text-normalization grammar
cache); `assets/nltk_data/` (WordNet) is fetched once with:

```bash
python3 -c "import nltk; nltk.download('wordnet', download_dir='assets/nltk_data')"
```

Everything else needed to run the server — code, the `checkpoints/kaani_male_female/` model,
the vocoder, vocabulary and lookup tables — is tracked in git, so no other download step is
needed.

---

## 4. Step 2 — install Docker

> Skip this step if `docker --version` and `docker compose version` already work on the target.

### Ubuntu / Debian (official Docker repository)

```bash
# 1. remove any old/conflicting packages (ok if it says nothing is installed)
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# 2. add Docker's official repository
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# (on Debian, replace 'ubuntu' with 'debian' in both the key URL and the repo line above)

# 3. install Docker Engine + the Compose plugin
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Start Docker and make it start on boot

```bash
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager        # should say "active (running)"
```

### (Recommended) run Docker without typing `sudo` every time

```bash
sudo usermod -aG docker $USER
# then LOG OUT and LOG BACK IN (or run: newgrp docker) for it to take effect
docker run --rm hello-world                     # verify it works without sudo
```

> If you skip this, prefix every `docker`/`docker compose` command below with `sudo`.

### Windows / macOS

Install **Docker Desktop** (<https://www.docker.com/products/docker-desktop/>). On Windows,
enable the **WSL2** backend. Then open a terminal (WSL/Ubuntu on Windows, Terminal on macOS),
`cd` into the copied folder, and continue from [Step 4](#6-step-4--configure-port-default-voice-cpu-vs-gpu).
GPU on Windows needs WSL2 + a recent NVIDIA driver; macOS is CPU-only.

---

## 5. Step 3 — GPU only: install the NVIDIA Container Toolkit

> **No NVIDIA GPU?** Skip this entire step and go to [Step 4](#6-step-4--configure-port-default-voice-cpu-vs-gpu)
> — you'll turn the GPU block off there and the server will run on CPU.

First confirm the host has a working NVIDIA driver:

```bash
nvidia-smi        # must print your GPU and a driver version. If "command not found",
                  # install the driver first: sudo ubuntu-drivers autoinstall && reboot
```

Then install the toolkit that lets containers use the GPU:

```bash
# add the toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# wire it into Docker and restart the daemon
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify a container can see the GPU:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
# should print the same GPU table as the host's nvidia-smi
```

---

## 6. Step 4 — configure (port, default voice, CPU vs GPU)

Open **`docker-compose.yml`** and adjust it for the target machine. The important settings:

| Setting | Where | What it does |
|---|---|---|
| **Host port** | `ports: "8030:8030"` | Left number = the port on the host. Change to e.g. `"9000:8030"` to serve on host port 9000. |
| **Default voice** | `KIOSK_TTS_DEFAULT_VOICE` | Voice used by a bare `/v1/tts` call (`male` or `female`). The `/v1/tts/male` and `/v1/tts/female` routes always override it. |
| **GPU vs CPU** | the `deploy:` block | **Keep it** if the host has a GPU + toolkit (Step 3). **Delete the whole `deploy:` block** if the host has no GPU — the same image then runs on CPU automatically. |

**By default the server only listens on the machine it runs on and its LAN** via the mapped
port. If you want other machines on the network to reach it, make sure the host firewall
allows the port (e.g. `sudo ufw allow 8030/tcp`).

---

## 7. Step 5 — build and start

```bash
cd ~/kiosk-tts-server

# build the image (first time downloads torch + CUDA — several GB, can take 5–20 min)
docker compose build

# start it in the background
docker compose up -d

# watch it load — wait for the line:  READY in <N> s  http://0.0.0.0:8030 ...
docker compose logs -f
```

(You can do build + start in one go with `docker compose up --build -d`.)

First startup inside the container takes **~10–15 seconds** to load and warm the model,
vocoder, number grammars, espeak and CUDA kernels. After that it stays warm and responds
in well under a second per sentence.

---

## 8. Step 6 — verify it works

```bash
# 1. health — should show "ready": true and list the two voices
curl -s localhost:8030/healthz | python3 -m json.tool

# 2. male voice -> male.wav
curl -s -X POST localhost:8030/v1/tts/male   -H 'Content-Type: application/json' \
     -d '{"text":"السلام علیکم، MARI میں خوش آمدید۔"}' -o male.wav

# 3. female voice -> female.wav
curl -s -X POST localhost:8030/v1/tts/female -H 'Content-Type: application/json' \
     -d '{"text":"السلام علیکم، MARI میں خوش آمدید۔"}' -o female.wav

# 4. play them (any audio player)
#    ffplay male.wav   /   aplay female.wav   /   open on Windows/macOS
```

If `/healthz` returns `{"ready": true, ...}` and the two `.wav` files play the right voices,
the server is good to go.

---

## 9. Managing the service (logs, stop, restart, update)

```bash
docker compose ps                 # is it running?
docker compose logs -f            # follow logs (Ctrl-C to stop watching)
docker compose restart            # restart the server
docker compose stop               # stop it (keeps the container)
docker compose up -d              # start it again
docker compose down               # stop and remove the container (image is kept)
```

The service is set to `restart: unless-stopped`, so it comes back automatically after a
reboot or a crash (as long as Docker itself starts on boot — see Step 2).

**Updating the model or code later:** replace the files in this folder (e.g. drop a new
checkpoint into `checkpoints/kaani_male_female/`), then rebuild:

```bash
docker compose up --build -d
```

---

## 10. Configuration reference

**Environment variables** (set under `environment:` in `docker-compose.yml`):

| Variable | Default | Meaning |
|---|---|---|
| `KIOSK_TTS_DEFAULT_VOICE` | `female` | Voice for a bare `/v1/tts` call: `male` or `female`. |

**Startup flags** (the container runs `python server/app.py --host 0.0.0.0 --port 8030`; to
change them, edit the `CMD` line at the bottom of the `Dockerfile` and rebuild):

| Flag | Default | Meaning |
|---|---|---|
| `--port` | `8030` | Port **inside** the container (leave at 8030; map it on the host in compose). |
| `--vocoder-device` | `cpu` | Set to `cuda` to run the vocoder on the GPU too (~38 ms faster per sentence, audio differs very slightly). GPU must be enabled. |
| `--device` | auto | Model device; auto-detects `cuda` if available, else `cpu`. Rarely needs setting. |

**Checkpoint:** baked into the image at build time. To swap it **without rebuilding**, mount
a volume over it in `docker-compose.yml` under the `tts` service:

```yaml
    volumes:
      - ./checkpoints/kaani_male_female:/app/checkpoints/kaani_male_female
```

---

## 11. HTTP API

Base URL: `http://<host>:8030`

| Method | Path | Body | Returns |
|---|---|---|---|
| GET  | `/healthz`       | —                                        | `{"ready": true, "voices": [...], "default_voice", "sample_rate", "device", ...}` |
| POST | `/v1/tts`        | `{"text", "speed"?, "voice"?, "seed"?}`  | `audio/wav` — 16-bit PCM, mono, 22050 Hz |
| POST | `/v1/tts/male`   | `{"text", "speed"?, "seed"?}`            | `audio/wav` — always the male voice |
| POST | `/v1/tts/female` | `{"text", "speed"?, "seed"?}`            | `audio/wav` — always the female voice |
| POST | `/v1/normalize`  | `{"text"}`                               | `{"sentences": [{"text","read"}]}` — what the model will actually say |

**Parameters**

- `text` — the text to speak (Urdu, English, or mixed). Max 3000 characters.
- `voice` — `male` / `m` / `0` / `hamza`, or `female` / `f` / `1` / `maryam`. Absent → the
  default voice. `/v1/tts` also accepts it as a query string: `POST /v1/tts?voice=male`.
- `speed` — 0.6–1.5, higher = faster (clamped to that range). Default `1.0`.
- `seed` — integer; the same `text` + `voice` + `speed` + `seed` always gives the same audio
  (results are cached, so repeats are instant). Default `1`.

**Response headers** on the audio routes: `X-Voice`, `X-Read` (url-encoded, what was read),
`X-Timing-Frontend-Ms`, `X-Timing-Model-Ms`, `X-Audio-Seconds`, `X-Cached`.

---

## 12. Connecting the kiosk (or any client)

Any client just POSTs text and gets back a WAV. From another machine, use the server's IP or
hostname instead of `localhost`, e.g. `http://192.168.1.50:8030/v1/tts/female`.

**If the client is itself a Docker container on the same host:** it cannot reach the server
via `localhost` (that's the container's own loopback). Use the host's Docker-bridge address
`172.17.0.1`, or put both on a shared Docker network. For the MARI kiosk specifically, see the
`MARI_INTEGRATION.md` notes in the original project — the kiosk posts `{"text","speed"}` and is
routed to `/v1/tts/male` or `/v1/tts/female` per presenter.

Minimal Python client:

```python
import requests
r = requests.post("http://SERVER_HOST:8030/v1/tts/female",
                  json={"text": "السلام علیکم۔", "speed": 1.0})
open("out.wav", "wb").write(r.content)
```

---

## 13. Troubleshooting

**`docker: permission denied` / `cannot connect to the Docker daemon`**
You didn't add yourself to the `docker` group, or Docker isn't running. Either prefix commands
with `sudo`, or do the `usermod -aG docker $USER` step in Step 2 (then log out/in). Check the
daemon with `sudo systemctl status docker`; start it with `sudo systemctl start docker`.

**Build fails with "no space left on device" or stops partway**
The image needs ~15 GB. Check `df -h /`. Free space, or move Docker's storage to a bigger disk.
Clear old/unused Docker data with `docker system prune -a` (this removes images/containers you
aren't using — read what it lists before confirming).

**`could not select device driver "nvidia"` / GPU not found when starting**
The NVIDIA Container Toolkit (Step 3) isn't installed or wasn't wired into Docker. Either
complete Step 3 (and `sudo systemctl restart docker`), **or** if this host has no GPU, delete
the `deploy:` block in `docker-compose.yml` to run on CPU.

**`/healthz` never returns / logs stop before "READY"**
Give it up to ~30 s on first load. If it still hasn't printed `READY`, check `docker compose logs`
for an error. Out-of-memory during load shows as the container exiting/restarting — give the
machine more RAM, or (on a GPU host that's short on VRAM) the model will still load on CPU.

**Port already in use (`bind: address already in use`)**
Something else is on host port 8030. Change the left number in `ports:` (e.g. `"9000:8030"`).

**It runs but sounds wrong / silent**
Confirm you POSTed non-empty `text` and got a `200` with a `audio/wav` body (not a JSON error).
`curl -v` shows the status and the `X-Read` header (what the model actually read). Max text
length is 3000 characters — longer requests return a 400.

**Reminder:** this image is **Linux x86-64 only** (a bundled compiled extension). It will not
run on ARM/Apple-Silicon hosts.
