# ADR-008: Supply Chain Security with Sigstore and SLSA

## Status

Accepted

## Context

Container supply chain attacks are an increasing threat. The platform builds and deploys ML pipeline images (training, pretrained model serving) to Kubernetes clusters across three clouds. Without image provenance verification, a compromised CI pipeline or registry could inject malicious images into production.

Key requirements:

- Cryptographic proof that images were built by our CI pipeline
- No static signing keys to manage or rotate
- Provenance metadata linking images to source commits
- Runtime enforcement preventing unsigned images from running
- SBOM (Software Bill of Materials) attached to every image

## Decision

We will adopt **Sigstore Cosign keyless signing** with **SLSA v1 Build Level 2 provenance** (GitHub artifact attestations) for all container images.

1. **Cosign keyless signing** via GitHub Actions OIDC — no static keys, certificates tied to workflow identity
2. **SLSA provenance** (v1, Build L2) via `actions/attest-build-provenance` on the pushed digest
3. **Signature verification in CI** by digest, against the same exact identity the cluster enforces
4. **Kyverno ClusterPolicy** enforcing signature verification at admission time
5. **SBOMs** generated with Trivy and attested to images via `cosign attest --type spdxjson`

## Consequences

### Positive

- Zero key management overhead — Sigstore keyless uses ephemeral certificates from Fulcio CA
- Cryptographic proof that images were built by GitHub Actions from this repository
- SLSA Build L2 provenance: signed, service-generated provenance tied to the exact digest (L3 would need an isolated reusable builder such as slsa-github-generator; not adopted)
- Kyverno blocks unsigned/tampered images before they reach the cluster
- SBOMs enable vulnerability scanning of deployed images
- Transparent log (Rekor) provides public audit trail

### Negative

- Requires `id-token: write` permission in GitHub Actions workflows
- Cosign verification adds latency to pod admission (~1-2s)
- External dependency on Sigstore infrastructure (Fulcio, Rekor)

### Neutral

- Kyverno policy runs in Enforce mode for `ghcr.io/judeoyovbaire/mlops-platform/*`, Audit mode for everything else
- Can be extended to verify Helm chart provenance in the future

## Alternatives Considered

### Alternative 1: Static Key Signing

**Pros:**
- Simple to understand
- No external dependency

**Cons:**
- Key management overhead (rotation, distribution, secure storage)
- Single point of failure if key is compromised
- No automatic identity binding to CI pipeline

**Why not chosen:** Keyless signing eliminates key management entirely while providing stronger identity guarantees through OIDC binding.

### Alternative 2: Notation (Microsoft/AWS)

**Pros:**
- OCI-native signing format
- AWS Signer and Azure Key Vault integration

**Cons:**
- Less mature ecosystem than Sigstore
- Cloud-specific tooling fragments multi-cloud story
- No built-in transparency log

**Why not chosen:** Sigstore is the CNCF standard with broader ecosystem support, and keyless signing is more elegant than cloud-specific key management.

## References

- [Sigstore Cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)
- [SLSA Framework](https://slsa.dev/)
- [Kyverno Image Verification](https://kyverno.io/docs/writing-policies/verify-images/)
- [GitHub Artifact Attestations](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations)

## Amendment (2026-11-01)

The original claim of SLSA Level 3 was not met: provenance was a hand-written
predicate signed by the build job itself, and `release.yaml` attested
`@sha256:latest` because the digests it referenced were never produced. The
admission policy also trusted any GitHub repository named `mlops-platform`.
Corrected in JDH-404: the Kyverno keyless attestor is pinned to
`https://github.com/judeoyovbaire/mlops-platform/.github/workflows/build-sign-publish.yaml@refs/heads/main` and `ghcr.io/judeoyovbaire/mlops-platform/*`; the build job verifies that same identity by
digest and attaches a GitHub artifact attestation (SLSA v1 Build L2).
