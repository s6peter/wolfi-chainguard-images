# 02 — Secure Image Lifecycle

An image's security is a property of its whole lifecycle, not a single scan. This
document walks the pipeline stage by stage, naming the control, the tooling, and
the gate at each step. The end state: an artifact that is minimal, signed,
attested, and verifiable from build to runtime.

```text
 SOURCE ─▶ BUILD ─▶ SBOM ─▶ SCAN ─▶ SIGN + ATTEST ─▶ STORE ─▶ ADMIT ─▶ RUN ─▶ WATCH ─▶ REBUILD
   │         │        │       │           │             │        │       │       │         │
 protected  minimal  full   gate on    keyless      immutable  verify  non-   runtime   rebuild,
 branch,    base,    deps   Crit/High  cosign +     digest,    sig +   root,  detection  never
 reviewed   pinned          fail       SLSA prov.   retention  policy  RO fs   (Falco)   patch-in-place
```

Each stage is a gate: the artifact does not advance until the stage passes. Gates
**fail closed**.

---

## Stage 1 — Source

- Build only from a **protected branch**; require review and green CI.
- No secrets in the repo or image; inject at runtime via mounted secrets/CSI.
- The commit SHA becomes part of the image's provenance and tag.

## Stage 2 — Build

Two supported build paths, both producing minimal images:

**A. Declarative (preferred) — apko + melange.**
Define the image as a package list and metadata; apko assembles a reproducible,
SBOM-carrying OCI image with no Dockerfile and no build-time shell.
See [../examples/apko/hardened-app.apko.yaml](../examples/apko/hardened-app.apko.yaml)
and [../examples/melange/example-package.melange.yaml](../examples/melange/example-package.melange.yaml).

**B. Multi-stage Dockerfile.**
Compile in a `-dev` stage, copy only the artifact into a distroless/`scratch`
final stage. See [../examples/dockerfile/Dockerfile.hardened-multistage](../examples/dockerfile/Dockerfile.hardened-multistage).

Build-stage rules:
- Pin every base by **digest**.
- Final stage has **no shell, no package manager, no build tools**.
- Set a **numeric non-root `USER`** (e.g. `65532`).
- Reproducible where possible (pinned deps, `SOURCE_DATE_EPOCH`).

## Stage 3 — SBOM generation

Generate a complete Software Bill of Materials at build time.

- Tool: `syft` (or apko's built-in SBOM), output SPDX or CycloneDX.
- The SBOM is **attached to the image as an attestation** (Stage 5), not just a
  file in CI.
- See [../examples/sbom/generate-sbom.sh](../examples/sbom/generate-sbom.sh).

The SBOM is what lets you answer "which of our 400 images contain `libxyz 1.2`?"
in minutes when the next critical CVE drops.

## Stage 4 — Vulnerability scan (release gate)

- Scan the built image with `grype` and/or `trivy` against the SBOM.
- **Gate:** no un-waived **Critical/High** vulnerabilities → build fails.
- Waivers are explicit, time-boxed, and recorded (see governance doc).
- Scanning a distroless image is fast and quiet — there is little to find.

## Stage 5 — Sign + attest

Establish cryptographic provenance:

- **Sign** the image with `cosign` — prefer **keyless** signing bound to the CI
  OIDC identity (no long-lived keys to steal).
- **Attest** the SBOM and SLSA build provenance to the image.
- All three (signature, SBOM attestation, provenance attestation) are pushed to
  the registry alongside the image.

See [../examples/signing/cosign-workflow.md](../examples/signing/cosign-workflow.md).

## Stage 6 — Store

- Push to the **private registry** by digest.
- Enable registry immutability / tag protection where available.
- Apply **retention**: keep released images and their attestations for the audit
  window; garbage-collect untagged build artifacts.

## Stage 7 — Admit (deploy-time gate)

The cluster's admission controller verifies **before scheduling**:

- Signature is valid and from the expected identity.
- Required attestations (SBOM, provenance) are present.
- Image is from an allowed registry, referenced by digest.
- Pod spec meets hardening baseline (non-root, read-only fs, dropped caps).

Unsigned or non-compliant images are **rejected**. See
[04-kubernetes-admission-and-runtime.md](04-kubernetes-admission-and-runtime.md)
and [../examples/kubernetes/](../examples/kubernetes/).

## Stage 8 — Run

Runtime hardening enforced by the Pod spec and Pod Security Standards:

- `runAsNonRoot: true`, numeric `runAsUser`.
- `readOnlyRootFilesystem: true` (mount writable `emptyDir` only where needed).
- `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`.
- `seccompProfile: RuntimeDefault`.
- Resource limits set; no `privileged`, no host namespaces, no hostPath.

See [../examples/kubernetes/deployment-hardened.yaml](../examples/kubernetes/deployment-hardened.yaml).

## Stage 9 — Watch (runtime detection)

Images go stale the moment they are built; new CVEs are disclosed daily.

- **Continuous scanning** of running images against fresh vulnerability data
  (e.g. re-scan registry images nightly).
- **Runtime threat detection** (Falco or equivalent) for anomalous syscalls,
  unexpected process execution, and drift from the image's expected behavior.
- Feed findings back into prioritization for the rebuild queue.

## Stage 10 — Rebuild (patch = rebuild)

The remediation model is **rebuild, not mutate**:

1. Golden base is rebuilt with the fixed package.
2. Downstream app images rebuild `FROM` the new base digest.
3. New images flow through Stages 2–8 again and roll out.
4. Old digests are drained and eventually removed from the registry.

**Never** `apt-get upgrade` inside a running container — it breaks immutability,
defeats provenance, and disappears on the next restart. The pipeline is the only
path to a change in production.

---

## The lifecycle as a checklist

- [ ] Built from a pinned, approved golden base
- [ ] Final image minimal (no shell/pkg-manager), non-root
- [ ] SBOM generated and attached as attestation
- [ ] Vulnerability gate passed (no un-waived Crit/High)
- [ ] Signed with cosign (keyless/OIDC) + SLSA provenance attested
- [ ] Pushed by digest to the private registry
- [ ] Admission policy verifies signature + provenance + Pod hardening
- [ ] Runtime spec: non-root, read-only fs, dropped caps, seccomp
- [ ] Continuous scan + runtime detection active
- [ ] Remediation path is rebuild-from-base, not in-place patch

---

**Next:** [03 — Container Security Controls](03-container-security-controls.md)
