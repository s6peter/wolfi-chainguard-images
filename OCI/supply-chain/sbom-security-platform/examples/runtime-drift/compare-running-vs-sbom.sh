#!/usr/bin/env bash
# Runtime drift detection: compare what a RUNNING container actually contains
# against the attested SBOM for the image it was built from (docs/07 §2A).
#
# Output:
#   - components present at RUNTIME but MISSING from the SBOM  -> integrity alert
#   - components in the SBOM but NOT seen at runtime           -> reachability hint (VEX)
#
# Approach: syft can scan a running container's filesystem via the container
# runtime. We generate a fresh runtime SBOM, fetch the build-time SBOM, and diff
# on purl.
#
# Usage:
#   ./compare-running-vs-sbom.sh <container-id-or-name> <image-ref@sha256:...>
#
# Requires: syft, jq. (cosign to pull the attested SBOM; or pass a local file.)

set -euo pipefail
CONTAINER="${1:?container id/name (docker/containerd)}"
IMAGE_REF="${2:?image ref by digest, e.g. registry.acme.internal/app@sha256:...}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> [1/4] Capturing RUNTIME inventory of container: $CONTAINER"
# Scan the live container filesystem. (Engine prefixes: docker:, containerd:, podman:)
syft "docker:${CONTAINER}" -o cyclonedx-json="$WORK/runtime.cdx.json"

echo ">> [2/4] Fetching BUILD-TIME (attested) SBOM for: $IMAGE_REF"
if [ -n "${SBOM_FILE:-}" ]; then
  cp "$SBOM_FILE" "$WORK/build.cdx.json"
else
  # Pull the SBOM attestation and extract its CycloneDX predicate.
  cosign download attestation --predicate-type=https://cyclonedx.org/bom "$IMAGE_REF" \
    | jq -r '.payload' | base64 -d | jq '.predicate' > "$WORK/build.cdx.json"
fi

echo ">> [3/4] Extracting component purls from each"
jq -r '.components[]?.purl // empty' "$WORK/runtime.cdx.json" | sort -u > "$WORK/runtime.purls"
jq -r '.components[]?.purl // empty' "$WORK/build.cdx.json"   | sort -u > "$WORK/build.purls"

echo ">> [4/4] Computing drift"
echo
echo "=== DRIFT: present at RUNTIME but ABSENT from SBOM (integrity alert) ==="
RUNTIME_ONLY="$(comm -23 "$WORK/runtime.purls" "$WORK/build.purls")"
if [ -n "$RUNTIME_ONLY" ]; then echo "$RUNTIME_ONLY"; else echo "(none)"; fi

echo
echo "=== In SBOM but NOT observed at runtime (reachability hint for VEX) ==="
SBOM_ONLY="$(comm -13 "$WORK/runtime.purls" "$WORK/build.purls")"
if [ -n "$SBOM_ONLY" ]; then echo "$SBOM_ONLY"; else echo "(none)"; fi

# Exit non-zero if integrity drift is found, so this can gate a CronJob / alert.
if [ -n "$RUNTIME_ONLY" ]; then
  echo
  echo ">> INTEGRITY DRIFT DETECTED. Route to platform as a finding (docs/07 §3)."
  echo "   Remediation: correct the BUILD (pin digests, remove runtime installs),"
  echo "   rebuild, re-attest, redeploy. Do NOT patch the running container."
  exit 2
fi
echo
echo ">> No integrity drift. Runtime matches the attested SBOM."
