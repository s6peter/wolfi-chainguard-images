# 02 — Core Concepts

To master ORAS you need a working model of how OCI registries store things. This
document builds that model bottom-up: blobs → manifests → media/artifact types →
the Referrers API. Everything ORAS does is a manipulation of these.

---

## 1. Content-addressed blobs

A registry stores **blobs** — opaque byte streams — each identified by the
**digest** of its content (`sha256:…`). Same bytes ⇒ same digest ⇒ stored once.
Your SBOM file, a config, an image layer: all blobs.

## 2. Manifests tie blobs together

A **manifest** is a small JSON document that references blobs by digest and gives
them meaning. The OCI **image manifest** has three relevant parts:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.cyclonedx+json",     // what KIND of artifact this is
  "config": { "mediaType": "...", "digest": "sha256:...", "size": 0 },
  "layers": [                                            // the actual payload blobs
    { "mediaType": "application/json", "digest": "sha256:...", "size": 1234,
      "annotations": { "org.opencontainers.image.title": "app.cyclonedx.json" } }
  ],
  "subject": { "mediaType": "...", "digest": "sha256:..." },  // OPTIONAL: what this refers to
  "annotations": { "org.opencontainers.image.created": "2026-07-22T00:00:00Z" }
}
```

Two fields are the heart of ORAS:

- **`artifactType`** — declares *what this artifact is* (e.g.
  `application/vnd.cyclonedx+json` for an SBOM). This is how you query for "all
  SBOMs" vs "all signatures".
- **`subject`** — declares *what this artifact is about*. When set, this manifest
  is a **referrer** of the subject (e.g. an SBOM whose subject is an image).

## 3. Media types & artifact types

- **`mediaType`** is the format of a blob/manifest (`application/json`,
  `application/yaml`, image layer types…).
- **`artifactType`** is the semantic kind of the whole artifact. You choose it.
  Conventions worth reusing:

| Artifact | Conventional `artifactType` |
|----------|------------------------------|
| CycloneDX SBOM | `application/vnd.cyclonedx+json` |
| SPDX SBOM | `application/spdx+json` |
| in-toto/SLSA attestation | `application/vnd.in-toto+json` |
| cosign signature | `application/vnd.dev.cosign.artifact.sig.v1+json` |
| Custom scan report | `application/vnd.acme.scan-report.v1+json` |

Pick stable types; the platform's discovery/filtering depends on them.

## 4. The Referrers API — the key concept

Introduced in **OCI Distribution Spec 1.1**, the Referrers API answers:

> "Given subject digest X, what artifacts have been attached to it?"

When you `oras attach` an SBOM to an image, ORAS creates a manifest whose
`subject` is that image's digest. Later, `oras discover` (or the registry's
`/v2/<name>/referrers/<digest>` endpoint) returns the graph of everything
pointing at that subject.

```text
                          image @sha256:AAA   (the subject)
                                 ▲   ▲   ▲
              subject=AAA ───────┘   │   └─────── subject=AAA
        SBOM manifest         signature manifest        provenance manifest
        artifactType=cyclonedx  artifactType=cosign.sig  artifactType=in-toto
```

You can even attach to a referrer (an attestation *about a signature*), forming a
graph — which is what tools like GUAC walk.

### Referrers fallback (older registries)

If a registry doesn't yet implement the Referrers **API**, the spec defines a
**tag schema fallback**: referrers are found via a predictable tag
(`sha256-<subject-digest>`). ORAS handles this automatically. Check your
registry: Zot, Harbor (recent), ECR, GHCR, ACR, GCR/Artifact Registry support
the Referrers API; some older/self-hosted ones rely on the fallback.

## 5. Reference forms — tag vs digest

- **Tag:** `registry/repo:tag` — mutable, human-friendly.
- **Digest:** `registry/repo@sha256:…` — immutable, the security-critical form.

**Always attach and verify by digest.** A tag can move; you want the SBOM bound
to the exact bytes you shipped. (This mirrors the deploy-by-digest rule in both
sibling projects.)

## 6. How the ORAS verbs map to the concepts

| Verb | What it does at the manifest level |
|------|-------------------------------------|
| `oras push` | Creates a new artifact manifest + uploads its blobs |
| `oras pull` | Fetches an artifact manifest and downloads its blobs |
| `oras attach` | Creates a manifest with `subject` set → a **referrer** |
| `oras discover` | Reads the Referrers API for a subject digest |
| `oras manifest fetch` | Prints the raw manifest JSON |
| `oras cp` | Copies an artifact (optionally with `-r`, its referrers) across registries |

---

**Next:** [03 — Step-by-Step Mastery](03-step-by-step-mastery.md)
