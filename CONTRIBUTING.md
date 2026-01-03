# Contributing to MLOps Platform

Thank you for your interest in contributing to the MLOps Platform! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [Documentation](#documentation)

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please be respectful and constructive in all interactions.

## Getting Started

### Prerequisites

- Python 3.10+
- Terraform 1.6+
- kubectl
- AWS CLI v2
- Docker (for local testing)

### Local Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/mlops-platform.git
   cd mlops-platform
   ```

2. **Create a virtual environment**
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # Linux/macOS
   # or
   .venv\Scripts\activate     # Windows
   ```

3. **Install dependencies**
   ```bash
   pip install -e ".[dev]"
   ```

4. **Install pre-commit hooks**
   ```bash
   pre-commit install
   ```

5. **Verify setup**
   ```bash
   make validate
   make test
   ```

## Development Workflow

### Branch Naming Convention

Use descriptive branch names following this pattern:

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feature/<description>` | `feature/add-gpu-autoscaling` |
| Bug fix | `fix/<description>` | `fix/mlflow-connection-timeout` |
| Documentation | `docs/<description>` | `docs/add-troubleshooting-guide` |
| Refactor | `refactor/<description>` | `refactor/terraform-modules` |
| Chore | `chore/<description>` | `chore/update-dependencies` |

### Commit Message Format

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(karpenter): add GPU node pool with SPOT instances

- Configure g4dn.xlarge instances for ML workloads
- Add scale-to-zero after 4 hours of idle time
- Include taints for GPU-specific scheduling

Closes #123
```

```
fix(mlflow): resolve database connection timeout

Increase connection pool timeout from 30s to 60s to handle
slow network conditions during peak usage.

Fixes #456
```

## Code Standards

### Python

- Follow [PEP 8](https://pep8.org/) style guide
- Use type hints for function signatures
- Maximum line length: 100 characters
- Use `ruff` for linting and formatting

```bash
# Run linter
ruff check .

# Auto-fix issues
ruff check --fix .

# Format code
ruff format .
```

### Terraform

- Use `terraform fmt` for formatting
- Follow [HashiCorp's style conventions](https://developer.hashicorp.com/terraform/language/style)
- Include descriptions for all variables and outputs
- Use meaningful resource names with project prefix

```bash
# Format Terraform files
terraform fmt -recursive infrastructure/terraform/

# Validate configuration
terraform validate
```

### Kubernetes Manifests

- Use `kubeconform` for validation
- Include resource requests and limits for all containers
- Add security contexts to all pods
- Use standard Kubernetes labels (`app.kubernetes.io/*`)

```bash
# Validate manifests
kubeconform -strict infrastructure/kubernetes/
```

### YAML

- Use 2-space indentation
- Quote strings that could be interpreted as other types
- Add comments for complex configurations

## Testing Requirements

### Before Submitting a PR

1. **Run all tests**
   ```bash
   make test
   ```

2. **Run linting**
   ```bash
   make lint
   ```

3. **Validate infrastructure**
   ```bash
   make validate
   ```

### Test Coverage

- New features should include tests
- Aim for 80%+ coverage on new code
- Critical paths (training, inference) require integration tests

### Test Types

| Type | Location | Command |
|------|----------|---------|
| Unit tests | `tests/test_*.py` | `pytest tests/` |
| E2E tests | `tests/test_e2e_*.py` | `pytest tests/ -m e2e` |
| Terraform validation | CI/CD | `terraform validate` |
| Manifest validation | CI/CD | `kubeconform` |

## Pull Request Process

### Creating a PR

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature
   ```

2. **Make your changes** following the code standards

3. **Commit with meaningful messages**
   ```bash
   git commit -m "feat(scope): description"
   ```

4. **Push to your fork/branch**
   ```bash
   git push origin feature/your-feature
   ```

5. **Open a Pull Request** with:
   - Clear title following commit message format
   - Description of changes
   - Link to related issues
   - Screenshots/logs if applicable

### PR Template

```markdown
## Summary
Brief description of changes

## Changes
- Change 1
- Change 2

## Testing
- [ ] Unit tests pass
- [ ] Linting passes
- [ ] Manual testing completed

## Related Issues
Closes #123
```

### Review Process

1. All PRs require at least one approval
2. CI checks must pass
3. No merge conflicts
4. Documentation updated if needed

### After Merge

- Delete your feature branch
- Update related issues
- Monitor deployment (if applicable)

## Documentation

### When to Update Docs

- New features require documentation
- API changes need updated examples
- Configuration changes need updated guides

### Documentation Structure

```
docs/
├── architecture.md      # System architecture
├── adr/                 # Architecture Decision Records
│   └── 001-*.md
├── runbooks/            # Operational procedures
│   └── *.md
└── api/                 # API documentation
```

### Architecture Decision Records (ADRs)

For significant architectural decisions, create an ADR:

```bash
# Create new ADR
cp docs/adr/template.md docs/adr/NNN-title.md
```

Follow the template structure:
- Context: Why is this decision needed?
- Decision: What was decided?
- Consequences: What are the implications?

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions
- Check existing issues before creating new ones

Thank you for contributing!