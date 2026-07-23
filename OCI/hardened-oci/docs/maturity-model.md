# Hardened Image Maturity Model

A staged adoption path. Each level has concrete **exit criteria** — you are at a
level only when every criterion is met. Use it to assess where a team or cluster
is today and what the next increment is.

```text
L0 Ad hoc ─▶ L1 Minimal bases ─▶ L2 Signed & scanned ─▶ L3 Enforced ─▶ L4 Continuous
 no control    smaller surface     provenance in CI       admission gate   self-healing
```

---

## Level 0 — Ad hoc (starting point)

Public base images, `latest` tags, root containers, no signing, no admission
policy. Security is reactive.

**Risk:** large attack surface, no provenance, no enforcement.

## Level 1 — Minimal bases

**Exit criteria:**
- [ ] All new services build on an approved minimal base (Wolfi/Chainguard/
      distroless/`scratch`), pinned by digest.
- [ ] Final images have no shell/package manager.
- [ ] Containers run as a numeric non-root user.
- [ ] No `:latest` in committed manifests.

**Outcome:** attack surface and CVE count drop sharply; the biggest win for the
least effort.

## Level 2 — Signed & scanned (provenance in CI)

**Exit criteria:**
- [ ] SBOM generated and attached as an attestation for every image.
- [ ] Vulnerability scan runs in CI as a **release gate** (fail on un-waived
      Critical/High).
- [ ] Images signed with `cosign` (keyless/OIDC preferred).
- [ ] SLSA build provenance attested.
- [ ] Images deployed by digest.

**Outcome:** every artifact is traceable and verifiable; supply-chain integrity
established. Maps to SLSA L2+.

## Level 3 — Enforced (admission gate)

**Exit criteria:**
- [ ] Admission controller (Kyverno/OPA) in **enforce** mode in production.
- [ ] Unsigned or wrong-identity images are **rejected**.
- [ ] SBOM/provenance attestation presence verified at admission.
- [ ] Allowed-registry + digest-only enforced.
- [ ] Pod Security Standards `restricted` enforced on app namespaces.
- [ ] Disciplined, time-boxed waiver process operating.

**Outcome:** the standards are no longer advisory — non-compliant images cannot
run. This is the level at which the program actually protects the cluster.

## Level 4 — Continuous (self-healing)

**Exit criteria:**
- [ ] Scheduled re-scanning of registry/running images against fresh CVE data.
- [ ] Runtime threat detection (Falco/eBPF) live with triaged alerting.
- [ ] Golden bases auto-rebuilt on upstream CVE fixes within SLA.
- [ ] Automated rebuild/rollout pipeline for downstream images on base updates.
- [ ] Default-deny network policies.
- [ ] Program metrics tracked and reported (doc 05 §5).

**Outcome:** vulnerabilities are remediated by automated rebuild-from-base, not
manual firefighting; runtime backstops the unknown. The program is
self-sustaining.

---

## Assessment quick-scan

| Question | If "no" → work at |
|----------|-------------------|
| Are all runtime images shell-less, non-root, pinned? | Level 1 |
| Is every image signed + SBOM'd + scanned in CI? | Level 2 |
| Would an unsigned image be *rejected* by the cluster right now? | Level 3 |
| Do fixed bases roll out to downstream images automatically? | Level 4 |

Most organizations get disproportionate risk reduction from reaching **Level 3**
— that is the recommended near-term target. Level 4 is the maturity destination.
