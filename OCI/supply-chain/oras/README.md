# ORAS — OCI Registry As Storage

**ORAS** (OCI Registry As Storage) lets you use any OCI-compliant container
registry as **general-purpose artifact storage** — not just for images, but for
SBOMs, signatures, provenance attestations, Helm charts, WASM modules, config
bundles, ML models, and arbitrary files. It is a CNCF project providing a CLI
(`oras`) and libraries (`oras-go`).

This project explains what ORAS is, gives a **step-by-step guide to master it**,
and shows **how it ties the other two projects together** — because ORAS and the
OCI **Referrers API** are the mechanism by which the SBOMs and attestations that
[`../hardened-oci`](../../hardened-oci) produces get stored, discovered, and
consumed by [`../sbom-security-platform`](../sbom-security-platform).

---

## Why ORAS matters here

The other two projects assume a registry can hold *more than images*:

- A hardened image is pushed to a registry, and its **SBOM + signature +
  provenance are attached to it** as related artifacts.
- The SBOM platform **discovers and pulls those attachments** from the registry
  to ingest and verify them.

That "attach an artifact to an image, then discover it later" pattern **is** the
OCI Referrers API — and ORAS is the general-purpose tool for it. `cosign` uses
the same registry mechanics under the hood; ORAS is what you reach for when you
want to store or move *any* artifact type yourself.

```text
                      ┌──────────── OCI Registry ────────────┐
 hardened-oci ──push──▶ image @sha256:...                     │
                      │      ▲ subject                         │
                      │      ├── SBOM (referrer)      ┐         │
                      │      ├── signature (referrer) ├ ORAS   │──discover/pull──▶ sbom-security-platform
                      │      └── provenance (referrer)┘  attach │
                      └───────────────────────────────────────┘
```

## What you can do with ORAS

| Capability | Command | Use in this program |
|------------|---------|---------------------|
| Push any file(s) as an OCI artifact | `oras push` | Store SBOMs, configs, bundles in the registry |
| Pull an artifact back | `oras pull` | Retrieve stored artifacts by reference |
| Attach an artifact to a subject | `oras attach` | Bind an SBOM/VEX/scan to an image (Referrers API) |
| Discover what's attached | `oras discover` | Find an image's SBOM/signature/provenance |
| Inspect/copy manifests | `oras manifest`, `oras cp` | Promote artifacts across registries |
| Authenticate | `oras login` | Registry access (pairs with workload identity) |

## How to navigate

| Path | Covers |
|------|--------|
| [docs/01-what-is-oras.md](docs/01-what-is-oras.md) | What ORAS is, why it exists, where it fits |
| [docs/02-core-concepts.md](docs/02-core-concepts.md) | OCI artifacts, manifests, media types, the Referrers API |
| [docs/03-step-by-step-mastery.md](docs/03-step-by-step-mastery.md) | Hands-on, level-by-level guide from install to CI |
| [docs/04-integration.md](docs/04-integration.md) | Wiring ORAS into hardened-oci and sbom-security-platform |
| [docs/learning-path.md](docs/learning-path.md) | Skills checklist / mastery levels |
| [examples/](examples/) | Runnable push / pull / attach / discover scripts + CI |

## Quick start

```bash
# 1. Push a file to a registry as an OCI artifact.
oras push registry.acme.internal/configs:v1 \
  --artifact-type application/vnd.acme.config \
  app-config.yaml:application/yaml

# 2. Attach an SBOM to an existing image (Referrers API).
oras attach --artifact-type application/vnd.cyclonedx+json \
  registry.acme.internal/payments-api@sha256:... \
  app.cyclonedx.json:application/json

# 3. Discover what's attached to that image.
oras discover registry.acme.internal/payments-api@sha256:...
```

Full, explained versions are in [examples/](examples/).

## Related projects

- [`../hardened-oci`](../../hardened-oci) — builds the hardened images ORAS
  distributes and attaches SBOMs to.
- [`../sbom-security-platform`](../sbom-security-platform) — discovers and
  ingests those attached SBOMs/attestations via ORAS/Referrers.

## Scope

A learning + reference project with adaptable artifacts. Examples use
`registry.acme.internal` and placeholder digests — substitute your own and
confirm your registry supports the Referrers API (OCI 1.1) or the tag fallback.
