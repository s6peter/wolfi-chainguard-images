# 03 — Modern Container Security Controls

The standards (doc 01) and the lifecycle (doc 02) are enforced by a set of
composable controls. This document describes each control, the tool that
implements it, and how they layer into defense in depth.

```text
        ┌─────────────────────────────────────────────┐
        │ 6. Runtime detection      (Falco / eBPF)     │
        ├─────────────────────────────────────────────┤
        │ 5. Admission enforcement  (Kyverno / OPA)    │
        ├─────────────────────────────────────────────┤
        │ 4. Signing + provenance   (cosign / SLSA)    │
        ├─────────────────────────────────────────────┤
        │ 3. Vulnerability scanning (grype / trivy)    │
        ├─────────────────────────────────────────────┤
        │ 2. SBOM                   (syft / apko)      │
        ├─────────────────────────────────────────────┤
        │ 1. Minimal hardened image (Wolfi/distroless) │
        └─────────────────────────────────────────────┘
   Each layer is independent; an attacker must defeat all of them.
```

---

## Control 1 — Minimal hardened images

**What:** the runtime image contains only the app and its direct dependencies —
no shell, package manager, compilers, or unused libraries.

**Why:** removes the tools an attacker needs after initial access (no `sh`, no
`curl`, no `apt`), and removes the packages that generate most CVEs.

**How:** build on Wolfi/Chainguard/distroless or `scratch`; multi-stage builds;
declarative apko builds. Set non-root numeric user in the image itself.

**Verifies:** `docker history`, image scan showing near-zero packages, absence of
`/bin/sh`.

## Control 2 — SBOM (Software Bill of Materials)

**What:** a machine-readable inventory of every component and version in the
image, in SPDX or CycloneDX format.

**Why:** enables instant impact analysis on new CVEs, license compliance, and is
a hard requirement of frameworks like NIST SSDF and US EO 14028.

**How:** generate with `syft` (or apko natively) at build time; attach as a
signed attestation with `cosign attest`, not just a loose file.

**Verifies:** `cosign verify-attestation --type spdxjson …` returns the SBOM.

## Control 3 — Vulnerability scanning

**What:** match the SBOM/image contents against vulnerability databases.

**Why:** catch known-vulnerable components before release and continuously after.

**How:** `grype` and/or `trivy` in CI as a **release gate** (fail on un-waived
Critical/High), plus scheduled re-scans of registry images against fresh data.

**Verifies:** CI scan report; scheduled scan dashboard; waiver ledger.

**Key nuance:** scanning is necessary but *not sufficient* — it only finds
*known* issues. Minimal images (Control 1) reduce what can be vulnerable in the
first place; scanning tells you when even that shrinks further.

## Control 4 — Signing and provenance

**What:** cryptographic proof of *who built the image, from what source, in what
pipeline*.

**Why:** prevents deployment of tampered or unknown images; anchors trust to an
identity rather than a mutable tag or a copyable key.

**How:**
- **`cosign` keyless signing** — signature bound to a short-lived cert issued
  against the CI's OIDC identity (Fulcio), logged in a transparency log
  (Rekor). No private key to leak.
- **SLSA provenance attestation** — signed statement of source repo, commit,
  build entrypoint, and builder, describing how the artifact was produced.

**Verifies:**
```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/acme/.+/.github/workflows/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  registry.acme.internal/payments-api@sha256:…
```
See [../examples/signing/cosign-workflow.md](../examples/signing/cosign-workflow.md).

## Control 5 — Admission enforcement

**What:** a Kubernetes admission controller that **verifies policy at deploy
time** and rejects non-compliant Pods before they schedule.

**Why:** turns the standards into enforced rules. Without it, everything above is
advisory.

**How:** **Kyverno** or **OPA Gatekeeper** policies that require:
- Valid signature from the expected identity (image verification).
- Present SBOM + provenance attestations.
- Allowed registry + digest reference (no `:latest`).
- Non-root, read-only fs, dropped capabilities, seccomp.

**Verifies:** deploy an unsigned image → request denied. See
[../examples/kubernetes/kyverno-verify-images.yaml](../examples/kubernetes/kyverno-verify-images.yaml)
and [../examples/kubernetes/opa-gatekeeper-constraint.yaml](../examples/kubernetes/opa-gatekeeper-constraint.yaml).

## Control 6 — Runtime security

**What:** detection and response for what an image does *after* it starts.

**Why:** admission is a point-in-time check; runtime catches exploitation,
drift, and zero-days that scanning could not know about.

**How:**
- **Pod Security Standards (restricted)** enforced per namespace — the platform
  baseline. See [../examples/kubernetes/pod-security-standards.yaml](../examples/kubernetes/pod-security-standards.yaml).
- **Falco / eBPF** runtime detection for anomalous syscalls, shell spawns in a
  shell-less container, unexpected outbound connections, and filesystem drift.
- **Network policies** for least-privilege east-west traffic (default deny).

**Verifies:** trigger a test detection (e.g. exec into a container) → alert
fires; PSA blocks a privileged Pod.

---

## How the controls reinforce each other

No single control is trusted alone:

- A **minimal image** (1) reduces what scanning (3) and runtime (6) must worry
  about.
- **SBOM** (2) makes scanning (3) precise and fast, and feeds impact analysis.
- **Signing** (4) makes admission (5) able to trust the image's identity.
- **Admission** (5) guarantees only images that passed 1–4 ever run.
- **Runtime** (6) is the backstop for everything the earlier layers could not
  have known at build time.

An attacker must defeat the base minimization, forge a valid signature from a
trusted CI identity, satisfy admission policy, **and** evade runtime detection —
a dramatically higher bar than pulling and running an arbitrary image.

## Control-to-tool quick reference

| Control | Primary tools | Gate location |
|---------|---------------|---------------|
| Minimal image | Wolfi, Chainguard, apko, distroless, `scratch` | Build |
| SBOM | syft, apko | Build |
| Scanning | grype, trivy | CI gate + scheduled |
| Signing / provenance | cosign, Fulcio, Rekor, SLSA | CI (post-build) |
| Admission | Kyverno, OPA Gatekeeper | Cluster (deploy) |
| Runtime | Pod Security Standards, Falco, NetworkPolicy | Cluster (runtime) |

---

**Next:** [04 — Kubernetes Admission & Runtime](04-kubernetes-admission-and-runtime.md)
