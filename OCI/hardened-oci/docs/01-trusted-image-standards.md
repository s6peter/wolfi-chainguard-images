# 01 — Trusted Image Standards

"Trusted" is not a feeling. It is a set of properties an image must provably have
before it is allowed to run. This document defines those properties and the
standards that produce them.

## 1. What makes an image trusted

An image is trusted in this program when **all** of the following hold:

| Property | Requirement |
|----------|-------------|
| **Approved base** | Built `FROM` a golden base in the catalog (Wolfi/Chainguard/distroless), pinned by digest. |
| **Minimal surface** | No shell, package manager, or compilers in the final layer unless explicitly justified. |
| **Non-root** | Runs as a numeric non-root UID; no `USER root` at runtime. |
| **Provenance** | Carries SLSA build provenance identifying the source commit and builder. |
| **SBOM** | Ships a complete SBOM (SPDX or CycloneDX) as an attached attestation. |
| **Signed** | Signed with `cosign` via keyless (OIDC) or a KMS key; signature verifiable. |
| **Scanned clean** | Passes the vulnerability gate (no un-waived Critical/High) at release. |
| **Immutable reference** | Deployed by digest (`@sha256:…`), never by mutable tag alone. |

If any property is missing, the image is untrusted and must not pass admission.

## 2. Base image policy (the foundation)

The single highest-leverage decision is the base image. See the enforceable
version in [../standards/base-image-policy.md](../standards/base-image-policy.md).

**Allowed bases (in preference order):**

1. **`scratch`** — for static binaries (Go, Rust). Zero OS surface.
2. **Chainguard / Wolfi distroless** — for apps needing a minimal runtime
   (glibc, certs, timezone data) but no shell.
3. **Chainguard `-dev` variants** — build stages only, never the final stage.
4. **Approved internal golden images** — derived from the above, pre-hardened.

**Disallowed as a runtime base** (without a documented, time-boxed exception):

- `latest` tags of anything.
- Full distributions (`ubuntu`, `debian`, `centos`) in the final stage.
- Community images from unverified publishers.
- Any base not pinned to a digest.

### Why Wolfi / Chainguard / distroless

- **Near-zero known CVEs** in the runtime layer — most CVEs live in packages that
  distroless images simply do not contain.
- **No shell = no `kubectl exec` foothold, no reverse shell** if the app is
  compromised.
- **Rolling, fast-patched packages** (Wolfi) with SBOMs and signatures produced
  at the source.
- **Smaller = faster pulls, less to scan, less to patch.**

```text
node:20            ~1.1 GB   shell + apt + hundreds of packages
node:20-slim       ~250 MB   shell + apt + fewer packages
cgr.dev/.../node   ~150 MB   no shell, no apt, minimal packages, signed + SBOM
```

## 3. Golden images

Golden images are the organization's blessed, pre-hardened bases that application
teams build on. They are:

- **Owned** by a platform/security team, not individual app teams.
- **Rebuilt on a schedule** (at minimum weekly) and on any upstream CVE fix.
- **Versioned and cataloged** — see [../standards/golden-image-catalog.md](../standards/golden-image-catalog.md).
- **Published with SBOM + signature + provenance**, exactly like app images.

App teams consume golden images by digest and inherit their hardening for free.
This centralizes patching: fix the base once, and every downstream image is
remediated on its next rebuild.

```text
                 ┌────────────────────┐
 upstream Wolfi  │  golden-base:jdk21  │  ← platform team owns, signs, rebuilds
 + hardening  →  │  (pinned, signed)   │
                 └─────────┬──────────┘
                           │ FROM @sha256:…
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
   payments-api       orders-api        ledger-worker   ← app teams inherit hardening
```

## 4. Provenance and identity

Trust is anchored to **who built what from where**:

- **Signing identity** — keyless signing binds the signature to an OIDC identity
  (a specific CI workflow, e.g. a GitHub Actions job on a protected branch), not
  to a shared key a human can copy.
- **Build provenance (SLSA)** — a signed attestation stating the source repo,
  commit, build parameters, and builder. Consumers verify the image came from the
  expected pipeline, not a laptop.
- **SBOM** — the ingredient list, used for scanning, license checks, and rapid
  "am I affected?" answers when a new CVE lands (e.g. the next Log4Shell).

These are covered operationally in
[03-container-security-controls.md](03-container-security-controls.md).

## 5. Naming, tagging, and reference standards

- **Registry:** all production images live in the org's private registry (or a
  verified upstream like `cgr.dev`). No public Docker Hub pulls in prod.
- **Tags are metadata, not identity.** Use immutable, informative tags
  (`1.4.2`, `1.4.2-20260722`, git SHA). Never deploy by `latest`.
- **Deploy by digest.** Kubernetes manifests reference `image@sha256:…`. Tags may
  appear as annotations for humans, but the digest is the contract.
- **No `:latest`, ever, in a committed manifest.** Enforced at admission.

## 6. Exceptions

Real migrations need escape hatches. Exceptions are:

- **Explicit** — a recorded waiver, not silence.
- **Time-boxed** — an expiry date, after which the gate fails closed again.
- **Attributed** — an owner and a justification.
- **Scoped** — narrowest possible (one CVE, one image), never a blanket bypass.

Exception handling is defined in
[05-governance-and-compliance.md](05-governance-and-compliance.md).

---

**Next:** [02 — Secure Image Lifecycle](02-secure-image-lifecycle.md)
