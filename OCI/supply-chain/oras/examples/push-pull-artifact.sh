#!/usr/bin/env bash
# Push an arbitrary file to a registry as an OCI artifact, then pull it back.
# Covers mastery Steps 1-3. Great first thing to run against a local registry.
#
# Local practice registry (no auth):
#   docker run -d -p 5000:5000 --name zot ghcr.io/project-zot/zot-linux-amd64:latest
#   export REG=localhost:5000
#
# Usage:
#   REG=localhost:5000 ./push-pull-artifact.sh
#
# Requires: oras.

set -euo pipefail
REG="${REG:?set REG, e.g. localhost:5000 or registry.acme.internal}"
REPO="${REPO:-playground/demo}"
TAG="${TAG:-v1}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "demo payload $(date -u +%FT%TZ 2>/dev/null || echo static)" > "$WORK/notes.txt"
printf 'owner: platform-security\nkind: demo\n' > "$WORK/config.yaml"

echo ">> Pushing artifact to $REG/$REPO:$TAG"
oras push "$REG/$REPO:$TAG" \
  --artifact-type application/vnd.acme.demo \
  --annotation "acme.owner=platform-security" \
  "$WORK/notes.txt:text/plain" \
  "$WORK/config.yaml:application/yaml"

echo ">> Manifest:"
oras manifest fetch "$REG/$REPO:$TAG" --pretty

echo ">> Pulling it back into ./pulled"
rm -rf ./pulled && mkdir -p ./pulled
oras pull "$REG/$REPO:$TAG" -o ./pulled
ls -l ./pulled

echo ">> Done. You used a container registry as generic artifact storage."
