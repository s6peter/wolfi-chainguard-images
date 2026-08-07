# How an App Team Uses the Golden Images

The consumer side of [`../golden-image-04/`](../golden-image-04/). That directory
is the platform team's job. This one is what an application developer touches.

**Everything here is verified working against the real promoted images** —
`ghcr.io/s6peter/approved/python` at `sha256:a0365f7b…`, promoted by run #6 on
2026-07-27. The Dockerfile builds, the container runs as UID 65532 on a
read-only root filesystem, and the runtime image has no shell.

---

## 1. The whole deal, in three lines

```dockerfile
FROM ghcr.io/s6peter/approved/python-dev:current@sha256:7a568bce… AS build
FROM ghcr.io/s6peter/approved/python:current@sha256:a0365f7b…     AS runtime
USER 65532:65532
```

Not `cgr.dev`. Not `:latest`. Not `mirror/`. Everything else in this directory
exists to make those lines safe to write and safe to keep current.

**Why not `cgr.dev` directly?** Chainguard's images are excellent and signed —
and still rejected at the cluster door. Their signature proves *origin*. The
`approved/` signature proves *review*: that this exact digest passed your
vulnerability thresholds, secret scan and CIS audit on a recorded date, with the
decision signed and attached to the image. Admission control trusts the second
one.

---

## 2. Getting a base image

```bash
./scripts/get-approved-base.sh              # what's available
./scripts/get-approved-base.sh python       # verify one and get the FROM line
```

Real output:

```
Verifying ghcr.io/s6peter/approved/python
  ok   resolved  sha256:a0365f7b90bf7b78a5e35f2709efb7c9263acf9c7b1905e0ec4c3e943c88e64d
  ok   signed by the golden image pipeline on refs/heads/main
  ok   gate decision: APPROVED  (critical=0 high=0 secrets=0)
  ok   attestation present: spdxjson
  ok   attestation present: vuln

# renovate: datasource=docker depName=ghcr.io/s6peter/approved/python
FROM ghcr.io/s6peter/approved/python:current@sha256:a0365f7b…
```

It doesn't just look the digest up — it verifies the signature, checks all three
attestations exist, and reads the gate decision to confirm it says `APPROVED`. If
any check fails you get nothing pasteable and a non-zero exit, so an unverified
digest can't be copied by accident.

Tested against `mirror/` and a non-existent key; both correctly refuse.

---

## 3. Keeping it current — the question you started with

*"If the digest changes every time upstream rebuilds, do you update every time?"*

Yes — and no human does it. [`renovate.json`](renovate.json) opens a one-line PR:

```diff
- FROM ghcr.io/s6peter/approved/python:current@sha256:a0365f7b…
+ FROM ghcr.io/s6peter/approved/python:current@sha256:9c41e2b8…
```

CI runs, and because a digest bump of an already-gated image is a **standard
change**, it automerges. Grouped and scheduled weekly, so you see one PR rather
than seven.

