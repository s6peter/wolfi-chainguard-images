# SPIFFE/SPIRE for Platform Service Identity

Cross-cluster, cross-cloud, short-lived mTLS identity for platform
service-to-service calls (docs/06 §4). Use when IRSA (cloud IAM) isn't enough —
e.g. a service in cluster B calling the platform API in cluster A, or non-K8s
workloads.

## SPIFFE ID scheme

```text
spiffe://acme.internal/ns/sbom-platform/sa/ingester
spiffe://acme.internal/ns/sbom-platform/sa/query-api
spiffe://acme.internal/cluster/prod-eu/ns/apps/sa/payments-api
```

## SPIRE registration entry (workload attestation)

Register which workloads get which SPIFFE ID, keyed on attestable selectors
(K8s namespace + ServiceAccount, node identity, etc.). SPIRE issues a short-TTL
SVID (X.509 cert) only to a process that matches.

```bash
spire-server entry create \
  -spiffeID spiffe://acme.internal/ns/sbom-platform/sa/ingester \
  -parentID spiffe://acme.internal/spire/agent/k8s_psat/prod-us \
  -selector k8s:ns:sbom-platform \
  -selector k8s:sa:sbom-ingester \
  -ttl 3600
```

## How it's used

1. The SPIRE agent on the node attests the workload (verifies it really is that
   namespace/SA) and hands it an SVID — a short-lived mTLS certificate.
2. The workload presents the SVID on outbound calls; the peer validates it and
   authorizes by **SPIFFE ID** (not IP, not a shared secret).
3. SVIDs rotate automatically (minutes-long TTL); nothing static to leak.

```text
ingester pod ──(SPIRE agent attests)──▶ SVID (mTLS cert, ~1h)
     │  mTLS to query-api, peer identity = spiffe://acme.internal/ns/sbom-platform/sa/query-api
     ▼
 authorized by SPIFFE ID in policy (e.g. Istio AuthorizationPolicy / app-level check)
```

## When to choose SPIFFE vs IRSA vs OIDC

| Scenario | Use |
|----------|-----|
| Pod → AWS S3/KMS | IRSA |
| CI → sign artifacts (keyless) | OIDC → Fulcio |
| CI/service → platform API (inbound authz) | OIDC token, audience-scoped |
| Service ↔ service mTLS across clusters/clouds/VMs | **SPIFFE/SPIRE** |

They compose — see docs/06 §5. Common deployment: SPIFFE via a service mesh
(Istio/Linkerd) so mTLS + identity are transparent to app code.
