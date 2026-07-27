#!/usr/bin/env bash
# =============================================================================
# golden-image.sh - regulated base image ingest, verify, scan, gate, promote
#
# The pipeline is a one-way street. An image can only reach the approved/
# namespace by passing every gate. There is no path that writes to approved/
# without a recorded decision, and no override flag.
#
#   STAGE 0  preflight        tool + config integrity
#   STAGE 1  resolve          tag -> immutable digest             (CM-2, 6.3.2)
#   STAGE 2  verify-upstream  cosign verify publisher signature   (SI-7, SR-4)
#   STAGE 3  ingest           skopeo copy --all into mirror/      (SC-7 boundary)
#   STAGE 4  custody          prove digest survived the copy      (SI-7)
#   STAGE 5  scan             trivy vuln + secret                 (6.3.1, RA-5)
#   STAGE 6  sbom             syft SPDX + CycloneDX               (EO 14028)
#   STAGE 7  config-audit     CIS Docker Benchmark section 4      (CIS 4.x)
#   STAGE 8  gate             deterministic PASS/FAIL decision    (CA-7)
#   STAGE 9  promote          mirror/ -> approved/ + sign + attest (SR-4, 6.3.2)
#   STAGE 10 evidence         bundle, hash, attach via ORAS        (SOX, AU-11)
#
# Failure at any stage: nothing is promoted, a page is raised, exit non-zero.
#
# Compliance references are cited per stage. See docs/compliance-mapping.md
# for the full control matrix (PCI-DSS, HIPAA/HITRUST, SOX, FedRAMP,
# NIST SP 800-190, CIS Docker Benchmark).
#
# Usage:
#   ./scripts/golden-image.sh lab-up                 start a local registry
#   ./scripts/golden-image.sh list                   show the catalogue
#   ./scripts/golden-image.sh run python             one image, all stages
#   ./scripts/golden-image.sh run-all                every catalogue entry
#   ./scripts/golden-image.sh verify-approved python what a consumer runs
#   ./scripts/golden-image.sh lab-down
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CATALOG="${ROOT_DIR}/catalog/images.json"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DATE="$(date -u +%Y-%m-%d)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# shellcheck disable=SC1091
[[ -f "${ROOT_DIR}/config/policy.env" ]] && source "${ROOT_DIR}/config/policy.env"
# shellcheck disable=SC1091
[[ -f "${ROOT_DIR}/config/policy.local.env" ]] && source "${ROOT_DIR}/config/policy.local.env"

