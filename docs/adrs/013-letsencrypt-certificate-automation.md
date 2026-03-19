# 13. Let's Encrypt Certificate Automation

**Status**: Proposed
**Date**: 2026-03-19
**Domain**: TLS/PKI, Day-2 Operations, Cluster Security

## Context

OKD deploys with self-signed certificates by default. The cluster-internal CA issues certificates for the API server (`api.okd-sno.ocpincubator.com:6443`), the web console (`console-openshift-console.apps.okd-sno.ocpincubator.com`), OAuth endpoints, and the default ingress controller. While these certificates are valid within the cluster's trust chain, they are not trusted by external clients:

- Browsers display security warnings on the web console and OAuth login
- CLI tools (`oc login`) require `--insecure-skip-tls-verify` or manual CA trust
- External integrations (CI/CD webhooks, monitoring, GitOps) reject untrusted TLS connections
- The `*.apps` wildcard certificate affects all Routes, not just the console

For a production-oriented SNO deployment on Hetzner, trusted certificates are a day-2 requirement. The cluster already has Route 53 DNS management (ADR-004) with AWS credentials available, which enables DNS-01 ACME challenges for automated certificate issuance.

## Decision

Use **cert-manager** with **Let's Encrypt** via the **DNS-01 challenge** (solved through AWS Route 53) to automate trusted wildcard certificates for the OKD cluster.

### Scope

Two certificate targets, in priority order:

1. **Ingress wildcard** (`*.apps.okd-sno.ocpincubator.com`): Covers the web console, OAuth, all application Routes. This is the highest-impact change -- a single certificate secures all ingress traffic.

2. **API server** (`api.okd-sno.ocpincubator.com`): Optional and more involved. Requires patching the kube-apiserver operator's serving cert configuration. Recommended only if external API consumers require trusted TLS.

### Approach A (Recommended): cert-manager operator via OperatorHub

1. Install cert-manager from OperatorHub (Red Hat-supported operator, available on OKD)
2. Create an AWS credentials Secret in the `cert-manager` namespace for Route 53 access
3. Create a `ClusterIssuer` resource pointing to Let's Encrypt production (or staging for testing) with DNS-01 solver configured for Route 53
4. Create a `Certificate` resource in `openshift-ingress` namespace for `*.apps.<cluster>.<domain>`
5. Patch the default `IngressController` to reference the cert-manager-issued Secret
6. (Optional) Create a `Certificate` for `api.<cluster>.<domain>` and patch the API server

**Why DNS-01 over HTTP-01**: The ingress certificate is a wildcard (`*.apps`), and HTTP-01 cannot validate wildcard domains. DNS-01 is the only ACME challenge type that supports wildcards. Since we already manage Route 53 via Ansible (ADR-004), the same AWS credentials and hosted zone can be reused.

### Approach B (Alternative): Manual certbot on jumpbox

1. Install `certbot` and `certbot-dns-route53` plugin on the jumpbox
2. Run `certbot certonly --dns-route53 -d '*.apps.okd-sno.ocpincubator.com'`
3. Create a TLS Secret from the issued certificate files
4. Patch the `IngressController` to use the Secret
5. Set up a cron job or systemd timer for renewal
6. After renewal, re-create the Secret and restart the ingress controller

**Trade-offs**: Approach B is simpler to set up initially but requires external renewal automation. Approach A handles renewal automatically within the cluster via cert-manager's certificate lifecycle management.

## Consequences

### Positive

- Browsers trust the web console and OAuth endpoints without security warnings
- CLI tools (`oc login`) work without `--insecure-skip-tls-verify`
- External integrations (webhooks, monitoring, GitOps) can verify TLS
- Automatic 90-day certificate renewal via cert-manager eliminates manual rotation
- Reuses existing Route 53 credentials from ADR-004 -- no new cloud dependencies
- cert-manager is a mature CNCF project with broad Kubernetes ecosystem support

### Negative

- Adds a dependency on Let's Encrypt availability (rate limits, outages)
- Requires AWS credentials to be available inside the cluster (not just on the jumpbox)
- cert-manager operator adds resource overhead (small, but present on SNO)
- DNS-01 challenge propagation can take 1-2 minutes per issuance
- Let's Encrypt certificates are only valid for 90 days (mitigated by automatic renewal)
- Staging vs production ACME endpoints require awareness during testing

## Key Considerations

### AWS Credentials for DNS-01

The cluster needs Route 53 write access for DNS-01 challenges. The existing AWS credentials (used by the `dns_configure` role on the jumpbox) can be reused:

- Create a Kubernetes Secret in `cert-manager` namespace with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- The IAM user (`digital-ocean`, per the current deployment) already has Route 53 permissions
- For better security, consider creating a dedicated IAM user with only `route53:GetChange`, `route53:ChangeResourceRecordSets`, and `route53:ListHostedZonesByName` permissions

### Ansible Integration

Two options for operationalizing this:

1. **Runbook only** (recommended for now): Document the manual `oc` commands in a runbook. Certificate setup is a one-time day-2 operation with automatic renewal, so full Ansible automation has limited value.

2. **Post-deploy role** (future): Create a `roles/cert_manager/` Ansible role that installs the operator, configures the ClusterIssuer, and issues certificates. This becomes valuable if clusters are deployed frequently.

### Certificate Resources

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@ocpincubator.com
    privateKeySecretRef:
      name: letsencrypt-production-key
    solvers:
    - dns01:
        route53:
          region: eu-central-1
          hostedZoneID: Z04957801CD6ZAE7L5S0E
          accessKeyIDSecretRef:
            name: aws-route53-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-route53-credentials
            key: secret-access-key
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: apps-wildcard
  namespace: openshift-ingress
spec:
  secretName: apps-wildcard-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
  - "*.apps.okd-sno.ocpincubator.com"
```

### IngressController Patch

```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  defaultCertificate:
    name: apps-wildcard-tls
```

## Related ADRs

- ADR-004: Route 53 DNS integration (provides the DNS infrastructure and credentials reused for DNS-01)
- ADR-003: Bootstrap-in-place architecture (the deployment that produces the cluster needing certificates)
- ADR-010: Ignition configuration generation (produces the initial self-signed certificates)

## Domain References

- cert-manager documentation: https://cert-manager.io/docs/
- cert-manager Route 53 DNS-01: https://cert-manager.io/docs/configuration/acme/dns01/route53/
- OpenShift replacing default ingress cert: https://docs.openshift.com/container-platform/latest/security/certificates/replacing-default-ingress-certificate.html
- OpenShift replacing API server cert: https://docs.openshift.com/container-platform/latest/security/certificates/api-server.html
- Let's Encrypt rate limits: https://letsencrypt.org/docs/rate-limits/
- ACME DNS-01 challenge: https://letsencrypt.org/docs/challenge-types/#dns-01-challenge
