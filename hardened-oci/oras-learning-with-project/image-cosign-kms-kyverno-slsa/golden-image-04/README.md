# Golden Image Process

Ingest, verification, scanning, gating, and promotion of upstream base images
for a regulated estate — banking, healthcare, government, insurance.

**The rule the whole design serves:** an application team can only build on a
base image that a machine has verified, scanned, gated, signed, and recorded.
No human can put an image into production by hand, and no image reaches the
approved namespace without a decision record attached to it.

---

## 1. Why this exists

Pulling `cgr.dev/chainguard/python:latest` at build time fails four separate
control families at once:

| What happens | What it breaks |
|---|---|
| The tag moves between build and deploy | SOX change integrity — what was tested is not what shipped |
| Build agents reach the public internet | PCI-DSS 1.3, FedRAMP SC-7 boundary protection |
| Nobody checks the publisher signature | NIST SI-7, SR-4 — no proof of origin |
| No scan record, no SBOM | PCI-DSS 6.3.1, EO 14028, FedRAMP RA-5 |

The golden image programme converts an uncontrolled internet dependency into a
reviewed, evidenced internal artifact.

---

## 2. The two-namespace model

One registry, two namespaces, one direction of travel.

```
        INTERNET                    │  ORGANISATION REGISTRY
                                    │
  cgr.dev/chainguard/python:latest  │   mirror/python      approved/python
              │                     │   (quarantine)       (production)
              │                     │        │                   │
              └──── ingest ─────────┼───────►│                   │
                                    │        │                   │
                                    │        └─── promote ──────►│
                                    │         (only if gated)    │
                                    │                            │
                                    │   admission control accepts
                                    │   approved/ only, by digest,
                                    │   signed, with attestations
```

- **`mirror/`** is quarantine. Anything can land here. Nothing here can run.
- **`approved/`** is production. It can only be reached by promotion from
  `mirror/`, and only when every gate passed. Nothing is ever pushed directly.

The Kyverno policies in [`policy/kyverno-golden-image.yaml`](policy/kyverno-golden-image.yaml)
are what make the arrow one-directional in practice. Without admission control
this document is a description of good intentions.

---

## 3. The pipeline

[`scripts/golden-image.sh`](scripts/golden-image.sh) — ten stages, fail-closed.

| # | Stage | What it proves | Primary controls |
|---|---|---|---|
| 0 | preflight | The pipeline's own toolchain is intact | NIST CM-6 |
| 1 | resolve | Tag → immutable digest, pinned for the whole run | PCI 6.3.2, CM-2 |
| 2 | verify-upstream | These bytes came from Chainguard's release workflow | SI-7, SR-4 |
| 3 | ingest | Copy into quarantine, no direct internet pull downstream | SC-7, 800-190 4.1.2 |
| 4 | custody | The digest survived the copy — content was not altered | SI-7, SOX |
| 5 | scan | Vulnerabilities and embedded secrets | PCI 6.3.1, RA-5, CIS 4.10 |
| 6 | sbom | Full component inventory, SPDX + CycloneDX | EO 14028, NTIA |
| 7 | config-audit | CIS Docker Benchmark §4 on the image config | CIS 4.1/4.6, 800-190 4.5 |
| 8 | gate | One deterministic decision, no override | CA-7, PCI 6.3.1, SOX |
| 9 | promote | Copy to `approved/`, sign, attest | SR-4, SLSA L3 |
| 10 | evidence | Bundle, hash, attach as an ORAS referrer | SOX, AU-11, HIPAA 164.316 |

Three details that carry most of the weight:

**Stage 1 pins the digest for the entire run.** Every later stage operates on
`repo@sha256:…`, never on the tag. Otherwise you can scan one image and promote
a different one if upstream rebuilds mid-run.

**Stage 4 is the chain-of-custody proof.** A digest is a hash of content, not of
location — so a faithful copy resolves to an identical digest in the new
registry. If it does not, the bytes changed and everything downstream is void.

