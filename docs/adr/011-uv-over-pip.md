# ADR-011: uv Over pip for Python Package Management

## Status

Accepted

## Context

The platform's Python toolchain (training pipelines, tests, linting) used pip with `pyproject.toml` for dependency management. As the project grew, several pain points emerged:

- `pip install` is slow, especially in CI where caching is imperfect
- No built-in lockfile — `pip freeze` is fragile and not cross-platform
- Dependency resolution conflicts are difficult to debug
- Virtual environment management requires separate tooling (venv, virtualenv)
- Docker builds spend significant time on `pip install` layers

uv is a Rust-based Python package manager from Astral (the Ruff team) that provides 10-100x faster installs, built-in lockfiles, and a unified workflow for virtual environments, dependency management, and tool execution.

## Decision

We will migrate from **pip** to **uv** for all Python package management, including:

1. **Local development:** `uv sync` replaces `pip install -e ".[dev]"`
2. **CI/CD:** `astral-sh/setup-uv` replaces `actions/setup-python` + `pip install`
3. **Docker builds:** `uv pip install --system` replaces `pip install`
4. **Tool execution:** `uv run` replaces direct tool invocation (ruff, pytest, etc.)
5. **Lockfile:** `uv.lock` provides deterministic, cross-platform dependency resolution

## Consequences

### Positive

- 10-100x faster dependency installation in CI and Docker builds
- Deterministic builds via `uv.lock` — same versions across all environments
- Unified tool: replaces pip, pip-tools, virtualenv, and pip-audit workflows
- Built-in Python version management (`.python-version` file)
- Cache-friendly — uv's global cache reduces redundant downloads
- Dockerfile optimization — `COPY --from=ghcr.io/astral-sh/uv:latest` adds uv without pip overhead

### Negative

- uv is newer than pip — less institutional knowledge
- Team members need to learn `uv sync` / `uv run` commands
- `uv.lock` is a new file to maintain (but auto-updated)

### Neutral

- Build-system changed from setuptools to hatchling (uv's default, also faster)
- `pyproject.toml` retains `[project.optional-dependencies]` for backwards compatibility
- `[tool.uv]` section added for uv-specific dev dependencies

## Alternatives Considered

### Alternative 1: pip + pip-tools

**Pros:**
- Familiar to all Python developers
- pip-compile provides lockfile-like behavior

**Cons:**
- Slow dependency resolution and installation
- pip-tools adds another tool to maintain
- No built-in virtual environment management

**Why not chosen:** uv provides all pip-tools functionality with dramatically better performance and fewer tools to manage.

### Alternative 2: Poetry

**Pros:**
- Mature lockfile support
- Good dependency resolution
- Popular in the Python ecosystem

**Cons:**
- Slower than uv
- Uses non-standard `pyproject.toml` format for some features
- No `--system` install mode for Docker containers
- Heavy runtime footprint

**Why not chosen:** uv is faster, uses standard `pyproject.toml`, and provides better Docker integration.

### Alternative 3: PDM

**Pros:**
- PEP 582 support
- Good lockfile implementation

**Cons:**
- Smaller community than Poetry or uv
- Slower than uv
- Less CI/CD integration support

**Why not chosen:** uv has better performance, broader adoption momentum, and first-class GitHub Actions support.

## References

- [uv Documentation](https://docs.astral.sh/uv/)
- [astral-sh/setup-uv GitHub Action](https://github.com/astral-sh/setup-uv)
- [uv: An extremely fast Python package installer](https://astral.sh/blog/uv)
