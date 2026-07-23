# 04 — Signing, Verification & Provenance

An SBOM you can't verify is a rumor. This document covers how the platform binds
SBOMs to artifacts with cryptographic signatures and SLSA provenance, and how
consumers verify that binding.

---

## 1. The trust chain

```text
source commit ──▶ CI build ──▶ image (digest) ──▶ cosign signature (keyless, OIDC identity)
                                    │
                                    ├──▶ SBOM attestation      (in-toto predicate: CycloneDX/SPDX)
                                    └──▶ provenance attestation (in-toto predicate: SLSA)
                                                 │
                          all recorded in Rekor transparency log
                                                 │
              consumer verifies: signature valid + identity expected + attestations present
```

Trust is anchored to **who built what, from where** — a CI OIDC identity — not to
a mutable tag or a copyable key.

## 2. Signing (cosign, keyless preferred)

- **Keyless signing** issues a short-lived certificate from **Fulcio** bound to
  the CI's OIDC identity, and logs the signature in **Rekor**. No long-lived key
  to steal — the top supply-chain win.
- The signing identity is a **CI workflow on a protected branch**, e.g.
  `https://github.com/acme/payments-api/.github/workflows/release.yml@refs/heads/main`.
- Key-based signing (KMS/HSM) is the fallback for air-gapped/regulated
  environments that can't reach public Sigstore — keys live in an HSM, never CI
  variables.

## 3. Attestations — binding SBOM & provenance to the artifact

An **attestation** is a signed statement *about* an artifact, in the **in-toto**
format, carrying a **predicate**:

| Predicate | What it asserts |
|-----------|-----------------|
| SBOM (CycloneDX / SPDX) | The component inventory of this exact digest |
| SLSA provenance | The source repo, commit, build entrypoint, and builder |
| Vulnerability scan (optional) | Scan results at build time |

```bash
# Attest the SBOM to the image (see examples/signing/attest-sbom.sh)
cosign attest --predicate app.cyclonedx.json \
  --type cyclonedx \
  registry.acme.internal/payments-api@sha256:...

# Attest SLSA provenance
cosign attest --predicate provenance.json \
  --type slsaprovenance \
  registry.acme.internal/payments-api@sha256:...
```

The attested SBOM is the **authoritative** one the platform ingests and trusts
(doc 02 §4, doc 03 §1). A loose SBOM file with no attestation is untrusted.

## 4. SLSA provenance & levels

**SLSA** (Supply-chain Levels for Software Artifacts) grades build integrity:

| Level | Roughly means | How this program reaches it |
|-------|---------------|------------------------------|
| L1 | Provenance exists | Emit build provenance |
| L2 | Signed provenance, hosted build | Keyless-signed provenance from CI |
| L3 | Hardened, non-falsifiable builder | Isolated, ephemeral CI builders; scoped OIDC |

Banks and insurers increasingly require **SLSA L2+** for internally-built and
critical vendor software. Provenance answers "did this really come from our
pipeline, or a developer laptop / compromised runner?"

## 5. Verification — the enforcement point

Verification asserts **identity**, not mere existence of a signature. This is the
single most-missed step.

```bash
# Verify signature AND that it was signed by the expected identity
cosign verify \
  --certificate-identity-regexp 'https://github.com/acme/.+/.github/workflows/release.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  registry.acme.internal/payments-api@sha256:...

# Verify the SBOM attestation is present and from the same identity
cosign verify-attestation --type cyclonedx \
  --certificate-identity-regexp 'https://github.com/acme/.+/.github/workflows/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  registry.acme.internal/payments-api@sha256:...
```

Where verification happens:
- **Platform ingest** — only verified SBOMs become authoritative.
- **Admission control** — clusters verify before scheduling (doc 05).
- **Air-gapped** — bundle Rekor/Fulcio roots offline (`cosign` supports offline
  verification with a trust bundle).

Full command reference:
[../examples/signing/attest-sbom.sh](../examples/signing/attest-sbom.sh) and
[../examples/signing/verify-attestations.sh](../examples/signing/verify-attestations.sh).

## 6. Anti-patterns

- Trusting an SBOM because it "came from CI" without verifying its attestation.
- Verifying *a* signature without pinning the **identity** (any Sigstore user
  could sign).
- Signing by tag instead of digest (tags move; sign what you ship).
- Long-lived signing keys in CI environment variables.

---

**Next:** [05 — Policy-as-Code](05-policy-as-code.md)
