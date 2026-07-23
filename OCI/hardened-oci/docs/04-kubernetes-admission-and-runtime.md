# 04 — Kubernetes Admission & Runtime Enforcement

This is where standards become enforced reality. Admission control decides what
is *allowed to run*; runtime control watches what *actually runs*. Both must fail
closed.

```text
kubectl apply ──▶ API server ──▶ Admission webhooks ──┬─▶ REJECT (unsigned / non-compliant)
                                                       └─▶ ADMIT ──▶ scheduled Pod
                                                                        │
                                                             Pod Security Standards
                                                             Falco / eBPF detection
                                                             NetworkPolicy (default deny)
```

---

## 1. Admission verification

An admission controller intercepts every Pod-creating request and validates it
against policy **before** the Pod is scheduled. Two mainstream engines:

| Engine | Model | Strength |
|--------|-------|----------|
| **Kyverno** | Policies as Kubernetes YAML | Native feel, built-in image verification (`verifyImages`) for cosign |
| **OPA Gatekeeper** | Rego constraints via CRDs | Maximum expressiveness for complex logic |

Pick one as the org standard (Kyverno is the lower-friction default). Run it in
**every** cluster; a cluster without enforcement is a gap.

### What the admission layer must enforce

**Image trust (the core of the program):**
- Image signature is valid and issued to the **expected CI identity**
  (keyless/OIDC), not any signer.
- Required **attestations present** (SBOM, SLSA provenance).
- Image pulled from an **allowed registry** only.
- Image referenced by **digest**, not a mutable tag; `:latest` rejected.

Example: [../examples/kubernetes/kyverno-verify-images.yaml](../examples/kubernetes/kyverno-verify-images.yaml)

**Workload hardening (the Pod spec baseline):**
- `runAsNonRoot: true` + numeric `runAsUser`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: ["ALL"]`
- `seccompProfile.type: RuntimeDefault`
- No `privileged`, `hostNetwork`, `hostPID`, `hostIPC`, or `hostPath`
- Resource `requests`/`limits` set

Examples:
[../examples/kubernetes/kyverno-require-non-root.yaml](../examples/kubernetes/kyverno-require-non-root.yaml),
[../examples/kubernetes/opa-gatekeeper-constraint.yaml](../examples/kubernetes/opa-gatekeeper-constraint.yaml)

### Rollout strategy: audit → enforce

Do not flip enforcement on cold. Roll out in phases per policy:

1. **Audit mode** — policy logs violations but admits everything. Measure the
   blast radius; find the non-compliant workloads.
2. **Enforce in non-prod** — block in dev/staging; teams fix.
3. **Enforce in prod** — fail closed. Exceptions go through the waiver process.

Kyverno `validationFailureAction: Audit → Enforce`; Gatekeeper
`enforcementAction: dryrun → deny`.

## 2. Pod Security Standards (the platform baseline)

Kubernetes ships three built-in profiles enforced by the Pod Security admission
plugin at the **namespace** level:

| Profile | Use |
|---------|-----|
| `privileged` | Only for trusted infra/system namespaces |
| `baseline` | Minimum for general workloads |
| **`restricted`** | **Target for all application namespaces** |

Label application namespaces to `restricted` in enforce mode:

```yaml
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/warn: restricted
pod-security.kubernetes.io/audit: restricted
```

See [../examples/kubernetes/pod-security-standards.yaml](../examples/kubernetes/pod-security-standards.yaml).

PSS is the fast, native floor. Kyverno/OPA layer the image-trust and org-specific
rules on top. Use both: PSS for the workload baseline, the policy engine for
signature verification and custom standards.

## 3. Runtime detection and response

Admission is point-in-time. Runtime security covers the gap between "admitted"
and "compromised."

- **Falco / eBPF sensors** watch syscalls and flag:
  - a shell spawning inside a shell-less (distroless) container — a strong
    compromise signal,
  - unexpected process execution or privilege changes,
  - writes to read-only paths, sensitive file reads,
  - unexpected outbound network connections.
- **Continuous image scanning** re-evaluates running images against fresh CVE
  data nightly, feeding the rebuild queue (doc 02, Stage 10).
- **Behavioral drift** from the image's known-good profile is alerted.

Because hardened images have no shell and no package manager, many classic
post-exploitation steps simply fail — and the *attempt* is a high-fidelity alert.

## 4. Network policy (least-privilege east-west)

- Default-deny ingress and egress per namespace.
- Allow only the specific flows each workload needs.
- Combined with mTLS (service mesh) where warranted.

## 5. Putting it together

A hardened deployment that satisfies this layer end to end:
[../examples/kubernetes/deployment-hardened.yaml](../examples/kubernetes/deployment-hardened.yaml)
— non-root, read-only root fs, all capabilities dropped, seccomp
`RuntimeDefault`, deployed by digest, ready to pass the admission policies above.

---

**Next:** [05 — Governance & Compliance](05-governance-and-compliance.md)
