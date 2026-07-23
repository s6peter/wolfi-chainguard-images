#!/usr/bin/env bash
# Registry-pull ingestion: given only an image reference, discover its SBOM
# referrer, pull it, verify its attestation identity, then hand off to the
# SBOM platform. Covers mastery Step 6 + integration doc §3.
#
# This is the CONSUMER side (pairs with sbom-security-platform ingestion).
#
# Usage:
#   ./pull-and-ingest.sh registry.acme.internal/payments-api@sha256:...
#
# Requires: oras, jq. (cosign optional but recommended for the verify step.)

set -euo pipefail
IMG="${1:?image ref BY DIGEST}"
OUT="${OUT:-./ingest}"
mkdir -p "$OUT"

echo ">> [1/4] Discovering the CycloneDX SBOM referrer for $IMG"
SBOM_REF=$(oras discover "$IMG" \
  --artifact-type application/vnd.cyclonedx+json --format json \
  | jq -r '.manifests[0].reference // empty')

if [ -z "$SBOM_REF" ]; then
  echo "ERROR: no CycloneDX SBOM attached to this image." >&2
  exit 1
fi
echo "   found: $SBOM_REF"

echo ">> [2/4] Pulling the SBOM"
oras pull "$SBOM_REF" -o "$OUT"
ls -l "$OUT"

echo ">> [3/4] Verifying attestation identity BEFORE trusting it (cosign)"
# ORAS moves bytes; trust comes from identity-pinned verification (integration §4).
if command -v cosign >/dev/null 2>&1; then
  cosign verify-attestation --type cyclonedx \
    --certificate-identity-regexp "${IDENTITY_REGEXP:-https://github.com/acme/.+/.github/workflows/.+}" \
    --certificate-oidc-issuer "${OIDC_ISSUER:-https://token.actions.githubusercontent.com}" \
    "$IMG" >/dev/null && echo "   attestation identity verified"
else
  echo "   (cosign not installed — SKIPPING verification; do NOT skip in production)"
fi

echo ">> [4/4] Handing off to the SBOM platform ingestion"
echo "   e.g. ../../sbom-security-platform/examples/ingestion/upload-to-dependency-track.sh"
echo "   (authenticate with workload identity, not a static API key)"
echo ">> Done."
