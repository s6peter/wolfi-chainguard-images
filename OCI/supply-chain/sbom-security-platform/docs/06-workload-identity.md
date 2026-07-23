# 06 — Secure Workload Identity (OIDC / IRSA / SPIFFE)

Every arrow in the platform diagram — CI uploading an SBOM, a service calling the
platform API, admission control querying a verdict — must authenticate. In a
mature program that authentication is **short-lived, federated identity**, never
a static secret. This document covers the three patterns enterprises use.

---

## 1. Why static secrets are the enemy

A long-lived API key or service-account token in a CI variable or a Kubernetes
Secret is a supply-chain liability: it can be exfiltrated, it rarely rotates, and
its use is hard to attribute. Federated workload identity replaces it with
**tokens that are short-lived, audience-scoped, and cryptographically tied to the
workload's identity**.

```text
static secret:   [long-lived key] ─────────────▶ resource   (steal once, use forever)
workload identity: workload ─(OIDC token, ~1h)─▶ trust ─▶ short-lived creds  (self-expiring, attributable)
```

## 2. OIDC federation (the foundation)

OpenID Connect is the common substrate. An identity provider (the CI system, the
Kubernetes API server, or a dedicated IdP) issues a signed JWT asserting *who the
workload is*. A relying party validates it against the issuer's public keys and
grants scoped access.

Two uses central to this platform:

- **Keyless signing** (doc 04) — CI presents its OIDC token to Sigstore Fulcio,
  which issues a short-lived signing cert bound to that identity.
- **Platform API access** — CI/services present an OIDC token to the platform
  ingestion/query API, which authorizes by identity claims (repo, workflow,
  namespace) instead of an API key.

Key claims to validate: `iss` (issuer), `aud` (audience — pin it),
`sub`/`repository`/`workflow` (the specific workload).

## 3. IRSA — IAM Roles for Service Accounts (AWS)

The dominant pattern for AWS-hosted platforms (many banks/insurers run on EKS).
IRSA maps a **Kubernetes ServiceAccount** to an **AWS IAM role** via the
cluster's OIDC provider — pods get temporary AWS credentials with **no static
keys**.

```text
Pod (ServiceAccount: sbom-ingester)
   │  projected OIDC token (from EKS OIDC provider)
   ▼
AWS STS AssumeRoleWithWebIdentity  ──▶  temp creds (~1h) for IAM role
   │  trust policy pins: OIDC provider + sub = system:serviceaccount:sbom:sbom-ingester + aud=sts.amazonaws.com
   ▼
scoped access to S3 (SBOM store), KMS (signing), etc.
```

- Trust policy pins the exact ServiceAccount, so only that workload can assume
  the role. Example:
  [../examples/workload-identity/irsa-trust-policy.json](../examples/workload-identity/irsa-trust-policy.json)
- ServiceAccount annotation binds the role. Example:
  [../examples/workload-identity/irsa-serviceaccount.yaml](../examples/workload-identity/irsa-serviceaccount.yaml)
- Equivalents: **GKE Workload Identity** (GCP), **Azure Workload Identity**
  (Azure AD federated credentials). Same shape — SA ↔ cloud role via OIDC.

## 4. SPIFFE / SPIRE — identity across clusters & clouds

For service-to-service identity that spans clusters, clouds, and non-Kubernetes
workloads, **SPIFFE** gives every workload a verifiable **SVID** (an X.509 cert
or JWT) with a **SPIFFE ID** like `spiffe://acme.internal/ns/sbom/sa/ingester`.
**SPIRE** is the runtime that attests workloads and issues short-lived SVIDs.

```text
workload ──attested by SPIRE agent (node + workload selectors)──▶ SVID (mТLS cert, minutes-long TTL)
   │
   └─▶ mutual TLS to platform API; peer identity = SPIFFE ID, authorized by policy
```

Use SPIFFE when:
- You need **mTLS identity** between the platform and services across many
  clusters/regions (common with a service mesh: Istio/Linkerd).
- Workloads are **heterogeneous** (VMs + Kubernetes + on-prem) and you want one
  identity fabric.

Example config: [../examples/workload-identity/spiffe-workload.md](../examples/workload-identity/spiffe-workload.md)

## 5. How the three fit together

| Need | Pattern |
|------|---------|
| CI signs artifacts without keys | OIDC → Fulcio (keyless) |
| CI/service authenticates to platform API | OIDC token, audience-scoped |
| Platform pods access cloud storage/KMS | IRSA (AWS) / Workload Identity (GCP/Azure) |
| Cross-cluster service-to-service mTLS | SPIFFE/SPIRE |

They compose: a platform pod uses **IRSA** for S3/KMS, presents a **SPIFFE**
SVID for mTLS to peer services, and validates **OIDC** tokens on inbound API
calls — all short-lived, all attributable, zero static secrets.

## 6. Principles

- **No static long-lived credentials** anywhere in the platform or its clients.
- **Audience-scope every token** — a token for the platform API must not work
  against anything else.
- **Least privilege** on the resulting cloud role / policy.
- **Attribute and log** every authenticated action by identity.
- **Short TTLs**; rely on continuous re-issuance, not rotation of secrets.

---

**Next:** [07 — Runtime SBOM Drift](07-runtime-sbom-drift.md)
