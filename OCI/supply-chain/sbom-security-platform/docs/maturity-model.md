# SBOM Security Platform — Maturity Model

A staged adoption path. Each level has concrete **exit criteria** — you are at a
level only when every criterion is met.

```text
L0 Blind ─▶ L1 Generating ─▶ L2 Centralized ─▶ L3 Enforced ─▶ L4 Continuous
 no SBOMs    SBOMs in CI      inventory+monitor  admission gate  runtime + identity + self-healing
```

---

## Level 0 — Blind

No SBOMs, or SBOMs generated and thrown away. Vulnerability response is manual
rescanning. Cannot answer "who is affected?" quickly. No provenance.

## Level 1 — Generating

**Exit criteria:**
- [ ] Every build produces an SBOM (CycloneDX or SPDX).
- [ ] Image-level SBOM (authoritative), not just source lockfiles.
- [ ] SBOMs meet a minimum quality bar (version + purl per component).

**Outcome:** raw material exists — but not yet queryable or trusted.

## Level 2 — Centralized (inventory + monitoring)

**Exit criteria:**
- [ ] SBOMs ingested into a central platform (Dependency-Track / GUAC),
      versioned per artifact/build.
- [ ] Continuous CVE correlation against stored SBOMs.
- [ ] "Who is affected by CVE-X?" answerable across the fleet in minutes.
- [ ] SBOMs signed & attested (cosign); ingest verifies attestations.
- [ ] VEX triage process operating to cut false positives.

**Outcome:** the platform now answers impact questions and is trustworthy. Huge
incident-response value even before enforcement.

## Level 3 — Enforced (policy-as-code)

**Exit criteria:**
- [ ] Admission control (Kyverno/OPA) in **enforce** mode in production.
- [ ] Unsigned / wrong-identity images **rejected**; SBOM + provenance
      attestations required.
- [ ] Vuln/license policy enforced (no un-waived Critical/High; license tiers).
- [ ] Deploy-by-digest, approved registries only.
- [ ] Disciplined, time-boxed waiver + VEX process.
- [ ] Policies versioned, tested in CI, GitOps-distributed to all clusters.

**Outcome:** evidence is enforced, not advisory. Non-compliant software cannot
deploy. This is the level that materially reduces supply-chain risk.

## Level 4 — Continuous (runtime + identity + self-healing)

**Exit criteria:**
- [ ] Workload identity everywhere (OIDC/IRSA/SPIFFE); **no static secrets** in
      the platform or its clients.
- [ ] Runtime drift detection (running container vs SBOM) live and routed.
- [ ] Behavioral runtime detection (Falco/Tetragon) live.
- [ ] Runtime reachability feeds VEX; findings auto-route to rebuild pipelines.
- [ ] New-CVE → identify → rebuild-from-base → redeploy largely automated.
- [ ] Full program metrics tracked and reported (doc 08 §6).

**Outcome:** build-time and runtime truth are continuously reconciled;
remediation is rebuild-driven and largely automated; identity is the perimeter.
Self-sustaining and audit-ready.

---

## Assessment quick-scan

| Question | If "no" → work at |
|----------|-------------------|
| Does every build emit an image-level SBOM? | Level 1 |
| Can you answer "who has CVE-X?" fleet-wide in minutes, from stored data? | Level 2 |
| Would an unsigned / no-SBOM image be *rejected* by prod right now? | Level 3 |
| Do you detect when a running container drifts from its SBOM? | Level 4 |
| Are there any static long-lived platform credentials? | Level 4 (remove them) |

**Recommended near-term target: Level 3.** Level 2 alone already transforms
incident response; Level 4 is the maturity destination.
