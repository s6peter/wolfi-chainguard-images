# syntax=docker/dockerfile:1.10
# check=error=true
# =============================================================================
# An application team's Dockerfile, consuming the golden image programme.
#
# THE ONE RULE: both FROM lines point at ghcr.io/s6peter/approved/*, pinned by
# digest. Not cgr.dev. Not :latest. Not mirror/.
#
# Why not cgr.dev directly, when Chainguard's images are excellent and signed?
# Because Chainguard's signature proves ORIGIN. The approved/ signature proves
# REVIEW - that this exact digest passed our vulnerability thresholds, secret
# scan, and CIS audit on a recorded date, with the decision signed and attached.
# Admission control trusts the second one. A pod built on cgr.dev directly is
# rejected at the cluster door even though the image is objectively fine.
#
# Digests below were resolved from approved/*:current on 2026-07-27 and are
# maintained by Renovate (see renovate.json). Do not hand-edit them.
# =============================================================================

# renovate: datasource=docker depName=ghcr.io/s6peter/approved/python-dev
FROM ghcr.io/s6peter/approved/python-dev:current@sha256:7a568bcee42666f73f041645a41c913ce1d442f4c24cf6019bc543a90820e531 AS build

# The -dev variant carries a shell, apk, and the toolchain needed to build
# wheels with C extensions. None of it survives into the runtime stage.
USER root
RUN mkdir -p /app && chown 65532:65532 /app
USER 65532:65532
WORKDIR /app

RUN python -m venv /app/venv
ENV PATH="/app/venv/bin:${PATH}" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY --chown=65532:65532 requirements.txt ./

# --require-hashes refuses to install anything whose SHA-256 is not listed.
# --only-binary=:all: additionally forbids executing arbitrary setup.py code.
# Together these make the dependency graph reproducible and defeat both
# dependency-confusion and a compromised package mirror. PCI-DSS 6.3.2.
#
# The hashes in requirements.txt were generated inside THIS builder image.
# Wheel hashes are per Python version: hashes produced on a different
# interpreter will not satisfy this step. See the header of requirements.txt.
RUN --mount=type=cache,target=/home/nonroot/.cache/pip,uid=65532,gid=65532 \
    pip install --require-hashes --only-binary=:all: -r requirements.txt

COPY --chown=65532:65532 app ./app


# -----------------------------------------------------------------------------
# Runtime: the non-dev approved image. Interpreter only - no shell, no apk,
# no pip. "No package manager in production" is itself a control: nothing can
# install at runtime, so an RCE lands somewhere with nothing to pivot with.
#
# Builder and runtime MUST share a Python minor version or the venv's compiled
# extensions will not import. Both are Python 3.14.6 here - verified, not
# assumed. If you bump one digest, bump the other from the same golden run.
# -----------------------------------------------------------------------------
# renovate: datasource=docker depName=ghcr.io/s6peter/approved/python
FROM ghcr.io/s6peter/approved/python:current@sha256:a0365f7b90bf7b78a5e35f2709efb7c9263acf9c7b1905e0ec4c3e943c88e64d AS runtime

ARG VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

# Provenance. This is how the image maps back to a change ticket during an
# audit, and how SBOM findings get attributed to a team.
LABEL org.opencontainers.image.title="example-api" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/s6peter/wolfi-chainguard-images" \
      io.internal.base-image="ghcr.io/s6peter/approved/python@sha256:a0365f7b90bf" \
      io.internal.data-classification="none" \
      io.internal.owner="app-team@example.internal"

WORKDIR /app

# COPY, never ADD. ADD fetches remote URLs and auto-extracts archives.
#
# --chmod applies to DIRECTORIES as well as files, and a directory without the
# execute bit cannot be traversed. --chmod=0444 here produced a clean build and
# a container that died with:
#     ERROR: Error loading ASGI app. Could not import module "app.main"
# because /app/app was unreadable as a directory. 0555 keeps it read-only while
# leaving it traversable. Use 0444 only when copying a single file.
COPY --from=build --chown=65532:65532 /app/venv /app/venv
COPY --from=build --chown=65532:65532 --chmod=0555 /app/app /app/app

ENV PATH="/app/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Numeric UID. Kubernetes runAsNonRoot can only verify a number; a username
# forces the kubelet to trust image metadata instead of checking.
USER 65532:65532

# Documentation only. EXPOSE publishes nothing and is not a network control.
EXPOSE 8080
STOPSIGNAL SIGTERM

# The interpreter is present, so this image can satisfy CIS 4.6 natively.
# Kubernetes ignores HEALTHCHECK regardless - k8s/deployment.yaml carries the
# equivalent probes, which are the control that actually runs.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/app/venv/bin/python", "-c", \
       "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status==200 else 1)"]

# Exec form, no shell wrapper: uvicorn is PID 1 and receives SIGTERM directly,
# so in-flight requests drain before the pod terminates.
ENTRYPOINT ["/app/venv/bin/python", "-m", "uvicorn", "app.main:app", \
            "--host", "0.0.0.0", "--port", "8080", \
            "--no-server-header", "--proxy-headers", "--forwarded-allow-ips", "*"]
