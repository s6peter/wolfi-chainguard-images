# Golden Image Catalog

The organization's blessed, pre-hardened base images. Application teams build
`FROM` these (by digest) and inherit their hardening. Owned and rebuilt by
Platform Security.

> This is a **template catalog**. Replace registry paths, digests, and owners
> with your organization's real values. Digests below are placeholders
> (`sha256:REPLACE_ME`) and MUST be filled with actual, verified digests.

---

## How to consume a golden image

```dockerfile
# Always pin by digest, never by tag alone.
FROM registry.acme.internal/golden/jre21@sha256:REPLACE_ME
```

Look up the current digest for a tag before pinning:

```bash
crane digest registry.acme.internal/golden/jre21:1.4.2
# or
cosign verify registry.acme.internal/golden/jre21:1.4.2 \
  --certificate-identity-regexp 'https://github.com/acme/golden-images/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Catalog

| Golden image | Upstream basis | Use case | Non-root UID | Shell | Rebuild SLA |
|--------------|----------------|----------|:------------:|:-----:|:-----------:|
| `golden/static` | `cgr.dev/chainguard/static` | Static Go/Rust binaries | 65532 | none | weekly |
| `golden/jre21` | Chainguard JRE 21 | JVM services | 65532 | none | weekly |
| `golden/node20` | Chainguard Node 20 | Node.js services | 65532 | none | weekly |
| `golden/python312` | Chainguard Python 3.12 | Python services | 65532 | none | weekly |
| `golden/nginx` | Chainguard nginx | Static/reverse proxy | 65532 | none | weekly |

Each entry, when published, carries: pinned digest, SBOM attestation, cosign
signature, SLSA provenance, and a last-rebuilt timestamp.

## Catalog entry contract

Every golden image published to the catalog MUST:

- be built from an approved upstream (per [base-image-policy.md](base-image-policy.md)),
- contain no shell or package manager in the runtime layer,
- declare a numeric non-root user,
- ship SBOM + signature + SLSA provenance,
- be rebuilt on its SLA cadence **and** on any relevant upstream CVE fix,
- be versioned; the previous digest remains pullable until downstreams migrate.

## Lifecycle of a golden image

```text
upstream CVE fix / weekly tick
        │
        ▼
 rebuild golden base ──▶ SBOM + scan + sign + provenance ──▶ publish new digest
        │                                                          │
        │                                    notify downstream owners (new digest)
        ▼                                                          ▼
 catalog updated                                downstream images rebuild FROM new digest
```

## Requesting a new golden image

Open a request to Platform Security including: language/runtime + version,
expected workloads, and any special runtime needs (writable paths, certs,
locale/timezone data). Platform Security builds, hardens, and publishes it, then
adds the row above.
