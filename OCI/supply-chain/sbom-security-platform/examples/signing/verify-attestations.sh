#!/usr/bin/env bash
# Verify an image signature AND its SBOM attestation, pinning the signer identity
# (docs/04 §5). Verifying identity — not just "a signature exists" — is the point.
#
# Usage:
#   ./verify-attestations.sh registry.acme.internal/payments-api@sha256:...
#
# Requires: cosign v2+.

set -euo pipefail
REF="${1:?usage: verify-attestations.sh <image-ref-by-digest>}"

# Pin to YOUR CI identity + issuer. These are examples for GitHub Actions.
IDENTITY_REGEXP="${IDENTITY_REGEXP:-https://github.com/acme/.+/.github/workflows/release.yml@refs/heads/main}"
OIDC_ISSUER="${OIDC_ISSUER:-https://token.actions.githubusercontent.com}"

echo ">> Verifying signature + identity"
cosign verify \
  --certificate-identity-regexp "$IDENTITY_REGEXP" \
  --certificate-oidc-issuer "$OIDC_ISSUER" \
  "$REF"

echo ">> Verifying SBOM attestation is present and from the same identity"
cosign verify-attestation \
  --type cyclonedx \
  --certificate-identity-regexp "$IDENTITY_REGEXP" \
  --certificate-oidc-issuer "$OIDC_ISSUER" \
  "$REF"

echo ">> Verified. This is the same check admission control performs (docs/05)."

# Air-gapped: verify offline with a bundled trust root, e.g.
#   cosign verify --offline --sct ... --certificate-identity-regexp ... "$REF"
