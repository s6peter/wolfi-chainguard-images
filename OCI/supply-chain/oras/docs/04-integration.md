# 04 — Integration with the Other Two Projects

ORAS is the plumbing that connects the *producer* project
([`hardened-oci`](../../../hardened-oci)) to the *manager/enforcer* project
([`sbom-security-platform`](../../sbom-security-platform)). This document shows
exactly where it fits and provides copy-adaptable commands.

---

## 1. The end-to-end picture

```text
  hardened-oci (produce)                 ORAS / Referrers                sbom-security-platform (manage+enforce)
 ┌────────────────────────┐           ┌────────────────────┐           ┌──────────────────────────────────────┐
 │ apko/Docker build       │           │  OCI Registry       │           │ discover referrers by image digest    │
 │ → image @sha256          │──push────▶│  image @sha256      │           │ → pull SBOM/provenance                 │
 │ → SBOM (CycloneDX)       │           │   ├─ SBOM (referrer) │──discover─▶│ → verify attestation identity          │
 │ → SLSA provenance        │──attach──▶│   ├─ signature       │   +pull   │ → ingest → CVE/VEX correlate → monitor │
 │ → cosign signature       │           │   └─ provenance      │           │ → admission verdict / runtime drift    │
 └────────────────────────┘           └────────────────────┘           └──────────────────────────────────────┘
```

ORAS/referrers is the **hand-off boundary**: producers write evidence next to the
image; the platform reads it back by digest. No side-channel, no separate store.

## 2. Integration with `hardened-oci` (the producer side)

`hardened-oci` builds a minimal, signed image and generates its SBOM + provenance
(its docs 02–03). ORAS is how the non-signature artifacts get attached, and how
everything gets promoted between registries.

### Attach the SBOM and provenance to the image

```bash
IMG="$REG/payments-api@sha256:REPLACE_WITH_REAL_DIGEST"

# SBOM produced by apko or syft (hardened-oci build output)
oras attach --artifact-type application/vnd.cyclonedx+json \
  "$IMG" app.cyclonedx.json:application/json

# SLSA provenance predicate
oras attach --artifact-type application/vnd.in-toto+json \
  "$IMG" provenance.json:application/json
```

> `cosign sign` / `cosign attest` write signatures & attestations using the same
> referrers mechanics — you can use cosign for those and ORAS for any additional
> artifact types. They interoperate because both target the Referrers API.

### Promote the image + all its evidence (dev → prod / air-gap)

```bash
oras cp -r "$REG/payments-api@sha256:REPLACE" \
           registry.prod.acme.internal/payments-api:1.4.2
```

This is the clean answer to "how do we move an image *and* its SBOM/signature
into the locked-down production or air-gapped registry" — a common bank/insurer
requirement (see the platform's enterprise-adoption doc).

## 3. Integration with `sbom-security-platform` (the consumer side)

The platform's **ingestion** (its doc 03 §1) can pull SBOMs straight from the
registry via referrers — a "registry as source of truth" pattern, instead of
CI pushing SBOMs to the platform API.

### Registry-pull ingestion

```bash
IMG="$REG/payments-api@sha256:REPLACE"

# 1. Discover the SBOM referrer.
SBOM_REF=$(oras discover "$IMG" \
  --artifact-type application/vnd.cyclonedx+json --format json \
  | jq -r '.manifests[0].reference')

# 2. Pull it.
oras pull "$SBOM_REF" -o ./ingest

# 3. Ingest into the platform (Dependency-Track), authenticated by workload identity.
#    (see sbom-security-platform/examples/ingestion/upload-to-dependency-track.sh)
```

See the runnable version:
[../examples/pull-and-ingest.sh](../examples/pull-and-ingest.sh).

### Which ingestion pattern to choose

| Pattern | How | When |
|---------|-----|------|
| **CI push** | CI POSTs SBOM to platform API | Tight, immediate; CI already has the SBOM |
| **Registry pull (ORAS)** | Platform discovers + pulls referrers | Decoupled; works for images built anywhere; ideal after `oras cp` promotion and for vendor images you only receive as registry refs |

Many enterprises use both: push for internal builds, pull for promoted/vendor
artifacts.

### Runtime drift uses the same source

The platform's runtime-drift check (its doc 07) needs the *build-time* SBOM to
diff against. It gets it the same way — `oras discover` + `oras pull` the SBOM
referrer for the running image's digest. One canonical SBOM, one retrieval path.

## 4. Verification still pins identity

ORAS moves bytes; it does **not** establish trust by itself. The platform and
admission control still **verify the signature/attestation identity** with cosign
(platform doc 04 §5) before trusting a pulled SBOM. ORAS + referrers answers
*"where is the evidence?"*; cosign answers *"is it authentic and from the
expected pipeline?"*. Use both.

```text
oras discover/pull  →  cosign verify-attestation (identity-pinned)  →  ingest as trusted
```

## 5. Division of labor summary

| Concern | Tool |
|---------|------|
| Build minimal hardened image | hardened-oci (apko/Docker) |
| Generate SBOM / provenance | syft / apko / build |
| Sign & attest (authenticity) | **cosign** |
| Store/attach arbitrary artifacts; move evidence between registries | **ORAS** |
| Discover & pull evidence by digest | **ORAS** (or cosign for its own types) |
| Verify identity before trust | **cosign** |
| Ingest, correlate, enforce, monitor | sbom-security-platform |

---

**Next:** [learning-path.md](learning-path.md) ·
**Related:** [`../../hardened-oci`](../../../hardened-oci) ·
[`../../sbom-security-platform`](../../sbom-security-platform)
