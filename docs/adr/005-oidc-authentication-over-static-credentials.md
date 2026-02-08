# ADR-005: OIDC Authentication Over Static Credentials

## Status

Accepted

## Context

CI/CD pipelines need to authenticate with cloud providers (AWS, Azure, GCP) to deploy infrastructure and applications. The traditional approach uses long-lived static credentials (access keys, service principal secrets) stored as GitHub Secrets, which poses security risks:

- Credentials can be leaked through logs or compromised repositories
- Rotation requires manual updates across multiple systems
- Static credentials provide broad access without time-bound restrictions
- Difficult to audit which workflow run used which credentials

## Decision

We will use **OIDC (OpenID Connect) federation** for all cloud provider authentication in CI/CD:

- **AWS**: GitHub Actions OIDC → AWS IAM Role (`aws-actions/configure-aws-credentials` with `role-to-assume`)
- **Azure**: GitHub Actions OIDC → Azure AD Federated Credential (`azure/login` with `client-id`, `tenant-id`, `subscription-id`)
- **GCP**: GitHub Actions OIDC → GCP Workload Identity Federation (`google-github-actions/auth` with `workload_identity_provider`)

## Consequences

### Positive

- **No stored secrets**: Cloud credentials are never stored in GitHub - tokens are issued per workflow run
- **Short-lived tokens**: OIDC tokens expire automatically (typically 1 hour), limiting blast radius
- **Auditable**: Each workflow run gets a unique token traceable to specific commit, branch, and actor
- **Zero rotation overhead**: No credential rotation needed since tokens are ephemeral
- **Fine-grained access**: IAM roles/policies can scope access by repository, branch, and environment

### Negative

- **Initial setup complexity**: Requires configuring identity providers and trust relationships in each cloud
- **Provider-specific configuration**: Each cloud has different OIDC setup steps
- **Debugging challenges**: Token exchange failures can be harder to diagnose than static credential issues

### Neutral

- GitHub Actions natively supports OIDC token generation (no additional tooling needed)
- All major cloud providers now support OIDC federation with GitHub Actions

## Alternatives Considered

### Alternative 1: Long-lived static credentials

**Why not chosen:** Security risk - credentials stored in GitHub Secrets can be leaked, don't expire, and are difficult to audit.

### Alternative 2: HashiCorp Vault for dynamic credentials

**Why not chosen:** Adds operational complexity of running and maintaining a Vault cluster. OIDC federation provides similar benefits natively.

## References

- [GitHub Actions OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS IAM OIDC Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Azure Workload Identity Federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)