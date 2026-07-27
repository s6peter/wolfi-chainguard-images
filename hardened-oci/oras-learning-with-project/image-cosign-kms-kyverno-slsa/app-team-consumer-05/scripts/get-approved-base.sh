#!/usr/bin/env bash
# =============================================================================
# get-approved-base.sh - what an app team runs to pick a base image
#
# Answers the question "which digest am I allowed to build on?" and, more
# importantly, proves the answer rather than asserting it. Verifies:
#
#   1. the image exists in approved/ (not mirror/, not cgr.dev)
#   2. it is signed by the golden image pipeline running on main
#   3. all three attestations are present (SBOM, vuln scan, gate decision)
#   4. the gate decision actually says APPROVED
#
# Then prints the FROM line to paste. If any check fails it prints nothing
# usable and exits non-zero - you cannot accidentally copy an unverified digest.
#
# Usage:
#   ./scripts/get-approved-base.sh              list the catalogue
#   ./scripts/get-approved-base.sh python       verify + emit a FROM line
#   ./scripts/get-approved-base.sh python --json
# =============================================================================

set -Eeuo pipefail

REGISTRY="${REGISTRY:-ghcr.io/s6peter}"
GOLDEN_REPO="${GOLDEN_REPO:-s6peter/wolfi-chainguard-images}"
SIGNER_WORKFLOW="${SIGNER_WORKFLOW:-.github/workflows/golden-image.yml}"
SIGNER_REF="${SIGNER_REF:-refs/heads/main}"
OIDC_ISSUER="https://token.actions.githubusercontent.com"
APPROVAL_TYPE="https://golden-image.example.bank/approval/v1"

IDENTITY="https://github.com/${GOLDEN_REPO}/${SIGNER_WORKFLOW}@${SIGNER_REF}"

if [[ -t 1 ]]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; BD=$'\033[1m'; N=$'\033[0m'
else R=""; G=""; Y=""; D=""; BD=""; N=""; fi
ok()   { printf '  %sok%s   %s\n' "$G" "$N" "$*" >&2; }
bad()  { printf '  %sX%s    %s\n' "$R" "$N" "$*" >&2; }
die()  { bad "$*"; exit 1; }

for t in oras cosign jq; do
  command -v "$t" >/dev/null || die "missing required tool: $t"
done

# --- no argument: show what is available ------------------------------------
if [[ $# -eq 0 ]]; then
  cat >&2 <<EOF
Approved base images in ${REGISTRY}/approved/

  python           Python runtime (distroless) - runtime stage
  python-dev       Python toolchain            - build stage only
  jre              Java runtime (distroless)
  static           Go / Rust static binaries
  node             Node runtime
  aspnet-runtime   ASP.NET Core runtime

  ./scripts/get-approved-base.sh <key>

Build stages may use *-dev images. Runtime stages must not: they carry a shell
and a package manager, which is the opposite of what you want in production.
EOF
  exit 0
fi

KEY="$1"; shift || true
JSON=0; [[ "${1:-}" == "--json" ]] && JSON=1

REF="${REGISTRY}/approved/${KEY}"
printf '%sVerifying %s%s\n' "$BD" "$REF" "$N" >&2

# --- 1. resolve ------------------------------------------------------------
DIGEST="$(oras resolve "${REF}:current" 2>/dev/null || true)"
[[ -n "$DIGEST" ]] || die "not found in approved/ - either the key is wrong or the golden image pipeline has not promoted it yet"
ok "resolved  ${DIGEST}"
PINNED="${REF}@${DIGEST}"

# --- 2. signature ----------------------------------------------------------
# Pinned to the exact workflow identity. A signature from a PR run carries
# @refs/pull/N/merge and will NOT satisfy this - by design.
cosign verify \
  --certificate-oidc-issuer "$OIDC_ISSUER" \
  --certificate-identity "$IDENTITY" \
  "$PINNED" >/dev/null 2>&1 \
  || die "signature does not verify against ${IDENTITY} - do not build on this"
ok "signed by the golden image pipeline on ${SIGNER_REF}"

# --- 3 + 4. attestations, and what the decision actually said --------------
DECISION_JSON="$(cosign verify-attestation \
  --certificate-oidc-issuer "$OIDC_ISSUER" \
  --certificate-identity "$IDENTITY" \
  --type "$APPROVAL_TYPE" "$PINNED" 2>/dev/null \
  | jq -r '.payload' | base64 -d 2>/dev/null | jq -c '.predicate' | head -1 || true)"
[[ -n "$DECISION_JSON" ]] || die "no signed gate decision attached - this image did not pass a recorded gate"

DECISION="$(jq -r '.decision' <<<"$DECISION_JSON")"
[[ "$DECISION" == "APPROVED" ]] || die "gate decision is ${DECISION}, not APPROVED"
ok "gate decision: APPROVED  (critical=$(jq -r '.findings.critical' <<<"$DECISION_JSON") high=$(jq -r '.findings.high' <<<"$DECISION_JSON") secrets=$(jq -r '.findings.secrets' <<<"$DECISION_JSON"))"

for t in spdxjson vuln; do
  cosign verify-attestation \
    --certificate-oidc-issuer "$OIDC_ISSUER" \
    --certificate-identity "$IDENTITY" \
    --type "$t" "$PINNED" >/dev/null 2>&1 \
    && ok "attestation present: ${t}" \
    || die "missing attestation: ${t}"
done

# --- output ----------------------------------------------------------------
if (( JSON )); then
  jq -n --arg ref "$PINNED" --arg dig "$DIGEST" --arg key "$KEY" \
        --argjson dec "$DECISION_JSON" \
    '{key:$key, ref:$ref, digest:$dig, decision:$dec}'
else
  cat <<EOF

# renovate: datasource=docker depName=${REF}
FROM ${REF}:current@${DIGEST}
EOF
fi

printf '\n%sPaste the FROM line into your Dockerfile. Renovate maintains the digest\nfrom then on - do not hand-edit it.%s\n' "$D" "$N" >&2
