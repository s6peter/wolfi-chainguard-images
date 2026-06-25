# Roadmap: Kernel-Free Container Images, Distroless, and Chainguard

## Core Mental Model

Container images are not full Linux machines. They usually do not include a kernel or bootloader. A container image is a filesystem plus metadata such as entrypoint, command, environment variables, users, and labels.

The container uses the host machine's Linux kernel.

```text
VM or ISO: kernel + bootloader + OS + app
Container image: filesystem + metadata + app
scratch image: empty filesystem + your app only
distroless image: minimal filesystem + runtime dependencies + app
Chainguard image: secure minimal Wolfi-based runtime image
```

## Goals

- Understand what container images contain and what they do not contain.
- Build images without a kernel, bootloader, shell, or package manager.
- Learn `scratch` and distroless images.
- Learn Chainguard Images, Wolfi, apko, and melange.
- Migrate real applications to Chainguard distroless images.
- Learn how to debug and scan minimal images safely.

## Phase 1: Container Image Basics

Learn these concepts:

- OCI image format
- Image layers
- Filesystem snapshots
- Entrypoint and command
- Environment variables
- Users and groups
- Why containers share the host kernel
- Difference between containers and virtual machines

Read:

- Docker image layers: https://docs.docker.com/get-started/docker-concepts/building-images/understanding-image-layers/
- OCI Image Specification: https://github.com/opencontainers/image-spec
- Containers from scratch: https://ericchiang.github.io/post/containers-from-scratch/

Videos:

- Container image layers: https://www.youtube.com/results?search_query=container+images+explained+layers+filesystem
- Containers from scratch: https://www.youtube.com/results?search_query=containers+from+scratch+linux+namespaces+cgroups

Practice:

```Dockerfile
FROM alpine
RUN apk add --no-cache curl
CMD ["curl", "--version"]
```

Commands to inspect images:

```bash
docker image inspect alpine
docker history alpine
docker save alpine -o alpine.tar
```

## Phase 2: Build `scratch` Images

`scratch` is the empty base image. It contains no shell, package manager, libraries, certificates, users, or OS tools.

Best use cases:

- Static Go binaries
- Static Rust binaries
- Small single-binary tools

Example Go image:

```Dockerfile
FROM golang:1.23 AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o app .

FROM scratch
COPY --from=build /src/app /app
ENTRYPOINT ["/app"]
```

Things you may need to add manually:

- CA certificates for HTTPS
- `/etc/passwd` for non-root users
- Timezone data
- Dynamic libraries if the binary is not fully static

Read:

- Docker scratch docs: https://docs.docker.com/build/building/base-images/#create-a-simple-parent-image-using-scratch
- Google Distroless examples: https://github.com/GoogleContainerTools/distroless

Videos:

- Docker scratch Go image: https://www.youtube.com/results?search_query=docker+scratch+image+golang
- Distroless explained: https://www.youtube.com/results?search_query=distroless+container+images+explained

## Phase 3: Learn Distroless Images

Distroless images include only what an application needs at runtime.

Usually removed:

- Shells such as `sh` and `bash`
- Package managers such as `apt`, `apk`, and `yum`
- Build tools
- Debug tools
- Extra OS files
- Unused libraries

Benefits:

- Smaller image size
- Smaller attack surface
- Fewer CVEs
- Better production security posture
- Cleaner software supply chain

Tradeoffs:

- Harder debugging
- No shell access by default
- No package installation at runtime
- Requires better logs, metrics, and health checks

Read:

- Google Distroless: https://github.com/GoogleContainerTools/distroless
- Chainguard Images docs: https://edu.chainguard.dev/chainguard/chainguard-images/
- Minimal container images from Chainguard: https://www.chainguard.dev/unchained/minimal-container-images-towards-a-more-secure-future

## Phase 4: Learn Wolfi, apko, and melange

Chainguard Images are built around a modern secure container ecosystem.

Learn these tools:

- Wolfi: minimal Linux distribution designed for containers.
- apko: declarative tool for building OCI images from YAML.
- melange: tool for building APK packages.
- Chainguard Images: production-ready minimal images with low-to-zero CVEs.

Read:

- Wolfi GitHub: https://github.com/wolfi-dev/os
- Wolfi overview: https://edu.chainguard.dev/open-source/wolfi/overview/
- apko GitHub: https://github.com/chainguard-dev/apko
- apko docs: https://edu.chainguard.dev/open-source/build-tools/apko/
- melange GitHub: https://github.com/chainguard-dev/melange
- melange docs: https://edu.chainguard.dev/open-source/build-tools/melange/
- Chainguard Academy: https://edu.chainguard.dev/
- Chainguard image catalog: https://images.chainguard.dev/

Videos:

