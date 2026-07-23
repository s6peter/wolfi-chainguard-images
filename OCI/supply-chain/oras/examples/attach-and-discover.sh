#!/usr/bin/env bash
# Attach an SBOM to an image via the Referrers API, then discover it.
# Covers mastery Steps 4-5 — the core supply-chain move.
#
# This is the PRODUCER side (pairs with hardened-oci output).
#
# Usage:
#   ./attach-and-discover.sh registry.acme.internal/payments-api@sha256:... ./app.cyclonedx.json
#
# Requires: oras. (SBOM can be produced by syft/apko; a sample lives at
# ../../sbom-security-platform/examples/sbom/app.cyclonedx.json)

set -euo pipefail
IMG="${1:?image ref BY DIGEST, e.g. registry/app@sha256:...}"
SBOM="${2:?path to CycloneDX SBOM json}"

case "$IMG" in
  *@sha256:*) : ;;
  *) echo "ERROR: attach by DIGEST, not a tag (see docs/02 §5)." >&2; exit 1 ;;
esac

echo ">> Attaching CycloneDX SBOM to $IMG"
oras attach --artifact-type application/vnd.cyclonedx+json \
  "$IMG" "$SBOM:application/json"

# Optionally attach SLSA provenance too:
# oras attach --artifact-type application/vnd.in-toto+json "$IMG" provenance.json:application/json

echo ">> Discovering referrers (evidence attached to the image):"
oras discover "$IMG" --format tree

echo
echo ">> The SBOM is now stored next to the image, discoverable by digest."
echo "   The platform can pull it via ./pull-and-ingest.sh"
