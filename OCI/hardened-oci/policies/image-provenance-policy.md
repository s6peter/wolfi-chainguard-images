# Image Provenance & Signing Policy

**Status:** Normative. The trust contract between the build pipeline and the
clusters. **Owner:** Platform Security.

This policy defines what provenance an image must carry and how clusters verify
it. It is enforced by the admission policies in
[../examples/kubernetes/](../examples/kubernetes/).

---

## 1. Signing

- Every released image MUST be signed with `cosign`.
- **Keyless signing** (Sigstore Fulcio/Rekor, OIDC identity) is the default and
  preferred method. The signing identity MUST be a **CI workflow identity** on a
  protected branch — not a human, not a shared long-lived key.
- If a KMS key is used instead (air-gapped environments), it MUST live in an HSM
  / cloud KMS, never in CI variables or the repo, with access audited.

## 2. Required attestations

Every released image MUST carry, as attestations attached to the image:

| Attestation | Format | Purpose |
|-------------|--------|---------|
| SBOM | SPDX or CycloneDX | Component inventory / impact analysis |
| SLSA provenance | in-toto / SLSA | Source + build integrity |

Optionally: signed vulnerability scan results.

## 3. Verification identity (the trust anchor)

Clusters MUST verify that the signature was issued to the **expected identity**,
not merely that *a* valid signature exists. Verification pins:

- **Certificate identity** — the specific CI workflow, e.g.
  `https://github.com/acme/<repo>/.github/workflows/release.yml@refs/heads/main`
  (regex allowed for repo/branch families).
- **OIDC issuer** — e.g. `https://token.actions.githubusercontent.com`.

An image signed by any other identity MUST be rejected.

## 4. Reference discipline

- Deploy by **digest** only.
- Pull only from **approved registries**.
- `:latest` and other mutable tags MUST NOT be used in committed manifests.

## 5. Enforcement

Admission control MUST, in production, **reject** any image that:
- is unsigned, or signed by an unexpected identity,
- is missing required attestations,
- comes from a non-approved registry,
- is referenced by a mutable tag.

Rollout follows audit → enforce (see
[../docs/04-kubernetes-admission-and-runtime.md](../docs/04-kubernetes-admission-and-runtime.md) §1).

---

## Waiver ledger (example schema)

Waivers are tracked as version-controlled records. Example:

```yaml
# waivers/2026-Q3.yaml
waivers:
  - id: WVR-2026-0142
    type: vulnerability            # vulnerability | policy
    scope:
      image: registry.acme.internal/orders-api
      cve: CVE-2026-12345
    reason: "Upstream fix pending; not reachable in our code path."
    compensating_control: "NetworkPolicy default-deny; no ingress from internet."
    owner: team-orders
    approved_by: security-leadership
    created: 2026-07-10
    expires: 2026-08-10             # fails closed after this date
  - id: WVR-2026-0143
    type: policy
    scope:
      image: registry.acme.internal/legacy-batch
      rule: require-digest
    reason: "Legacy vendor image; migration to golden base in progress."
    compensating_control: "Isolated namespace, restricted RBAC."
    owner: team-platform
    approved_by: security-leadership
    created: 2026-07-15
    expires: 2026-09-01
```

Expired waivers MUST NOT be honored. A scheduled job SHOULD report waivers
expiring within 14 days and any expired-but-still-referenced waivers.
