#!/usr/bin/env bash
# =============================================================================
# admission-test.sh - prove the golden image policies actually work
#
# WHY THIS EXISTS
#
# Two bugs shipped in kyverno-golden-image.yaml that were invisible on reading:
#   1. imageReferences pointed at the wrong registry owner  -> every rule
#      silently PASSED, so the control did nothing at all.
#   2. attestors expected a static public key while the pipeline signs keyless
#      -> every rule would have FAILED, denying every pod in the cluster.
#
# Reading YAML catches neither. Executing it catches both immediately.
# "How do you know the control works?" is a question every assessor asks, and
# the output of this script is the answer.
#
# HOW IT WORKS
#
# `kubectl apply --dry-run=server` runs the full admission chain - mutating
# webhooks, validating webhooks, Kyverno image verification against the real
# registry and Rekor - WITHOUT creating pods, pulling images, or needing a
# schedulable node. Each case asserts admit-vs-deny and, on a denial, that the
# message came from the policy under test rather than an unrelated one.
#
# USAGE
#   ./tests/admission-test.sh                full run, then tear down
#   KEEP=1 ./tests/admission-test.sh         leave the cluster up
#   MODE=Audit ./tests/admission-test.sh     observe instead of enforce
#
# After merge, point it at the real promoted images:
#   TEST_IMAGE_PREFIX=ghcr.io/s6peter TEST_SIGNER_REF=refs/heads/main \
#     ./tests/admission-test.sh
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
POLICY_SRC="${ROOT_DIR}/policy/kyverno-golden-image.yaml"

CLUSTER="${CLUSTER:-golden-image-admission}"
NS="${NS:-golden-test}"
MODE="${MODE:-Enforce}"
KEEP="${KEEP:-0}"
KYVERNO_CHART_VERSION="${KYVERNO_CHART_VERSION:-3.5.1}"

# Defaults target the dry-run namespace the pull_request workflow produced,
# because that is what exists before this branch merges.
TEST_IMAGE_PREFIX="${TEST_IMAGE_PREFIX:-ghcr.io/s6peter/dryrun}"
TEST_SIGNER_REF="${TEST_SIGNER_REF:-refs/pull/1/merge}"
PROD_IMAGE_PREFIX="ghcr.io/s6peter"
PROD_SIGNER_REF="refs/heads/main"

WORK="$(mktemp -d)"
CLUSTER_UP=0
trap 'rc=$?; [[ "$KEEP" == "1" ]] || cleanup; rm -rf "$WORK"; exit $rc' EXIT

if [[ -t 1 ]]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'
  D=$'\033[2m'; BD=$'\033[1m'; N=$'\033[0m'
else R=""; G=""; Y=""; B=""; D=""; BD=""; N=""; fi

log()   { printf '%s %s\n' "${D}$(date -u +%H:%M:%S)${N}" "$*"; }
head1() { printf '\n%s%s== %s%s\n' "$B" "$BD" "$*" "$N"; }
die()   { printf '%sFATAL%s %s\n' "$R" "$N" "$*"; exit 1; }

PASS=0; FAIL=0; SKIP=0; ERRORS=0
declare -a RESULTS=()

