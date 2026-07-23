# 05 — Policy-as-Code

Evidence (SBOMs, attestations, findings) only protects you if a machine enforces
rules against it at deploy time. This document covers the Kubernetes admission
layer — Kyverno and OPA/Gatekeeper — and how it consumes the platform's evidence.

---

## 1. What the policy layer decides

At admission, before a Pod schedules, policy asks:

1. **Is the image signed by an expected identity?** (cosign verification)
2. **Does it carry the required attestations?** (SBOM + SLSA provenance present)
3. **Does its SBOM/vuln posture pass?** (no un-waived Critical/High; license OK)
4. **Is it from an approved registry, pinned by digest?**
5. **Does the workload meet the hardening baseline?** (non-root, RO fs, dropped
   caps — see the `hardened-oci` sibling)

Rules 1–2 are verifiable **locally** by the admission controller (cosign).
Rule 3 typically needs a **platform lookup** (the vuln/VEX verdict lives in
Dependency-Track/GUAC). Design for both.

```text
kubectl apply ─▶ API server ─▶ admission webhook
                                   │
                    ┌──────────────┼───────────────┐
             verify signature   check attestations   query platform verdict
             (local, cosign)    (local, cosign)      (Dependency-Track API)
                                   │
                         ADMIT ◀───┴───▶ REJECT (fail closed)
```

## 2. Kyverno vs OPA/Gatekeeper

| | Kyverno | OPA/Gatekeeper |
|-|---------|----------------|
| Policy language | Kubernetes-native YAML | Rego |
| Image verification | **Built-in `verifyImages`** (cosign, attestations) | Via external data / ext_authz |
| Best for | Most teams; native feel, strong image-verify | Complex custom logic, cross-resource rules |
| Platform lookups | `apiCall` / external data | `external_data` / providers |

**Recommendation:** Kyverno as the default (native cosign attestation
verification is a big win for this use case); Gatekeeper where you need rich Rego
logic. Many enterprises run both.

Examples:
- Kyverno verify signature + SBOM attestation:
  [../examples/policy/kyverno/verify-sbom-attestation.yaml](../examples/policy/kyverno/verify-sbom-attestation.yaml)
- Kyverno block on platform vuln verdict:
  [../examples/policy/kyverno/block-critical-vulns.yaml](../examples/policy/kyverno/block-critical-vulns.yaml)
- Gatekeeper require-provenance constraint:
  [../examples/policy/gatekeeper/require-provenance-template.yaml](../examples/policy/gatekeeper/require-provenance-template.yaml)

## 3. Local vs platform-backed policy — the availability trade-off

Two ways to enforce vuln policy, with different failure modes:

| Approach | How | Failure behavior |
|----------|-----|------------------|
| **Attestation-embedded** | Scan/VEX verdict attested at build; admission verifies the attestation locally | Works even if platform is down; verdict is build-time (may be stale) |
| **Live platform query** | Admission calls the platform API at deploy | Always fresh; but a platform outage blocks deploys |

**Recommended hybrid:** verify signature + attestations **locally** (always
available), and consult the platform for the **live vuln verdict** with a
**cached fallback** and a **short TTL**. If the platform is unreachable, fall
back to the last cached verdict rather than failing all deploys — but never fall
back to "allow anything unsigned." Fail closed on *trust*, degrade gracefully on
*freshness*. (Referenced in [01-platform-architecture.md](01-platform-architecture.md) §4.)

## 4. Rollout: audit → enforce

Never flip enforcement cold:

1. **Audit** — log violations, admit everything. Size the blast radius.
2. **Enforce non-prod** — block in dev/staging; teams remediate.
3. **Enforce prod** — fail closed; exceptions via the waiver process.

Kyverno `validationFailureAction: Audit → Enforce`; Gatekeeper
`enforcementAction: dryrun → deny`.

## 5. Policy scope examples (what regulated orgs enforce)

- **No un-waived Critical/High** reaches production.
- **Every prod image signed** by an approved CI identity, **SBOM attestation
  present**.
- **Deploy by digest**, approved registries only, no `:latest`.
- **License policy** — block AGPL/GPL in specific service tiers.
- **Provenance required** — SLSA L2+ for payment/PII services.
- **Exceptions** are scoped, owned, justified, time-boxed, and approved
  (governance in [08-enterprise-adoption.md](08-enterprise-adoption.md)).

## 6. Policy as versioned, tested code

- Policies live in Git, reviewed like application code.
- **Test** policies in CI (Kyverno CLI `kyverno test`, Gatekeeper `gator test`)
  against known-good and known-bad manifests before rollout.
- Distributed to clusters via GitOps (Argo CD / Flux) so every cluster enforces
  the same rules — no drift between clusters.

---

**Next:** [06 — Workload Identity](06-workload-identity.md)