The classification from [`../golden-image-04/README.md`](../golden-image-04/README.md#4-change-control-classification)
is encoded directly in the config:

| Change | Renovate behaviour | Why |
|---|---|---|
| Digest bump | grouped weekly, **automerged** | Already gated by the golden pipeline; a second review adds delay, not assurance |
| Minor/major (3.14 → 3.15) | never automerged, labelled `normal-change` | Builder and runtime must move together or the venv breaks |
| Security advisory | **bypasses the schedule** | PCI-DSS 6.3.3 gives one month; losing a week to wait for Monday is free risk |

> Pinning without this bot is worse than not pinning. It converts a moving base
> into a frozen, un-patched one.

---

## 4. The Dockerfile

[`Dockerfile`](Dockerfile) — two stages, both on approved bases.

Three things in it that came from actually building it rather than from theory:

**Builder and runtime must share a Python minor version.** The venv's compiled
extensions won't import across versions. Both digests here are Python 3.14.6 —
verified by running `python --version` in each image, not assumed. If you bump
one digest, bump the other from the same golden run.

**Dependency hashes are per Python version.** `requirements.txt` is fully
hash-pinned with `--require-hashes`, which defeats dependency confusion and a
compromised mirror. But the hashes must be generated **inside the builder
image** — hashes produced on a different interpreter won't satisfy the build. The
command is in the file's header.

**`--chmod=0444` on a directory breaks it.** `--chmod` applies to directories
too, and a directory without the execute bit can't be traversed. This produced a
clean build and a container that died with `Could not import module "app.main"`.
Use `0555` for directories, `0444` only for a single file.

> That last one also affects [`../regulated-dockerfile-practice-03/Dockerfile.dotnet-aspnet`](../regulated-dockerfile-practice-03/), which does
> `COPY --chmod=0444 /src/publish/ ./` — same latent bug. Worth fixing there.

---

## 5. Deploying

[`k8s/deployment.yaml`](k8s/deployment.yaml) is written to pass admission on the
first try. Every field maps to a policy that checks it:

| Manifest field | Policy that requires it |
|---|---|
| `image: …@sha256:…` | `golden-image-require-digest` + the CI gate below |
| `runAsNonRoot: true`, `runAsUser: 65532` | `golden-image-runtime-hardening`, CIS Docker 4.1 |
| `readOnlyRootFilesystem: true` | `golden-image-runtime-hardening`, CIS 5.12 |
| `capabilities.drop: ["ALL"]` | least privilege, FedRAMP AC-6 |
| `allowPrivilegeEscalation: false` | `golden-image-runtime-hardening` |
| `seccompProfile: RuntimeDefault` | `golden-image-runtime-hardening` |
| `io.internal.base-image` annotation | `app-image-base-must-be-approved` |

`readOnlyRootFilesystem` is the one people drop first and shouldn't. It's what
makes "no package manager in the image" mean something — without it an attacker
still writes tooling to a writable path and runs it.

### ⚠️ A gap this directory found

The golden image policy allows exactly one pattern to run: `ghcr.io/s6peter/approved/*`.

That's right for base images — but an **app image isn't a base image**. It lives
at `ghcr.io/s6peter/apps/example-api`. Under the golden image policy alone, the
app team's own image is denied and nothing starts.

[`k8s/kyverno-app-images.yaml`](k8s/kyverno-app-images.yaml) supplies the missing
half. Apply it *alongside* the golden image policies, not instead of them:

- The golden image policy governs what you may **build on**.
- This one governs what you may **run**.

Note the deliberate asymmetry: base images must be signed by the *golden image*
workflow, app images by the *app's own* build workflow. Two identities. An app
team can't mint a base image, and the platform team's signature can't vouch for
application code.

It ships in `Audit` mode. Review the policy report before switching to `Enforce`.

---

## 6. CI

[`ci/app-build.yml`](ci/app-build.yml) — a **template**. It does not run where it
sits; copy it to `.github/workflows/` to activate. Left inactive deliberately, so
merging this directory doesn't silently start pushing app images.

The order matters:

```
1. verify every FROM digest is signed by the golden pipeline   ← before building
2. check manifests are digest-pinned                            ← before building
3. build ONCE
4. scan + SBOM the digest you built
5. sign the digest
6. render the manifest with the real digest → GitOps
```

Steps 1 and 2 run first on purpose. There's no point compiling an application on
a base image the cluster will refuse to run.

**Build once, deploy many.** One build, one digest, promoted unchanged through
dev → test → staging → prod. Rebuild per environment and you have four digests
and no chain of custody.

---

## 7. The one control that can't live at admission

```bash
./scripts/check-manifests.sh k8s
```

Admission control **cannot** enforce "the manifest carries a digest". Kyverno's
`verifyDigest` resolves and appends the digest during verification, so by the
time any validating webhook runs, a tag reference already looks digest-pinned.
Measured, not assumed — see the `KNOWN LIMITATION` note in
[`../golden-image-04/policy/kyverno-golden-image.yaml`](../golden-image-04/policy/kyverno-golden-image.yaml).

The runtime property survives: the container runs verified bytes. What's lost is
**reviewability** — if the manifest says `:current`, whoever approved the PR
can't see which build they approved, and the tag may resolve differently at each
admission. That's the SOX-relevant half.

So it lives in CI, against raw YAML, before anything can mutate it. Tested both
ways: passes on the real manifest, fails on a tag reference.

> General lesson, not a Kyverno quirk: **a control downstream of a mutation
> cannot observe what the mutation erased.** Worth auditing anywhere you have
> mutating and validating rules over the same field.

---

## 8. Try it

```bash
# verify a base image the way CI does
./scripts/get-approved-base.sh python

# build and run it hardened, exactly as Kubernetes will
docker build -t example-api:test .
docker run --rm -p 8080:8080 --read-only --cap-drop ALL \
  --security-opt no-new-privileges --user 65532:65532 example-api:test

curl localhost:8080/whoami
# {"uid":65532,"gid":65532,"root_fs_writable":false}

# prove there is no shell to pivot with
docker run --rm --entrypoint /bin/sh example-api:test -c id
# exec: "/bin/sh": stat /bin/sh: no such file or directory

# the pre-merge manifest gate
./scripts/check-manifests.sh k8s
```

## 9. Files

| Path | Purpose |
|---|---|
| [`Dockerfile`](Dockerfile) | Two-stage app build on approved bases |
| [`requirements.txt`](requirements.txt) | Hash-pinned deps, generated in the builder image |
| [`app/main.py`](app/main.py) | Trivial FastAPI app; `/whoami` proves non-root at runtime |
| [`.dockerignore`](.dockerignore) | Keeps `.git`, `.env`, keys out of the build context |
| [`renovate.json`](renovate.json) | Digest bump automation, change-class aware |
| [`scripts/get-approved-base.sh`](scripts/get-approved-base.sh) | Find + verify an approved base |
| [`scripts/check-manifests.sh`](scripts/check-manifests.sh) | Pre-merge digest-pinning gate |
| [`k8s/deployment.yaml`](k8s/deployment.yaml) | Admission-compliant manifest |
| [`k8s/kyverno-app-images.yaml`](k8s/kyverno-app-images.yaml) | The missing app-image policies |
| [`ci/app-build.yml`](ci/app-build.yml) | Build pipeline template (copy to activate) |
