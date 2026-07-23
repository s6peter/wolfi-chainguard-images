# 03 — Step-by-Step Mastery

A progressive, hands-on path from zero to using ORAS in a production supply-chain
pipeline. Each step has a **goal**, **commands**, and a **check** (how you know
it worked). Do them in order; each builds on the last.

Prerequisites: a working OCI registry you can push to (a local `zot` or
`registry:2` is perfect for practice), and the `oras` CLI.

Throughout, `REG=registry.acme.internal` — substitute your registry.

---

## Step 0 — Install & authenticate

**Goal:** have a working `oras` and be logged in.

```bash
# Install (Linux example). See https://oras.land for other platforms.
VERSION=1.2.0
curl -LO "https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_amd64.tar.gz"
mkdir -p oras-install && tar -zxf oras_${VERSION}_*.tar.gz -C oras-install
sudo mv oras-install/oras /usr/local/bin/ && rm -rf oras-install oras_*.tar.gz

oras version
export REG=registry.acme.internal
oras login "$REG" -u "$USER"      # prompts for password/token; use a token, not a password
```

**Check:** `oras version` prints a version ≥ 1.2; `oras login` reports success.

> Practice locally with no auth:
> `docker run -d -p 5000:5000 --name zot ghcr.io/project-zot/zot-linux-amd64:latest`
> then `export REG=localhost:5000` and skip `oras login`.

---

## Step 1 — Push your first artifact

**Goal:** store an arbitrary file in the registry as an OCI artifact.

```bash
echo "hello supply chain" > notes.txt

oras push "$REG/playground/notes:v1" \
  --artifact-type application/vnd.acme.notes \
  notes.txt:text/plain
```

**Check:**
```bash
oras manifest fetch "$REG/playground/notes:v1" --pretty
# You should see artifactType=application/vnd.acme.notes and a layer for notes.txt.
```

You just used a container registry as generic storage. That's the whole premise.

---

## Step 2 — Pull it back

**Goal:** retrieve the artifact by reference.

```bash
mkdir out && cd out
oras pull "$REG/playground/notes:v1"
cat notes.txt        # -> "hello supply chain"
cd ..
```

**Check:** the file returns byte-for-byte.

---

## Step 3 — Annotations & multiple files

**Goal:** push several files with metadata.

```bash
oras push "$REG/playground/bundle:v1" \
  --artifact-type application/vnd.acme.bundle \
  --annotation "org.opencontainers.image.created=2026-07-22T00:00:00Z" \
  --annotation "acme.owner=platform-security" \
  notes.txt:text/plain \
  ./config.yaml:application/yaml
```

**Check:** `oras manifest fetch ... --pretty` shows both layers and your
annotations. Annotations are how you carry human/machine metadata.

---

## Step 4 — Attach an artifact to a subject (Referrers API)

**Goal:** bind an SBOM to an existing image — the core supply-chain move.

```bash
# Assume you already have a hardened image pushed (see ../../hardened-oci).
IMG="$REG/payments-api@sha256:REPLACE_WITH_REAL_DIGEST"

# Generate an SBOM (or reuse ../../sbom-security-platform/examples/sbom/app.cyclonedx.json)
syft "$IMG" -o cyclonedx-json > app.cyclonedx.json

oras attach --artifact-type application/vnd.cyclonedx+json \
  "$IMG" \
  app.cyclonedx.json:application/json
```

**Check:** the command prints a new manifest digest — the SBOM manifest whose
`subject` is the image.

> **Always attach by digest**, never a tag (concepts doc §5).

---

## Step 5 — Discover what's attached

**Goal:** ask the registry what refers to an image.

```bash
oras discover "$IMG" --format tree
```

**Check:** you see the image with your CycloneDX SBOM listed under it. Add a
signature/provenance (cosign) and they show up here too — this is the unified
evidence view.

Filter by type:
```bash
oras discover "$IMG" --artifact-type application/vnd.cyclonedx+json --format json
```

---

## Step 6 — Pull a referrer back (what the platform does)

**Goal:** retrieve the attached SBOM given only the image — the ingestion path.

```bash
# Get the SBOM referrer's digest, then pull it.
SBOM_DIGEST=$(oras discover "$IMG" \
  --artifact-type application/vnd.cyclonedx+json --format json \
  | jq -r '.manifests[0].reference')

oras pull "$SBOM_DIGEST" -o ./ingest
ls ./ingest    # -> app.cyclonedx.json, ready to ingest into the platform
```

**Check:** you recovered the SBOM starting from just the image reference. This is
exactly how [`../../sbom-security-platform`](../../sbom-security-platform)
sources SBOMs from the registry.

---

## Step 7 — Copy artifacts across registries (with referrers)

**Goal:** promote an image *and its SBOM/signature* dev → prod, or into air-gap.

```bash
# -r / --recursive copies the subject AND everything attached to it.
oras cp -r "$REG/payments-api@sha256:REPLACE" \
           registry.prod.acme.internal/payments-api:1.4.2
```

**Check:** `oras discover` against the destination shows the same referrers. The
evidence travels with the artifact — critical for promotion and air-gapped
transfer.

---

## Step 8 — Authentication with workload identity (no static creds)

**Goal:** in CI, log in without a stored password.

- Most registries accept a short-lived token from your cloud/OIDC provider.
  Obtain it via workload identity (see
  [`../../sbom-security-platform/docs/06-workload-identity.md`](../../sbom-security-platform/docs/06-workload-identity.md)),
  then:

```bash
oras login "$REG" -u AWS --password-stdin <<< "$(aws ecr get-login-password)"   # ECR example (IRSA-backed)
```

**Check:** push/pull works with a credential that expires — nothing long-lived
on disk.

---

## Step 9 — Put it in CI

**Goal:** attach + push artifacts automatically on every build.

Wire the pattern into your pipeline — see
[../examples/ci-attach-artifacts.yml](../examples/ci-attach-artifacts.yml). The
job: build → SBOM → `oras attach` SBOM (and cosign sign/attest) → done. The
registry now holds the image and its evidence, discoverable by digest.

**Check:** after a pipeline run, `oras discover <image-digest>` shows the SBOM
attached automatically.

---

## Step 10 — Master the graph & fallback

**Goal:** operate confidently on real registries.

- Inspect raw manifests: `oras manifest fetch --pretty`.
- Understand your registry's referrers support (API vs tag fallback — concepts
  §4). Test: `oras discover` on a registry and confirm results.
- Attach to a referrer (attestation about a signature) and walk the graph.
- Know the artifact-type conventions your org standardizes on (concepts §3).

**Check:** you can, from an image digest alone, enumerate every piece of evidence
and pull any of it — on any of your registries.

---

## You've mastered ORAS when you can…

- [ ] Push/pull arbitrary artifacts with correct media & artifact types.
- [ ] Attach SBOM/signature/provenance to an image **by digest** via referrers.
- [ ] Discover and pull any referrer given only the image reference.
- [ ] Copy an artifact **with its referrers** across registries / into air-gap.
- [ ] Authenticate with short-lived, identity-based credentials.
- [ ] Automate attach in CI and verify via `oras discover`.
- [ ] Explain how cosign's registry behavior is the same referrers pattern.

See the condensed checklist in [learning-path.md](learning-path.md).

---

**Next:** [04 — Integration](04-integration.md)