EVIDENCE_ROOT="$(cd "${ROOT_DIR}" && mkdir -p "${EVIDENCE_ROOT:-./evidence}" && cd "${EVIDENCE_ROOT:-./evidence}" && pwd)"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RST=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[36m'; C_BLD=$'\033[1m'
else
  C_RST=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BLD=""
fi

_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log()   { printf '%s %s\n' "${C_DIM}$(_ts)${C_RST}" "$*" >&2; }
stage() { printf '\n%s\n%s\n' "${C_BLU}${C_BLD}== $* ${C_RST}" "${C_DIM}$(printf '%.0s-' {1..70})${C_RST}" >&2; }
ok()    { printf '  %sPASS%s  %s\n' "${C_GRN}" "${C_RST}" "$*" >&2; }
warn()  { printf '  %sWARN%s  %s\n' "${C_YEL}" "${C_RST}" "$*" >&2; }
bad()   { printf '  %sFAIL%s  %s\n' "${C_RED}" "${C_RST}" "$*" >&2; }
die()   { bad "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Registry helpers - plain-HTTP handling for the local lab registry
# ---------------------------------------------------------------------------
is_insecure_registry() { [[ "${REGISTRY}" =~ ^(localhost|127\.0\.0\.1|host\.docker\.internal)(:[0-9]+)?(/|$) ]]; }

skopeo_dest_flags() { is_insecure_registry && echo "--dest-tls-verify=false" || true; }
skopeo_src_flags()  { is_insecure_registry && echo "--src-tls-verify=false"  || true; }
skopeo_inspect_flags() { is_insecure_registry && echo "--tls-verify=false" || true; }
cosign_reg_flags()  { is_insecure_registry && echo "--allow-insecure-registry" || true; }
oras_reg_flags()    { is_insecure_registry && echo "--plain-http" || true; }

# cosign v3 changed the signing surface: it resolves a Sigstore "signing config"
# by default, and --tlog-upload=false is rejected unless that is also disabled.
# v2 has no --use-signing-config flag at all, so the flag has to be conditional.
cosign_major() {
  local v; v="$(cosign version 2>/dev/null | awk -F'v' '/GitVersion/{print $2}' | cut -d. -f1)"
  printf '%s' "${v:-2}"
}

if is_insecure_registry; then
  export TRIVY_INSECURE=true TRIVY_NON_SSL=true
  export SYFT_REGISTRY_INSECURE_USE_HTTP=true
fi
[[ -n "${TRIVY_DB_REPOSITORY:-}" ]] && export TRIVY_DB_REPOSITORY

# ---------------------------------------------------------------------------
# Paging - a failed gate wakes a human. NIST IR-6, PCI-DSS 12.10.
# ---------------------------------------------------------------------------
page() {
  local key="$1" stage_name="$2" detail="$3"
  local page_file="${EVID_DIR:-${EVIDENCE_ROOT}}/PAGE-${RUN_ID}.json"

  jq -n \
    --arg ts "$(_ts)" --arg key "$key" --arg stage "$stage_name" \
    --arg detail "$detail" --arg sev "${PAGE_SEVERITY:-high}" \
    --arg run "$RUN_ID" --arg runner "${HOSTNAME:-unknown}" \
    '{timestamp:$ts, severity:$sev, run_id:$run, image_key:$key,
      failed_stage:$stage, detail:$detail, runner:$runner,
      action:"promotion blocked - image quarantined in mirror/ namespace",
      escalation:"platform-base-images on-call"}' \
    > "$page_file" 2>/dev/null || true

  bad "PAGE RAISED -> ${page_file}"

  if [[ -n "${PAGE_WEBHOOK:-}" ]]; then
    curl -sS -m 10 -X POST -H 'Content-Type: application/json' \
      --data @"$page_file" "$PAGE_WEBHOOK" >/dev/null 2>&1 \
      && log "page delivered to webhook" || warn "webhook delivery failed"
  fi

  # GitHub Actions: surface as an annotation the workflow can act on.
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '::error title=Golden image gate failed (%s)::%s\n' "$key" "$detail"
    {
      echo "### :rotating_light: Gate failed - \`${key}\`"
      echo ""
      echo "**Stage:** ${stage_name}"
      echo "**Detail:** ${detail}"
      echo ""
      echo "Image remains quarantined in \`mirror/\`. Nothing was promoted."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

trap 'bad "pipeline aborted at line ${LINENO} (exit $?)"' ERR

# ---------------------------------------------------------------------------
# STAGE 0 - preflight
# CIS Docker 1.x host config / NIST CM-6. A pipeline that cannot prove its own
# toolchain cannot make trustworthy assertions about anything else.
# ---------------------------------------------------------------------------
preflight() {
  stage "STAGE 0 - preflight"
  local missing=()
  for t in skopeo cosign trivy syft jq oras curl sha256sum; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  (( ${#missing[@]} )) && die "missing required tools: ${missing[*]}"

  [[ -f "$CATALOG" ]] || die "catalogue not found: $CATALOG"
  jq -e . "$CATALOG" >/dev/null || die "catalogue is not valid JSON"

  # The catalogue is the authorised-base-image register. Hash it into the
  # evidence so an auditor can prove which revision governed this run.
  CATALOG_SHA="$(sha256sum "$CATALOG" | cut -d' ' -f1)"

  ok "toolchain present"
  ok "catalogue valid (sha256:${CATALOG_SHA:0:16}...)"
  log "signing mode: ${COSIGN_SIGN_MODE}   registry: ${REGISTRY}"

  if [[ "${COSIGN_SIGN_MODE}" == "keyfile" ]]; then
    warn "keyfile signing is LAB ONLY - production requires kms or keyless"
  fi
}

# ---------------------------------------------------------------------------
# Catalogue lookup - merges defaults with any per-image override.
# ---------------------------------------------------------------------------
load_image() {
  local key="$1"
  IMG_JSON="$(jq -e --arg k "$key" '.images[] | select(.key==$k)' "$CATALOG")" \
    || die "no catalogue entry for key '${key}'"

  UPSTREAM="$(jq -r '.upstream'      <<<"$IMG_JSON")"
  MIRROR_REPO="$(jq -r '.mirror'     <<<"$IMG_JSON")"
  APPROVED_REPO="$(jq -r '.approved' <<<"$IMG_JSON")"
  TIER="$(jq -r '.tier'              <<<"$IMG_JSON")"
  OWNER="$(jq -r '.owner'            <<<"$IMG_JSON")"
  SCOPE="$(jq -r '.data_scope | join(",")' <<<"$IMG_JSON")"

  # jq's `*` deep-merges: catalogue defaults, overridden per image.
  GATE="$(jq -n --slurpfile c "$CATALOG" --argjson i "$IMG_JSON" \
          '($c[0].defaults.gate) * ($i.gate // {})')"
  VERIFY="$(jq -n --slurpfile c "$CATALOG" --argjson i "$IMG_JSON" \
          '($c[0].defaults.verify) * ($i.verify // {})')"

  MIRROR_REF="${REGISTRY}/${MIRROR_REPO}"
  APPROVED_REF="${REGISTRY}/${APPROVED_REPO}"

  EVID_DIR="${EVIDENCE_ROOT}/${key}/${RUN_DATE}-${RUN_ID}"
  mkdir -p "$EVID_DIR"
}

# ---------------------------------------------------------------------------
# STAGE 1 - resolve tag to immutable digest
# PCI-DSS 6.3.2 | NIST CM-2 | SLSA provenance
#
# Everything downstream operates on the digest, never the tag. If the tag moves
# mid-run, we do not silently scan one image and promote another.
# ---------------------------------------------------------------------------
stage_resolve() {
  stage "STAGE 1 - resolve upstream digest"
  log "upstream: ${UPSTREAM}"

  if UP_DIGEST="$(oras resolve "$UPSTREAM" 2>/dev/null)"; then
    :
  else
    warn "oras resolve unavailable, falling back to skopeo"
    UP_DIGEST="sha256:$(skopeo inspect --raw docker://"${UPSTREAM}" | sha256sum | cut -d' ' -f1)"
  fi
  [[ "$UP_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || die "bad digest: ${UP_DIGEST}"

  UPSTREAM_REPO="${UPSTREAM%%:*}"
  UP_PINNED="${UPSTREAM_REPO}@${UP_DIGEST}"
  SHORT="${UP_DIGEST#sha256:}"; SHORT="${SHORT:0:12}"

  ok "resolved -> ${UP_DIGEST}"
  printf '%s\n' "$UP_PINNED" > "${EVID_DIR}/01-resolved-ref.txt"
}

# ---------------------------------------------------------------------------
# STAGE 2 - verify the upstream publisher signature
# NIST SI-7 / SR-4 | PCI-DSS 6.3.2 | HITRUST 09.j
#
# Answers: did these exact bytes come from Chainguard's release workflow, or
# did something substitute them in transit or in a compromised mirror?
# Verified against the DIGEST - verifying a tag proves nothing about what we
# resolved a moment ago.
# ---------------------------------------------------------------------------
stage_verify_upstream() {
  stage "STAGE 2 - verify upstream publisher signature"

  local mode issuer identity pubkey
  mode="$(jq -r '.mode'                       <<<"$VERIFY")"
  issuer="$(jq -r '.issuer // empty'          <<<"$VERIFY")"
  identity="$(jq -r '.identity_regexp // empty' <<<"$VERIFY")"
  pubkey="$(jq -r '.public_key // empty'      <<<"$VERIFY")"

  local out="${EVID_DIR}/02-upstream-verification.json"
  local rc=0

  case "$mode" in
    keyless)
      log "keyless: issuer=${issuer}"
      log "         identity~=${identity}"
      cosign verify \
        --certificate-oidc-issuer "$issuer" \
        --certificate-identity-regexp "$identity" \
        --rekor-url "${REKOR_URL}" \
        "$UP_PINNED" > "$out" 2>"${EVID_DIR}/02-upstream-verification.log" || rc=$?
      ;;
    key)
      cosign verify --key "$pubkey" "$UP_PINNED" \
        > "$out" 2>"${EVID_DIR}/02-upstream-verification.log" || rc=$?
      ;;
    none)
      # Only ever acceptable for an internally built base. Recorded as a
      # compensating-control exception so it shows up in the evidence review.
      warn "upstream verification DISABLED for this entry - exception must be documented"
      jq -n '{verified:false, reason:"verification disabled in catalogue"}' > "$out"
      ;;
    *) die "unknown verify mode '${mode}'" ;;
  esac

  if (( rc != 0 )); then
    page "$IMG_KEY" "verify-upstream" \
      "cosign could not verify ${UP_PINNED} against the expected publisher identity"
    die "upstream signature verification failed - possible tampering or supply-chain compromise"
  fi

  ok "publisher signature verified against digest"
}

# ---------------------------------------------------------------------------
# STAGE 3 - ingest into the quarantine mirror
# NIST SC-7 (boundary) | 800-190 4.1.2 | PCI-DSS 1.3 (no direct internet pull)
#
# --all           copies every architecture in the manifest list. Without it
#                 you get one platform and a DIFFERENT digest.
# --preserve-digests  fails loudly rather than silently re-compressing.
# ---------------------------------------------------------------------------
stage_ingest() {
  stage "STAGE 3 - ingest into mirror (quarantine)"
  local dest="${MIRROR_REF}:ingest-${RUN_DATE}"
  log "${UP_PINNED}"
  log "  -> ${dest}"

  # shellcheck disable=SC2046
  skopeo copy --all --preserve-digests \
    $(skopeo_src_flags) $(skopeo_dest_flags) \
    "docker://${UP_PINNED}" "docker://${dest}" \
    2>&1 | tee "${EVID_DIR}/03-ingest.log" >/dev/null

  MIRROR_PINNED="${MIRROR_REF}@${UP_DIGEST}"
  ok "copied to quarantine"
}

# ---------------------------------------------------------------------------
# STAGE 4 - chain of custody
# NIST SI-7 | SOX ITGC change integrity
#
# A digest is a hash of content, not of location. If the copy is faithful, the
# mirrored manifest resolves to the identical digest. If it does not, the bytes
# changed in transit and everything downstream is void.
# ---------------------------------------------------------------------------
stage_custody() {
  stage "STAGE 4 - chain of custody"
  local mirror_digest
  # shellcheck disable=SC2046
  mirror_digest="sha256:$(skopeo inspect --raw $(skopeo_inspect_flags) \
    "docker://${MIRROR_REF}:ingest-${RUN_DATE}" | sha256sum | cut -d' ' -f1)"

  jq -n --arg up "$UP_DIGEST" --arg mir "$mirror_digest" \
        --arg src "$UP_PINNED" --arg dst "${MIRROR_REF}:ingest-${RUN_DATE}" \
    '{upstream_digest:$up, mirror_digest:$mir, match:($up==$mir),
      source:$src, destination:$dst}' > "${EVID_DIR}/04-custody.json"

  if [[ "$mirror_digest" != "$UP_DIGEST" ]]; then
    page "$IMG_KEY" "custody" \
      "digest changed during copy: ${UP_DIGEST} -> ${mirror_digest}"
    die "chain of custody broken - content was altered in transit"
  fi
  ok "digest preserved end to end: ${UP_DIGEST}"
}

# ---------------------------------------------------------------------------
# STAGE 5 - vulnerability and secret scan
# PCI-DSS 6.3.1 / 11.3 | NIST RA-5 | HIPAA 164.308(a)(1)(ii)(A) | 800-190 4.1.1
#
# The secret scanner is the automated form of CIS Docker 4.10: it catches
# credentials baked into a layer, which no vulnerability feed would ever report.
# ---------------------------------------------------------------------------
stage_scan() {
  stage "STAGE 5 - vulnerability and secret scan"
  local out="${EVID_DIR}/05-trivy.json"

  trivy image \
    --scanners "${TRIVY_SCANNERS}" \
    --format json --output "$out" \
    --quiet --timeout 15m \
    "$MIRROR_PINNED" 2>"${EVID_DIR}/05-trivy.log" \
    || { page "$IMG_KEY" "scan" "trivy failed to execute"; die "scanner error"; }

  CRIT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$out")
  HIGH=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")]     | length' "$out")
  MED=$(jq  '[.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM")]   | length' "$out")
  SECRETS=$(jq '[.Results[]?.Secrets[]?] | length' "$out")

  # Unfixed findings are tracked separately: they cannot be remediated by
  # patching, so they belong in risk acceptance, not in the patch SLA clock.
  CRIT_FIXABLE=$(jq '[.Results[]?.Vulnerabilities[]?
                      | select(.Severity=="CRITICAL" and (.FixedVersion // "") != "")] | length' "$out")
  HIGH_FIXABLE=$(jq '[.Results[]?.Vulnerabilities[]?
                      | select(.Severity=="HIGH" and (.FixedVersion // "") != "")] | length' "$out")

  log "critical=${CRIT} (fixable ${CRIT_FIXABLE})  high=${HIGH} (fixable ${HIGH_FIXABLE})  medium=${MED}  secrets=${SECRETS}"
  ok "scan complete"
}

# ---------------------------------------------------------------------------
# STAGE 6 - SBOM
# EO 14028 / NTIA minimum elements | FedRAMP SI-7 | 800-190 4.1.4
#
# Two formats because two audiences: SPDX for regulators and procurement,
# CycloneDX for Dependency-Track and vulnerability correlation.
# Generated against the digest, so the SBOM is bound to exact bytes.
# ---------------------------------------------------------------------------
stage_sbom() {
  stage "STAGE 6 - SBOM generation"
  # IFS is restricted to newline/tab at the top of this script, so a
  # space-separated list has to be split explicitly.
  local _fmts=(); IFS=' ' read -r -a _fmts <<<"${SYFT_FORMATS}"
  for fmt in "${_fmts[@]}"; do
    local ext="${fmt%-json}"
    syft scan "registry:${MIRROR_PINNED}" -o "${fmt}=${EVID_DIR}/06-sbom.${ext}.json" -q \
      2>"${EVID_DIR}/06-syft-${ext}.log" \
      || { page "$IMG_KEY" "sbom" "syft failed for format ${fmt}"; die "SBOM generation failed"; }
    ok "${fmt} -> 06-sbom.${ext}.json"
  done
  PKG_COUNT=$(jq '[.packages // .components // []] | flatten | length' \
    "${EVID_DIR}/06-sbom.spdx.json" 2>/dev/null || echo 0)
  log "packages inventoried: ${PKG_COUNT}"
}

# ---------------------------------------------------------------------------
# STAGE 7 - image configuration audit
# CIS Docker Benchmark section 4 | NIST 800-190 4.5.1 | PCI-DSS 2.2
#
# Scanners check what is IN the image. This checks how the image is CONFIGURED
# to run - the part CVE feeds never look at, and where CIS 4.1 lives.
# ---------------------------------------------------------------------------
stage_config_audit() {
  stage "STAGE 7 - CIS configuration audit"
  local cfg="${EVID_DIR}/07-image-config.json"
  # shellcheck disable=SC2046
  skopeo inspect --config $(skopeo_inspect_flags) "docker://${MIRROR_PINNED}" > "$cfg"

  local user healthcheck ports findings='[]'
  user="$(jq -r '.config.User // ""' "$cfg")"
  healthcheck="$(jq -r 'if .config.Healthcheck then "present" else "absent" end' "$cfg")"
  ports="$(jq -r '(.config.ExposedPorts // {}) | keys | join(",")' "$cfg")"

  # CIS 4.1 - the image must not run as root.
  CIS_NONROOT=true
  if [[ -z "$user" || "$user" == "root" || "$user" == "0" || "$user" == 0:* ]]; then
    CIS_NONROOT=false
    findings="$(jq -c '. + [{control:"CIS-4.1", severity:"high",
      finding:"image runs as root or does not declare USER"}]' <<<"$findings")"
  fi

  # CIS 4.6 - healthcheck. Informational for distroless: a runtime with no
  # shell physically cannot satisfy it, and Kubernetes ignores it regardless.
  if [[ "$healthcheck" == "absent" ]]; then
    findings="$(jq -c '. + [{control:"CIS-4.6", severity:"informational",
      finding:"no HEALTHCHECK - compensating control: Kubernetes probes"}]' <<<"$findings")"
  fi

  # Privileged port bind would require NET_BIND_SERVICE, contradicting drop:ALL.
  CIS_PORTS=true
  if [[ -n "$ports" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      local n="${p%%/*}"
      if [[ "$n" =~ ^[0-9]+$ ]] && (( n < 1024 )); then
        CIS_PORTS=false
        findings="$(jq -c --arg p "$p" '. + [{control:"CIS-5.7", severity:"medium",
          finding:("exposes privileged port " + $p + " - requires NET_BIND_SERVICE")}]' <<<"$findings")"
      fi
    done < <(tr ',' '\n' <<<"$ports")
  fi

  jq -n --arg user "$user" --arg hc "$healthcheck" --arg ports "$ports" \
        --argjson nonroot "$CIS_NONROOT" --argjson f "$findings" \
    '{user:$user, healthcheck:$hc, exposed_ports:$ports,
      cis_4_1_nonroot:$nonroot, findings:$f}' > "${EVID_DIR}/07-cis-audit.json"

  [[ "$CIS_NONROOT" == true ]] && ok "CIS 4.1 non-root user: ${user}" \
                               || bad "CIS 4.1 violated: runs as root"
  [[ "$healthcheck" == "present" ]] && ok "CIS 4.6 healthcheck present" \
                                    || warn "CIS 4.6 no healthcheck (expected for distroless)"
}

# ---------------------------------------------------------------------------
# STAGE 8 - the gate
# NIST CA-7 / RA-5 | PCI-DSS 6.3.1 | SOX ITGC
#
# A single deterministic decision, computed from thresholds declared in the
# catalogue. No human judgement at runtime, no override flag. If you want a
# different answer you change the catalogue - which is a reviewed commit.
# ---------------------------------------------------------------------------
stage_gate() {
  stage "STAGE 8 - policy gate"

  local max_crit max_high max_sec allow_unfixed require_nonroot forbid_ports
  max_crit=$(jq -r '.max_critical'      <<<"$GATE")
  max_high=$(jq -r '.max_high'          <<<"$GATE")
  max_sec=$(jq -r '.max_secrets'        <<<"$GATE")
  allow_unfixed=$(jq -r '.allow_unfixed'   <<<"$GATE")
  require_nonroot=$(jq -r '.require_nonroot' <<<"$GATE")
  forbid_ports=$(jq -r '.forbid_privileged_ports' <<<"$GATE")

  local eval_crit="$CRIT" eval_high="$HIGH"
  if [[ "$allow_unfixed" == "true" ]]; then
    eval_crit="$CRIT_FIXABLE"; eval_high="$HIGH_FIXABLE"
    log "counting fixable findings only (unfixed tracked as accepted risk)"
  fi

  local violations='[]'
  add_violation() {
    violations="$(jq -c --arg c "$1" --arg m "$2" '. + [{control:$c, reason:$m}]' <<<"$violations")"
  }

  (( eval_crit > max_crit )) && add_violation "PCI-DSS-6.3.1" \
      "critical vulnerabilities ${eval_crit} exceeds threshold ${max_crit}"
  (( eval_high > max_high )) && add_violation "PCI-DSS-6.3.1" \
      "high vulnerabilities ${eval_high} exceeds threshold ${max_high}"
  (( SECRETS > max_sec )) && add_violation "CIS-4.10" \
      "embedded secrets detected: ${SECRETS}"
  [[ "$require_nonroot" == "true" && "$CIS_NONROOT" != "true" ]] && add_violation "CIS-4.1" \
      "image runs as root"
  [[ "$forbid_ports" == "true" && "${CIS_PORTS}" != "true" ]] && add_violation "CIS-5.7" \
      "image exposes a privileged port"

  local count; count=$(jq 'length' <<<"$violations")
  local decision; [[ "$count" -eq 0 ]] && decision="APPROVED" || decision="REJECTED"

  jq -n \
    --arg d "$decision" --arg ts "$(_ts)" --arg run "$RUN_ID" \
    --arg key "$IMG_KEY" --arg up "$UP_PINNED" --arg dig "$UP_DIGEST" \
    --arg tier "$TIER" --arg owner "$OWNER" --arg scope "$SCOPE" \
    --arg cat "$CATALOG_SHA" \
    --argjson crit "$CRIT" --argjson critfix "$CRIT_FIXABLE" \
    --argjson high "$HIGH" --argjson highfix "$HIGH_FIXABLE" \
    --argjson med "$MED" --argjson sec "$SECRETS" \
    --argjson gate "$GATE" --argjson v "$violations" \
    '{decision:$d, timestamp:$ts, run_id:$run, image_key:$key,
      subject:{ref:$up, digest:$dig}, tier:$tier, owner:$owner,
      data_scope:$scope, catalogue_sha256:$cat,
      findings:{critical:$crit, critical_fixable:$critfix,
                high:$high, high_fixable:$highfix,
                medium:$med, secrets:$sec},
      thresholds:$gate, violations:$v,
      controls_evaluated:["PCI-DSS-6.3.1","PCI-DSS-6.3.2","CIS-4.1","CIS-4.10",
                          "CIS-5.7","NIST-800-190-4.1","NIST-RA-5","NIST-SI-7"]}' \
    > "${EVID_DIR}/08-decision.json"

  if [[ "$decision" == "REJECTED" ]]; then
    jq -r '.[] | "    - [\(.control)] \(.reason)"' <<<"$violations" >&2
    page "$IMG_KEY" "gate" "$(jq -r '[.[].reason] | join("; ")' <<<"$violations")"
    die "GATE REJECTED - image quarantined in mirror/, nothing promoted"
  fi

  ok "GATE APPROVED - no violations"
}

# ---------------------------------------------------------------------------
# STAGE 9 - promote, sign, attest
# PCI-DSS 6.3.2 | NIST SR-4 / SI-7 | SLSA build L3 | SOX change authorisation
#
# Promotion is a copy between namespaces, digest preserved. The bank's own
# signature is what downstream admission control trusts - Chainguard's
# signature proves origin, ours proves "this passed OUR gate on this date".
# ---------------------------------------------------------------------------
stage_promote() {
  stage "STAGE 9 - promote, sign, attest"

  local dated="${APPROVED_REF}:${RUN_DATE}"
  local addressed="${APPROVED_REF}:sha256-${SHORT}"
  local floating="${APPROVED_REF}:${PROMOTE_FLOATING_TAG}"

  for dst in "$dated" "$addressed" "$floating"; do
    # shellcheck disable=SC2046
    skopeo copy --all --preserve-digests \
      $(skopeo_src_flags) $(skopeo_dest_flags) \
      "docker://${MIRROR_PINNED}" "docker://${dst}" >/dev/null 2>&1
    ok "promoted -> ${dst}"
  done

  APPROVED_PINNED="${APPROVED_REF}@${UP_DIGEST}"

  # --- signing -------------------------------------------------------------
  local sign_args=(--yes)
  local tlog_args=()
  if [[ "${TLOG_UPLOAD:-true}" == "true" ]]; then
    tlog_args=(--rekor-url "${REKOR_URL}")
  else
    # Lab only. Skipping the transparency log removes the tamper-evident
    # record, so a production run with this set is itself an audit finding.
    warn "transparency log upload DISABLED - lab mode only"
    tlog_args=(--tlog-upload=false)
    [[ "$(cosign_major)" -ge 3 ]] && tlog_args+=(--use-signing-config=false)
  fi
  sign_args+=("${tlog_args[@]}")

  # shellcheck disable=SC2046
  local reg_flags; reg_flags=$(cosign_reg_flags)
  [[ -n "$reg_flags" ]] && sign_args+=("$reg_flags")

  case "${COSIGN_SIGN_MODE}" in
    kms|keyfile) sign_args+=(--key "${COSIGN_KEY_REF}") ;;
    keyless)     : ;;   # OIDC identity from the CI runner
    *) die "unknown COSIGN_SIGN_MODE '${COSIGN_SIGN_MODE}'" ;;
  esac

  cosign sign "${sign_args[@]}" "$APPROVED_PINNED" \
    > "${EVID_DIR}/09-sign.log" 2>&1 \
    || { page "$IMG_KEY" "sign" "cosign sign failed"; die "signing failed"; }
  ok "image signed (${COSIGN_SIGN_MODE})"

  # --- attestations --------------------------------------------------------
  # Three signed claims, each bound to the digest. Kyverno enforces their
  # presence at admission, so an unattested image cannot start in the cluster.
  attest() {
    local ptype="$1" predicate="$2" label="$3"
    local args=(--yes --type "$ptype" --predicate "$predicate" "${tlog_args[@]}")
    [[ -n "$reg_flags" ]] && args+=("$reg_flags")
    case "${COSIGN_SIGN_MODE}" in kms|keyfile) args+=(--key "${COSIGN_KEY_REF}") ;; esac
    cosign attest "${args[@]}" "$APPROVED_PINNED" >>"${EVID_DIR}/09-attest.log" 2>&1 \
      || { page "$IMG_KEY" "attest" "cosign attest failed for ${label}"; die "attestation failed"; }
    ok "attested: ${label}"
  }

  attest spdxjson "${EVID_DIR}/06-sbom.spdx.json" "SPDX SBOM"
  attest vuln     "${EVID_DIR}/05-trivy.json"      "vulnerability scan"
  attest "https://golden-image.example.bank/approval/v1" \
         "${EVID_DIR}/08-decision.json"            "gate decision"
}

