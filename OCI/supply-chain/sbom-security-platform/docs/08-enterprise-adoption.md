# 08 — Enterprise Adoption: Banks, Insurers, Large Retail

The technical platform is the same across industries; the drivers, constraints,
and emphasis differ. This document covers how regulated enterprises actually
operate the platform — governance, compliance, scale — and the patterns specific
to banking, insurance, and large retail.

---

## 1. Regulatory drivers

| Framework | Sector | What it pushes for |
|-----------|--------|--------------------|
| **US EO 14028 / NIST SSDF (SP 800-218)** | All (esp. gov suppliers) | SBOMs, provenance, secure build attestation |
| **PCI DSS 4.0** | Retail, banks (card data) | Inventory, vuln mgmt, change control, least privilege |
| **DORA** (EU) | Banks, insurers | ICT risk mgmt, third-party/software supply-chain resilience |
| **NYDFS 500** | Financial services (NY) | Asset inventory, vuln mgmt, access controls |
| **FFIEC** | US banks | Third-party & software risk management |
| **NIS2** (EU) | Critical sectors incl. finance/retail | Supply-chain security, incident reporting |
| **NIST SP 800-190** | All | Container image/registry/runtime security |

Common thread: **prove what's in your software, prove where it came from, prove
you can find and fix it fast.** That is exactly what this platform produces as a
byproduct — the SBOM store, attestations, VEX, and drift findings *are* the
evidence.

## 2. Governance & operating model (RACI)

| Activity | Platform/Sec Eng | App teams | Security leadership / GRC |
|----------|:----------------:|:---------:|:-------------------------:|
| Run the SBOM platform (DT/GUAC, storage) | **R/A** | I | I |
| SBOM generation in pipelines | C | **R/A** | I |
| Signing/attestation pipeline templates | **R/A** | C | I |
| Policy-as-code (author & operate) | **R/A** | C | A |
| VEX triage (is it exploitable?) | C | **R** (owns the code) | A |
| Vulnerability remediation (rebuild) | C | **R/A** | I |
| Exceptions/waivers approval | R | R (request) | **A** |
| Audit evidence & regulator response | R | C | **A** |

Structural choice: **the platform team owns the inventory and enforcement
machinery; app teams own remediation and VEX judgment for their own code.**

## 3. Exception / waiver discipline

Regulated environments need escape hatches that satisfy an auditor:

- **Scoped** — one CVE, one artifact, one environment. Never a blanket bypass.
- **Owned + justified** — named owner, documented reason.
- **Compensating control** — network isolation, WAF, restricted RBAC.
- **Time-boxed** — expiry date; fails closed automatically after.
- **Approved** — Security/GRC accountable for Critical waivers.
- **Recorded** — version-controlled waiver ledger = audit evidence.

VEX `not_affected` statements are a *disciplined form of exception* — they say
"present but not exploitable, here's why" and are themselves auditable.

## 4. Scale & resilience patterns

- **Fleet scale** — thousands of images, hundreds of clusters. Central platform
  is the source of truth; admission enforcement is distributed per cluster via
  GitOps so no cluster is unprotected.
- **Availability in the deploy path** — hybrid policy (doc 05 §3): verify
  signatures/attestations locally (always up), consult platform for live vuln
  verdicts with cached fallback. Fail closed on trust, degrade on freshness.
- **Air-gapped / regulated zones** (common in banks) — mirror CVE feeds
  (OSV/NVD), run regional platform instances, use offline Sigstore trust bundles
  for verification.
- **Data residency** — SBOM/finding data may be subject to residency rules;
  deploy regional stores accordingly.

## 5. Sector-specific emphasis

### Banking & capital markets
- Strong **DORA / NYDFS / FFIEC** pressure on third-party software risk →
  emphasis on **provenance (SLSA L2+)** and vendor-supplied SBOM ingestion.
- Frequently **air-gapped** production zones and strict change control →
  offline verification, rebuild-not-patch is mandatory.
- **PII + payment data** workloads get the highest policy tier (provenance
  required, zero un-waived Critical/High, internet-exposure-weighted priority).

### Insurance
- Heavy **legacy + acquired estates** → SBOM ingestion for software you *didn't*
  build (vendor SBOMs, third-party services); **license compliance** matters for
  actuarial/data platforms.
- Long data-retention obligations → strong point-in-time SBOM reconstruction.

### Large retail
- **PCI DSS 4.0** on cardholder-data environments → inventory + vuln mgmt +
  segmentation; policy tiers separate CDE workloads.
- **Massive seasonal scale** and many microservices → dedupe and fast
  fleet-wide impact queries are essential; **supplier/vendor SBOMs** for a large
  third-party footprint (payment, loyalty, e-commerce platforms).

## 6. Metrics regulators and leadership care about

- **% of production artifacts with a signed, attested SBOM in the platform** → 100%.
- **% of deploys passing admission with verified provenance** → 100%.
- **Mean time to answer "who is affected?"** for a new critical CVE → minutes.
- **Mean time to remediate (rebuild in prod)** Critical/High.
- **Open / expired waivers**; **VEX triage backlog**.
- **Runtime drift findings** and time-to-resolution.
- **SBOM coverage & quality score** across the estate.

## 7. Rollout sequence (pragmatic)

1. Stand up the platform (Dependency-Track first; add GUAC for graph later).
2. Wire **SBOM generation + attestation** into the golden CI templates.
3. **Ingest** everything (even before enforcing) to build the inventory — you
   get impact-query value on day one.
4. Turn on **policy in audit**, then enforce non-prod, then prod.
5. Add **workload identity** to kill static secrets.
6. Add **runtime drift** detection.
7. Track progress on the [maturity model](maturity-model.md).

---

**See also:** [maturity-model.md](maturity-model.md) ·
[../architecture/reference-architecture.md](../architecture/reference-architecture.md)
