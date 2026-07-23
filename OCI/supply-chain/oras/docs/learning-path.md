# ORAS Learning Path

A condensed skills checklist mapped to the hands-on steps in
[03-step-by-step-mastery.md](03-step-by-step-mastery.md). Use it to track your
progress from novice to production-ready.

```text
L0 Aware ─▶ L1 Basic I/O ─▶ L2 Referrers ─▶ L3 Portability ─▶ L4 Production
 knows what   push/pull     attach/discover  cp -r, air-gap    CI + identity + graph
 ORAS is      artifacts     evidence         promotion         + cosign interplay
```

---

## Level 0 — Aware
- [ ] Can explain "OCI Registry As Storage" in one sentence.
- [ ] Knows the difference between an image and a generic OCI artifact.
- [ ] Knows ORAS relates to cosign (general vs specialized referrers client).

_Read: [01-what-is-oras.md](01-what-is-oras.md)._

## Level 1 — Basic I/O
- [ ] Installed `oras`, authenticated to a registry (Step 0).
- [ ] Pushed and pulled an arbitrary file artifact (Steps 1–2).
- [ ] Set correct `artifactType`, media types, and annotations (Step 3).
- [ ] Can read a manifest with `oras manifest fetch --pretty`.

_Concepts: blobs, manifests, media/artifact types
([02-core-concepts.md](02-core-concepts.md) §1–3)._

## Level 2 — Referrers (the key skill)
- [ ] Attached an SBOM to an image **by digest** (`oras attach`, Step 4).
- [ ] Discovered attachments (`oras discover --format tree`, Step 5).
- [ ] Pulled a referrer back given only the image ref (Step 6).
- [ ] Understands the Referrers API and the tag fallback
      ([02 §4](02-core-concepts.md)).

## Level 3 — Portability
- [ ] Copied an image **with its referrers** across registries (`oras cp -r`,
      Step 7).
- [ ] Can move evidence into an air-gapped / prod-locked registry.
- [ ] Understands why attach/verify must be by digest, not tag.

## Level 4 — Production
- [ ] Authenticates with short-lived, workload-identity credentials (Step 8).
- [ ] Automated attach in CI; verifies via `oras discover` (Step 9).
- [ ] Can walk/inspect the referrers graph on real registries (Step 10).
- [ ] Understands the ORAS↔cosign division of labor: ORAS moves bytes, cosign
      proves authenticity ([04-integration.md](04-integration.md) §4).
- [ ] Can wire ORAS into both sibling projects (integration doc).

---

## Recommended sequence for this program

1. **L0–L2** on a throwaway local registry (`zot`/`registry:2`) — fast feedback.
2. **L3** against two real registries you control.
3. **L4** inside a real pipeline, then connect to
   [`../../sbom-security-platform`](../../sbom-security-platform) ingestion and
   [`../../hardened-oci`](../../../hardened-oci) promotion.

Target for operating in this program: **Level 4**.
