# Hardened OCI Images for Kubernetes — Enterprise Program

A reference program for how organizations build, sign, distribute, and enforce
**hardened OCI images** across Kubernetes environments. It defines trusted image
standards, a secure image lifecycle, and the modern container security controls
that tie the two together.

The material is tool-grounded (Wolfi, Chainguard Images, apko, melange, Sigstore
`cosign`, Syft/Grype/Trivy, Kyverno, OPA Gatekeeper, Pod Security Standards,
Falco) but the practices are vendor-neutral and map onto any registry, CI system,
or runtime.

---

## Why this exists

Most container CVEs come from the base image and its OS packages — not the
application code. A typical `node:latest` or `python:latest` image ships hundreds
of megabytes of shells, package managers, and libraries the workload never uses,
each one an attack surface and a patching obligation.

A hardened-image program flips the default: **minimal by construction, signed by
policy, and verified at admission.** The goal is that nothing runs in a cluster
unless it is a known-good artifact from a trusted pipeline.

```text
Untrusted default:  arbitrary image  → pull → run
Hardened program:   trusted base → build → SBOM → scan → sign → attest
                                   → push → admission-verify → run → watch → rebuild
```

## Program principles

1. **Minimal by default.** No shell, no package manager, no build tools in the
   runtime image. Distroless / Wolfi-based. Smallest possible attack surface.
2. **Provenance over trust.** Every image is signed and carries an SBOM plus
   build provenance. Consumers verify signatures, not reputations.
3. **Non-root, read-only, least-privilege.** The image and its Pod spec both
   assume the workload has the fewest capabilities that let it function.
4. **Rebuild, don't patch in place.** Images are immutable. Vulnerabilities are
   fixed by rebuilding from an updated base and re-releasing — never by
   `apt-get upgrade` inside a running container.
5. **Enforcement at the gate.** Policy is executed by an admission controller in
   every cluster, not left to reviewer goodwill. Fail closed.
6. **Everything is evidence.** SBOMs, scan reports, signatures, and attestations
   are retained and auditable for compliance (SLSA, NIST SSDF, PCI, FedRAMP).

## How to navigate

| Path | What it covers |
|------|----------------|
| [docs/01-trusted-image-standards.md](docs/01-trusted-image-standards.md) | What "trusted" means: base image policy, golden images, provenance, naming |
| [docs/02-secure-image-lifecycle.md](docs/02-secure-image-lifecycle.md) | Build → SBOM → scan → sign → store → deploy → run → patch/rebuild |
| [docs/03-container-security-controls.md](docs/03-container-security-controls.md) | Signing, SBOM, scanning, hardening controls and how they compose |
| [docs/04-kubernetes-admission-and-runtime.md](docs/04-kubernetes-admission-and-runtime.md) | Admission verification, Pod Security, runtime detection |
| [docs/05-governance-and-compliance.md](docs/05-governance-and-compliance.md) | Roles, exceptions, audit evidence, framework mapping |
| [docs/maturity-model.md](docs/maturity-model.md) | Level 0→4 adoption path with concrete exit criteria |
| [standards/](standards/) | The enforceable base-image policy and golden-image catalog |
| [policies/](policies/) | Image provenance & signing policy (the contract) |
| [examples/](examples/) | Working build, CI, signing, SBOM, and Kubernetes policy artifacts |

## Quick start for a team adopting the program

1. Read [docs/01-trusted-image-standards.md](docs/01-trusted-image-standards.md)
   and pick a golden base from [standards/golden-image-catalog.md](standards/golden-image-catalog.md).
2. Build with [examples/apko/hardened-app.apko.yaml](examples/apko/hardened-app.apko.yaml)
   or [examples/dockerfile/Dockerfile.hardened-multistage](examples/dockerfile/Dockerfile.hardened-multistage).
3. Wire the pipeline from [examples/ci/github-actions-build-sign-scan.yml](examples/ci/github-actions-build-sign-scan.yml).
4. Deploy behind the admission policies in [examples/kubernetes/](examples/kubernetes/).
5. Confirm your maturity level against [docs/maturity-model.md](docs/maturity-model.md).

## Scope

This is an architectural + operational reference and a set of ready-to-adapt
artifacts. The example manifests are illustrative starting points — pin digests,
substitute your registry and identities, and validate against your own clusters
before production use.
