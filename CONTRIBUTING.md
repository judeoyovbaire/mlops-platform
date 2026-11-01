# Contributing

This is a single-maintainer repository. Changes go through pull requests that must pass the required CI checks.

## Prerequisites

- Python 3.12 (`.python-version`; the pipeline and serving images run 3.10, enforced by a ruff per-file target)
- [uv](https://docs.astral.sh/uv/)
- Terraform 1.17 (CI pins 1.17.1; the platform needs `>= 1.8`, the bootstrap stack `>= 1.5.7`)
- kubectl, Helm 3, AWS CLI v2, Docker

## Setup

```bash
git clone https://github.com/judeoyovbaire/mlops-platform.git
cd mlops-platform
uv sync                          # installs the project and the dev dependency group
uv sync --extra drift-detection  # optional: the drift-detection library
uv run pre-commit install
make validate && make test
```

## Checks

```bash
uv run ruff check pipelines/ components/ scripts/ tests/ examples/
uv run ruff format --check pipelines/ components/ scripts/ tests/ examples/
terraform fmt -check -recursive infrastructure/terraform/
```

CI validates Kubernetes manifests with kubeconform (`ci-cd.yaml` job `validate-kubernetes`); locally, rely on pre-commit.

## Tests

| Type | Location | Command |
|------|----------|---------|
| Unit | `tests/unit/` | `uv run pytest tests/unit` |
| Property | `tests/property/` | `uv run pytest tests/property` |
| Integration | `tests/integration/` | `uv run pytest tests/integration` |
| Kind E2E | `tests/e2e/` | `uv run pytest -m e2e` |
| Kyverno policies | `tests/policies/` | `scripts/test-policies.sh` |

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`, with types `feat`, `fix`, `docs`, `refactor`, `test`, `chore`.

```
feat(karpenter): restrict GPU pool to g5 (vLLM crashes on T4)
```

## Documentation layout

```
docs/
├── architecture.md   # System design
├── adr/              # Architecture Decision Records
├── runbooks/         # Operational procedures
├── retros/           # Deployment retrospectives
└── evidence/         # Captured run evidence
```

For a significant architectural decision, copy `docs/adr/template.md` to `docs/adr/NNN-title.md` and add it to `docs/adr/README.md`.
