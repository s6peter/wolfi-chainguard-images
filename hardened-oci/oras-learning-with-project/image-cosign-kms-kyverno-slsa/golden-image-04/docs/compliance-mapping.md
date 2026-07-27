# Compliance Control Mapping

Which pipeline stage satisfies which control, and — equally important — which
controls this programme does **not** satisfy.

Stage numbers refer to [`../scripts/golden-image.sh`](../scripts/golden-image.sh).
Admission rules refer to [`../policy/kyverno-golden-image.yaml`](../policy/kyverno-golden-image.yaml).

---

## PCI-DSS v4.0

| Req | Requirement | Where satisfied | Evidence |
|---|---|---|---|
| 1.3 | No direct inbound/outbound to untrusted networks from CDE | Stage 3 — builds pull from `approved/`, never the internet | `03-ingest.log` |
| 2.2 | Configuration standards for all system components | Stage 7 CIS audit; admission rule 1 | `07-cis-audit.json` |
| 2.2.4 | Only necessary services enabled | Distroless base — no shell, no package manager | `06-sbom.spdx.json` |
| 6.3.1 | Identify and rank vulnerabilities | Stage 5 + Stage 8 thresholds | `05-trivy.json`, `08-decision.json` |
| 6.3.2 | Inventory of bespoke and third-party software | Stage 6 SBOM; `catalog/images.json` | Both SBOM formats |
| 6.3.3 | Critical/high patches within one month | Nightly ingest + weekly consumer batching | Run history |
| 6.5.x | Change control procedures | Standard vs normal change classification (README §4) | Git history of catalogue |
| 8.3.1 | Strong authentication, no shared secrets | Keyless OIDC or KMS; no key on disk in CI | Workflow definition |
| 10.5.1 | Retain audit history ≥12 months | 7-year retention | `manifest.json` |
| 11.3.1 | Internal vulnerability scans quarterly and after change | Every run scans | `05-trivy.json` |
| 12.10 | Incident response | Gate failure pages on-call | `PAGE-*.json`, GitHub issue |

---

## HIPAA Security Rule / HITRUST CSF

| Ref | Safeguard | Where satisfied |
|---|---|---|
| 164.308(a)(1)(ii)(A) | Risk analysis | Stage 5 scan + Stage 8 recorded risk decision |
| 164.308(a)(1)(ii)(B) | Risk management | Threshold enforcement; documented risk acceptance path |
| 164.308(a)(5)(ii)(B) | Protection from malicious software | Stage 2 signature verification; Stage 5 secret + vuln scan |
| 164.312(a)(1) | Access control | Non-root enforcement (Stage 7, CIS 4.1) + admission rule 4 |
| 164.312(b) | Audit controls | Full evidence bundle per run |
| 164.312(c)(1) | Integrity | Stage 4 custody proof; digest-pinned admission |
| 164.312(e)(1) | Transmission security | TLS to registry; digest verification after transfer |
| 164.316(b)(2) | Retain documentation 6 years | 7-year retention exceeds |
| HITRUST 09.j | Controls against malicious code | Stages 2 and 5 |
| HITRUST 10.m | Technical vulnerability management | Stages 5, 8 and the SLA cadence |

**PHI-specific note:** the `data_scope` field in the catalogue tags which images
carry PHI workloads. That tag drives tiering and the stricter thresholds, and it
is what lets you answer "which images are in PHI scope" without a survey.

---

## SOX — IT General Controls

| Control area | Requirement | Where satisfied |
|---|---|---|
| Change management | Authorised, tested, approved changes | Standard/normal classification; catalogue is a reviewed commit |
| Change integrity | Deployed = approved | Stage 4 custody + digest-only admission (rule 2) |
| Segregation of duties | Requester ≠ approver | Catalogue changes require PR review; pipeline is the only writer to `approved/` |
| Access to programs | Restricted, logged | GITHUB_TOKEN is job-scoped and expires; no standing registry credential |
| Audit trail | Complete, retained, tamper-evident | Evidence bundle + Rekor transparency log + 7-year retention |

The two artifacts a SOX walkthrough asks for:

1. **`catalog/images.json` and its git history** — the authorised base image
   register, with who approved each change and when.
2. **`08-decision.json` for any given image** — the control that ran, the
   thresholds in force, and the outcome, signed and bound to a digest.

---

## FedRAMP / NIST SP 800-53 Rev 5

