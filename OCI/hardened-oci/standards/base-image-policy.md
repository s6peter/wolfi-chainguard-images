# Base Image Policy (Enforceable Standard)

**Status:** Normative. This is the policy admission control enforces.
**Owner:** Platform Security.
**Applies to:** all container images built or deployed by the organization.

The keywords MUST, MUST NOT, SHOULD, and MAY are used per RFC 2119.

---

## 1. Approved runtime bases

The final (runtime) stage of an image MUST use one of:

1. **`scratch`** — for fully static binaries (Go, Rust). Preferred where viable.
2. **Chainguard / Wolfi distroless** images (e.g. `cgr.dev/chainguard/static`,
   `cgr.dev/chainguard/jre`, language runtimes) — for workloads needing a minimal
   runtime without a shell.
3. **Approved internal golden images** derived from (1) or (2) — see
   [golden-image-catalog.md](golden-image-catalog.md).

All bases MUST be pinned by **digest** (`@sha256:…`), not by tag alone.

## 2. Build-stage bases

Non-final build stages MAY use larger images (e.g. Chainguard `-dev` variants,
official language SDK images) provided:
- they are pinned by digest, and
- **nothing** from them leaks into the final stage except the built artifact(s).

## 3. Prohibited in the runtime stage

The runtime image MUST NOT contain:
- a shell (`/bin/sh`, `/bin/bash`, `busybox` shell),
- a package manager (`apk`, `apt`, `yum`, `dnf`, `pip` as a runtime tool),
- compilers or build toolchains,
- secrets, private keys, or credentials,
- `latest` or other mutable tags as the base reference.

Full general-purpose distributions (`ubuntu`, `debian`, `centos`, `alpine` with
shell) MUST NOT be the runtime base without an approved, time-boxed exception.

## 4. User and filesystem

- The image MUST declare a **numeric non-root `USER`** (e.g. `65532`).
- The image SHOULD be designed to run with a **read-only root filesystem**
  (writable paths mounted at runtime as needed).

## 5. Provenance requirements

Every released image MUST have:
- a complete **SBOM** attached as an attestation (SPDX or CycloneDX),
- a **cosign signature** (keyless/OIDC preferred),
- a **SLSA build provenance** attestation.

## 6. Reference and deployment

- Production workloads MUST be deployed by **digest**.
- Images MUST originate from an **approved registry**.
- `:latest` MUST NOT appear in any committed Kubernetes manifest.

## 7. Remediation

Vulnerabilities MUST be remediated by **rebuilding** from an updated base and
re-releasing through the pipeline. In-place mutation of running containers
(`apt-get upgrade`, etc.) is prohibited.

## 8. Exceptions

Exceptions to this policy MUST be scoped, owned, justified, compensated,
time-boxed, and approved per
[../docs/05-governance-and-compliance.md](../docs/05-governance-and-compliance.md) §2.

---

## Machine-checkable summary

| Rule | Enforced by |
|------|-------------|
| Approved base, pinned by digest | Build lint + admission |
| No shell / package manager in runtime | Build lint + scan |
| Numeric non-root user | Admission (`runAsNonRoot`) |
| SBOM + signature + provenance present | CI + admission (`verifyImages`) |
| Approved registry, digest-only, no `:latest` | Admission |
| Read-only root fs, dropped caps, seccomp | Admission + PSS `restricted` |
