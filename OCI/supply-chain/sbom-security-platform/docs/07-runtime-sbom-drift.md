# 07 — Runtime Security: Comparing Running Containers vs SBOM

An SBOM describes what an artifact *should* contain at build time. A running
container can diverge — through injected dependencies, `curl | sh` in an
entrypoint, a compromised process writing binaries, or a base layer that shipped
more than the SBOM recorded. **Runtime drift detection reconciles what is
actually running against the SBOM it claims.** Divergence is a high-fidelity
security signal.

---

## 1. Why build-time truth isn't enough

```text
BUILD TIME (SBOM):   app + libs A,B,C          ← attested, signed, in the platform
                             │
                             ▼  deploy
RUNTIME (actual):    app + libs A,B,C + X       ← where did X come from?
                                        └──────── drift = investigate
```

Drift causes worth catching:

- **Injected/downloaded dependencies** — an entrypoint that fetches code at
  start (`pip install`, `curl | sh`), so the running set ≠ the built set.
- **Post-exploitation artifacts** — an attacker drops a binary or library.
- **Mutable base drift** — the image wasn't pinned by digest and the base
  changed under it.
- **Config/agent sidecars** injected at runtime not reflected in the SBOM.
- **Loaded-but-not-declared** — the classic "is Log4j *actually loaded* in this
  JVM, or just present on disk?" question.

## 2. Two complementary techniques

### A. Inventory reconciliation (running packages vs SBOM)

Periodically capture what is installed/loaded in a running pod and **diff it
against the attested SBOM** for that image digest.

```text
for each running pod:
  digest      := pod.container.image digest
  sbom        := platform.get_authoritative_sbom(digest)     # doc 03
  running     := inventory(pod)                              # installed pkgs / loaded libs
  drift       := running − sbom        (present at runtime, absent from SBOM)
              ∪ sbom − running_loaded  (shipped but never loaded → reachability signal)
  if drift:   raise finding, route to owner
```

- **`present at runtime but not in SBOM`** → integrity alert (highest priority).
- **`in SBOM but never loaded`** → informs reachability/VEX (`not_affected` if a
  vulnerable lib is never loaded).

Reference implementation:
[../examples/runtime-drift/compare-running-vs-sbom.sh](../examples/runtime-drift/compare-running-vs-sbom.sh)
(captures a running container's package inventory via `syft`, fetches the
artifact's SBOM, and reports the delta).

### B. Behavioral runtime detection (Falco / Tetragon / eBPF)

Watch syscalls and process/network activity for behavior that *implies* drift or
compromise, in real time:

- a **shell spawned** in a shell-less (distroless) container,
- a process **writing an executable** to disk, then executing it,
- **package-manager or `curl`/`wget` execution** at runtime,
- unexpected **outbound connections** (exfiltration, C2).

Falco/Tetragon give real-time alerts; inventory reconciliation gives a precise,
attributable "what changed" answer. Use both: behavior catches the event,
reconciliation confirms and scopes the impact.

## 3. Feeding results back into the platform

Runtime findings are not a dead end — they close the loop:

```text
drift finding ─▶ platform correlates with SBOM/CVE/VEX
              ─▶ enriches reachability (loaded vs present) → sharper VEX
              ─▶ prioritizes: drift in a deployed, internet-facing service first
              ─▶ routes: ticket / SOAR / forced rebuild-from-base
```

- Confirmed integrity drift on a production workload is an **incident**, not a
  ticket.
- "Present but never loaded" downgrades a vuln's priority via VEX
  (`not_affected` with justification "component not loaded at runtime").
- Repeated drift from the same image → fix the build (pin digests, remove
  runtime downloads), don't just clean the pod.

## 4. Remediation model

Consistent with the whole program: **rebuild, don't mutate.**

- Never "fix" a drifted container in place — it breaks immutability and
  provenance and vanishes on restart.
- Correct the **build** (pin bases by digest, eliminate runtime `install`
  steps), rebuild, re-attest the SBOM, redeploy.
- Quarantine (cordon/isolate via NetworkPolicy) a container with confirmed
  malicious drift pending investigation.

## 5. Operational placement

- **Reconciliation job** — scheduled DaemonSet/CronJob per cluster; samples
  running pods, queries the platform, reports drift. Rate-limit to avoid load.
- **Behavioral sensors** — Falco/Tetragon as a DaemonSet on every node.
- **Central correlation** — both feed the platform, which owns dedup,
  prioritization, and routing (doc 03 §6).

---

**Next:** [08 — Enterprise Adoption](08-enterprise-adoption.md)
