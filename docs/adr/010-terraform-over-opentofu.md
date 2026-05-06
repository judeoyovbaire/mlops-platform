# ADR-010: Terraform Over OpenTofu

## Status

Accepted

## Context

OpenTofu emerged as an open-source fork of Terraform after HashiCorp changed Terraform's license from MPL 2.0 to BSL 1.1 in August 2023. OpenTofu is backed by the Linux Foundation and maintains MPL 2.0 licensing. As a multi-cloud infrastructure platform, we need to decide which IaC tool to use.

Key factors:

- This is a portfolio/educational project, not a commercial product — the BSL license restriction on "competitive offerings" does not apply
- Terraform has a larger ecosystem, more provider support, and broader community knowledge
- OpenTofu maintains API compatibility with Terraform but may diverge over time
- Hiring managers evaluating this portfolio are more likely to have Terraform experience

## Decision

We will continue using **Terraform** rather than migrating to OpenTofu.

## Consequences

### Positive

- Broader ecosystem support — Terraform has more providers, modules, and documentation
- Lower risk of compatibility issues with third-party tooling (Terragrunt, Atlantis, Spacelift)
- More recognizable on a portfolio — Terraform is the industry standard name
- No migration effort required

### Negative

- BSL license would restrict use in a competing IaC product (not applicable here)
- If OpenTofu gains exclusive features, we would miss them

### Neutral

- The codebase is compatible with OpenTofu — migration is a single binary swap if needed
- Both tools use the same HCL configuration language and provider ecosystem
- We document this decision for transparency about license awareness

## Alternatives Considered

### Alternative 1: OpenTofu

**Pros:**
- MPL 2.0 license (fully open source)
- Linux Foundation governance
- No commercial use restrictions

**Cons:**
- Smaller community and ecosystem
- Risk of provider compatibility divergence
- Less recognized by hiring managers

**Why not chosen:** The license restriction does not affect a portfolio project, and Terraform's ecosystem advantages outweigh OpenTofu's licensing benefits for this use case.

### Alternative 2: Pulumi

**Pros:**
- Use general-purpose programming languages (Python, TypeScript)
- Better testing story with native language test frameworks
- Rich type system

**Cons:**
- Different paradigm from Terraform — not a drop-in replacement
- Smaller multi-cloud module ecosystem
- Would require complete rewrite of infrastructure code

**Why not chosen:** The migration cost is prohibitive, and HCL is the dominant IaC language in platform engineering.

## References

- [HashiCorp BSL License](https://www.hashicorp.com/bsl)
- [OpenTofu](https://opentofu.org/)
- [Terraform vs OpenTofu Comparison](https://opentofu.org/docs/intro/migration/)
