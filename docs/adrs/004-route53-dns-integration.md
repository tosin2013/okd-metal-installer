# 4. AWS Route 53 for DNS Management

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: DNS, Cloud Integration

## Context

OKD clusters require specific DNS records to function: `api.<cluster>.<domain>`, `api-int.<cluster>.<domain>`, `*.apps.<cluster>.<domain>`, and individual node A/PTR records. Manual DNS configuration is error-prone, slow, and a common source of installation failures.

The PRD specifies AWS Route 53 as the DNS provider. This aligns with Hetzner-hosted bare-metal servers that use external DNS (Hetzner does not provide managed DNS with the same API richness as Route 53).

## Decision

Integrate AWS Route 53 for automated DNS record management using the `amazon.aws.route53` Ansible collection module. The Ansible role will:

1. Accept the Route 53 hosted zone ID and AWS credentials as input variables
2. Create `A` records for each cluster node (control plane, workers)
3. Create `A` records for `api` and `api-int` endpoints pointing to control plane nodes (or a load balancer VIP)
4. Create a wildcard `A` record for `*.apps` pointing to the ingress endpoint
5. Optionally create `PTR` records for reverse DNS
6. Support idempotent record creation/updates for re-runs

AWS credentials will be provided via standard Ansible mechanisms: environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), Ansible vault-encrypted variables, or IAM instance profiles.

## Consequences

### Positive

- Fully automated DNS setup eliminates a major source of installation failures
- Ansible's `amazon.aws.route53` module is well-maintained and idempotent
- Route 53's API-first design enables reliable automation
- Supports TTL management for rapid iteration during development
- Credential handling via Ansible Vault provides secure secret management

### Negative

- Couples the tool to AWS for DNS (other DNS providers would require additional roles)
- Requires AWS account and IAM permissions; adds a cloud dependency to an otherwise on-prem tool
- Route 53 costs money (though minimal for the record counts involved)
- Users in fully air-gapped environments cannot use Route 53 and will need an alternative DNS solution

## Implementation Plan

1. Create `roles/dns_configure/` Ansible role
2. Define required variables: `route53_zone_id`, `cluster_name`, `base_domain`, node IPs
3. Implement tasks for A record creation (api, api-int, *.apps, individual nodes)
4. Add optional PTR record creation tasks
5. Add a pre-flight check task to validate AWS credentials and zone access
6. Document the required IAM policy for least-privilege access

## Related PRD Sections

- Section 5: "Route 53 DNS Integration"
- Section 6: Route 53 integration details, required DNS records

## Domain References

- amazon.aws.route53 module: https://docs.ansible.com/ansible/latest/collections/amazon/aws/route53_module.html
- OKD DNS requirements: https://docs.okd.io/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal
