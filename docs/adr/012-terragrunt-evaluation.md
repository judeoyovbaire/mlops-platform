# ADR-012: Evaluate Terragrunt for DRY Terraform Configuration

## Status

Proposed

## Context

The platform maintains six environment directories (`aws/{dev,prod}`, `azure/{dev,prod}`,
`gcp/{dev,prod}`), each with its own `variables.tf` containing duplicated default values for
~20 Helm chart versions. When a chart version is bumped, six files must be updated in lockstep.

## Decision Drivers

- **DRY principle**: Helm version defaults are copy-pasted across environments.
- **Operational risk**: Forgetting to update one environment causes version skew.
- **Onboarding cost**: New contributors must understand the duplication pattern.
- **Toolchain complexity**: Terragrunt adds a wrapper around `terraform` invocations.

## Considered Options

1. **Terragrunt `include` + `inputs`** — Single `terragrunt.hcl` per environment inheriting
   from a root config. Eliminates variable duplication entirely.
2. **Terraform variable files (`.tfvars`)** — Shared `common.tfvars` loaded via `-var-file`.
   Reduces but does not eliminate duplication (variables still need declarations).
3. **Status quo** — Accept duplication; rely on CI validation and Dependabot PRs.

## Decision

Option 1 (Terragrunt) is recommended for a future iteration. The current setup is functional
and the duplication is manageable at the current scale (6 environments, ~20 shared variables).

## Consequences

- **If adopted**: Reduced maintenance burden, single source of truth for Helm versions,
  but requires team familiarity with Terragrunt and CI pipeline adjustments.
- **If deferred**: Continue with Dependabot-managed version bumps and manual synchronisation.
  Add `validation` blocks to Helm version variables as an interim guard rail.
