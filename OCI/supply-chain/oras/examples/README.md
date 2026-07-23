# Examples — ORAS

Runnable artifacts for the [step-by-step mastery guide](../docs/03-step-by-step-mastery.md)
and the [integration doc](../docs/04-integration.md).

> Set `REG` to your registry. For zero-risk practice, run a local registry:
> `docker run -d -p 5000:5000 --name zot ghcr.io/project-zot/zot-linux-amd64:latest`
> then `export REG=localhost:5000`. Placeholders read `REPLACE_*`.

| File | Purpose | Guide step | Side |
|------|---------|-----------|------|
| [push-pull-artifact.sh](push-pull-artifact.sh) | Push & pull an arbitrary artifact | Steps 1–3 | learn |
| [attach-and-discover.sh](attach-and-discover.sh) | Attach an SBOM to an image, discover it | Steps 4–5 | producer |
| [pull-and-ingest.sh](pull-and-ingest.sh) | Discover + pull an SBOM, verify identity, hand off | Step 6 | consumer |
| [ci-attach-artifacts.yml](ci-attach-artifacts.yml) | Automate attach + sign in CI | Step 9 | producer |

## Flow these implement

```text
push-pull-artifact.sh      → learn the basic registry-as-storage mechanic
        │
attach-and-discover.sh     → PRODUCER: bind SBOM to image (hardened-oci output)
        │  (registry now holds image + evidence, by digest)
pull-and-ingest.sh         → CONSUMER: platform pulls evidence, verifies, ingests
        │
ci-attach-artifacts.yml    → do the producer step automatically on every build
```

## Try it end to end (local registry)

```bash
export REG=localhost:5000

# 1. Learn the basics
./push-pull-artifact.sh

# 2. Push a hardened image (see ../../hardened-oci) or any image, then:
IMG="$REG/payments-api@sha256:REPLACE_WITH_REAL_DIGEST"
./attach-and-discover.sh "$IMG" ../../sbom-security-platform/examples/sbom/app.cyclonedx.json

# 3. Consume it the way the platform does
./pull-and-ingest.sh "$IMG"
```

## Related

- Produce the images/SBOMs: [`../../hardened-oci`](../../../hardened-oci)
- Ingest/enforce/monitor: [`../../sbom-security-platform`](../../sbom-security-platform)
