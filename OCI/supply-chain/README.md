# Supply Chain Security

Enterprise reference programs for **software supply chain security** — how
regulated organizations (banks, insurers, large retailers) prove what is in
their software, where it came from, and enforce that across Kubernetes fleets.

Vendor-neutral but tool-grounded: SBOMs (CycloneDX/SPDX), Sigstore `cosign`,
in-toto/SLSA provenance, Syft/Trivy, Dependency-Track, GUAC, Kyverno,
OPA/Gatekeeper, SPIFFE/SPIRE, IRSA, Falco/Tetragon.

---

## Projects

| Project | What it covers |
|---------|----------------|
| [sbom-security-platform/](sbom-security-platform/) | The **SBOM Security Platform** — generate, sign/attest, ingest, store, and continuously monitor SBOMs at fleet scale; policy-as-code at admission; workload identity (OIDC/IRSA/SPIFFE); runtime drift (running container vs SBOM). |
| [oras/](oras/) | **ORAS (OCI Registry As Storage)** — what it is, a step-by-step guide to mastering it, and how it stores/attaches SBOMs, signatures, and provenance in registries via the OCI **Referrers API** — the plumbing connecting the other projects. |

## Related (sibling directory)

| Project | What it covers |
|---------|----------------|
| [../hardened-oci/](../hardened-oci/) | **Hardened OCI Images** — *building and delivering* minimal, signed, hardened images (Wolfi/Chainguard/distroless), the secure image lifecycle, and Kubernetes admission/runtime controls. |

## How they fit together

`hardened-oci` **produces** trustworthy artifacts; `oras` is the **registry
plumbing** that stores and moves the evidence; `sbom-security-platform`
**manages and enforces** it.

```text
  hardened-oci                 ORAS / Referrers API          sbom-security-platform
 ┌───────────────────┐        ┌────────────────────┐        ┌─────────────────────────────┐
 │ build minimal,    │ image  │  OCI registry       │        │ discover + pull evidence     │
 │ signed image      │ + SBOM │  image @sha256       │ disc.  │ → verify identity (cosign)   │
 │ (Wolfi/apko/      │───────▶│   ├─ SBOM (referrer) │──────▶ │ → ingest → CVE/VEX → monitor │
 │  cosign/SLSA)     │ attach │   ├─ signature       │  +pull │ → policy verdict / drift     │
 │                   │───────▶│   └─ provenance      │        │                              │
 └───────────────────┘        └────────────────────┘        └─────────────────────────────┘
        produce                     store + move                    manage + enforce
```

A hardened image's attested SBOM is attached to it in the registry (ORAS +
Referrers), then pulled, verified, ingested, enforced, and diffed against the
running container by the platform.

## Suggested reading order

1. **Produce**: [../hardened-oci/README.md](../hardened-oci/README.md) — build a
   minimal, signed image with an attested SBOM.
2. **Store & move**: [oras/README.md](oras/README.md) — understand how the SBOM,
   signature, and provenance live in the registry and travel with the image.
3. **Manage & enforce**: [sbom-security-platform/README.md](sbom-security-platform/README.md)
   — ingest that SBOM, gate deployments on it, and detect runtime drift.

Each project ships staged docs, a maturity/learning path, and adaptable working
artifacts under its own `examples/`.
