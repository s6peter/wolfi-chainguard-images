# Examples — Working Artifacts

Adaptable artifacts implementing the SBOM Security Platform. Each maps to a
platform capability and the docs that explain it.

> Illustrative starting points. **Pin real digests/hashes**, substitute your
> registry, account IDs, OIDC issuers, and platform URLs, and validate against
> your own environment. Placeholders read `REPLACE_*`.

| Path | Purpose | Docs |
|------|---------|------|
| [sbom/app.cyclonedx.json](sbom/app.cyclonedx.json) | Sample CycloneDX SBOM (primary format) | 02 |
| [sbom/app.spdx.json](sbom/app.spdx.json) | Sample SPDX SBOM (compliance/partners) | 02 |
| [sbom/vex.cyclonedx.json](sbom/vex.cyclonedx.json) | VEX statement (`not_affected` + justification) | 03 §4 |
| [sbom/generate-and-merge.sh](sbom/generate-and-merge.sh) | Generate CDX+SPDX, merge base+app | 02 |
| [signing/attest-sbom.sh](signing/attest-sbom.sh) | Sign image + attest SBOM/provenance | 04 |
| [signing/verify-attestations.sh](signing/verify-attestations.sh) | Verify signature + attestation by identity | 04 §5 |
| [ingestion/upload-to-dependency-track.sh](ingestion/upload-to-dependency-track.sh) | Ingest SBOM into the platform | 03 §1 |
| [policy/kyverno/verify-sbom-attestation.yaml](policy/kyverno/verify-sbom-attestation.yaml) | Admission: require signed image + SBOM + provenance (local) | 05 |
| [policy/kyverno/block-critical-vulns.yaml](policy/kyverno/block-critical-vulns.yaml) | Admission: block on live platform vuln verdict (degrades gracefully) | 05 §3 |
| [policy/gatekeeper/require-provenance-template.yaml](policy/gatekeeper/require-provenance-template.yaml) | OPA/Gatekeeper equivalent | 05 |
| [workload-identity/irsa-trust-policy.json](workload-identity/irsa-trust-policy.json) | IRSA IAM trust policy (pins the SA) | 06 §3 |
| [workload-identity/irsa-serviceaccount.yaml](workload-identity/irsa-serviceaccount.yaml) | SA↔IAM role binding, no static keys | 06 §3 |
| [workload-identity/spiffe-workload.md](workload-identity/spiffe-workload.md) | SPIFFE/SPIRE mTLS identity | 06 §4 |
| [runtime-drift/compare-running-vs-sbom.sh](runtime-drift/compare-running-vs-sbom.sh) | Diff running container vs attested SBOM | 07 §2A |
| [runtime-drift/drift-cronjob.yaml](runtime-drift/drift-cronjob.yaml) | Scheduled per-cluster drift reconciliation | 07 §5 |
| [ci/github-actions-sbom-pipeline.yml](ci/github-actions-sbom-pipeline.yml) | Build→SBOM→sign→attest→ingest | 02, 04 |

## Suggested walk-through

1. **Generate** an SBOM — inspect the sample CDX/SPDX, then run
   `sbom/generate-and-merge.sh` on a real image.
2. **Sign + attest** with `signing/attest-sbom.sh`, then confirm with
   `signing/verify-attestations.sh` (note: it pins *identity*, not just "signed").
3. **Ingest** into Dependency-Track with `ingestion/upload-to-dependency-track.sh`
   and query "who has component X?".
4. **Enforce**: apply the Kyverno policies in *audit*, then *enforce*; try to
   deploy an unsigned image → rejected.
5. **Identity**: wire IRSA (`workload-identity/`) so the platform uses no static
   secrets.
6. **Drift**: run `runtime-drift/compare-running-vs-sbom.sh` against a running
   container; schedule it with `drift-cronjob.yaml`.

## Related

- Building the hardened images these SBOMs describe:
  [`../../../hardened-oci`](../../../hardened-oci)
- Platform blueprint: [`../architecture/reference-architecture.md`](../architecture/reference-architecture.md)
