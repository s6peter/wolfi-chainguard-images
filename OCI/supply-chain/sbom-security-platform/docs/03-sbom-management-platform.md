# 03 — SBOM Management Platform (Ingestion, Storage, Query, VEX)

This is the core: the system that turns a stream of SBOMs into a living,
queryable inventory and keeps it correlated with vulnerability intelligence.

---

## 1. Ingestion

The ingestion API accepts SBOMs (CycloneDX/SPDX) and attestations. Requirements:

- **Authenticated writes only** — via workload identity (doc 06). No anonymous
  uploads; every SBOM is attributed to a producer identity.
- **Idempotent, versioned** — keyed by `(project, artifact, digest, build-id)`.
  Re-uploading the same build is a no-op; a new build is a new version.
- **Validated** — schema-valid, quality-gated (doc 02 §5), and — for the
  authoritative copy — **verified against its attestation** (doc 04).
- **Multiple sources** — CI push, registry webhook, or platform-side pull.

Two common ingestion patterns:

```text
Push (CI-driven):   CI ──(OIDC)──▶ ingestion API           # tight, immediate
Pull (registry):    registry event ──▶ platform fetches attestation from OCI
```

Example: [../examples/ingestion/upload-to-dependency-track.sh](../examples/ingestion/upload-to-dependency-track.sh)

## 2. Storage & normalization

- **Normalize** CycloneDX and SPDX into one internal component model keyed on
  **purl + hash**. Downstream logic never branches on format.
- **Dedupe** components across artifacts — `log4j-core@2.14.1` is one component
  referenced by many artifacts. This is what makes fleet-wide impact queries
  fast.
- **Model the graph**: component → artifact (image) → deployment → cluster. The
  ability to walk this graph is the whole point.

```text
component (purl) ──used_by──▶ artifact (digest) ──deployed_as──▶ workload ──runs_in──▶ cluster
```

**Dependency-Track** stores this as projects/components with continuous analysis.
**GUAC** ingests SBOMs + attestations into a graph you can query for blast
radius and provenance ("what depends on X", "what was built by pipeline Y").
Many enterprises run **both**: Dependency-Track for component/VEX management,
GUAC for graph reasoning.

## 3. Continuous vulnerability correlation

The store is joined continuously against vulnerability feeds:

- Feeds: **OSV, NVD, GitHub Advisories**, vendor feeds. Mirror them for
  air-gapped/regulated environments.
- On new CVE: the platform re-evaluates **stored** SBOMs — no rebuild or rescan
  of images needed to know you're affected.
- This is the Log4Shell answer: *"12 artifacts, 3 in prod, here are the
  deployments"* — in seconds, from data you already have.

```text
new CVE arrives ─▶ match component purl/version across ALL stored SBOMs
                 ─▶ apply VEX ─▶ rank by exploitability + exposure ─▶ alert/ticket
```

## 4. VEX — cutting false-positive noise

A raw SBOM×CVE join produces overwhelming noise; most matches aren't actually
exploitable in context. **VEX (Vulnerability Exploitability eXchange)** is how the
platform records and applies that judgment:

| VEX status | Meaning | Effect |
|------------|---------|--------|
| `not_affected` | Vulnerable component present but not exploitable (e.g. code path unused) | Suppress with justification |
| `affected` | Confirmed exploitable | Prioritize remediation |
| `fixed` | Remediated in this version | Close |
| `under_investigation` | Triage in progress | Track |

- VEX statements are **first-class, attributed, and time-stamped** records — not
  ad-hoc suppressions.
- `not_affected` requires a **justification** (e.g. "vulnerable method not
  called", "inline mitigation present").
- VEX is itself audit evidence: it shows a regulator you triaged, not ignored.
- CycloneDX carries VEX natively; the platform (Dependency-Track) manages it.

See [../examples/sbom/vex.cyclonedx.json](../examples/sbom/vex.cyclonedx.json).

## 5. Query & policy API

The platform exposes:

- **Impact queries** — "which artifacts/deployments contain purl X in version
  range Y?" (used in incident response).
- **Policy verdicts** — "is artifact @digest permitted?" combining vuln posture,
  license policy, VEX, and provenance. Consumed by admission control (doc 05).
- **License queries** — "any GPL/AGPL in customer-facing services?" (a real
  concern for banks/retailers shipping software).
- **Exports** — SPDX/CycloneDX for auditors, partners, and regulators.

## 6. Findings lifecycle & routing

Findings don't just sit on a dashboard:

```text
finding ─▶ deduped ─▶ VEX-triaged ─▶ prioritized (exploitability + exposure)
        ─▶ routed: ticket to owning team | SOAR playbook | rebuild pipeline
        ─▶ tracked to closure (remediated by rebuild, not patch-in-place)
```

Prioritization inputs: severity, **is it reachable/exploitable (VEX)**, is it
**deployed** (vs just built), internet exposure, data sensitivity of the
workload. A Critical CVE in an internet-facing payments service outranks the same
CVE in an offline batch job.

## 7. Retention & audit

- Retain SBOMs + findings + VEX for the regulatory window.
- Point-in-time reconstruction: "prove what components service X ran on
  2026-03-01" — answerable from versioned SBOMs + deployment history.
- All ingest/verdict/VEX actions are logged and attributed.

---

**Next:** [04 — Signing, Verification & Provenance](04-signing-verification-provenance.md)