**Stage 9 signs with the organisation's own key.** Chainguard's signature proves
*origin*. Yours proves *"this passed our gate, on this date, against these
thresholds."* Admission control trusts the second one. An image signed by
Chainguard but never gated by you is rejected.

---

## 4. Change control classification

This is what makes weekly patching survivable. Two categories, and knowing which
is which is the difference between a functioning programme and a change board
that meets every morning.

| Action | Class | Approval |
|---|---|---|
| Digest bump of an existing catalogue entry | **Standard change** | Pre-approved. Rides the process approval. |
| Adding or removing a catalogue entry | **Normal change** | CAB |
| Re-tiering an image, changing gate thresholds | **Normal change** | CAB + risk acceptance |
| Emergency patch for an actively exploited CVE | **Emergency change** | Post-implementation review |

The board approves the *process* once. Each nightly run then rides that
approval, provided it stays inside the envelope: digest-only bump, no major
version jump, all gates green. Step outside the envelope and it becomes a normal
change automatically — which is why the thresholds live in
[`catalog/images.json`](catalog/images.json), a reviewed file, and not in a
runtime flag.

> `catalog/images.json` plus its git history **is** the authorised base image
> register. That is the artifact a SOX walkthrough asks to see.

---

## 5. Cadence and SLAs

```
nightly 02:00 UTC   pipeline ingests, gates, promotes        (this repo)
weekly  Monday      Renovate batches bump PRs to app repos
per PR              app CI builds once, tests, scans, signs
then                dev → test → staging → pre-prod → prod
```

**Build once, deploy many.** The application image is built one time and the
same digest is promoted through every environment. Rebuilding per environment
produces four different digests and destroys the chain of custody.

Regulatory clocks the cadence has to beat:

| Framework | Requirement |
|---|---|
| PCI-DSS 6.3.3 | Critical/high patches within one month of release |
| FedRAMP ConMon | High 30 days · Moderate 90 · Low 180 |
| HIPAA 164.308(a)(1)(ii)(B) | Reasonable and appropriate risk reduction (no fixed clock) |

Nightly ingest plus weekly consumer batching leaves roughly three weeks of
buffer against the 30-day clock. Critical CVEs use the emergency path and
compress the whole chain to 24–72 hours — the same gates, expedited.

---

## 6. When the gate fails

There is no override flag. This is deliberate.

1. Nothing is promoted. `approved/` still holds the last good digest, so no
   running workload is affected and no deploy is blocked.
2. The image stays quarantined in `mirror/`.
3. A page is raised — webhook plus a GitHub issue that is the durable record.
4. Evidence is retained for the failed run exactly as for a successful one. A
   rejection is as auditable as an approval.

Three ways out, in order of preference:

- **Wait.** Chainguard usually rebuilds within hours; most findings clear
  themselves. This resolves the large majority of failures.
- **Risk-accept.** Amend the threshold in `catalog/images.json` with a
  documented justification. That is a reviewed commit and a *normal change*.
- **Replace.** Move the catalogue entry to a different upstream.

What is not available: promoting anyway.

---

## 7. Evidence and retention

Every run writes `evidence/<key>/<date>-<run-id>/`:

```
01-resolved-ref.txt              tag → digest resolution
02-upstream-verification.json    publisher signature verification
03-ingest.log                    skopeo copy transcript
04-custody.json                  digest preservation proof
05-trivy.json                    vulnerability + secret scan
06-sbom.spdx.json                SPDX SBOM
06-sbom.cyclonedx.json           CycloneDX SBOM
07-cis-audit.json                CIS Docker Benchmark §4 audit
08-decision.json                 the gate decision, signed as an attestation
manifest.json                    bundle index
SHA256SUMS                       integrity manifest
```

The bundle is attached to the promoted image as an **ORAS referrer**, so the
evidence travels with the artifact rather than living in a separate system that
has to be kept in sync. An auditor pulls the image and pulls its evidence:

```bash
oras discover ghcr.io/perscoba/approved/python@sha256:… -o json
```

