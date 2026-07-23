# Signing, Attesting, and Verifying with cosign

The hands-on reference for the provenance controls (docs/03 §4, policies/). All
commands operate on an image **by digest**.

Prerequisites: `cosign` v2+, push access to the registry, and (for keyless) an
OIDC identity — a CI workflow token, or `cosign` will open a browser for
interactive OIDC.

```bash
REF=registry.acme.internal/payments-api@sha256:REPLACE_ME
```

---

## 1. Keyless signing (preferred)

No key to manage or leak. The signature is bound to a short-lived certificate
issued by Fulcio against your OIDC identity and logged in the Rekor
transparency log.

```bash
# In CI, the OIDC token is ambient (id-token: write). Locally it opens a browser.
COSIGN_YES=true cosign sign "$REF"
```

## 2. Generate and attest an SBOM

```bash
# Produce an SBOM from the image.
syft "$REF" -o spdx-json > sbom.spdx.json

# Attach it to the image as a signed attestation (not just a loose file).
COSIGN_YES=true cosign attest \
  --predicate sbom.spdx.json \
  --type spdxjson \
  "$REF"
```

## 3. Attest SLSA build provenance

Most CI systems can emit provenance automatically (e.g. the GitHub
`build-push-action` with `provenance: true`, or `slsa-github-generator`). To
attest a provenance predicate manually:

```bash
COSIGN_YES=true cosign attest \
  --predicate provenance.json \
  --type slsaprovenance \
  "$REF"
```

## 4. Verify a signature — pin the identity

Verification MUST assert *who* signed, not just that a signature exists. This is
the trust anchor (policies/image-provenance-policy.md §3).

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/acme/.+/.github/workflows/release.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$REF"
```

Verify the SBOM attestation is present and from the same identity:

```bash
cosign verify-attestation \
  --type spdxjson \
  --certificate-identity-regexp 'https://github.com/acme/.+/.github/workflows/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$REF"
```

The cluster performs the equivalent of §4 automatically at admission — see
[../kubernetes/kyverno-verify-images.yaml](../kubernetes/kyverno-verify-images.yaml).

---

## Key-based signing (air-gapped / no OIDC)

Only when keyless is not possible. The key MUST live in a KMS/HSM.

```bash
# Reference a cloud KMS key rather than a file on disk.
COSIGN_YES=true cosign sign --key awskms:///alias/cosign-signing "$REF"

cosign verify --key awskms:///alias/cosign-signing "$REF"
```

Never store a raw `cosign.key` in the repo or CI variables. Rotate on a schedule
and audit key usage.

---

## Common failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `no matching signatures` | Wrong identity/issuer regex | Match the actual signer identity in Rekor |
| Verify fails on tag but works on digest | Tag moved after signing | Always sign & verify by digest |
| CI keyless sign fails | Missing `id-token: write` | Grant the OIDC permission to the job |
| Admission rejects a signed image | Cluster policy identity ≠ signer | Align the policy's identity/issuer with CI |
