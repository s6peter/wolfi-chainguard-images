# Reference Architecture

A concrete, opinionated instantiation of the platform (doc 01) using named
open-source components. Treat as a starting blueprint; substitute equivalents to
taste.

```text
                          ┌───────────────────────── CI / Build ─────────────────────────┐
                          │  build ─▶ Syft/Trivy (SBOM CycloneDX) ─▶ cosign sign+attest    │
                          │                 │ OIDC (keyless, Fulcio/Rekor)                 │
                          └─────────────────┼────────────────────────────────────────────┘
                                            │ OIDC-auth push (SBOM + attestation)
                                            ▼
   ┌──────────────────────────────── SBOM Security Platform (HA) ────────────────────────────────┐
   │                                                                                              │
   │   Ingestion API ─▶ Normalizer (CDX/SPDX→model) ─▶ SBOM Store ─┬─▶ Dependency-Track (VEX/CVE) │
   │        ▲                                                       └─▶ GUAC (supply-chain graph)  │
   │        │ IRSA → S3 (raw SBOM blobs) / KMS                                                     │
   │   Continuous Monitor ◀── CVE feeds (OSV / NVD / GHSA, mirrored)                               │
   │        │                                                                                     │
   │   Query + Policy API ─────────────────────────────────────────────────────────────────────┐ │
   └────────┼─────────────────────────────────────────────────────────────────────────────────┼─┘
            │ read verdicts / attestation refs                                                   │
   ┌────────┼──────────────── Kubernetes clusters (×N, GitOps-managed) ───────────────┐          │
   │  Admission: Kyverno verifyImages (cosign) + apiCall→Policy API (vuln verdict)     │          │
   │  Runtime:   Falco/Tetragon (behavior) + drift CronJob (running vs SBOM) ──────────┼──────────┘
   │  Identity:  SPIFFE/SPIRE (mTLS), IRSA (cloud access)                               │
   └───────────────────────────────────────────────────────────────────────────────────┘
                                            │
                     ┌──────────────────────┴───────────────────────┐
                     ▼                                               ▼
              SIEM / SOAR / ticketing                    Dashboards / GRC / auditor exports
```

## Component choices

| Concern | Reference choice | Alternatives |
|---------|------------------|--------------|
| SBOM generation | Syft | Trivy, apko (native), build plugins |
| Format (primary) | CycloneDX JSON | SPDX JSON |
| Signing / attestation | cosign (keyless) | KMS-key cosign (air-gapped) |
| Component/VEX mgmt | Dependency-Track | — |
| Supply-chain graph | GUAC | — |
| Raw SBOM blob store | S3 (via IRSA) | GCS / Azure Blob |
| CVE feeds | OSV + NVD + GHSA (mirrored) | vendor feeds |
| Admission policy | Kyverno | OPA/Gatekeeper |
| Workload identity | OIDC + IRSA + SPIFFE/SPIRE | GKE/Azure WI |
| Runtime detection | Falco / Tetragon | — |
| Policy delivery | Argo CD / Flux (GitOps) | — |

## Non-functional requirements

- **Availability:** platform is in the deploy path via admission → HA store,
  cached verdicts, local signature verification (fail closed on trust, degrade on
  freshness — doc 05 §3).
- **Scale:** millions of component rows; dedupe on purl+hash; version SBOMs per
  build.
- **Security:** every arrow authenticated by workload identity; no static
  secrets; least-privilege cloud roles.
- **Auditability:** versioned SBOMs + attestations + VEX + decision logs retained
  for the regulatory window; point-in-time reconstruction.
- **Portability:** works multi-cloud and air-gapped (mirrored feeds, offline
  Sigstore trust bundles).
