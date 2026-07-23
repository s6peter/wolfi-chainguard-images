#!/usr/bin/env bash
# Ingest a CycloneDX SBOM into Dependency-Track (docs/03 §1).
#
# In production the API key is NOT a static secret in an env var — it is obtained
# via workload identity (OIDC exchange). This script shows the API shape; see
# ../workload-identity/ for how to acquire short-lived credentials instead.
#
# Usage:
#   DT_URL=https://dtrack.acme.internal DT_APIKEY=... \
#   ./upload-to-dependency-track.sh payments-api 1.4.2 ./sbom-out/app.cyclonedx.json
#
# Requires: curl, base64.

set -euo pipefail
PROJECT="${1:?project name}"
VERSION="${2:?project version}"
SBOM="${3:?path to CycloneDX json}"

: "${DT_URL:?set DT_URL}"
: "${DT_APIKEY:?in prod, obtain via OIDC/workload identity, not a static key}"

echo ">> Uploading SBOM for ${PROJECT}:${VERSION} to ${DT_URL}"

# Dependency-Track auto-creates the project version if autoCreate=true.
curl -sf -X POST "${DT_URL}/api/v1/bom" \
  -H "X-Api-Key: ${DT_APIKEY}" \
  -H "Content-Type: application/json" \
  -d @- <<JSON
{
  "projectName": "${PROJECT}",
  "projectVersion": "${VERSION}",
  "autoCreate": true,
  "bom": "$(base64 -w0 < "$SBOM")"
}
JSON

echo
echo ">> Uploaded. Dependency-Track now performs continuous CVE correlation."
echo "   Query impact later via: GET ${DT_URL}/api/v1/component?... (see docs/03 §5)"

# GUAC ingestion alternative (graph reasoning):
#   guacone collect files ./sbom-out/app.cyclonedx.json