cleanup() {
  [[ "$CLUSTER_UP" == "1" ]] || return 0
  log "deleting kind cluster ${CLUSTER}"
  kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# kubectl acquisition
#
# --dry-run=server landed in kubectl 1.18. An older client (e.g. a pinned EKS
# 1.17 binary) rejects the flag CLIENT-SIDE, which would look like an admission
# denial to any naive test. Rather than replace the operator's system kubectl -
# it may be pinned deliberately to match a real cluster - fetch a modern one
# into a cache directory and use that only for this test.
# ---------------------------------------------------------------------------
KUBECTL="${KUBECTL:-kubectl}"
KUBECTL_CACHE="${HOME}/.cache/golden-image-04/bin"

kubectl_minor() {
  "$1" version --client 2>/dev/null \
    | grep -oE 'GitVersion:"v[0-9]+\.[0-9]+' | head -1 \
    | grep -oE '[0-9]+\.[0-9]+$' | cut -d. -f2
}

ensure_kubectl() {
  local minor; minor="$(kubectl_minor "$KUBECTL" || true)"
  if [[ -n "$minor" ]] && (( minor >= 18 )); then
    log "kubectl 1.${minor} supports --dry-run=server"
    return 0
  fi

  log "${Y}system kubectl is 1.${minor:-?} - too old for --dry-run=server${N}"
  mkdir -p "$KUBECTL_CACHE"
  local cached="${KUBECTL_CACHE}/kubectl"
  if [[ -x "$cached" ]] && (( "$(kubectl_minor "$cached")" >= 18 )); then
    KUBECTL="$cached"; log "using cached kubectl 1.$(kubectl_minor "$cached")"
    return 0
  fi

  local ver; ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" \
    || die "cannot reach dl.k8s.io to fetch a usable kubectl"
  log "downloading kubectl ${ver} to ${KUBECTL_CACHE} (system kubectl untouched)"
  curl -fsSL -o "${cached}.tmp" "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl" \
    || die "kubectl download failed"
  local want; want="$(curl -fsSL "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl.sha256")"
  echo "${want}  ${cached}.tmp" | sha256sum -c - >/dev/null \
    || die "kubectl checksum mismatch - refusing to use it"
  chmod +x "${cached}.tmp" && mv "${cached}.tmp" "$cached"
  KUBECTL="$cached"
  log "kubectl ${ver} verified and cached"
}

preflight() {
  head1 "preflight"
  for t in kind helm python3 oras curl sha256sum; do
    command -v "$t" >/dev/null || die "missing required tool: $t"
  done
  command -v "$KUBECTL" >/dev/null || die "missing required tool: kubectl"
  [[ -f "$POLICY_SRC" ]] || die "policy not found: $POLICY_SRC"
  ensure_kubectl
  log "mode=${MODE}  images=${TEST_IMAGE_PREFIX}  signer-ref=${TEST_SIGNER_REF}"
}

# ---------------------------------------------------------------------------
# Build the lab policy from the production one.
# Single source of truth: production YAML is rewritten, never forked. Every
# substitution is printed so the delta between what production enforces and
# what was tested here is explicit rather than assumed.
# ---------------------------------------------------------------------------
build_lab_policy() {
  head1 "building lab policy from production source"
  LAB_POLICY="${WORK}/policy-lab.yaml"
  python3 - "$POLICY_SRC" "$LAB_POLICY" \
      "$PROD_IMAGE_PREFIX" "$TEST_IMAGE_PREFIX" \
      "$PROD_SIGNER_REF" "$TEST_SIGNER_REF" "$MODE" <<'PY'
import sys, yaml
src, out, pimg, timg, pref, tref, mode = sys.argv[1:8]
raw = open(src).read(); subs = []
if pimg != timg:
    for kind in ("approved", "mirror"):
        old, new = f"{pimg}/{kind}/", f"{timg}/{kind}/"
        if old in raw:
            raw = raw.replace(old, new); subs.append((old, new))
if pref != tref:
    raw = raw.replace(f"@{pref}", f"@{tref}"); subs.append((f"@{pref}", f"@{tref}"))

docs = [d for d in yaml.safe_load_all(raw) if d]
# kind runs its storage provisioner in local-path-storage; enforcing the
# hardening policy against it cluster-wide would break the cluster itself.
EXCLUDE = ["kube-system", "kyverno", "local-path-storage",
           "kube-public", "kube-node-lease"]
for d in docs:
    spec = d.get("spec", {})
    if "validationFailureAction" in spec:
        spec["validationFailureAction"] = mode
    for rule in spec.get("rules", []):
        for ex in rule.get("exclude", {}).get("any", []):
            res = ex.get("resources", {})
            if "namespaces" in res:
                res["namespaces"] = EXCLUDE
        for vi in rule.get("verifyImages", []) or []:
            if "failureAction" in vi:
                vi["failureAction"] = mode
with open(out, "w") as f:
    yaml.safe_dump_all(docs, f, sort_keys=False, default_flow_style=False)
for o, n in subs:
    print(f"  rewrote  {o}  ->  {n}")
print(f"  failureAction -> {mode}")
print(f"  excluded namespaces -> {', '.join(EXCLUDE)}")
PY
}

setup_cluster() {
  # REUSE=1 iterates on the policy against an already-running cluster. Never
  # use it for a result you intend to keep as evidence: a fresh cluster is the
  # only way to prove the policies work from a clean state.
  if [[ "${REUSE:-0}" == "1" ]] && kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    head1 "reusing existing kind cluster (REUSE=1)"
    CLUSTER_UP=1
    "$KUBECTL" config use-context "kind-${CLUSTER}" >/dev/null
    "$KUBECTL" get ns "$NS" >/dev/null 2>&1 || "$KUBECTL" create namespace "$NS" >/dev/null
    log "${Y}not a clean-state run - do not file this output as evidence${N}"
    return 0
  fi
  head1 "creating kind cluster"
  kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
  kind create cluster --name "$CLUSTER" --wait 150s >/dev/null 2>&1 \
    || die "kind create failed"
  CLUSTER_UP=1
  "$KUBECTL" config use-context "kind-${CLUSTER}" >/dev/null
  log "cluster ready"

  head1 "installing Kyverno (chart ${KYVERNO_CHART_VERSION})"
  helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
  helm repo update kyverno >/dev/null 2>&1
  helm install kyverno kyverno/kyverno \
    --version "${KYVERNO_CHART_VERSION}" \
    -n kyverno --create-namespace \
    --set admissionController.replicas=1 \
    --set backgroundController.replicas=1 \
    --wait --timeout 8m >/dev/null 2>&1 || die "kyverno install failed"
  log "kyverno: $("$KUBECTL" -n kyverno get deploy -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' | sed 's/.*://')"
  "$KUBECTL" create namespace "$NS" >/dev/null
}

apply_policies() {
  head1 "applying policies"
  "$KUBECTL" apply -f "$LAB_POLICY" >/dev/null || die "policy apply failed"
  # A policy that never becomes Ready silently does nothing. Assert readiness.
  local n=0
  for _ in $(seq 1 40); do
    n="$("$KUBECTL" get clusterpolicy -o json | python3 -c \
      'import json,sys;d=json.load(sys.stdin);print(sum(1 for i in d["items"] if any(c.get("type")=="Ready" and c.get("status")=="True" for c in i.get("status",{}).get("conditions",[]))))')"
    [[ "$n" -ge 4 ]] && break
    sleep 4
  done
  "$KUBECTL" get clusterpolicy --no-headers -o custom-columns='N:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status' | sed 's/^/  /'
  [[ "$n" -ge 4 ]] || die "only ${n}/4 policies Ready - webhooks would not fire"
}

# ---------------------------------------------------------------------------
# Test primitives
# ---------------------------------------------------------------------------
POD_CTX='
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    seccompProfile:
      type: RuntimeDefault'

C_CTX='
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        privileged: false
        capabilities:
          drop: ["ALL"]'

make_pod() {
  cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $1
  namespace: ${NS}
spec:${3}
  restartPolicy: Never
  containers:
    - name: app
      image: $2${4}
YAML
}

# expect <case> <admit|deny> <expected-policy-name-regex|''> <manifest>
#
# CRITICAL: a non-zero kubectl exit is NOT evidence of an admission denial.
# A bad flag, an unreachable apiserver, or malformed YAML also exits non-zero.
# An earlier version of this function treated every failure as "denied", so a
# client-side flag error reported a working control - the same fail-open shape
# as the policy bugs this script exists to catch. A denial is only counted when
# the admission webhook actually says so.
expect() {
  local name="$1" want="$2" why="$3" manifest="$4"
  local out rc=0
  out="$(printf '%s' "$manifest" | "$KUBECTL" apply --dry-run=server -f - 2>&1)" || rc=$?

  local got
  if [[ $rc -eq 0 ]]; then
    got="admit"
  elif grep -qiE 'admission webhook .* denied the request|denied the request' <<<"$out"; then
    got="deny"
  else
    # Neither admitted nor denied by policy: the harness itself is broken.
    # Surface it loudly instead of scoring it.
    ERRORS=$((ERRORS+1))
    printf '  %sERROR%s %-44s harness failure, not a policy result\n' "$Y" "$N" "$name"
    printf '%s\n' "$out" | tr '\n' ' ' | cut -c1-220 | sed 's/^/          /'; echo
    RESULTS+=("ERROR|${name}|${want}|error|$(tr '\n' ' ' <<<"$out" | cut -c1-160)")
    return 0
  fi

  local ok=1 detail=""
  if [[ "$got" != "$want" ]]; then
    ok=0; detail="expected ${want}, got ${got}"
  elif [[ "$want" == "deny" && -n "$why" ]] && ! grep -qiE -- "$why" <<<"$out"; then
    ok=0; detail="denied by the wrong policy (expected /${why}/)"
  fi

  if [[ $ok -eq 1 ]]; then
    PASS=$((PASS+1)); printf '  %sPASS%s  %-44s %s\n' "$G" "$N" "$name" "${D}${got}${N}"
    RESULTS+=("PASS|${name}|${want}|${got}|")
  else
    FAIL=$((FAIL+1)); printf '  %sFAIL%s  %-44s %s\n' "$R" "$N" "$name" "$detail"
    printf '%s\n' "$out" | tr '\n' ' ' | cut -c1-300 | sed 's/^/          /'; echo
    RESULTS+=("FAIL|${name}|${want}|${got}|${detail}")
  fi
}

run_matrix() {
  head1 "admission test matrix (mode=${MODE})"
  local APPROVED="${TEST_IMAGE_PREFIX}/approved/static"
  local MIRROR="${TEST_IMAGE_PREFIX}/mirror/static"
  local DIGEST
  DIGEST="$(oras resolve "${APPROVED}:current" 2>/dev/null || true)"
  [[ -n "$DIGEST" ]] || die "cannot resolve ${APPROVED}:current - has the pipeline run?"
  log "subject: ${APPROVED}@${DIGEST:0:26}..."

  # 1. Happy path: expected signer identity, digest reference, hardened context.
  expect "approved + digest + signed + hardened" admit "" \
    "$(make_pod good "${APPROVED}@${DIGEST}" "$POD_CTX" "$C_CTX")"

  # 2. Upstream Chainguard is signed by Chainguard and entirely trustworthy -
  #    and still denied, because it never passed OUR gate. Most-misunderstood rule.
  expect "upstream cgr.dev direct" deny "golden-image-registry-allowlist" \
    "$(make_pod upstream "cgr.dev/chainguard/static:latest" "$POD_CTX" "$C_CTX")"

  # 3. mirror/ holds ungated images by definition.
  expect "mirror/ quarantine" deny "golden-image-registry-allowlist" \
    "$(make_pod mirrored "${MIRROR}@${DIGEST}" "$POD_CTX" "$C_CTX")"

  # 4. Tag not digest. Expected ADMIT, and that is not a gap in the policy - it
  #    is a structural property of Kyverno that this test discovered:
  #    verifyDigest:true resolves and appends the digest during verification, so
  #    every validating webhook downstream sees ...:current@sha256:... and the
  #    digest condition is already satisfied. mutateDigest:false does not change
  #    it. Confirmed by dumping the post-admission object.
  #
  #    The runtime guarantee holds (verified bytes run). What admission cannot
  #    enforce is that the MANIFEST records the digest - see case 4b, and the
  #    KNOWN LIMITATION note on golden-image-require-digest.
  expect "approved/ by tag (digest pinned by Kyverno)" admit "" \
    "$(make_pod bytag "${APPROVED}:current" "$POD_CTX" "$C_CTX")"

  # 4b. The manifest-hygiene control, enforced where it actually works: against
  #     raw manifests in CI, before any admission webhook can mutate them.
  #     This is the SOX-relevant half - a reviewer must be able to see the digest.
  if command -v "$KUBECTL" >/dev/null && kyverno version >/dev/null 2>&1; then
    local mf="${WORK}/tagged-pod.yaml"
    make_pod bytag "${APPROVED}:current" "$POD_CTX" "$C_CTX" > "$mf"
    if kyverno apply "$POLICY_SRC" --resource "$mf" 2>&1 | grep -qi 'fail'; then
      PASS=$((PASS+1)); printf '  %sPASS%s  %-44s %s\n' "$G" "$N" \
        "manifest hygiene: tag rejected pre-merge" "${D}deny${N}"
      RESULTS+=("PASS|manifest hygiene: tag rejected pre-merge|deny|deny|")
    else
      FAIL=$((FAIL+1)); printf '  %sFAIL%s  %-44s %s\n' "$R" "$N" \
        "manifest hygiene: tag rejected pre-merge" "kyverno CLI did not flag it"
      RESULTS+=("FAIL|manifest hygiene: tag rejected pre-merge|deny|admit|kyverno CLI did not flag it")
    fi
  else
    SKIP=$((SKIP+1))
    log "skip manifest-hygiene case: kyverno CLI not installed (this is the CI-side control)"
  fi

  # 5-8. Runtime hardening: the half a Dockerfile cannot enforce.
  expect "no securityContext" deny "golden-image-runtime-hardening" \
    "$(make_pod nosc "${APPROVED}@${DIGEST}" "" "")"

  expect "writable root filesystem" deny "golden-image-runtime-hardening" \
    "$(make_pod rwroot "${APPROVED}@${DIGEST}" "$POD_CTX" '
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: false
        capabilities:
          drop: ["ALL"]')"

  expect "capabilities not dropped" deny "golden-image-runtime-hardening" \
    "$(make_pod caps "${APPROVED}@${DIGEST}" "$POD_CTX" '
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          add: ["NET_ADMIN"]')"

  # CIS Docker 4.1 verified by the kubelet, not trusted from image metadata.
  expect "runAsUser 0 (root)" deny "golden-image-runtime-hardening" \
    "$(make_pod asroot "${APPROVED}@${DIGEST}" '
  securityContext:
    runAsNonRoot: false
    runAsUser: 0
    seccompProfile:
      type: RuntimeDefault' "$C_CTX")"

  # 9. An image in approved/ this workflow never signed must not be admitted.
  local UNSIGNED="${TEST_IMAGE_PREFIX}/approved/never-signed"
  if oras resolve "${UNSIGNED}:current" >/dev/null 2>&1; then
    SKIP=$((SKIP+1)); log "skip unsigned case (repo unexpectedly exists)"
  else
    expect "unsigned image in approved/" deny "" \
      "$(make_pod unsigned "${UNSIGNED}@${DIGEST}" "$POD_CTX" "$C_CTX")"
  fi
}

report() {
  head1 "result"
  printf '  passed %s%d%s   failed %s%d%s   errors %s%d%s   skipped %d\n\n' \
    "$G" "$PASS" "$N" \
    "$([[ $FAIL -gt 0 ]] && printf '%s' "$R" || printf '%s' "$G")" "$FAIL" "$N" \
    "$([[ $ERRORS -gt 0 ]] && printf '%s' "$Y" || printf '%s' "$G")" "$ERRORS" "$N" "$SKIP"
  if [[ $ERRORS -gt 0 ]]; then
    printf '  %sharness errors present - results are NOT a statement about the policy%s\n\n' "$Y" "$N"
  fi

  mkdir -p "${ROOT_DIR}/evidence"
  local ev="${ROOT_DIR}/evidence/admission-test-$(date -u +%Y%m%dT%H%M%SZ).json"
  python3 - "$ev" "$MODE" "$TEST_IMAGE_PREFIX" "$TEST_SIGNER_REF" \
    "$PASS" "$FAIL" "$SKIP" "$ERRORS" "${RESULTS[@]}" <<'PY'
import json, sys, datetime
ev, mode, img, ref, p, f, s, e = sys.argv[1:9]
rows = []
for r in sys.argv[9:]:
    st, name, want, got, detail = (r.split("|") + [""]*5)[:5]
    rows.append({"status": st, "case": name, "expected": want,
                 "actual": got, "detail": detail})
json.dump({"kind": "admission-control-test/v1",
           "timestamp": datetime.datetime.now(datetime.timezone.utc)
                        .strftime("%Y-%m-%dT%H:%M:%SZ"),
           "mode": mode, "image_prefix": img, "signer_ref": ref,
           "summary": {"passed": int(p), "failed": int(f), "skipped": int(s),
                       "harness_errors": int(e)},
           "cases": rows,
           "controls_exercised": ["PCI-DSS-2.2", "PCI-DSS-6.3.2", "CIS-Docker-4.1",
                                  "NIST-SI-7", "NIST-800-190-4.4",
                                  "FedRAMP-CM-7", "FedRAMP-AC-6"]},
          open(ev, "w"), indent=2)
print(f"  evidence: {ev}")
PY

  if [[ "$KEEP" == "1" ]]; then
    printf '\n  cluster kept. inspect with:\n'
    printf '    %s get clusterpolicy\n    %s get polr -A\n' "$KUBECTL" "$KUBECTL"
    printf '    %s -n kyverno logs -l app.kubernetes.io/component=admission-controller --tail=50\n' "$KUBECTL"
    printf '    kind delete cluster --name %s\n' "$CLUSTER"
  fi
  [[ $FAIL -eq 0 && $ERRORS -eq 0 ]]
}

preflight
build_lab_policy
setup_cluster
apply_policies
run_matrix
report