Retention is set to the longest applicable requirement — **7 years** (SOX).
HIPAA is 6, FedRAMP AU-11 is 3, PCI-DSS 10.5.1 is 12 months.

> Retention must be enforced by object-lock storage, not by policy. An operator
> who can delete evidence breaks the control regardless of the runbook.

---

## 8. Running it

### Locally, against a throwaway registry

```bash
cd golden-image-04
./scripts/golden-image.sh lab-up          # registry:2 on localhost:5000
./scripts/golden-image.sh list
./scripts/golden-image.sh run static      # smallest image, fastest loop
./scripts/golden-image.sh verify-approved static
./scripts/golden-image.sh lab-down
```

Requires `skopeo cosign trivy syft jq oras curl`. Copy
`config/policy.env` to `config/policy.local.env` before changing anything.

The lab default is `COSIGN_SIGN_MODE=keyfile`, which the script warns about on
every run. A private key on disk is a finding in any real audit — production is
`kms` (HSM-backed, key never leaves the boundary) or `keyless` (OIDC, no key
exists at all).

### In CI

[`.github/workflows/golden-image.yml`](../../../../../.github/workflows/golden-image.yml)
at the repository root — GitHub only reads workflows from there, which is why
that one file lives outside this directory.

- Nightly `schedule`, plus `workflow_dispatch` with a `dry_run` input.
- `pull_request` runs the gates but redirects promotion to a throwaway
  namespace, so a PR can never write to `approved/`.
- Signs keyless via OIDC: the identity is the workflow itself, so there is no
  private key to steal and the certificate records which workflow at which
  commit produced the signature. Swap to KMS by setting two env vars.
- Toolchain versions are pinned and cosign's download is checksum-verified —
  the pipeline's own tools are part of the trusted computing base.

> **Before this runs in a regulated environment:** pin the third-party actions
> to commit SHAs. They are referenced by tag here for readability, and the
> workflow header carries the `gh api` command to resolve each one.

### cosign v2 vs v3

The script detects the cosign major version and adapts, because v3 changed the
signing surface: it resolves a Sigstore *signing config* by default, and
`--tlog-upload=false` is rejected unless `--use-signing-config=false` is passed
alongside it. v2 has no such flag. Only lab mode is affected — a production run
uploads to the transparency log and never takes that path.

The CI workflow pins **cosign v2.4.1** deliberately. Kyverno 1.18 verifies
signatures using cosign v2 libraries, and v3 changed the signature bundle
format. Before bumping the CI pin to v3, sign one image and confirm the Kyverno
policies in [`policy/`](policy/) still verify it — do that in a test cluster,
because the failure mode is every pod being denied at admission.

---

## 9. Files

| Path | Purpose |
|---|---|
| [`catalog/images.json`](catalog/images.json) | Authorised base image register — the SOX artifact |
| [`config/policy.env`](config/policy.env) | Registry, signing mode, thresholds, retention |
| [`scripts/golden-image.sh`](scripts/golden-image.sh) | The ten-stage pipeline |
| [`policy/kyverno-golden-image.yaml`](policy/kyverno-golden-image.yaml) | Admission enforcement |
| [`docs/compliance-mapping.md`](docs/compliance-mapping.md) | Control-by-control matrix |
| `.github/workflows/golden-image.yml` | CI (repo root — required location) |

---

## 10. What this does not cover

Stated plainly, because a control document that overclaims is worse than none.

- **Runtime security.** The pipeline governs what enters the cluster. Detecting
  a compromised *running* container needs Falco or an equivalent.
- **Application images.** This programme governs base images only. Application
  builds consume `approved/` and run their own pipeline — see
  [`../regulated-dockerfile-practice-03/`](../regulated-dockerfile-practice-03/).
- **Registry hardening.** The lab registry has no authentication. Production
  needs authn, RBAC, immutable tags on `approved/`, and its own audit log.
- **Air-gap transfer.** Physically moving artifacts across a diode is a
  separate process; the digest is what makes it verifiable on the far side.