- Chainguard Wolfi apko melange: https://www.youtube.com/results?search_query=Chainguard+Wolfi+apko+melange
- Chainguard distroless images: https://www.youtube.com/results?search_query=Chainguard+distroless+images
- Wolfi Linux container security: https://www.youtube.com/results?search_query=Wolfi+Linux+container+security

## Phase 5: Transition to Chainguard Images

Start by replacing common runtime base images with Chainguard equivalents.

Common replacements:

```Dockerfile
FROM node:22
```

Use:

```Dockerfile
FROM cgr.dev/chainguard/node:latest
```

Python:

```Dockerfile
FROM cgr.dev/chainguard/python:latest
```

Java runtime:

```Dockerfile
FROM cgr.dev/chainguard/jre:latest
```

Static binaries:

```Dockerfile
FROM cgr.dev/chainguard/static:latest
```

Dynamic glibc binaries:

```Dockerfile
FROM cgr.dev/chainguard/glibc-dynamic:latest
```

Migration checklist:

- Inventory current base images.
- Identify each app runtime: Go, Node, Python, Java, nginx, etc.
- Find matching Chainguard image at https://images.chainguard.dev/
- Convert Dockerfiles to multi-stage builds.
- Use a builder image for compilation or dependency installation.
- Use a minimal Chainguard runtime image.
- Remove runtime package-manager assumptions.
- Remove shell assumptions.
- Run as non-root.
- Add health checks, logs, and metrics.
- Scan images with Grype or Trivy.
- Generate an SBOM with Syft.
- Pin production images by digest.
- Verify signatures or provenance with Cosign where possible.

## Example: Go with Chainguard

```Dockerfile
FROM cgr.dev/chainguard/go:latest AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM cgr.dev/chainguard/static:latest
COPY --from=build /app/server /server
ENTRYPOINT ["/server"]
```

## Example: Node with Chainguard

```Dockerfile
FROM cgr.dev/chainguard/node:latest-dev AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
RUN npm prune --omit=dev

FROM cgr.dev/chainguard/node:latest
WORKDIR /app
COPY --from=build /app ./
CMD ["server.js"]
```

## Debugging Distroless Images

Distroless images often do not have a shell. Do not rely on this workflow:

```bash
kubectl exec -it pod -- sh
```

Use these instead:

- Application logs
- Health endpoints
- Metrics
- Kubernetes ephemeral debug containers
- Chainguard `:latest-dev` images for debugging
- Local reproduction with a fuller builder or debug image

Read:

- Kubernetes debug running pod: https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/

## Tools to Learn

- Docker: https://docs.docker.com/
- BuildKit and buildx: https://docs.docker.com/build/
- crane: https://github.com/google/go-containerregistry/tree/main/cmd/crane
- Syft: https://github.com/anchore/syft
- Grype: https://github.com/anchore/grype
- Trivy: https://github.com/aquasecurity/trivy
- Cosign: https://github.com/sigstore/cosign
- apko: https://github.com/chainguard-dev/apko
- melange: https://github.com/chainguard-dev/melange

## Study Projects

Do these in order:

1. Build a normal Alpine-based image.
2. Inspect its layers and metadata.
3. Build the same app with `scratch`.
4. Build the same app with Google Distroless.
5. Build the same app with a Chainguard runtime image.
6. Scan all versions with Grype or Trivy.
7. Compare image size, packages, CVEs, and shell availability.
8. Generate an SBOM with Syft.
9. Pin the final image by digest.
10. Document how you will debug it in production.

## Six-Week Study Plan

### Week 1: Container Image Internals

Focus on image layers, OCI metadata, Dockerfiles, and the difference between containers and VMs.

Deliverable: build and inspect a basic Alpine image.

### Week 2: `scratch` Images

Focus on static binaries, empty filesystems, CA certificates, users, and runtime dependencies.

Deliverable: run a static Go or Rust app from `scratch`.

### Week 3: Distroless Images

Focus on removing shells, package managers, and debug tools from runtime images.

Deliverable: migrate one app from Alpine or Debian to distroless.

### Week 4: Chainguard Images

Focus on Chainguard runtime images for your language stack.

Deliverable: migrate one app to a Chainguard image and scan it.

### Week 5: Wolfi, apko, and melange

Focus on how Chainguard-style images and packages are built.

Deliverable: build a small custom image with apko.

### Week 6: Production Migration

Focus on repeatable migration, SBOMs, digest pinning, non-root execution, and debugging.

Deliverable: migrate one real application completely and document the process.

## Final Target

By the end, you should be comfortable moving from this:

```Dockerfile
FROM ubuntu:latest
RUN apt-get update && apt-get install -y curl
COPY app /app
CMD ["/app"]
```

To this style:

```Dockerfile
FROM cgr.dev/chainguard/static:latest
COPY app /app
ENTRYPOINT ["/app"]
```

And you should understand what was removed, why it was removed, and how to debug the result safely.
