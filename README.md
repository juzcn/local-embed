# local-embed

**A standalone local embedding service.** Run it on your machine, point any
OpenAI-compatible client at it, and embed text through your own models —
no API key, no network, no per-token cost.

```bash
local-embed set-gguf bge-m3 --path D:\models\bge-m3.gguf   # configure a model
local-embed                                                # serve
curl http://127.0.0.1:17347/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"model": "bge-m3", "input": "hello world"}'
```

It loads local **GGUF** (llama-cpp) and/or **HF transformer**
(sentence-transformers) models and serves them as an
[OpenAI-compatible](https://platform.openai.com/docs/api-reference/embeddings)
`/v1/embeddings` API.  The server never downloads weights — you pre-download
them ([Model weights](#model-weights)).

On the same port it also exposes `/v1/models`, `/health`, and a Streamable
HTTP MCP endpoint at `/mcp` (see [As an MCP server](#as-an-mcp-server)).

```
   any OpenAI-compatible client ──┐
   an editor / agent / pipeline ──┤── POST /v1/embeddings ──┐
   a RAG indexer ─────────────────┘                          ▼
                                              ┌───────────────────────┐
   MCP client ─────────── /mcp ─────────────> │      local-embed      │
                                              │  models load on demand │
                                              └───────────────────────┘
```

## Features

- **OpenAI-compatible** `/v1/embeddings` + Models API + `/health`.
- Two backends (GGUF / transformer), **many models as peers — each request
  names the one it wants** (standard OpenAI semantics, no "active model").
- **Lazy load** — startup is fast; each model materialises on the first
  request that names it (per-model `autoload: true` preloads a specific
  model at startup).
- **Real dimension** reported after load (a guessed width is never served).
- **Enforced context limit** — an over-long input is a `400`, never a
  quietly shortened vector; the limit is reconciled with the window the
  weights themselves report.
- **Fully offline** — no telemetry, no downloads at runtime, no API key.

Requires Python ≥ 3.13.

## Install

Two steps: the app, then the model backend you want.  The app is a normal
Python package; the backend is deliberately *not* bundled, because every
real install needs a per-platform index or `CMAKE_ARGS` that a package extra
cannot carry (see the [platform matrix](#gguf-backend--platform-matrix)).

### 1. The app

**One-click** (installs `uv` if needed, then the app into its own isolated
tool environment):

```bash
# macOS / Linux / WSL
curl -fsSL https://raw.githubusercontent.com/juzcn/local-embed/main/install.sh | bash

# Windows PowerShell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/juzcn/local-embed/main/install.ps1 | iex"
```

**Or by hand** — the installers do exactly this:

```bash
uv tool install --force --python '>=3.13' local-embed
```

> `--python '>=3.13'` is not optional. Without it `uv` builds the tool
> environment on whichever interpreter it prefers; local-embed needs ≥ 3.13, so
> an older environment has no compatible release to install at all. With the
> constraint, uv fetches a suitable interpreter or fails loudly.

`--force` (used by the installers too) is **idempotent** — the first run
installs, re-running **updates** to the latest release. A plain
`uv tool install local-embed` no-ops when the tool is already installed.

That gives you a `local-embed` command on your PATH, in an isolated
environment that holds nothing but this app. `uv tool uninstall local-embed`
(or `uninstall.sh` / `uninstall.ps1`) removes it and leaves your config alone.

### 2. A model backend

Add the backend to the environment the app itself runs in. `uv` takes the
venv **root directory** and finds the interpreter inside it, so set the
target once and reuse it — `uv tool dir` prints the root that holds every
tool venv:

```bash
PY="$(uv tool dir)/local-embed"   # installed by step 1
```

```powershell
$PY = "$(uv tool dir)\local-embed"   # the same target, PowerShell syntax
```

Then install per the matrix below, e.g. `uv pip install --python "$PY"
llama-cpp-python`.  Everything past this point uses the same `$PY`.
The installers print this same link when they finish:
<https://github.com/juzcn/local-embed#2-a-model-backend>.

> If you run local-embed inside an *existing* environment instead of a tool
> install (a project checkout's `.venv`, or another app's venv), install the
> backend into **that** environment's interpreter. `--python` is optional only
> when the target is unambiguous: uv resolves `--python` > `$VIRTUAL_ENV` >
> `.venv` in the current directory (walking up), and errors when it finds none
> — a venv is never created implicitly.

**Every command block here is POSIX shell** (`bash` / `zsh` / WSL). On Windows
PowerShell the same two things have different spellings, and nothing else
changes: the variable assignment, and the `VAR=value command` prefix that sets
an environment variable for one command.

```powershell
$env:CMAKE_ARGS = "-DGGML_CUDA=on"    # then run the uv pip install on its own line
```

A venv is **platform-bound**: a Windows-created `.venv` (`Scripts\`, `Lib\`)
has no `bin/python` and cannot be used from WSL or a Linux container. Keep the
Linux venv on the Linux filesystem (`~/venvs/local-embed`) rather than creating
one inside a checkout that lives on a Windows drive — the second `uv venv`
rewrites `pyvenv.cfg` and breaks the Windows one.

### `gguf` backend — platform matrix

`gguf` (llama-cpp-python) is platform-sensitive: PyPI ships **only the sdist**
(no prebuilt wheels), so on Linux / WSL / macOS a plain install **compiles from
source** (needs a C compiler + CMake ≥ 3.21). **Windows has no default C
toolchain** (no MSVC), so it uses the upstream prebuilt wheels — CPU or CUDA —
neither needing MSVC.  GPU variants pass `CMAKE_ARGS`.  Every command takes the
target as `$PY`, the environment set under [Install](#install):

| Platform | Command |
|---|---|
| Linux / WSL / macOS, CPU | `uv pip install --python "$PY" llama-cpp-python` (compiles from source) |
| macOS arm64 (Metal) | `CMAKE_ARGS="-DGGML_METAL=on" uv pip install --python "$PY" llama-cpp-python` |
| NVIDIA CUDA (Linux) | `CMAKE_ARGS="-DGGML_CUDA=on" uv pip install --python "$PY" llama-cpp-python` (needs the CUDA toolkit **and** an NVIDIA device) |
| **Windows, CPU** | `uv pip install --python "$PY" --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu llama-cpp-python` (prebuilt wheel — no MSVC) |
| **Windows, CUDA** | `uv pip install --python "$PY" --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu124 llama-cpp-python` (prebuilt CUDA wheel — no MSVC, needs an NVIDIA driver) |

Swap the `cu124` suffix for the CUDA series whose **runtime is installed** on
the machine — `cu118`, `cu121` … `cu125`, `cu130`, `cu132` — not merely the one
the driver supports; the next paragraph is why that distinction bites.
Upstream asks for compute capability ≥ 6.0 on the CUDA 12 wheels and ≥ 7.5 on
CUDA 13.

Those wheels link their CUDA series **dynamically** — a `cu124` wheel imports
`cudart64_12.dll` and `cublas64_12.dll` — so that runtime has to be installed
for real.  The NVIDIA **driver alone is not enough**: it provides `nvcuda.dll`
and nothing more.  A CUDA 12 wheel on a machine with only the CUDA 11.8
toolkit (`cudart64_110.dll`) fails, and the error names the outermost module
rather than the missing one:

```
RuntimeError: Failed to load shared library '...\llama_cpp\lib\llama.dll'
```

The real gap is two levels down: `llama.dll` → `ggml.dll` → `ggml-cuda.dll` →
`cudart64_12.dll`.  Match the index to the CUDA major version you have
(`cu118` against a CUDA 11.8 install), or install the CUDA runtime for the
series you picked.  **Determine the version rather than assuming it** — they are
two different numbers on the same machine: `nvidia-smi` prints the newest CUDA
the *driver* can drive (a ceiling), while `nvcc --version` prints the *toolkit*
actually installed.  The wheel needs the second.  `--extra-index-url .../whl/cpu`
sidesteps it all, at the cost of GPU offload.

The two Windows rows are the workarounds — everywhere else uses the standard
source build from PyPI.  Take a CUDA row only with a GPU present: without a
device it offloads nothing, so the Linux row buys a longer build and the
Windows row a larger download, both for plain CPU speed.  If the `gguf` backend
is missing, the server errors at startup with the exact command for your
platform.

### `transformer` backend — CPU-only machines

`sentence-transformers` pulls `torch`, and on Linux PyPI's `torch` is the
**CUDA build**: its metadata requires a dozen-odd `nvidia-*` runtime wheels
(~2.5 GB) whether or not a GPU exists.  They are runtime libraries, not a
toolkit — nothing in that set is `nvcc` — so on a GPU-less machine they enable
nothing at all.

Install the CPU wheel first, from PyTorch's own index; the second command then
finds `torch` satisfied and pulls no `nvidia-*`:

```bash
uv pip install --python "$PY" --index-url https://download.pytorch.org/whl/cpu torch
uv pip install --python "$PY" sentence-transformers
```

Swapping the CUDA build out afterwards leaves those wheels orphaned — nothing
depends on them any more — so drop them:

```bash
uv pip freeze --python "$PY" | grep ^nvidia | cut -d= -f1 | xargs uv pip uninstall --python "$PY"
```

macOS needs none of this (its `torch` is CPU/MPS).  The `gguf` backend touches
none of it either: llama-cpp-python has no torch dependency.

### `transformer` backend — Linux / WSL + NVIDIA GPU

The plain install is already the right one — nothing to route around:

```bash
uv pip install --python "$PY" sentence-transformers
```

On Linux, PyPI's `torch` *is* the CUDA build with its `nvidia-*` runtime wheels,
which is the problem described above **only on a machine without a GPU**; with
one, that is exactly what you want.  The runtime comes from those wheels, so the
`nvidia-smi` ceiling is the check that matters (driver new enough for the torch
build), and the `torch.cuda.is_available()` check below confirms it.

### `transformer` backend — Windows + NVIDIA GPU

PyPI's **Windows** `torch` is the mirror image of Linux's: a ~124 MB **CPU-only**
wheel, with every `nvidia-*` requirement in its metadata marked
`platform_system == "Linux"`.  A plain `uv pip install sentence-transformers`
therefore gets a CPU torch — silently, with no error, just no GPU.

The CUDA build exists only on PyTorch's own index, as `+cuXXX` wheels that
bundle the CUDA runtime DLLs (hence ~2 GB, and no `nvidia-*` packages on
Windows) — **bundled**, unlike the `gguf` wheels above, which link the runtime
externally: so here the `nvidia-smi` driver ceiling *is* the right rule, and a
separately installed CUDA toolkit is not needed:

```bash
uv pip install --python "$PY" --index-url https://download.pytorch.org/whl/cu130 torch
uv pip install --python "$PY" sentence-transformers
```

Two steps, same ordering as the CPU row and for the same reason.  Pick `cuXXX`
at most the CUDA version `nvidia-smi` reports — on Windows / cp313 the newest
`torch` each index resolves is:

| Index | Latest `torch` |
|---|---|
| `cu126` | 2.14.0 |
| `cu130` | 2.14.0 |
| `cu132` | 2.14.0 |
| `cu128` | 2.11.0 |
| `cu129` | 2.9.0 |
| `cu124` | 2.6.0 |
| `cu118` | 2.7.1 |

Confirm the build, not just the version — a CPU torch installs cleanly and
reports a plain `2.14.0`:

```bash
uv run --python "$PY" python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
# 2.14.0+cu130 True
```

The `+cuXXX` suffix is the tell; without it nothing will offload.

### Both backends at once

One `uv pip install`:

```bash
uv pip install --python "$PY" sentence-transformers llama-cpp-python
# Windows CPU: add the upstream wheel index (see the matrix above)
```

On a GPU-less Linux machine, install `torch` from the CPU index first (above) —
this same command otherwise drags in the ~2.5 GB of `nvidia-*` wheels.

Installing does **not** fetch a model — get the weights first.

## Quick start

1. **Install** the app, then a backend — steps 1 and 2 of [Install](#install).
2. **Download weights** — see [Model weights](#model-weights).
3. **Configure a model** — the CLI helper writes `local_embed.yaml`:

   ```bash
   local-embed set BAAI/bge-m3 --HF_HUB_CACHE <dir>     # transformer
   local-embed set-gguf bge-m3 --path D:\models\bge.gguf # gguf
   ```

4. **Start the service**:

   ```bash
   local-embed          # serve on http://127.0.0.1:17347
   ```

5. **Embed text** — point any OpenAI-compatible client at
   `http://127.0.0.1:17347/v1` (see [HTTP API](#http-api-openai-compatible)).

## Configuration: `local_embed.yaml`

Everything — host, port, models, backend — comes from
`local_embed.yaml`, written by the CLI helpers or by hand. Path resolution:
`$LOCAL_EMBED_FILE` > `~/.local-embed/local_embed.yaml` — the working directory
is never consulted. A host that wants the config beside its own exports
`$LOCAL_EMBED_FILE`; Slife seeds `~/.local-embed/local_embed.yaml` and relies
on the default.

```yaml
models:
  "bge-m3":
    backend: "gguf"
    gguf_path: "…"
    device: ""
    autoload: false
  "bge-m3-transformer":
    backend: "transformer"
    model: "BAAI/bge-m3"
    device: ""
env:                                       # injected into this process before any model loads
  HF_HUB_CACHE: 'C:\…\HuggingFace\hub'     # where transformer repos resolve
  HF_HUB_OFFLINE: "1"                      # force offline
host: "127.0.0.1"                          # standalone only
port: 17347                                # standalone only
```

- `models` — map of name → `{backend, gguf_path | model, device, max_tokens, autoload}`.
  Every configured model is a peer; there is **no `active_model`** — each
  request names the model it wants (standard OpenAI semantics).
- `max_tokens` (per model, default the family's published limit) — the context
  length the server **enforces**, so an over-long input is a `400` instead of a
  silently shortened vector.  It is also the width llama.cpp is configured to
  accept, and is reconciled with the window the weights report (see
  [Errors](#errors--the-openai-contract)).
- `autoload` (per model, default `false`) — a model's weights are large and
  memory-hungry, so nothing loads until a request names it (**lazy**).
  `autoload: true` on one model eager-loads just that model in the
  background at startup (memory paid up front for a warm first embed); every
  unflagged model stays lazy.
- `env:` — injected before any backend loads; an existing shell env var wins.
  Without `HF_HUB_CACHE`, transformer repos resolve against the default cache
  and a model downloaded elsewhere is silently re-fetched.
- Single-model convenience — top-level `backend`/`model`/`gguf_path`/`device`
  — still works.

Reads are read-only at runtime — the server has no config-mutating tools.

## Model weights

The server never downloads models; both backends fail at load time when their
weights are missing (`gguf` needs the `gguf_path` file, `transformer` needs the
repo in the HF cache).

### GGUF

`.gguf` files are, in general, **community conversions** — upstream releases
are PyTorch weights, not GGUF — so there is **no single authoritative source**:
conversions are scattered across Hugging Face, ModelScope, Ollama, llama.cpp
community uploads and various project sites. Pick any source you trust; the
transport doesn't matter, local-embed only needs the file on disk.

HF is the most common host and its CLI pulls a single file:

```bash
uv tool install "huggingface-hub[cli]"      # provides `hf`
hf download <owner>/<repo> <model>.gguf --local-dir D:\models\bge-m3
# one-off, no permanent tool install:
uvx --from huggingface-hub hf download <owner>/<repo> <model>.gguf --local-dir D:\models\bge-m3
```

Any source also works from a browser or `wget`/`curl` — on HF, every file is
fetchable from `https://huggingface.co/<owner>/<repo>/resolve/main/<model>.gguf`.

Prefer a high-fidelity quant such as **Q8_0** (~99 % of the original accuracy at
roughly a third of the size). Point `gguf_path` at the file:

```yaml
models:
  "bge-m3":
    backend: "gguf"
    gguf_path: 'D:\models\bge-m3\bge-m3-q8_0.gguf'
```

### Transformer

`sentence-transformers` resolves an HF repo id against the local hub cache:

```bash
hf download BAAI/bge-m3     # -> ~/.cache/huggingface/hub/models--BAAI--bge-m3
```

```yaml
models:
  "bge-m3":
    backend: "transformer"
    model: "BAAI/bge-m3"
```

## HTTP API (OpenAI-compatible)

The endpoint surface is a superset of the OpenAI Embeddings + Models APIs, all
on one port.

### `POST /v1/embeddings`

```bash
curl http://127.0.0.1:17347/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"model": "bge-m3", "input": ["hello world", "another text"]}'
```

`input` is a string or a list of strings; `model` is **required** and names
any configured model.  Returns the standard shape:

```json
{
  "object": "list",
  "data": [
    {"object": "embedding", "index": 0, "embedding": [0.012, ...]},
    {"object": "embedding", "index": 1, "embedding": [...]}
  ],
  "model": "bge-m3",
  "usage": {"prompt_tokens": 3, "total_tokens": 3}
}
```

OpenAI forbids empty-string input, so an empty/whitespace string in the
batch is rejected with a strict `400` — there is no zero-vector row
alignment on the wire; filter blanks before batching.

#### Errors — the OpenAI contract

Every error uses the standard envelope
`{"error": {"message", "type", "param", "code"}}` (`param` / `code` are
`null` when not applicable):

| Status | `type` | When | `param` / `code` |
|---|---|---|---|
| `400` | `invalid_request_error` | unparseable JSON body; `input` not a string/array of strings; missing `model`; empty / whitespace-only input | `input` / `model` |
| `400` | `invalid_request_error` | input exceeds the model's context length (`max_tokens` — never silently truncated) | `input` / `context_length_exceeded` |
| `404` | `invalid_request_error` | unknown `model` ("does not exist or you do not have access to it") | — / `model_not_found` |
| `503` | `server_error` | the model's engine is **still loading** (is_loading — retry shortly) or unavailable (backend dependency missing, load failed) | — |
| `500` | `server_error` | unexpected internal failure | — |

Split long documents into pieces of at most `max_tokens` tokens client-side —
local-embed rejects an over-long input rather than embedding a prefix of it.

`max_tokens` is the limit the server **enforces**, so it is also the width
llama.cpp is configured to accept — and it is reconciled with the window the
weights themselves report, in both directions. A model trained on less than
the limit is clamped down to its own window; a `max_tokens` set above the
8 192-token context window is clamped to that window. Whatever the config
says, `/v1/models` and `/health` report the number actually in force, and a
request over it is a `400` rather than a quietly shortened vector.

### `GET /v1/models`

Every configured model, each with its real embedding dimension
(`dimension` / `dimension_known`), backend, and load state.  The listing is
standard — no `active` marker, all models are peers.

### `GET /v1/models/{id}`

One model's detail (the OpenAI `retrieve` endpoint); 404 with the standard
error envelope when the id is unknown.

### `GET /health`

Liveness + engine state: `{status, models: [{name, backend, model,
dimension, dimension_known, loaded, available, max_tokens}]}` — `status`
is `ok` when any configured model's backend is usable.

### Any OpenAI client

Point `base_url` at `http://127.0.0.1:17347/v1` — the `openai` package, or any
OpenAI-compatible SDK:

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:17347/v1", api_key="local")
vecs = client.embeddings.create(model="bge-m3", input=["hello"])
```

## CLI

The `local-embed` command is how you run the app and write its config. The
service is configured by `local_embed.yaml` and consumed over the HTTP API —
the CLI just makes both steps convenient, and takes no model or endpoint flags
of its own.

### `local-embed` — run the service

```bash
local-embed                 # binds 127.0.0.1:17347 by default
```

The CLI takes no model/endpoint flags — the config is the only source of truth.
A port already in use is a hard error with one actionable line (no silent
fallback to a free port): stop the other instance or change `port` in the
config.  Running the CLI while a service already holds the port is a mistake
worth reporting — a host that *spawns* local-embed handles the same situation
differently (see [Using it as another app's embedding backend](#using-it-as-another-apps-embedding-backend)).

### `local-embed set` / `set-gguf` — write the config

`set` (transformer) and `set-gguf` (gguf) upsert a model in the config and
pin port (and, for `set`, the HF cache + offline flag). Both are
**idempotent** — re-running yields the same config — and leave other models
untouched.  There is no `active_model`: every configured model is a peer
and requests name the one they want.

| | `set` (transformer) | `set-gguf` |
|---|---|---|
| `<model_name>` | required — HF repo id (key + repo loaded) | required — config key |
| weight ref | `--HF_HUB_CACHE <dir>` — cache must contain the repo | `--path <PATH>` required — existing `.gguf` file |
| cache fallback | env `HF_HUB_CACHE`, else error | — |
| env written | `HF_HUB_CACHE` + `HF_HUB_OFFLINE: "1"` (offline server) | — |
| `--port <n>` | omit to keep the configured port | omit to keep the configured port |

```bash
local-embed set BAAI/bge-m3 [--HF_HUB_CACHE <dir>] [--port 17347]
local-embed set-gguf bge-m3 --path D:\models\bge-m3\bge-m3-q8_0.gguf [--port 17347]
```

`--port` is a choice, not a rewrite: omitting it keeps whatever port the
config already pins, and only falls back to `17347` when the config has none.
Pass it explicitly to move the service — every host's static `base_url`
points at that port, so a command that only meant to add a model should not
relocate it.

Any error — cache unset, repo not in cache, file missing, unparseable config
— exits non-zero and writes nothing. Changes apply on the next server start.

### Model download — offline by default

`HF_HUB_OFFLINE=1` by default, so the server **never downloads** a model (it's
too slow). Make the model available yourself — see
[Model weights](#model-weights): `hf download BAAI/bge-m3` for the transformer
route (into the HF cache), or drop a GGUF file and point `gguf_path` at it.

## Dimension

The real output width is only known once the model is loaded (`n_embd` /
`get_sentence_embedding_dimension`). `GET /v1/models` (or `/v1/models/{id}`)
reports the real dimension, so a client can size its vector table correctly —
a wrong width silently drops every mis-sized embedding. A guessed dimension is
never served as authoritative.

## As an MCP server

`/mcp` is a standard **MCP Streamable HTTP** endpoint, so any MCP client that
supports Streamable HTTP can register local-embed as an MCP server. Start it
first:

```bash
local-embed          # serve on http://127.0.0.1:17347
```

then register the URL. The MCP client config shape is `{"type": "http",
"url": …}` — for example, Claude Code's `.mcp.json` (or `~/.claude.json`):

```json
{
  "mcpServers": {
    "local-embed": {
      "type": "http",
      "url": "http://127.0.0.1:17347/mcp"
    }
  }
}
```

Or with the Claude Code CLI:

```bash
claude mcp add --transport http local-embed http://127.0.0.1:17347/mcp
```

> **Claude Desktop** registers remote HTTP MCP servers through its **connectors
> UI** (Settings → Connectors → Add connector → Remote), not
> `claude_desktop_config.json` — and a remote connector expects a hosted HTTPS
> URL, so a `127.0.0.1` server needs a tunnel or a stdio→HTTP bridge to be
> reachable from the desktop app.

**Over MCP you get status, not embeddings.** The only MCP tool is the internal
`__check` status probe (model list, dimensions, load state) — local-embed is
a *service-provider* MCP server, not a tool provider. To embed text, point
your consumer at the OpenAI-compatible `/v1/*` API instead. A client that only
speaks stdio can reach it through a stdio→HTTP bridge (e.g. `mcp-remote`).

## Using it as another app's embedding backend

local-embed is an app, not a library — nothing imports it. Anything that
speaks the OpenAI Embeddings API can consume it, including a host process
that spawns it as a child. That is the whole integration: give the consumer
the `base_url` below.

Because the consumer's `base_url` is static config, local-embed binds a
**fixed** port (`17347` by default) instead of an OS-assigned one — the port
is the service's identity, so whoever holds it *is* local-embed as far as
every consumer is concerned. Two consequences worth knowing:

- **A port already served is a hard error.** Start the CLI while something
  else holds `17347` and it fails with one actionable line rather than
  silently taking a different port, which would be invisible to every
  consumer pointing here. Stop the other instance, or change `port` in
  `local_embed.yaml`.
- **One service, many consumers.** Several apps (or several machines in
  WSL + Windows) can point at a single running local-embed instead of each
  holding its own copy of a ~2 GB model.

### Example: slife

slife spawns local-embed as a plugin and consumes it over HTTP — the same
OpenAI-compatible endpoint as any other client. Point its embedding config
at the stable port:

```yaml
embeddings:
  providers:
    local:
      base_url: "http://127.0.0.1:17347/v1"  # stable port from local_embed.yaml
      api_key: "local"
      model: "bge-m3"                        # id POSTed on /v1/embeddings
  active_model: "local"      # a provider id — never a "provider/model" ref
  enabled: true
```

slife treats every embedding model as a remote OpenAI-compatible endpoint —
local-embed is one such endpoint. The model a request hits is the one the
caller names; when the config names no model, slife discovers it from
`GET /v1/models` (the first entry) on load. When the service is unreachable,
slife degrades gracefully to keyword search.

When slife spawns the plugin and finds a local-embed already serving the
port (a daemon shared by several hosts, or one you started by hand), the
spawned child **adopts** it rather than failing: it serves MCP on an
OS-assigned port, loads no model of its own, and its `__check` reports the
adopted service's facts. The running instance keeps serving. The adopter
also stands watch — if the adopted service goes away, the child takes the
fixed port over and serves embeddings itself, so consumers keep embedding
without a restart.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Log: `backend_unavailable … reason=llama_cpp_not_installed` / `sentence_transformers_not_installed` | Run the platform's install from *Install* above — the log prints the exact command for your platform, its own interpreter included. |
| Transformer route won't load with `HF_HUB_OFFLINE=1` | The repo isn't in the cache — run `hf download BAAI/bge-m3` and make sure `HF_HUB_CACHE` points at the cache that holds it. |
| GGUF route won't load | File missing at `gguf_path` — check the path in `local_embed.yaml`, and that the client requests a configured model id (`GET /v1/models` lists them; all configured models are peers — nothing is gated behind an `active_model`). |
| `Error: cannot bind 127.0.0.1:17347` on start | Something already holds the port. If it is another local-embed, it is already serving — point your client at it instead, or stop it. If it is a different service, change `port` in `local_embed.yaml`. |
| An embedding looks wrong / too short a document matched | The input exceeded the model's context window. Check `max_tokens` for that model in `GET /v1/models` — the limit in force is the model's real window, and an over-long input is a `400`, never a silently truncated vector. |
| First embed very slow | The model's weights are loading (and, for a transformer, warming up) on the first request that names it. Set `autoload: true` on that model to pre-warm it at startup instead. |

## Re-adding a backend (after an upgrade)

`uv tool install --force` (what the installers and an update run) rebuilds the
tool environment, which **drops** any backend added to it — re-run the
`uv pip install` from step 2 of [Install](#install) after upgrading.

The backends are **not** package extras — every real install needs a
per-platform choice (a PyTorch index, `CMAKE_ARGS`, or the upstream Windows
wheel index), so the platform matrix above is the authority on which command
your platform needs:

| Backend | Package | Cost |
|---------|---------|------|
| GGUF | `llama-cpp-python` | offline, ~300 MB + the model |
| Transformer | `sentence-transformers` | ~2 GB + the model |

```bash
# into the app's own tool venv (step 1's tool install):
uv pip install --python "$(uv tool dir)/local-embed" llama-cpp-python
uv pip install --python "$(uv tool dir)/local-embed" sentence-transformers

# or run from a checkout with no tool venv at all — add to the ephemeral env:
uvx --with llama-cpp-python --from git+https://github.com/juzcn/local-embed.git local-embed
```

Add `--extra-index-url …/whl/cpu` (or `…/whl/cu124`) on Windows and `CMAKE_ARGS` for the Linux/Metal GPU builds; on a GPU-less Linux machine install the CPU `torch` first — the platform matrix gives both.

Re-running an installer rebuilds the tool environment (`uv tool install --force`), which **drops** a backend added this way — re-run the `uv pip install` above after an upgrade.

## Development

Requires [uv](https://docs.astral.sh/uv/).

```bash
uv sync --locked     # create .venv with runtime + dev dependencies
uv run pytest        # run the test suite
uv run ruff check    # lint
uv run ruff format   # format
uv run pyright       # type-check
```

CI runs the suite on Windows, macOS, and Linux (`.github/workflows/ci.yml`), plus lint and type-check jobs.

### Releasing

Bump `version` in `pyproject.toml`, commit, then push a tag with the same
version:

```bash
git tag -a v0.4.1 -m "local-embed 0.4.1" && git push origin v0.4.1
```

`.github/workflows/publish.yml` fails unless the tag matches the package
version exactly, then uploads to PyPI via trusted publishing.

## License

MIT — see the repository root `LICENSE`.
