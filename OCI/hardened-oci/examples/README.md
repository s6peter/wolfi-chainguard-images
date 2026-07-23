# Examples — Working Artifacts

Ready-to-adapt artifacts implementing the program. Each maps to a stage in the
[secure image lifecycle](../docs/02-secure-image-lifecycle.md) and a control in
[container security controls](../docs/03-container-security-controls.md).

> These are illustrative starting points. **Pin real digests**, substitute your
> registry and CI identities, and validate against your own clusters before
> production use. Placeholders read `REPLACE_ME` / `REPLACE_WITH_REAL_DIGEST`.

| Artifact | Purpose | Lifecycle stage |
|----------|---------|-----------------|
| [apko/hardened-app.apko.yaml](apko/hardened-app.apko.yaml) | Declarative, SBOM-carrying image build (preferred) | Build |
| [melange/example-package.melange.yaml](melange/example-package.melange.yaml) | Build the app into a signed apk for apko | Build |
| [dockerfile/Dockerfile.hardened-multistage](dockerfile/Dockerfile.hardened-multistage) | Multi-stage build → distroless/scratch final | Build |
| [sbom/generate-sbom.sh](sbom/generate-sbom.sh) | Generate SBOM + scan against it | SBOM + Scan |
| [ci/github-actions-build-sign-scan.yml](ci/github-actions-build-sign-scan.yml) | Full build→scan→sign→attest pipeline (GH) | Build→Sign |
| [ci/gitlab-ci.yml](ci/gitlab-ci.yml) | Same pipeline for GitLab CI | Build→Sign |
| [signing/cosign-workflow.md](signing/cosign-workflow.md) | Sign / attest / verify commands | Sign + Verify |
| [kubernetes/kyverno-verify-images.yaml](kubernetes/kyverno-verify-images.yaml) | Admission: verify signature + attestations | Admit |
| [kubernetes/kyverno-require-non-root.yaml](kubernetes/kyverno-require-non-root.yaml) | Admission: workload hardening + digest-only | Admit |
| [kubernetes/opa-gatekeeper-constraint.yaml](kubernetes/opa-gatekeeper-constraint.yaml) | Gatekeeper equivalent of the hardening rules | Admit |
| [kubernetes/pod-security-standards.yaml](kubernetes/pod-security-standards.yaml) | Namespace PSS `restricted` baseline | Run |
| [kubernetes/deployment-hardened.yaml](kubernetes/deployment-hardened.yaml) | A Deployment that passes all of the above | Run |

## Suggested order to try them

1. **Build** a minimal image — start with the Dockerfile (familiar) or apko
   (preferred). Confirm it has no shell: `docker run --rm --entrypoint sh IMAGE`
   should fail.
2. **SBOM + scan** with `sbom/generate-sbom.sh`.
3. **Wire CI** from the GitHub or GitLab pipeline — this signs + attests.
4. **Verify** locally with the cosign commands in `signing/`.
5. **Enforce** in a test cluster: apply the PSS labels, then the Kyverno (or
   Gatekeeper) policies in **audit** mode, then flip to **enforce**.
6. **Deploy** `deployment-hardened.yaml` and confirm it is admitted while an
   unsigned or root image is rejected.
