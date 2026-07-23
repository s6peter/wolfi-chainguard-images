#!/usr/bin/env bash
# Generate an SBOM for an image and (optionally) scan it against the SBOM.
#
# Part of the secure image lifecycle (docs/02, Stages 3–4). Run in CI after
# build, before signing. The SBOM should then be attached as an attestation with
# cosign (see ../signing/cosign-workflow.md).
#
# Usage:
#   ./generate-sbom.sh registry.acme.internal/payments-api@sha256:...
#
# Requires: syft, grype (https://github.com/anchore).

set -euo pipefail

REF="${1:?usage: generate-sbom.sh <image-ref-by-digest>}"
OUT_DIR="${OUT_DIR:-./sbom-out}"
FAIL_ON="${FAIL_ON:-high}"   # severity threshold that fails the scan

mkdir -p "$OUT_DIR"

echo ">> Generating SBOM (SPDX + CycloneDX) for: $REF"
syft "$REF" -o spdx-json="$OUT_DIR/sbom.spdx.json"
syft "$REF" -o cyclonedx-json="$OUT_DIR/sbom.cyclonedx.json"
echo ">> SBOM written to $OUT_DIR/"

echo ">> Scanning against the generated SBOM (fail on: $FAIL_ON)"
# Scanning the SBOM is fast and deterministic vs. re-reading the image.
grype "sbom:$OUT_DIR/sbom.spdx.json" --fail-on "$FAIL_ON" -o table

echo ">> Done. Next: attach the SBOM as an attestation:"
echo "   cosign attest --predicate $OUT_DIR/sbom.spdx.json --type spdxjson $REF"
