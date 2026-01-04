# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the MLOps Platform.

## What is an ADR?

An Architecture Decision Record captures an important architectural decision made along with its context and consequences. ADRs help teams understand why certain decisions were made and provide historical context for future maintainers.

## ADR Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-kserve-over-seldon.md) | Use KServe over Seldon Core for Model Serving | Accepted | 2024-01 |
| [002](002-karpenter-over-cluster-autoscaler.md) | Use Karpenter over Cluster Autoscaler | Accepted | 2024-01 |
| [003](003-rawdeployment-mode-kserve.md) | Use RawDeployment Mode for KServe | Accepted | 2024-01 |

## Creating a New ADR

1. Copy the template:
   ```bash
   cp docs/adr/template.md docs/adr/NNN-title.md
   ```

2. Fill in the sections following the template structure

3. Update the index in this README

4. Submit a PR for review

## ADR Lifecycle

- **Proposed**: Initial state, under discussion
- **Accepted**: Decision has been agreed upon
- **Deprecated**: Decision is no longer relevant
- **Superseded**: Replaced by a newer ADR
