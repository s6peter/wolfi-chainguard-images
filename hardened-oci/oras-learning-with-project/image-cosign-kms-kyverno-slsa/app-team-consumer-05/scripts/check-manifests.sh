#!/usr/bin/env bash
# =============================================================================
# check-manifests.sh - the pre-merge gate that admission control cannot be
#
# WHY THIS SCRIPT EXISTS
#
# Admission control cannot enforce "the manifest carries a digest". Kyverno's
# verifyDigest resolves and appends the digest during image verification, so by
# the time any validating webhook runs, a tag reference already looks digest-
# pinned. Measured, not assumed - see the KNOWN LIMITATION note on
# golden-image-require-digest.
#
# The consequence: the only place this control can live is here, in CI, against
# raw YAML, before anything has had a chance to mutate it.
#
# The property being protected is reviewability. If the manifest says :current,
# a reviewer approving the PR cannot see which build they approved, and the tag
# may resolve differently at each admission. That is the SOX-relevant half of
# digest pinning, and it is invisible at runtime.
#
# Usage:  ./scripts/check-manifests.sh [dir]        (default: k8s/)
# =============================================================================
set -Eeuo pipefail

DIR="${1:-k8s}"
if [[ -t 1 ]]; then R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; N=$'\033[0m'
else R=""; G=""; Y=""; D=""; N=""; fi

command -v python3 >/dev/null || { echo "python3 required"; exit 1; }

python3 - "$DIR" <<'PY'
import sys, os, re, glob
d = sys.argv[1]
files = sorted(glob.glob(os.path.join(d, "**", "*.y*ml"), recursive=True))
if not files:
    print(f"no manifests found under {d}/"); sys.exit(1)

# Match `image:` values in pod specs. Deliberately textual rather than a YAML
# parse: a Helm template or kustomize overlay is not valid YAML but still needs
# checking, and this must never silently skip a file it cannot parse.
IMAGE = re.compile(r'^\s*-?\s*image:\s*["\']?([^"\'\s#]+)', re.M)
PLACEHOLDER = re.compile(r'@sha256:0{64}$')

fails, checked = [], 0
for f in files:
    for m in IMAGE.finditer(open(f).read()):
        ref, checked = m.group(1), checked + 1
        line = open(f).read()[:m.start()].count("\n") + 1
        if "{{" in ref or "${" in ref:
            print(f"  skip  {f}:{line}  templated: {ref}")
            continue
        if PLACEHOLDER.search(ref):
            # CI rewrites this before deploy; flagging it would block every PR.
            print(f"  todo  {f}:{line}  CI placeholder digest (rewritten at deploy)")
            continue
        if "@sha256:" not in ref:
            fails.append((f, line, ref, "no digest - tag references are not reviewable"))
        elif re.search(r':latest@|:current@', ref):
            # tag+digest is fine and encouraged: the digest resolves, the tag
            # documents which stream it came from.
            print(f"  ok    {f}:{line}  {ref.split('@')[0]}@{ref.split('@')[1][:19]}...")
        else:
            print(f"  ok    {f}:{line}  {ref.split('@')[0]}@{ref.split('@')[1][:19]}...")

print()
if fails:
    for f, line, ref, why in fails:
        print(f"  FAIL  {f}:{line}\n        {ref}\n        {why}")
    print(f"\n{len(fails)} of {checked} image reference(s) not digest-pinned")
    print("Fix with: ./scripts/get-approved-base.sh <key>   (base images)")
    print("          or let CI rewrite the app image digest at build time")
    sys.exit(1)
print(f"all {checked} image reference(s) acceptable")
PY