# ---------------------------------------------------------------------------
# STAGE 10 - evidence bundle
# SOX 7yr | HIPAA 164.316(b)(2) 6yr | PCI-DSS 10.5.1 12mo | FedRAMP AU-11 3yr
#
# The bundle is attached to the image as an ORAS referrer, so the evidence
# travels with the artifact instead of living in a separate system that has to
# be kept in sync. An auditor pulls the image and pulls its evidence.
# ---------------------------------------------------------------------------
stage_evidence() {
  stage "STAGE 10 - evidence bundle"

  ( cd "$EVID_DIR" && sha256sum ./* > SHA256SUMS 2>/dev/null || true )

  jq -n \
    --arg run "$RUN_ID" --arg ts "$(_ts)" --arg key "$IMG_KEY" \
    --arg up "$UP_PINNED" --arg appr "${APPROVED_PINNED:-not-promoted}" \
    --arg dig "$UP_DIGEST" --arg cat "$CATALOG_SHA" \
    --arg tier "$TIER" --arg owner "$OWNER" \
    --arg ret "${EVIDENCE_RETENTION_YEARS}" --arg mode "${COSIGN_SIGN_MODE}" \
    '{manifest_version:"golden-image-evidence/v1",
      run_id:$run, generated:$ts, image_key:$key,
      upstream:$up, approved:$appr, digest:$dig,
      catalogue_sha256:$cat, tier:$tier, owner:$owner,
      signing_mode:$mode,
      retention_years:($ret|tonumber),
      contents:{
        "01-resolved-ref.txt":"tag to digest resolution",
        "02-upstream-verification.json":"publisher signature verification",
        "03-ingest.log":"skopeo copy transcript",
        "04-custody.json":"digest preservation proof",
        "05-trivy.json":"vulnerability and secret scan",
        "06-sbom.spdx.json":"SPDX SBOM",
        "06-sbom.cyclonedx.json":"CycloneDX SBOM",
        "07-cis-audit.json":"CIS Docker Benchmark section 4 audit",
        "08-decision.json":"signed gate decision",
        "SHA256SUMS":"integrity manifest"
      }}' > "${EVID_DIR}/manifest.json"

  local bundle_dir bundle_name bundle
  bundle_dir="$(cd "$(dirname "$EVID_DIR")" && pwd)"
  bundle_name="${IMG_KEY}-${RUN_DATE}-${RUN_ID}-evidence.tar.gz"
  bundle="${bundle_dir}/${bundle_name}"

  tar -czf "$bundle" -C "$bundle_dir" "$(basename "$EVID_DIR")"
  BUNDLE_SHA="$(sha256sum "$bundle" | cut -d' ' -f1)"
  ok "bundle sha256:${BUNDLE_SHA:0:16}... ($(du -h "$bundle" | cut -f1))"

  if [[ -n "${APPROVED_PINNED:-}" ]]; then
    # ORAS rejects absolute file paths by default (they would leak the build
    # host's directory layout into the artifact's annotations). Push from the
    # bundle's own directory with a relative name instead.
    # shellcheck disable=SC2046
    ( cd "$bundle_dir" && oras attach $(oras_reg_flags) \
        --artifact-type "application/vnd.bank.golden-image.evidence.v1+tar+gzip" \
        --annotation "run_id=${RUN_ID}" \
        --annotation "org.opencontainers.artifact.created=$(_ts)" \
        "$APPROVED_PINNED" "${bundle_name}:application/gzip" ) \
      >"${EVID_DIR}/10-oras-attach.log" 2>&1 \
      && ok "evidence attached as ORAS referrer" \
      || warn "ORAS attach failed - evidence retained locally only"
  fi

  printf '\n%s%sGOLDEN IMAGE PUBLISHED%s\n' "$C_GRN" "$C_BLD" "$C_RST" >&2
  printf '  %s\n  evidence: %s\n\n' "${APPROVED_PINNED:-n/a}" "$EVID_DIR" >&2

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### :white_check_mark: \`${IMG_KEY}\` promoted"
      echo ""
      echo "| | |"
      echo "|---|---|"
      echo "| Upstream | \`${UPSTREAM}\` |"
      echo "| Digest | \`${UP_DIGEST}\` |"
      echo "| Approved | \`${APPROVED_PINNED}\` |"
      echo "| Critical / High | ${CRIT} / ${HIGH} |"
      echo "| Secrets | ${SECRETS} |"
      echo "| Tier | ${TIER} |"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

# ---------------------------------------------------------------------------
# Consumer-side verification - what an application team or auditor runs.
# This is also exactly what the Kyverno policy enforces at admission.
# ---------------------------------------------------------------------------
verify_approved() {
  local key="$1"
  load_image "$key"
  IMG_KEY="$key"
  stage "verify approved image: ${key}"

  local ref="${APPROVED_REF}:${PROMOTE_FLOATING_TAG}"
  local digest; digest="$(oras resolve $(oras_reg_flags) "$ref")" \
    || die "cannot resolve ${ref} - has it been promoted?"
  local pinned="${APPROVED_REF}@${digest}"
  log "verifying ${pinned}"

  local args=(); [[ -n "$(cosign_reg_flags)" ]] && args+=("$(cosign_reg_flags)")
  [[ "${TLOG_UPLOAD:-true}" == "true" ]] || args+=(--insecure-ignore-tlog=true)
  case "${COSIGN_SIGN_MODE}" in
    kms|keyfile) args+=(--key "${COSIGN_PUB_REF}") ;;
    keyless)     args+=(--certificate-oidc-issuer "https://token.actions.githubusercontent.com"
                        --certificate-identity-regexp ".*") ;;
  esac

  cosign verify "${args[@]}" "$pinned" >/dev/null 2>&1 \
    && ok "bank signature valid" || die "signature verification FAILED"

  for t in spdxjson vuln "https://golden-image.example.bank/approval/v1"; do
    cosign verify-attestation "${args[@]}" --type "$t" "$pinned" >/dev/null 2>&1 \
      && ok "attestation present: ${t}" || bad "attestation MISSING: ${t}"
  done

  # shellcheck disable=SC2046
  oras discover $(oras_reg_flags) -o json "$pinned" 2>/dev/null \
    | jq -r '.manifests[]? | "  referrer: \(.artifactType) \(.digest[0:19])..."' >&2 || true
}

# ---------------------------------------------------------------------------
# Pipeline driver
# ---------------------------------------------------------------------------
run_one() {
  IMG_KEY="$1"
  load_image "$IMG_KEY"

  printf '\n%s%s================ GOLDEN IMAGE: %s (%s) ================%s\n' \
    "$C_BLD" "$C_BLU" "$IMG_KEY" "$TIER" "$C_RST" >&2

  stage_resolve
  stage_verify_upstream
  stage_ingest
  stage_custody
  stage_scan
  stage_sbom
  stage_config_audit
  stage_gate
  stage_promote
  stage_evidence
}

cmd_list() {
  printf '%-18s %-46s %-8s %s\n' KEY UPSTREAM TIER SCOPE
  jq -r '.images[] | [.key, .upstream, .tier, (.data_scope|join(","))] | @tsv' "$CATALOG" \
    | while IFS=$'\t' read -r k u t s; do printf '%-18s %-46s %-8s %s\n' "$k" "$u" "$t" "$s"; done
}

cmd_lab_up() {
  command -v docker >/dev/null || die "docker required for the lab registry"
  docker rm -f golden-lab-registry >/dev/null 2>&1 || true
  docker run -d --name golden-lab-registry -p 5000:5000 --restart=no registry:2 >/dev/null
  log "lab registry on localhost:5000 (REGISTRY=localhost:5000)"
  log "note: a lab registry is NOT a control boundary - production needs authn/authz and RBAC"
}

cmd_lab_down() { docker rm -f golden-lab-registry >/dev/null 2>&1 && log "lab registry removed" || true; }

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    run)             preflight; run_one "${1:?usage: run <image-key>}" ;;
    run-all)
      preflight
      local failed=() k
      while IFS= read -r k; do
        ( run_one "$k" ) || failed+=("$k")
      done < <(jq -r '.images[].key' "$CATALOG")
      if (( ${#failed[@]} )); then
        bad "failed: ${failed[*]}"; exit 1
      fi
      ok "all catalogue entries promoted"
      ;;
    verify-approved) preflight; verify_approved "${1:?usage: verify-approved <image-key>}" ;;
    list)            cmd_list ;;
    lab-up)          cmd_lab_up ;;
    lab-down)        cmd_lab_down ;;
    help|-h|--help)  usage 0 ;;
    *)               bad "unknown command: ${cmd}"; usage 1 ;;
  esac
}

main "$@"
