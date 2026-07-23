# SBOM Security Platform — Enterprise Reference Program

How large regulated enterprises — **banks, insurers, and large retailers** —
build and operate an **SBOM Security Platform**: the system that generates,
ingests, stores, and continuously monitors Software Bills of Materials at fleet
scale, binds them to cryptographic **signatures and provenance**, enforces
**policy-as-code** at Kubernetes admission, secures platform access with
**workload identity (OIDC/IRSA/SPIFFE)**, and detects **runtime drift** between a
running container and the SBOM it was built from.

Tool-grounded (Syft, Trivy, Dependency-Track, GUAC, Sigstore `cosign`, in-toto,
SLSA, OPA/Gatekeeper, Kyverno, SPIFFE/SPIRE, Falco/Tetragon) but vendor-neutral.

> Sibling project: [`../../hardened-oci`](../../hardened-oci) covers *building*
> hardened images. **This** project is the platform that manages the evidence
> those images produce and enforces it across the fleet.

---

## The problem this platform solves

A large enterprise runs thousands of container images across hundreds of
clusters. When the next Log4Shell-class CVE drops on a Friday night, the only
question that matters is:

> **"Which of our running workloads contain the vulnerable component — right
> now — and can we prove it?"**

Ad-hoc scanning cannot answer this at scale, in seconds, with an audit trail.
An SBOM Security Platform can, because it treats the SBOM as a **first-class,
queryable, signed data asset** for every artifact, correlated with what is
actually deployed and running.

```text
generate  →  sign/attest  →  ingest & normalize  →  store & index  →  query & monitor
   │             │                  │                    │                  │
 Syft/Trivy    cosign         platform API         SBOM database      "who has libX?"
 CycloneDX     in-toto/SLSA   (Dependency-Track      + VEX + CVE       continuous CVE
 or SPDX       attestation     / GUAC)                correlation       + license watch
                                                                             │
                              policy-as-code (admission) ◀──────────────────┤
                              runtime drift (running vs SBOM) ◀──────────────┘
```

## What the platform does (capability map)

| Capability | Question it answers | Primary tooling |
|------------|---------------------|-----------------|
| **SBOM generation** | What's in this artifact? | Syft, Trivy, apko, build plugins → CycloneDX / SPDX |
| **Signing & provenance** | Who built it, from where, is it tamper-free? | cosign, in-toto, SLSA attestations |
| **Ingestion & management** | Central inventory of every SBOM, versioned | Dependency-Track, GUAC |
| **Continuous monitoring** | Which components are now vulnerable? | DT/GUAC + CVE feeds + VEX |
| **Policy-as-code** | Should this be allowed to deploy? | Kyverno, OPA/Gatekeeper |
| **Workload identity** | Can this service prove who it is to the platform? | OIDC, IRSA, SPIFFE/SPIRE |
| **Runtime drift** | Does the running container match its SBOM? | package diff, Falco/Tetragon |

## Program principles

1. **The SBOM is a signed data asset, not a build byproduct.** It is attested,
   versioned, centrally stored, and queryable — never a file that dies in CI.
2. **Provenance before trust.** Every SBOM is bound to a signature and SLSA
   provenance; the platform verifies identity, not reputation.
3. **One inventory, many questions.** A single normalized store answers CVE
   impact, license, and "what's deployed" across the whole fleet.
4. **Enforce with code, not review.** Deployment decisions are executed by
   admission controllers reading attested evidence.
5. **Identity is the perimeter.** Every service and pipeline authenticates with
   short-lived, federated identity (OIDC/IRSA/SPIFFE) — no static secrets.
6. **Build-time truth must match runtime truth.** Continuously reconcile what is
   *running* against the SBOM it *claims* — drift is a signal.
7. **Everything is auditable evidence** for DORA, PCI DSS, NYDFS, FFIEC, EO
   14028, and NIST SSDF.

## How to navigate

| Path | Covers |
|------|--------|
| [docs/01-platform-architecture.md](docs/01-platform-architecture.md) | Components, data flow, deployment topology, scale |
| [docs/02-sbom-generation-and-formats.md](docs/02-sbom-generation-and-formats.md) | CycloneDX vs SPDX, generation, merging, versioning |
| [docs/03-sbom-management-platform.md](docs/03-sbom-management-platform.md) | Ingestion, storage, query, VEX, continuous monitoring |
| [docs/04-signing-verification-provenance.md](docs/04-signing-verification-provenance.md) | cosign, in-toto, SLSA, attestation binding |
| [docs/05-policy-as-code.md](docs/05-policy-as-code.md) | Kyverno & OPA/Gatekeeper gates on SBOM/attestations |
| [docs/06-workload-identity.md](docs/06-workload-identity.md) | OIDC, IRSA, SPIFFE/SPIRE, keyless identity |
| [docs/07-runtime-sbom-drift.md](docs/07-runtime-sbom-drift.md) | Comparing running containers vs SBOM |
| [docs/08-enterprise-adoption.md](docs/08-enterprise-adoption.md) | Bank / insurer / retail patterns, compliance, scale |
| [docs/maturity-model.md](docs/maturity-model.md) | L0→L4 adoption path |
| [architecture/](architecture/) | Reference architecture + platform data model |
| [examples/](examples/) | Working SBOMs, signing, ingestion, policy, identity, drift |

## Quick start

1. Understand the shape: [docs/01-platform-architecture.md](docs/01-platform-architecture.md).
2. Generate + attest an SBOM: [examples/sbom/](examples/sbom/) →
   [examples/signing/attest-sbom.sh](examples/signing/attest-sbom.sh).
3. Ingest it: [examples/ingestion/upload-to-dependency-track.sh](examples/ingestion/upload-to-dependency-track.sh).
4. Gate deployments on it: [examples/policy/](examples/policy/).
5. Give the platform an identity: [examples/workload-identity/](examples/workload-identity/).
6. Detect drift: [examples/runtime-drift/compare-running-vs-sbom.sh](examples/runtime-drift/compare-running-vs-sbom.sh).

## Scope

Architectural + operational reference plus adaptable artifacts. Example manifests
are starting points — pin digests, substitute registries/identities/account IDs,
and validate against your own environment before production use.
