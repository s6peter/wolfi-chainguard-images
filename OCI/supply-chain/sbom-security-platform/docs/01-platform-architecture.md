# 01 — Platform Architecture

The SBOM Security Platform is a data platform first and a security tool second.
Its job is to turn a stream of build-time and runtime evidence into a single,
queryable, signed inventory that policy and humans can act on.

---

## 1. Logical components

```text
┌──────────────┐   ┌──────────────┐   ┌───────────────────────┐   ┌───────────────────┐
│  PRODUCERS   │   │   SIGNING     │  │      PLATFORM CORE     │   │    CONSUMERS       │
│              │   │               │  │                        │   │                    │
│ CI builds    │──▶│ cosign        │─▶│ Ingestion API          │◀──│ Admission control  │
│ Syft/Trivy   │   │ in-toto/SLSA  │  │ Normalizer (CDX/SPDX)  │   │ (Kyverno / OPA)    │
│ apko/melange │   │ attestations  │  │ SBOM store + index     │──▶│ Dashboards / SIEM  │
│ registries   │   │ Fulcio/Rekor  │  │ VEX + CVE correlation  │   │ Auditors / GRC     │
│ runtime      │   │               │  │ Query + policy API     │──▶│ Ticketing / SOAR   │
│ sensors      │──▶│ (verify)      │─▶│ Continuous monitor     │   │ Rebuild pipelines  │
└──────────────┘   └──────────────┘  └───────────────────────┘   └───────────────────┘
        ▲                                       ▲
        └──────── workload identity (OIDC / IRSA / SPIFFE) authenticates every arrow ────────┘
```

### Producers
- **CI build systems** emit an SBOM per artifact (Syft/Trivy/apko).
- **Registries** hold images + attached attestations.
- **Runtime sensors** report what is actually installed/running per pod.

### Signing layer
- `cosign` signs images and **attaches SBOM + SLSA provenance as attestations**.
- Keyless (Fulcio/Rekor) preferred; identity is a CI OIDC workflow.
- Consumers **verify** identity + attestation presence before trusting an SBOM.

### Platform core (the heart)
- **Ingestion API** — authenticated endpoint that accepts SBOMs/attestations.
- **Normalizer** — parses CycloneDX and SPDX into one internal component model.
- **SBOM store + index** — the versioned, queryable inventory (component →
  artifact → deployment mappings).
- **VEX + CVE correlation** — joins components to vulnerability feeds and applies
  VEX statements ("not affected / fixed / under investigation").
- **Query + policy API** — serves impact queries and admission decisions.
- **Continuous monitor** — re-evaluates the stored inventory against fresh CVE
  data on a schedule; alerts on newly-vulnerable components.

### Consumers
- **Admission controllers** query the policy API / verify attestations.
- **Dashboards, SIEM, GRC, ticketing/SOAR, rebuild pipelines** consume findings.

## 2. Reference tooling

| Layer | Off-the-shelf options |
|-------|----------------------|
| SBOM generation | Syft, Trivy, apko (native), language build plugins |
| Formats | CycloneDX, SPDX |
| Signing / provenance | cosign, in-toto, SLSA, Fulcio, Rekor |
| SBOM management core | **Dependency-Track** (component/vuln/VEX mgmt), **GUAC** (supply-chain graph) |
| Registry (attestation store) | Harbor, OCI registries (attestations as OCI artifacts) |
| Vulnerability feeds | OSV, NVD, GitHub Advisories, vendor feeds |
| Policy-as-code | Kyverno, OPA/Gatekeeper |
| Workload identity | OIDC, IRSA, SPIFFE/SPIRE |
| Runtime | Falco, Tetragon, package-diff jobs |

**Dependency-Track** is the pragmatic center of gravity for most enterprises:
continuous component intelligence, VEX, and an API. **GUAC** complements it when
you need to reason over the *graph* of artifacts, dependencies, and attestations
("what is downstream of this compromised package?").

## 3. Data flow (end to end)

1. CI builds an artifact and generates its SBOM (CycloneDX/SPDX).
2. CI signs the image and **attests** the SBOM + SLSA provenance (cosign).
3. CI (or a registry webhook) **uploads** the SBOM to the platform ingestion
   API, authenticated by workload identity.
4. Platform **normalizes** and stores it, versioned per artifact + build.
5. Platform **correlates** components with CVE feeds and VEX; raises findings.
6. At deploy, **admission control** verifies the attestation and/or queries the
   platform's policy verdict; non-compliant deploys are rejected.
7. **Runtime sensors** report installed packages per pod; the platform
   **reconciles running vs SBOM** and flags drift.
8. **Continuous monitor** re-scans stored SBOMs against new CVEs; findings feed
   dashboards, tickets, and rebuild pipelines.

## 4. Deployment topology (enterprise scale)

```text
        ┌─────────────────── Platform (HA, regional) ───────────────────┐
        │  ingestion API   normalizer   SBOM DB (HA)   monitor   query   │
        └───────▲───────────────────────────────────────────▲──────────┘
                │ mTLS + workload identity                    │ read APIs
   ┌────────────┼───────────────┐                 ┌───────────┼───────────┐
   │ cluster A  │  cluster B ... │      ...        │ SIEM  GRC  dashboards │
   │ (Kyverno)  │  (Kyverno)     │                 └───────────────────────┘
   │ runtime    │  runtime       │
   │ sensors    │  sensors       │
   └────────────┴───────────────┘
```

Scale characteristics enterprises design for:

- **Thousands of images × many builds/day** → the store must version SBOMs and
  dedupe components; expect millions of component rows.
- **Hundreds of clusters** → admission policy distributed to each cluster;
  central platform is the source of truth and the monitor.
- **Multi-region / air-gapped** (common in banks) → mirrored CVE feeds, regional
  platform instances, offline verification bundles for Rekor.
- **High availability** → the platform is in the deploy path (admission); design
  admission to **fail closed on policy but degrade gracefully** (cache verdicts,
  verify signatures locally) so a platform outage doesn't halt all deploys
  unsafely. This trade-off is called out in [05-policy-as-code.md](05-policy-as-code.md).

## 5. Trust boundaries

- Producers → platform: authenticated writes only (workload identity).
- Platform → consumers: signed, read-only verdicts and findings.
- Nothing is trusted because it *arrived*; SBOMs are trusted because their
  **attestation verifies to an expected identity**.

---

**Next:** [02 — SBOM Generation & Formats](02-sbom-generation-and-formats.md)