| Control | Name | Where satisfied |
|---|---|---|
| CM-2 | Baseline configuration | Catalogue + digest pinning |
| CM-6 | Configuration settings | Stage 7 CIS audit |
| CM-7 | Least functionality | Distroless bases; admission rule 1 |
| CM-8 | System component inventory | Stage 6 SBOM |
| RA-5 | Vulnerability monitoring | Stage 5, nightly |
| SI-7 | Software/firmware/information integrity | Stages 2, 4; signature verification at admission |
| SR-3 | Supply chain controls and processes | The programme as a whole |
| SR-4 | Provenance | Stage 2 upstream verification + Stage 9 organisation signature |
| SR-11 | Component authenticity | Stage 2 keyless verification against publisher identity |
| AU-11 | Audit record retention | 7 years |
| AC-6 | Least privilege | Non-root, drop ALL, no privilege escalation (admission rule 4) |
| IA-5 | Authenticator management | Keyless OIDC / KMS — no static signing key |
| SC-7 | Boundary protection | Two-namespace model; no build-time internet egress |
| IR-6 | Incident reporting | Page on gate failure |

**ConMon remediation windows:** high 30 days, moderate 90, low 180. The nightly
cadence is what keeps the programme inside the 30-day window with buffer.

---

## NIST SP 800-190 — Application Container Security Guide

| § | Risk | Countermeasure in this programme |
|---|---|---|
| 4.1.1 | Image vulnerabilities | Stage 5 + gate thresholds |
| 4.1.2 | Image configuration defects | Stage 7 CIS audit |
| 4.1.3 | Embedded malware | Stage 2 publisher verification; minimal distroless surface |
| 4.1.4 | Embedded clear-text secrets | Trivy secret scanner, gate `max_secrets: 0` |
| 4.1.5 | Use of untrusted images | Two-namespace model + admission allowlist |
| 4.2.x | Registry risks — insecure connections, stale images | TLS; dated tags; nightly refresh |
| 4.3.x | Orchestrator risks | Kyverno admission control |
| 4.4.x | Container runtime risks | Runtime hardening policy (rule 4) |
| 4.5.1 | App running as root | CIS 4.1 gate + `runAsNonRoot` enforcement |

---

## CIS Docker Benchmark §4 — Container Images

| Control | Description | Status | Where |
|---|---|---|---|
| 4.1 | Create a user for the container | **Enforced** | Stage 7 gate; admission rule 4 |
| 4.2 | Use trusted base images | **Enforced** | Stage 2 signature verification |
| 4.3 | Do not install unnecessary packages | **Enforced** | Distroless bases; SBOM review |
| 4.4 | Scan and rebuild images | **Enforced** | Nightly pipeline |
| 4.5 | Enable content trust | **Enforced** | Cosign + Rekor, both directions |
| 4.6 | Add HEALTHCHECK | **Compensating** | Distroless cannot; Kubernetes probes instead |
| 4.7 | Do not use update instructions alone | N/A | Base images, not built here |
| 4.8 | Remove setuid/setgid | **Inherited** | Chainguard base property |
| 4.9 | Use COPY not ADD | N/A | Applies to application Dockerfiles |
| 4.10 | Do not store secrets | **Enforced** | Trivy secret scanner, threshold 0 |
| 4.11 | Install only verified packages | **Inherited** | Wolfi signed package repositories |

CIS 4.6 is the honest one. A distroless runtime has no shell and no curl, so a
`HEALTHCHECK` cannot execute — and Kubernetes ignores `HEALTHCHECK` regardless,
running only the probes in the pod spec. Stage 7 records the absence as an
informational finding with the compensating control named, rather than silently
passing or failing an image for something the runtime cannot support.

---

## Deliberate gaps

Controls a reader might expect here and will not find.

| Gap | Why | Where it belongs |
|---|---|---|
| Runtime threat detection | Pipeline governs entry, not behaviour | Falco / eBPF runtime security |
| Application image builds | Different lifecycle and owner | `../regulated-dockerfile-practice-03/` |
| Registry authn/authz | Lab registry is unauthenticated | Harbor / Artifactory / ECR configuration |
| Network segmentation | Out of scope | CNI policy, service mesh |
| Air-gap transfer | Separate physical process | Data diode procedure |
| Key ceremony and rotation | Not automatable here | KMS/HSM operational runbook |
| Penetration testing | PCI-DSS 11.4 requires it separately | Annual engagement |

A rejected image is evidence too. Retain failed-run bundles on the same
schedule as successful ones — an assessor sampling a quarter will ask what
happened to the runs that did not promote, and "we deleted them" is the wrong
answer.
