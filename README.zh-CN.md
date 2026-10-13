# local-embed

**一个独立的本地 embedding 服务。** 它加载一个本地 GGUF
（llama-cpp）或 HF transformer embedding 模型，并把它暴露为一个
[OpenAI 兼容](https://platform.openai.com/docs/api-reference/embeddings)
的 `/v1/embeddings` URL —— 任何 OpenAI 兼容客户端都能通过它为文本生成 embedding。

在一个端口上它提供两套接口：用于 embedding 的 OpenAI 兼容 `/v1/*` API，以及位于 `/mcp` 的 Streamable HTTP MCP 端点。

local-embed 同时是三样东西：一个独立应用、一个 Streamable HTTP
**MCP 服务器**（见[作为 MCP 服务器](#作为-mcp-服务器)），以及一个符合规范的
**slife 插件**（见[作为 slife 嵌入后端运行](#作为-slife-嵌入后端运行)）。
产品是那个 embedding URL；MCP 和插件接口是宿主用来管理这同一个独立服务的方式。

两种后端：**`gguf`** 加载本地 `.gguf` 文件（llama-cpp-python）；
**`transformer`** 从本地 hub 缓存加载 HF repo id
（sentence-transformers）。服务器从不下载权重——由你预先下载
（[模型权重](#模型权重)）。

```
   any OpenAI-compatible client ──┐
   slife (memdb / memfiles) ──────┤── POST /v1/embeddings ──┐
   vector DB / RAG pipeline ──────┘                          ▼
                                              ┌───────────────────────┐
   slife (plugin host) ─── /mcp ────────────> │       local-embed     │
                                              │  models load on demand │
                                              └───────────────────────┘
```

## 特性

- **OpenAI 兼容**的 `/v1/embeddings` + Models API + `/health`。
- 两种后端（GGUF / transformer），**多个模型地位平等——由每个请求自己指名想要的那个**（标准 OpenAI 语义，没有“当前模型”）。
- **懒加载**——启动很快；每个模型在第一个指名它的请求到来时才实体化（按模型设置的 `autoload: true` 会在启动时预加载指定模型）。
- 加载后报告**真实维度**（绝不把猜出来的宽度当作结果提供）。
- 可独立运行，也能**作为 slife 插件被加载**（见[作为 slife 嵌入后端运行](#作为-slife-嵌入后端运行)）。

需要 Python ≥ 3.13。

## 安装

核心包是 `fastmcp` + `starlette` + `ruamel.yaml`（round-trip YAML——
保留注释的配置解析器）。模型后端按下面的平台矩阵分别安装。

一键安装脚本（必要时先装 `uv`，再运行 `uv tool install --force --python '>=3.13' local-embed`——**不**包含后端，见下文）：

```bash
# macOS / Linux / WSL
curl -fsSL https://raw.githubusercontent.com/juzcn/local-embed/main/install.sh | bash

# Windows PowerShell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/juzcn/local-embed/main/install.ps1 | iex"
```

手动安装等价：

```bash
# the app + CLI (standalone tool)
uv tool install --force --python '>=3.13' local-embed
```

后端**不属于**这个包——没有 extras，因为每一次真实安装都需要某个按平台选择的索引或 `CMAKE_ARGS`，而 extra 承载不了这些。用 `uv pip install --python "$(uv tool dir)/local-embed" …` 加上它，按下方的矩阵操作。

`--force`（安装脚本也用它）是**幂等**的——首次运行安装，重跑会**更新**到最新的 PyPI 发布版。不带 `--force` 的 `uv tool install local-embed` 在工具已安装时是空操作。

如果你是在一个*已有*环境里（与另一个工具并存）运行 local-embed，请把后端装进**那个**环境的解释器，而不是另建一个。

这里没有什么需要查的，也没有 `bin/` 与 `Scripts/` 之争：uv 接收 venv 的**根目录**，自己从中找到解释器，而 `uv tool dir` 打印的是容纳所有工具 venv 的那个根目录。所以设置一次目标并复用：

```bash
PY="$(uv tool dir)/local-embed"   # installed by the installers above
PY="$(uv tool dir)/slife"         # running as slife's embedding backend
PY=.venv                          # a project checkout (run from its root)
```

选出与你安装方式匹配的那一行，然后 `uv pip install --python "$PY"
llama-cpp-python`——下方的矩阵用的是同一个 `$PY`。

**这里的每个命令块都是 POSIX shell**（`bash` / `zsh` / WSL）。在 Windows
PowerShell 上，同样的两件事写法不同，其余一律不变：变量赋值，以及为单条命令设置环境变量的 `VAR=value command` 前缀。

```powershell
$PY = "$(uv tool dir)\slife"          # the same target, PowerShell syntax
$env:CMAKE_ARGS = "-DGGML_CUDA=on"    # then run the uv pip install on its own line
```

你运行的那种安装决定用哪一行：

- **工具安装**——`uv tool install local-embed` 以及上面的安装脚本落在 uv 的工具 venv 里。当 local-embed 作为 slife 的 embedding 后端运行时，提供服务的进程是 slife 的，所以后端属于 slife 的工具 venv（`install.sh` / `install.ps1` 装的是 slife）。新来一次 `uv tool install
  local-embed` *不是*解决办法——它构建的是一个独立的工具，而不是正在提供服务的那个环境。
- **项目检出**——该检出的 `.venv`。
- **正在运行的服务器**——缺少的后端会在启动时报错，并给出确切的命令，其中包含它自己的解释器。

只有当目标明确时 `--python` 才是可选的：uv 按 `--python` > `$VIRTUAL_ENV` > 当前目录（向上回溯）的 `.venv` 顺序解析，一个都找不到就报错——venv 绝不会被隐式创建。只要涉及不止一个 venv，就显式给出它。

venv 是**平台绑定**的：Windows 创建的 `.venv`（`Scripts\`、`Lib\`）没有 `bin/python`，无法从 WSL 或 Linux 容器使用。把 Linux venv 放在 Linux 文件系统上（`~/venvs/local-embed`），不要在位于 Windows 盘符上的检出目录里创建它——第二次 `uv venv` 会重写 `pyvenv.cfg`，把 Windows 那个弄坏。

### `gguf` 后端——平台矩阵

`gguf`（llama-cpp-python）对平台敏感：PyPI 只发布 **sdist**（没有预编译 wheel），所以在 Linux / WSL / macOS 上一次普通安装会**从源码编译**（需要 C 编译器和 CMake ≥ 3.21）。**Windows 没有默认的 C 工具链**（没有 MSVC），因此它使用上游的预编译 wheel——CPU 或 CUDA——两者都不需要 MSVC。GPU 变体通过 `CMAKE_ARGS` 传参。每条命令都以 `$PY` 作为目标，即[安装](#安装)一节设置的那个环境：

| 平台 | 命令 |
|---|---|
| Linux / WSL / macOS, CPU | `uv pip install --python "$PY" llama-cpp-python`（从源码编译） |
| macOS arm64 (Metal) | `CMAKE_ARGS="-DGGML_METAL=on" uv pip install --python "$PY" llama-cpp-python` |
| NVIDIA CUDA (Linux) | `CMAKE_ARGS="-DGGML_CUDA=on" uv pip install --python "$PY" llama-cpp-python`（需要 CUDA toolkit **和**一块 NVIDIA 设备） |
| **Windows, CPU** | `uv pip install --python "$PY" --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu llama-cpp-python`（预编译 wheel——无需 MSVC） |
| **Windows, CUDA** | `uv pip install --python "$PY" --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu124 llama-cpp-python`（预编译 CUDA wheel——无需 MSVC，需要 NVIDIA 驱动） |

把 `cu124` 后缀换成机器上**实际安装了运行时**的那个 CUDA 系列——`cu118`、`cu121` … `cu125`、`cu130`、`cu132`——而不只是驱动支持的那一个；下一段说明这个区别为什么会咬人。上游要求 CUDA 12 wheel 的计算能力 ≥ 6.0，CUDA 13 上 ≥ 7.5。

那些 wheel **动态**链接各自的 CUDA 系列——一个 `cu124` wheel 会导入
`cudart64_12.dll` 和 `cublas64_12.dll`——所以那个运行时必须真实安装。仅装
NVIDIA **驱动是不够的**：它提供 `nvcuda.dll`，仅此而已。在只装了 CUDA 11.8
toolkit（`cudart64_110.dll`）的机器上使用 CUDA 12 wheel 会失败，而且错误指向的是最外层的模块，而不是缺失的那个：

```
RuntimeError: Failed to load shared library '...\llama_cpp\lib\llama.dll'
```

真正的缺口在往下两层：`llama.dll` → `ggml.dll` → `ggml-cuda.dll` →
`cudart64_12.dll`。把索引与你的 CUDA 主版本对上
（对 CUDA 11.8 安装用 `cu118`），或者为你所选的系列安装 CUDA 运行时。**要确认版本，而不是想当然**——在同一台机器上它们是两个不同的数字：`nvidia-smi` 打印的是*驱动*能驱动的最高 CUDA（一个上限），而 `nvcc --version` 打印的才是实际安装的 *toolkit*。wheel 需要的是后者。`--extra-index-url .../whl/cpu` 可以绕开这一切，代价是放弃 GPU 卸载。

那两行 Windows 是变通方案——其他地方都用 PyPI 的标准源码构建。只有在确实有 GPU 时才选 CUDA 行：没有设备时它什么也卸载不了，于是 Linux 行换来更久的构建、Windows 行换来更大的下载，全都只为换来普通的 CPU 速度。若 `gguf` 后端缺失，服务器会在启动时报错，并给出适用于你平台的确切命令。

### `transformer` 后端——仅 CPU 的机器

`sentence-transformers` 会拉入 `torch`，而在 Linux 上 PyPI 的 `torch` 是
**CUDA 构建**：无论有没有 GPU，它的元数据都要求十几个 `nvidia-*` 运行时
wheel（约 2.5 GB）。它们是运行时库，不是 toolkit——那组里没有 `nvcc`——所以在没有 GPU 的机器上它们什么都启用不了。

先装 CPU wheel，来自 PyTorch 自己的索引；第二条命令随后会发现 `torch`
已满足，不会拉任何 `nvidia-*`：

```bash
uv pip install --python "$PY" --index-url https://download.pytorch.org/whl/cpu torch
uv pip install --python "$PY" sentence-transformers
```

之后再换成 CUDA 构建会把那些 wheel 变成孤儿——已经没有东西依赖它们了——所以卸掉它们：

```bash
uv pip freeze --python "$PY" | grep ^nvidia | cut -d= -f1 | xargs uv pip uninstall --python "$PY"
```

macOS 不需要这些（它的 `torch` 是 CPU/MPS）。`gguf` 后端也完全不碰它：
llama-cpp-python 没有 torch 依赖。

### `transformer` 后端——Linux / WSL + NVIDIA GPU

普通安装就是对的——无需绕过任何东西：

```bash
uv pip install --python "$PY" sentence-transformers
```

在 Linux 上，PyPI 的 `torch` *就是*带 `nvidia-*` 运行时 wheel 的 CUDA 构建，
这正是上文所述的问题，**但只发生在没有 GPU 的机器上**；有 GPU 时，那恰恰是你想要的。运行时来自那些 wheel，所以真正要紧的检查是 `nvidia-smi` 给出的上限（驱动要足够新，能支持该 torch 构建），下面的 `torch.cuda.is_available()` 检查用来确认这一点。

### `transformer` 后端——Windows + NVIDIA GPU

PyPI 的 **Windows** `torch` 是 Linux 的镜像：一个约 124 MB 的 **纯 CPU**
wheel，其元数据里每一项 `nvidia-*` 要求都标着
`platform_system == "Linux"`。因此一次普通的 `uv pip install sentence-transformers`
拿到的是 CPU 版 torch——悄无声息，没有报错，只是没有 GPU。

CUDA 构建只存在于 PyTorch 自己的索引上，形如 `+cuXXX` wheel，它们打包了
CUDA 运行时 DLL（因此约 2 GB，且 Windows 上没有 `nvidia-*` 包）——是**打包**的，与上面的 `gguf` wheel 不同，后者在外部链接运行时：所以这里 `nvidia-smi` 的驱动上限*就是*正确的规则，也不需要单独安装 CUDA toolkit：

```bash
uv pip install --python "$PY" --index-url https://download.pytorch.org/whl/cu130 torch
uv pip install --python "$PY" sentence-transformers
```

两步，顺序与 CPU 行相同，原因也相同。选取的 `cuXXX` 至多等于 `nvidia-smi`
报告的 CUDA 版本——在 Windows / cp313 上，各索引能解析出的最新 `torch` 是：

| 索引 | 最新 `torch` |
|---|---|
| `cu126` | 2.14.0 |
| `cu130` | 2.14.0 |
| `cu132` | 2.14.0 |
| `cu128` | 2.11.0 |
| `cu129` | 2.9.0 |
| `cu124` | 2.6.0 |
| `cu118` | 2.7.1 |

要确认是哪个构建，而不仅是版本号——CPU 版 torch 能干净安装，并报告一个普通的 `2.14.0`：

```bash
uv run --python "$PY" python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
# 2.14.0+cu130 True
```

`+cuXXX` 后缀就是它的标志；没有它就不会有任何卸载。

### 两种后端同时安装

一次 `uv pip install`：

```bash
uv pip install --python "$PY" sentence-transformers llama-cpp-python
# Windows CPU: add the upstream wheel index (see the matrix above)
```

在没有 GPU 的 Linux 机器上，先从 CPU 索引安装 `torch`（见上文）——否则这条同样的命令会拖入约 2.5 GB 的 `nvidia-*` wheel。

安装**不会**获取模型——先去拿权重。

## 快速开始

1. **安装**应用和一个后端（见上文）。
2. **下载权重**——见[模型权重](#模型权重)。
3. **配置一个模型**——CLI 辅助命令会写出 `local_embed.yaml`：

   ```bash
   local-embed set BAAI/bge-m3 --HF_HUB_CACHE <dir>     # transformer
   local-embed set-gguf bge-m3 --path D:\models\bge.gguf # gguf
   ```

4. **启动服务**：

   ```bash
   local-embed          # serve on http://127.0.0.1:17347
   ```

5. **为文本生成 embedding**——把任何 OpenAI 兼容客户端指向
   `http://127.0.0.1:17347/v1`（见 [HTTP API](#http-api-openai-兼容)）。

## 配置：`local_embed.yaml`

一切——host、port、models、backend——都来自 `local_embed.yaml`，由 CLI 辅助命令或手工写入。路径解析：
`$LOCAL_EMBED_FILE` > slife 项目根（开发时）> `~/.local-embed/local_embed.yaml`。

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

- `models` —— name → `{backend, gguf_path | model, device, max_tokens, autoload}` 的映射。每个已配置的模型都是一个地位平等的成员；**没有 `active_model`**——每个请求各自指名它想要的模型（标准 OpenAI 语义）。
- `autoload`（按模型设置，默认 `false`）——一个模型的权重很大且吃内存，所以在有请求指名它之前什么都不会加载（**懒加载**）。给某个模型设 `autoload: true` 只是让那一个模型在启动时于后台预先加载（用提前付出的内存换取第一次 embedding 时就绪）；每个未加此标记的模型保持懒加载。
- `env:` ——在任何后端加载之前注入；已存在的 shell 环境变量优先。没有 `HF_HUB_CACHE`，transformer repo 会按默认缓存解析，而在别处下载好的模型会被无声地重新拉取。
- 单模型便捷写法——顶层的 `backend`/`model`/`gguf_path`/`device`
  ——仍然可用。

运行时读取是只读的——服务器没有任何修改配置的工具。

## 模型权重

服务器从不下载模型；两种后端在权重缺失时都会在加载阶段失败（`gguf` 需要
`gguf_path` 指向的文件，`transformer` 需要该 repo 在 HF 缓存中）。

### GGUF

`.gguf` 文件一般来说是**社区转换**的产物——上游发布的是 PyTorch 权重，不是
GGUF——所以**没有唯一的权威来源**：转换版本散落在 Hugging Face、ModelScope、
Ollama、llama.cpp 社区上传以及各种项目站点上。挑一个你信任的来源就行；传输渠道不重要，local-embed 只需要文件在磁盘上。

HF 是最常见的主机，它的 CLI 可以拉取单个文件：

```bash
uv tool install "huggingface-hub[cli]"      # provides `hf`
hf download <owner>/<repo> <model>.gguf --local-dir D:\models\bge-m3
# one-off, no permanent tool install:
uvx --from huggingface-hub hf download <owner>/<repo> <model>.gguf --local-dir D:\models\bge-m3
```

任何来源也可以通过浏览器或 `wget`/`curl` 获取——在 HF 上，每个文件都可以从
`https://huggingface.co/<owner>/<repo>/resolve/main/<model>.gguf` 获取。

优先选高保真的量化，例如 **Q8_0**（约为原始模型 99% 的精度，体积约三分之一）。把 `gguf_path` 指向该文件：

```yaml
models:
  "bge-m3":
    backend: "gguf"
    gguf_path: 'D:\models\bge-m3\bge-m3-q8_0.gguf'
```

### Transformer

`sentence-transformers` 会按本地 hub 缓存解析 HF repo id：

```bash
hf download BAAI/bge-m3     # -> ~/.cache/huggingface/hub/models--BAAI--bge-m3
```

```yaml
models:
  "bge-m3":
    backend: "transformer"
    model: "BAAI/bge-m3"
```

## HTTP API (OpenAI 兼容)

端点集合是 OpenAI Embeddings + Models API 的超集，全部在同一个端口上。

### `POST /v1/embeddings`

```bash
curl http://127.0.0.1:17347/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"model": "bge-m3", "input": ["hello world", "another text"]}'
```

`input` 是字符串或字符串列表；`model` 是**必需**的，指名任意一个已配置的模型。返回标准结构：

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

OpenAI 禁止空字符串输入，所以批次里的空字符串/纯空白字符串会被严格地以 `400`
拒绝——线上没有零向量行来对齐；在分批之前先过滤掉空白。

#### 错误——OpenAI 契约

每个错误都使用标准信封
`{"error": {"message", "type", "param", "code"}}`（`param` / `code` 不适用时为 `null`）：

| 状态 | `type` | 触发条件 | `param` / `code` |
|---|---|---|---|
| `400` | `invalid_request_error` | JSON 请求体无法解析；`input` 不是字符串/字符串数组；缺少 `model`；输入为空/仅含空白 | `input` / `model` |
| `400` | `invalid_request_error` | 输入超过模型的上下文长度（`max_tokens`——绝不静默截断） | `input` / `context_length_exceeded` |
| `404` | `invalid_request_error` | 未知的 `model`（“does not exist or you do not have access to it”） | — / `model_not_found` |
| `503` | `server_error` | 该模型的引擎**仍在加载**（is_loading——稍后重试）或不可用（后端依赖缺失、加载失败） | — |
| `500` | `server_error` | 意外的内部故障 | — |

在客户端把长文档切成不超过 `max_tokens` 个 token 的片段（slife 的语义 drainer 会自动做这件事）。

### `GET /v1/models`

列出每个已配置的模型，各自带有真实的 embedding 维度
（`dimension` / `dimension_known`）、后端和加载状态。这个列表是标准的——没有
`active` 标记，所有模型地位平等。

### `GET /v1/models/{id}`

单个模型的详情（OpenAI 的 `retrieve` 端点）；id 未知时以标准错误信封返回 404。

### `GET /health`

存活状态 + 引擎状态：`{status, models: [{name, backend, model,
dimension, dimension_known, loaded, available, max_tokens}]}` —— 当任一已配置模型的后端可用时，`status` 为 `ok`。

### 任意 OpenAI 客户端

把 `base_url` 指向 `http://127.0.0.1:17347/v1`——`openai` 包，或任何 OpenAI 兼容
SDK：

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:17347/v1", api_key="local")
vecs = client.embeddings.create(model="bge-m3", input=["hello"])
```

## CLI（辅助工具）

`local-embed` CLI 是个**辅助工具**，不是产品本身：它启动服务并写配置文件。服务由
`local_embed.yaml` 配置、通过 HTTP API 使用——CLI 只是让这两步更省事。

### `local-embed`——运行服务

```bash
local-embed                 # binds 127.0.0.1:17347 by default
```

CLI 不接受任何模型/端点相关参数——配置是唯一的真相来源。端口已被占用是硬错误，
只给一行可操作的提示（不会静默退回到某个空闲端口）：停掉另一个实例，或改配置里的
`port`。在服务已占住端口时运行 CLI 是个值得报出来的错误——同样的情形在 slife
拉起插件时处理方式不同（见[接管正在运行的服务](#接管正在运行的服务)）。

### `local-embed set` / `set-gguf`——写配置

`set`（transformer）和 `set-gguf`（gguf）在配置中 upsert 一个模型并固定端口
（对 `set` 而言还包括 HF 缓存 + 离线标志）。两者都是**幂等**的——重跑得到相同的配置——且不碰其他模型。没有 `active_model`：
每个已配置的模型地位平等，请求各自指名想要的那个。

| | `set` (transformer) | `set-gguf` |
|---|---|---|
| `<model_name>` | 必需——HF repo id（既是 key，也是所加载的 repo） | 必需——配置 key |
| 权重引用 | `--HF_HUB_CACHE <dir>`——缓存中必须含有该 repo | `--path <PATH>` 必需——已存在的 `.gguf` 文件 |
| 缓存回退 | 环境变量 `HF_HUB_CACHE`，否则报错 | — |
| 写入的环境变量 | `HF_HUB_CACHE` + `HF_HUB_OFFLINE: "1"`（离线服务器） | — |
| `--port <n>` | 默认 `17347` | 默认 `17347` |

```bash
local-embed set BAAI/bge-m3 [--HF_HUB_CACHE <dir>] [--port 17347]
local-embed set-gguf bge-m3 --path D:\models\bge-m3\bge-m3-q8_0.gguf [--port 17347]
```

任何错误——缓存未设置、缓存中没有该 repo、文件不存在——都以非零码退出且什么都不写。改动在服务器下次启动时生效。

### 模型下载——默认离线

默认 `HF_HUB_OFFLINE=1`，所以服务器**从不下载**模型（太慢了）。由你自己让模型可用——见[模型权重](#模型权重)：transformer 路线用 `hf download BAAI/bge-m3`
（下载到 HF 缓存中），或者放一个 GGUF 文件并让 `gguf_path` 指向它。

## 维度

真实的输出宽度只有在模型加载之后才知道（`n_embd` /
`get_sentence_embedding_dimension`）。`GET /v1/models`（或 `/v1/models/{id}`）
报告真实维度，这样客户端才能正确地为其向量表定尺寸——错误的宽度会静默丢弃每一个尺寸不符的 embedding。猜测出来的维度永远不会被当作权威结果提供。

## 作为 MCP 服务器

`/mcp` 是一个标准的 **MCP Streamable HTTP** 端点，所以任何支持 Streamable HTTP
的 MCP 客户端都能把 local-embed 注册为 MCP 服务器。先启动它：

```bash
local-embed          # serve on http://127.0.0.1:17347
```

然后注册该 URL。MCP 客户端配置的形状是 `{"type": "http",
"url": …}`——例如 Claude Code 的 `.mcp.json`（或 `~/.claude.json`）：

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

或者用 Claude Code CLI：

```bash
claude mcp add --transport http local-embed http://127.0.0.1:17347/mcp
```

> **Claude Desktop** 通过它的 **connectors UI**（Settings → Connectors → Add
> connector → Remote）注册远程 HTTP MCP 服务器，而不是
> `claude_desktop_config.json`——并且远程连接器要求一个托管的 HTTPS
> URL，所以 `127.0.0.1` 上的服务器需要隧道或 stdio→HTTP 桥接，才能从桌面应用访问。

**通过 MCP 你得到的是状态，不是 embedding。** 唯一的 MCP 工具是内部的
`__check` 状态探针（模型列表、维度、加载状态）——local-embed 是一个*服务提供方*型 MCP 服务器，而不是工具提供方。要为文本生成 embedding，请把你的消费方指向
OpenAI 兼容的 `/v1/*` API。只会说 stdio 的客户端可以通过 stdio→HTTP 桥接（例如
`mcp-remote`）访问它。

## 作为 slife 嵌入后端运行

local-embed 是一个**插件**——slife 中央插件规格里的一行，所以 slife 会拉起它、监视它，并像对待其他所有子插件一样汇报它。它也可以独立运行（PATH 上的
`local-embed`），CLI 正是为此而设；slife 仍然纯粹把 MODEL SERVICE 当作一个
OpenAI 兼容的 HTTP 端点来消费（绝不通过 MCP 工具）。

由于其配置固定了一个端口，而某个静态 embeddings `base_url` 指向它，它是唯一一个端口**固定**的插件：它自己绑定那个端口，而那个端口就是服务的身份——在所有宿主看来，谁占着这个端口，*谁就是* local-embed。

因此第二个实例并不自动等同于错误。当 slife 拉起插件并发现已经有一个 local-embed
在服务该端口（WSL 里被多个宿主共享的守护进程，或者你手动启动的一个），子进程会
**接管**它而不是失败；见下文。同一个端口被任何*不是* local-embed 的东西占着则仍然是硬错误，会给出原因，且正在运行的服务不会被触碰。

### 接管正在运行的服务

被拉起的子进程在开始服务之前，先在配置的端口上探测 `GET /health`：

- **有 local-embed 应答** → 它被接管。子进程在一个由 OS 分配的端口上提供 MCP，
  **自己不加载任何模型**，其 `__check` 报告被接管服务的事实（每次探测都重新读取，所以一个停止应答的服务会被读作*不可用*，而不是过时的好消息）。宿主的
  `base_url` 本就一直被服务着——由一个很可能已经预热的实例。
- **没有东西应答，或者应答的是别的东西** → 子进程绑定该端口并照常提供服务；陌生的东西仍然会大声失败，而不会被接管。

接管是自动的，无需配置。正是它让共享一个服务变得可行：Windows 上的 slife 和
WSL 上的 jack 可以同时指向同一个 local-embed，而不必各自持有一份约 2 GB
的模型副本。

接管方还会**监视**：如果被接管的服务消失了，子进程会接过这个固定端口、自己提供
embedding，并预热标了 `autoload` 的模型，这样宿主无需重启也能继续生成
embedding。反过来则不可能——一旦子进程占住了端口，原来的服务就无法回来，直到子进程重启。

把 slife 的 embedding 配置指向守护进程稳定的端口：

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

slife 把每个 embedding 模型都当作远程 OpenAI 兼容端点——local-embed 就是这样一个端点。请求命中的模型由调用方指名；当配置没有指名模型时，slife 在加载时从
`GET /v1/models`（第一项）发现它。当守护进程不可达时，slife 会优雅降级到关键词搜索（`system_health` 中的 `check_embeddings` 探测**当前生效**提供方的 HTTP
端点并报告其不可达——它从不假定该提供方就是 local-embed）。

它仍然提供的 MCP 接口是内部的 **`__check`**（引擎状态：模型列表、维度、加载状态）——一个供直接探测的服务提供方门面，而不是 slife 插件契约。它还在同一端口上通过 `@mcp.custom_route` 提供普通的 OpenAPI 路由（`/v1/embeddings`、
`/v1/models`、`/health`）——一个端口，两套协议，无需 slife 参与。

---

## 故障排查

| 现象 | 解决办法 |
|---------|-----|
| 日志：`backend_unavailable … reason=llama_cpp_not_installed` / `sentence_transformers_not_installed` | 运行上文*安装*一节中你所在平台的安装命令——日志会打印确切的命令。 |
| Transformer 路线在 `HF_HUB_OFFLINE=1` 下无法加载 | 该 repo 不在缓存里——运行 `hf download BAAI/bge-m3`，并确保 `HF_HUB_CACHE` 指向存放它的那个缓存。 |
| GGUF 路线无法加载 | `gguf_path` 处的文件缺失——检查 `BGE_M3_GGUF_PATH` / `gguf_path`，并确认客户端请求的是 `"bge-m3"`（所有已配置的模型地位平等——没有任何东西被 `active_model` 挡在门后）。 |
| `system_health` 显示 `embeddings` 为 `unavailable` | 当前生效的 embedding 端点没有应答 `GET /v1/models`。如果那个提供方是 `local_embed`，请检查同一份报告里的 `local-embed` 那一行——slife 自己会启动该服务，所以它缺失意味着插件启动失败（其日志里有原因；一个**非** local-embed 的服务占着 17347 端口也会导致这种情况）。否则去修云服务提供方的 key：`api_key` 按 `${VAR}` → 环境变量 → credstore 的顺序解析。该组件只探测**当前生效**的提供方，且它的那一行以该提供方的 id 为键。 |
| 第一次 embedding 非常慢 | transformer 的下载/预热被推迟到第一次 embedding；之后的调用很快。 |

## 重新添加后端（手动安装）

后端**不是**包的 extras——每一次真实安装都需要按平台做选择（某个 PyTorch 索引、
`CMAKE_ARGS`，或上游的 Windows wheel 索引）。直接安装该包；上文*安装*下的平台矩阵才是判断你的平台需要哪条命令的权威依据：

| 后端 | 包 | 开销 |
|---------|---------|------|
| GGUF | `llama-cpp-python` | 离线，约 300 MB + 模型 |
| Transformer | `sentence-transformers` | 约 2 GB + 模型 |

```bash
# a tool install (the installers) — into the tool's own venv:
uv pip install --python "$(uv tool dir)/local-embed" llama-cpp-python
uv pip install --python "$(uv tool dir)/local-embed" sentence-transformers

# uvx / git checkout — there is no tool venv; add the package to the ephemeral env:
uvx --with llama-cpp-python --from git+https://github.com/juzcn/local-embed.git local-embed
```

在 Windows 上加上 `--extra-index-url …/whl/cpu`（或 `…/whl/cu124`），并为
Linux/Metal GPU 构建加 `CMAKE_ARGS`；在没有 GPU 的 Linux 机器上先安装 CPU 版
`torch`——第 1 步的条目给出了两者。遗留的进程内 embedding 后端用的是同样的这两个包，所以这同样覆盖了它们。

重跑安装脚本会重建工具环境（`uv tool install --force`），**会丢掉**这样加上的后端——升级后请重新执行上面的 `uv pip install`。

## 开发

需要 [uv](https://docs.astral.sh/uv/)。

```bash
uv sync --locked     # 创建 .venv，安装运行时 + 开发依赖
uv run pytest        # 运行测试
uv run ruff check    # 静态检查
uv run ruff format   # 格式化
uv run pyright       # 类型检查
```

CI 在 Windows、macOS、Linux 上跑测试（`.github/workflows/ci.yml`），另有独立的 lint 和类型检查任务。

### 发版

改 `pyproject.toml` 里的 `version`，提交，然后推一个同名 tag：

```bash
git tag -a v0.3.1 -m "local-embed 0.3.1" && git push origin v0.3.1
```

`.github/workflows/publish.yml` 会校验 tag 与包版本完全一致，不一致直接失败；通过后经 trusted publishing 上传到 PyPI。

## 许可证

MIT——见仓库根目录的 `LICENSE`。
