# 05 — Governance & Compliance

Controls only hold if someone owns them, exceptions are disciplined, and evidence
is retained. This document defines the operating model around the technical
program.

---

## 1. Roles and ownership (RACI)

| Activity | Platform/Security | App teams | Security leadership |
|----------|:-----------------:|:---------:|:-------------------:|
| Golden base images (build, sign, patch) | **R/A** | I | I |
| Base image policy & catalog | **R/A** | C | A |
| App image builds (from golden base) | C | **R/A** | I |
| CI signing/scanning pipeline templates | **R/A** | C | I |
| Admission policies (author & operate) | **R/A** | C | A |
| Exceptions/waivers approval | **R** | R (request) | **A** |
| Runtime detection & response | **R/A** | C | I |
| Audit evidence & framework mapping | R | C | **A** |

R = Responsible, A = Accountable, C = Consulted, I = Informed.

The key structural choice: **the platform team owns the hardened bases and the
enforcement machinery; app teams consume them.** This centralizes patching and
keeps enforcement consistent across clusters.

## 2. Exception / waiver process

Migrations and third-party images need escape hatches — but disciplined ones.

A valid waiver has:

- **Scope** — the narrowest unit (a single CVE ID, a single image, one
  namespace). Never a blanket "disable policy X."
- **Owner** — a named accountable person/team.
- **Justification** — why the control can't be met yet.
- **Compensating control** — what mitigates the risk meanwhile (e.g. network
  isolation, WAF, restricted RBAC).
- **Expiry** — a date. On expiry the gate fails closed again automatically.
- **Approval** — Security leadership is Accountable for Critical waivers.

Waivers are recorded in a ledger (see the machine-readable examples in
[../policies/image-provenance-policy.md](../policies/image-provenance-policy.md)
and the scan-waiver convention in the CI examples). The ledger is itself audit
evidence.

**Anti-patterns:** permanent waivers, undated waivers, org-wide bypass
annotations, "temporary" exceptions that never expire.

## 3. Evidence and auditability

Every stage of the lifecycle emits durable evidence:

| Evidence | Produced at | Used for |
|----------|-------------|----------|
| SBOM attestation | Build | Impact analysis, license, SSDF |
| Scan report | CI gate + scheduled | Vuln management, waiver justification |
| Signature (Rekor entry) | Sign | Tamper-evidence, non-repudiation |
| SLSA provenance | Build | Supply-chain integrity, SLSA level |
| Admission decision logs | Deploy | Proof enforcement is live |
| Runtime alerts | Runtime | Incident response, detection coverage |
| Waiver ledger | Exception | Risk acceptance record |

Retain for the applicable audit window. Because signatures and attestations live
in the registry and the transparency log, evidence is reconstructable after the
fact, not dependent on CI logs alone.

## 4. Compliance framework mapping

The program's controls map cleanly onto major frameworks:

| Framework | Requirement | Program control(s) |
|-----------|-------------|--------------------|
| **NIST SSDF (SP 800-218)** | Provenance, SBOM, secure build | SBOM (C2), signing/provenance (C4), protected build (Stage 1–2) |
| **US EO 14028** | SBOM, supply-chain integrity | SBOM attestation, SLSA provenance |
| **SLSA** | Build integrity levels | Keyless signing + provenance → SLSA L2/L3 |
| **NIST SP 800-190** (container security) | Image, registry, runtime hardening | All six controls in doc 03 |
| **CIS Kubernetes Benchmark** | Pod/cluster hardening | PSS restricted, admission policies, network policy |
| **PCI DSS** | Vuln mgmt, least privilege, change control | Scan gate, non-root/RO-fs, rebuild-not-patch |
| **FedRAMP** | Continuous monitoring, hardening | Scheduled scans, runtime detection, evidence retention |

Map each control once; reuse the evidence across audits rather than re-collecting
per framework.

## 5. Metrics (is the program working?)

Track and report:

- **% of running images signed & verified at admission** → target 100%.
- **% built on approved golden bases** → target 100% for owned services.
- **Median CVE remediation time** (disclosure → rebuilt image in prod).
- **Golden base freshness** (age since last rebuild) → within SLA (e.g. ≤7 days).
- **Open waivers** and **expired-but-still-present** waivers → drive to zero.
- **Admission denials over time** → should fall as teams comply.
- **Runtime alerts triaged / mean time to respond.**

## 6. Continuous improvement

- Review the base-image policy and golden-image catalog on a fixed cadence.
- Feed runtime alerts and scan trends into the rebuild prioritization.
- Advance clusters and teams up the [maturity model](maturity-model.md); track
  each team's current level.

---

**See also:** [maturity-model.md](maturity-model.md) ·
[../standards/base-image-policy.md](../standards/base-image-policy.md) ·
[../policies/image-provenance-policy.md](../policies/image-provenance-policy.md)
