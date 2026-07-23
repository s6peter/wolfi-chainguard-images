# 02 — SBOM Generation & Formats

An SBOM is only useful if it is complete, generated at the right moment, in a
format the platform can normalize, and versioned per build. This document covers
what a good SBOM contains, CycloneDX vs SPDX, where to generate, and how to
manage SBOMs over an artifact's life.

---

## 1. What a useful SBOM contains

| Field | Why it matters |
|-------|----------------|
| Component name + **version** | The join key for CVE correlation |
| **Package URL (purl)** | Canonical, ecosystem-aware identity (`pkg:npm/lodash@4.17.21`) |
| Cryptographic **hashes** | Integrity; matching runtime binaries |
| **License** | License compliance (big deal in regulated orgs) |
| **Dependency relationships** | Transitive impact ("who pulls in libX?") |
| Supplier / author | Provenance and vendor risk |
| Component **type** (lib/app/OS pkg/container) | Scoping queries |

A component without a version or purl is nearly useless for security — insist on
both.

## 2. CycloneDX vs SPDX

Both are supported OCI/ISO-aligned standards. Support **both** on ingest; pick a
**primary** for your own generation.

| Dimension | CycloneDX | SPDX |
|-----------|-----------|------|
| Origin | OWASP | Linux Foundation / ISO 5962 |
| Strength | Security-first: VEX, vuln data, purls, services | License/compliance-first, broad legal adoption |
| VEX support | Native, first-class | Via profiles/extensions |
| Common in | AppSec tooling (Dependency-Track native) | Compliance, legal, government (EO 14028) |
| Formats | JSON, XML, protobuf | JSON, tag-value, RDF, YAML |

**Practical recommendation for a security platform:** generate **CycloneDX JSON**
as primary (best VEX + vulnerability model, native to Dependency-Track), and be
able to **ingest and emit SPDX** for compliance/legal and partners who require
it. See samples:
- [../examples/sbom/app.cyclonedx.json](../examples/sbom/app.cyclonedx.json)
- [../examples/sbom/app.spdx.json](../examples/sbom/app.spdx.json)

## 3. Where to generate — and generate more than once

The same artifact yields different SBOMs at different lifecycle points. Capture
several and reconcile them:

| Stage | SBOM type | Catches |
|-------|-----------|---------|
| **Source** | dependency-manifest SBOM (lockfiles) | declared deps, quick PR feedback |
| **Build** | build-time SBOM | what actually got compiled/bundled |
| **Image** | **container-image SBOM** (Syft/Trivy on the final image) | *everything present in the shipped artifact* — the authoritative one |
| **Runtime** | runtime inventory | what is actually loaded/installed in the running pod |

The **image SBOM is authoritative** for "what did we ship." The runtime inventory
is what [07-runtime-sbom-drift.md](07-runtime-sbom-drift.md) reconciles against
it. Source SBOMs miss vendored/base-image content; image SBOMs catch it.

### Generation commands

```bash
# CycloneDX JSON from a built image (authoritative image SBOM)
syft registry.acme.internal/payments-api@sha256:... -o cyclonedx-json > app.cyclonedx.json

# SPDX JSON (for compliance/partners)
syft registry.acme.internal/payments-api@sha256:... -o spdx-json > app.spdx.json

# Trivy alternative (also does SBOM + scan)
trivy image --format cyclonedx --output app.cdx.json registry.acme.internal/payments-api@sha256:...
```

apko/melange builds emit SBOMs natively at build time — prefer those where the
image is built declaratively (see the `hardened-oci` sibling project).

## 4. SBOM management over an artifact's life

An SBOM is not write-once. Manage it as versioned data:

- **Version per build.** Key SBOMs by `(artifact, digest, build-id)`. Never
  overwrite; the platform keeps history for "what did prod look like on date X?"
- **Merge with discipline.** Combining SBOMs (e.g. app + base image) must
  preserve component provenance; merge on purl+hash, not name alone.
- **Enrich, don't mutate.** CVE and VEX data are layered *on top of* the SBOM in
  the platform, not edited into the original signed document.
- **Bind to the artifact.** The authoritative SBOM is the one **attested to the
  image** (doc 04); loose files are conveniences, the attestation is truth.

## 5. Quality gates on SBOMs themselves

A platform should reject or flag low-quality SBOMs on ingest:

- [ ] Every component has a version and a purl.
- [ ] Hashes present for binary components.
- [ ] Dependency relationships populated (not a flat bag).
- [ ] Generated against the **image**, not just source lockfiles.
- [ ] Attested to a known artifact digest (not orphaned).

Track an "SBOM quality score" per artifact; low scores are a supply-chain risk in
their own right (you can't answer impact questions you have no data for).

---

**Next:** [03 — SBOM Management Platform](03-sbom-management-platform.md)
