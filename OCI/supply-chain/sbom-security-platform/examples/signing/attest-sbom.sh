#!/usr/bin/env bash
# Sign an image and attach SBOM + SLSA provenance as attestations (docs/04).
# Keyless (OIDC) — in CI the token is ambient; locally cosign opens a browser.
#
# Usage:
#   ./attest-sbom.sh registry.acme.internal/payments-api@sha256:... ./sbom-out/app.cyclonedx.json
#
# Requires: cosign v2+.

set -euo pipefail
REF="${1:?usage: attest-sbom.sh <image-ref-by-digest> <sbom.json> [provenance.json]}"
SBOM="${2:?path to CycloneDX SBOM json}"
PROV="${3:-}"

export COSIGN_YES=true

echo ">> Signing image (keyless): $REF"
cosign sign "$REF"

echo ">> Attesting SBOM (CycloneDX predicate)"
cosign attest --predicate "$SBOM" --type cyclonedx "$REF"

if [ -n "$PROV" ]; then
  echo ">> Attesting SLSA provenance"
  cosign attest --predicate "$PROV" --type slsaprovenance "$REF"
fi

echo ">> Done. Verify with ./verify-attestations.sh $REF"
