"""local-embed — standalone local embedding server.

Loads local GGUF (llama-cpp) and/or HF transformer embedding models and
exposes them as an OpenAI-compatible ``/v1/embeddings`` HTTP endpoint plus
an MCP ``/mcp`` endpoint.  slife's memdb/memfiles plugins both call it over
HTTP, so a model is never loaded twice in one process tree.

Modules::

    server.py     FastMCP plugin — MCP tools + /v1/embeddings custom route
    engine.py     Model engine (gguf / transformer), lazy load + encode
    config.py     local_embed.yaml loading and path resolution
    cmd_set.py    ``local-embed set`` / ``set-gguf`` config writers
    cli.py        Console entry point (``local-embed``)
    adopt.py      Adopt a local-embed already holding the fixed port
    threads.py    run_daemon — daemon-thread offload for blocking model calls
    logging.py    Structured logging setup

Usage::

    local-embed set-gguf bge-m3 --path /path/to/model.gguf
    local-embed set BAAI/bge-m3 --HF_HUB_CACHE ~/.cache/huggingface/hub
    local-embed                      # serve, config from local_embed.yaml
"""

from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as _version

try:
    __version__ = _version("local-embed")
except PackageNotFoundError:
    # Running from a source tree that was never installed.
    __version__ = "0.0.0"

__all__ = ["__version__"]
