# 01 — What is ORAS?

**ORAS** stands for **OCI Registry As Storage**. It is a CNCF project — a CLI
(`oras`) and Go libraries (`oras-go`) — that lets you push, pull, attach, and
discover **arbitrary artifacts** in any OCI-compliant registry, not just
container images.

---

## 1. The core idea

Container registries are extremely good at what they do: content-addressed,
layered, replicated, access-controlled storage with a mature ecosystem
(Harbor, ECR, GCR/Artifact Registry, ACR, GHCR, Docker Hub, Zot). ORAS asks:
*if you already run a registry, why stand up separate storage for all the other
artifacts in your supply chain?*

```text
Before ORAS:                          With ORAS:
  images        → registry              images        ┐
  SBOMs         → S3 bucket             SBOMs          │
  signatures    → some DB              signatures      ├─▶ ONE OCI registry
  provenance    → CI artifacts         provenance      │   (content-addressed,
  Helm charts   → chart museum         Helm/WASM/etc.  ┘    signed, replicated)
```

Everything becomes a first-class, content-addressed OCI object with a digest, so
it inherits the registry's integrity, replication, retention, and RBAC.

## 2. What problem it solves in a supply-chain program

The evidence a secure supply chain generates — SBOMs, signatures, VEX,
provenance — has to *live somewhere trustworthy and be findable*. ORAS provides
the canonical answer: **store it in the registry, next to the artifact it
describes, linked by the OCI Referrers API.**

That single decision means:

- **One source of truth.** The image and everything about it live together.
- **Discoverability.** Given an image digest, you can ask the registry "what SBOM
  / signature / provenance is attached?" — no external index required.
- **Portability.** `oras cp` promotes an artifact *and its attachments* across
  registries (dev → prod, or into an air-gapped zone).
- **Uniform trust & access.** Registry auth, replication, and immutability apply
  to attestations exactly as they do to images.

## 3. ORAS vs adjacent tools

| Tool | Role | Relationship to ORAS |
|------|------|----------------------|
| `docker`/`podman` | Build & run **images** | ORAS handles *non-image* artifacts they can't |
| `cosign` | Sign & attest images | Stores signatures/attestations in the registry using the **same referrers mechanics** ORAS exposes generally |
| `crane` | Low-level image/registry ops | Overlaps on registry plumbing; ORAS is artifact-oriented |
| Helm (OCI) | Package charts | Charts are OCI artifacts; ORAS can push/pull them too |
| Registry (Harbor/Zot/ECR…) | The storage itself | ORAS is a *client*; the registry must support OCI 1.1 (or tag fallback) |

Key mental model: **`cosign` is a specialized referrers client for signatures and
attestations; ORAS is the general-purpose referrers client for any artifact.**
They coexist — cosign for signing, ORAS when you need to store/move arbitrary
things or inspect the raw referrers graph.

## 4. Where it fits in this program

- [`../../hardened-oci`](../../../hardened-oci) produces hardened images **and**
  their SBOM/provenance. ORAS (and cosign) place those in the registry.
- [`../../sbom-security-platform`](../../sbom-security-platform) **discovers and
  pulls** them from the registry to ingest, verify, and monitor.
- ORAS is the shared plumbing — covered concretely in
  [04-integration.md](04-integration.md).

## 5. When you do (and don't) need ORAS directly

**Reach for ORAS when you:**
- store non-image artifacts in a registry (config bundles, ML models, WASM),
- attach custom artifact types (custom scan reports, internal metadata) to an
  image via referrers,
- need to inspect or copy the raw referrers graph,
- move artifacts + their attachments between registries / into air-gap.

**You may not touch ORAS directly when:**
- `cosign` already handles your signing/SBOM/provenance attach+verify (it does
  the referrers work for you) — but it's still ORAS-shaped underneath, and
  understanding ORAS makes cosign's registry behavior legible.

---

**Next:** [02 — Core Concepts](02-core-concepts.md)
