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

We will adopt **Sigstore Cosign keyless signing** with **SLSA Level 3 provenance** for all container images.

1. **Cosign keyless signing** via GitHub Actions OIDC — no static keys, certificates tied to workflow identity
2. **SLSA provenance attestations** attached to images using `cosign attest`
3. **GitHub native build attestations** via `actions/attest-build-provenance@v2`
4. **Kyverno ClusterPolicy** enforcing signature verification at admission time
5. **SBOMs** generated with Trivy and attached to images via `cosign attach sbom`

## Consequences

### Positive

- Zero key management overhead — Sigstore keyless uses ephemeral certificates from Fulcio CA
- Cryptographic proof that images were built by GitHub Actions from this repository
- SLSA Level 3 provenance provides build integrity guarantees
- Kyverno blocks unsigned/tampered images before they reach the cluster
- SBOMs enable vulnerability scanning of deployed images
- Transparent log (Rekor) provides public audit trail

### Negative

- Requires `id-token: write` permission in GitHub Actions workflows
- Cosign verification adds latency to pod admission (~1-2s)
- External dependency on Sigstore infrastructure (Fulcio, Rekor)

### Neutral

- Kyverno policy runs in Enforce mode for GHCR images, Audit mode for third-party images
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
