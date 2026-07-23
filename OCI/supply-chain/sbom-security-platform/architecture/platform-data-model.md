# Platform Data Model

The core entities the platform stores and the relationships that make fleet-wide
questions answerable. Format-agnostic (CycloneDX and SPDX both normalize into
this).

```text
 Component ──appears_in──▶ SBOM ──describes──▶ Artifact ──deployed_as──▶ Workload ──runs_in──▶ Cluster
     │                       │                    │                                    
     │                       │                    └──has──▶ Attestation (signature, SBOM, SLSA provenance)
     │                                                             
     ├──matched_to──▶ Vulnerability ◀──triaged_by── VEXStatement
     └──has──▶ License
```

## Entities

### Component
The atomic unit. Deduplicated across the fleet.
- `purl` (primary identity, e.g. `pkg:maven/org.apache.logging.log4j/log4j-core@2.14.1`)
- `name`, `version`, `type` (library | application | os-package | container)
- `hashes[]`, `licenses[]`, `supplier`

### SBOM
A versioned document describing one artifact build.
- `id`, `format` (cyclonedx | spdx), `spec_version`
- `artifact_digest` (the image it describes), `build_id`, `created_at`
- `quality_score`, `source` (build stage: source | build | image | runtime)
- `components[]` (relationships), `attestation_ref`

### Artifact
A container image (or other releasable unit).
- `digest` (sha256, the immutable key), `repository`, `tags[]`
- `provenance_ref`, `sboms[]` (multiple, versioned)

### Attestation
Signed statements bound to an artifact (doc 04).
- `type` (cosign-signature | sbom | slsa-provenance)
- `predicate_ref`, `signer_identity`, `oidc_issuer`, `rekor_uuid`, `verified`

### Vulnerability
- `id` (CVE / GHSA / OSV), `severity`, `cvss`, `affected_ranges[]`, `fixed_in`
- `source` (feed), `exploit_known`

### VEXStatement
Applied exploitability judgment (doc 03 §4).
- `vuln_id`, `component_purl`, `artifact_digest`
- `status` (not_affected | affected | fixed | under_investigation)
- `justification` (required for not_affected), `author`, `timestamp`, `expires`

### Workload / Deployment
- `workload_id`, `namespace`, `cluster`, `artifact_digest`, `replicas`
- `exposure` (internet | internal), `data_sensitivity` (pii | pci | none)
- `running_inventory_ref` (for drift reconciliation, doc 07)

### Finding
- `id`, `vuln_id` | `drift_id`, `artifact`/`workload`, `status`, `priority`
- `priority` = f(severity, VEX, deployed?, exposure, data_sensitivity)
- `route` (ticket | soar | rebuild), `opened_at`, `closed_at`

## Key queries the model enables

```text
Q: "Which running workloads contain purl X (version range)?"
   Component(purl=X) → SBOM → Artifact → Workload(runs_in=*)   # incident response

Q: "Prove service S's components on date D."
   Workload(S) @ date D → Artifact.digest → SBOM(version @ D) → Components[]

Q: "What is downstream of compromised package P?"   (GUAC graph)
   Component(P) → all Artifacts → all Workloads (blast radius)

Q: "Any un-waived Critical in internet-facing PCI workloads?"
   Workload(exposure=internet, data=pci) → Artifact → Vulnerability(sev=critical)
     minus VEXStatement(status in {not_affected, fixed})

Q: "Does running inventory match the SBOM?"   (drift, doc 07)
   Workload.running_inventory  △  Artifact.sbom.components
```

## Notes

- **purl + hash** is the universal join key — insist on both at ingest.
- **Versioning is non-negotiable**: SBOMs are append-only per build so
  point-in-time reconstruction works for audits.
- Vulnerability and VEX data are **layered on top** of the immutable signed SBOM,
  never edited into it.
