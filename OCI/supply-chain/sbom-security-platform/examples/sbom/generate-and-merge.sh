#!/usr/bin/env bash
# Generate SBOMs (CycloneDX + SPDX) for an image and optionally merge with a
# base-image SBOM. Part of docs/02.
#
# Usage:
#   ./generate-and-merge.sh registry.acme.internal/payments-api@sha256:...
#
# Requires: syft. (Merge step uses cyclonedx-cli if present.)

set -euo pipefail
REF="${1:?usage: generate-and-merge.sh <image-ref-by-digest>}"
OUT="${OUT:-./sbom-out}"
mkdir -p "$OUT"

echo ">> CycloneDX (primary, best for the security platform)"
syft "$REF" -o cyclonedx-json="$OUT/app.cyclonedx.json"

echo ">> SPDX (for compliance / partners)"
syft "$REF" -o spdx-json="$OUT/app.spdx.json"

# Optional: merge app SBOM with a base-image SBOM on purl+hash so nothing from
# the base is lost. Requires cyclonedx-cli (https://github.com/CycloneDX/cyclonedx-cli).
if command -v cyclonedx >/dev/null 2>&1 && [ -f "$OUT/base.cyclonedx.json" ]; then
  echo ">> Merging base + app SBOMs"
  cyclonedx merge \
    --input-files "$OUT/base.cyclonedx.json" "$OUT/app.cyclonedx.json" \
    --output-file "$OUT/merged.cyclonedx.json"
fi

echo ">> Done. Next: attest to the image (../signing/attest-sbom.sh),"
echo "   then ingest (../ingestion/upload-to-dependency-track.sh)."
