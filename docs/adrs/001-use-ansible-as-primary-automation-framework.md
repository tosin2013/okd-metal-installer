# 1. Use Ansible as Primary Automation Framework

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Infrastructure Automation, Configuration Management

## Context

The OKD-Metal installer requires an orchestration layer to coordinate bare-metal provisioning workflows including host inventory management, Ignition configuration generation, ISO customization, DNS record creation, and network configuration. The PRD originally suggested a "Python/FastAPI or Go" lightweight API backend to accept declarative host definitions and serve Ignition configurations over HTTP.

However, the project's core problem domain -- bare-metal infrastructure provisioning -- aligns directly with the strengths of Ansible: declarative inventory management, idempotent configuration, extensive module ecosystem for infrastructure tasks (AWS Route 53, file templating, command execution), and native support for orchestrating multi-host workflows without requiring a long-running service.

## Decision

Use Ansible as the primary automation and orchestration framework for OKD-Metal, replacing the proposed standalone API service.

Key architectural mappings:

- **Host definitions**: Ansible inventory files and `group_vars`/`host_vars` replace API-driven host registration
- **Ignition generation**: Ansible roles wrapping `openshift-install` replace dynamic HTTP-served Ignition
- **ISO customization**: Ansible playbooks invoking `coreos-installer iso customize`
- **DNS management**: `amazon.aws.route53` Ansible collection module
- **Network config**: Ansible templates generating NMState/nmconnection files
- **End-to-end workflow**: Ansible playbooks provide the orchestration layer

## Consequences

### Positive

- Eliminates the need for a persistent API service, reducing operational complexity
- Ansible's declarative inventory model is a natural fit for bare-metal host definitions (MAC addresses, roles, IP allocations)
- Extensive existing Ansible collections for AWS, networking, and OS-level tasks
- Idempotent execution enables safe re-runs and incremental provisioning
- Large community familiarity in the infrastructure/ops space, aligning with the OKD target audience
- No custom API code to maintain, test, or secure

### Negative

- Loses the ability to dynamically serve Ignition configs over HTTP from a persistent endpoint; must pre-generate and stage configs
- Ansible playbook execution is inherently sequential per host group (though parallelism is configurable via `forks`)
- Debugging Ansible playbooks can be less transparent than debugging API request/response cycles
- Requires Ansible to be installed on the operator workstation or jumpbox

## Implementation Plan

1. Define Ansible collection structure: `okd_metal` collection with roles for each provisioning phase
2. Create inventory schema with required host variables (MAC, role, IP, disk target)
3. Implement roles: `ignition_generate`, `iso_customize`, `dns_configure`, `network_configure`, `cluster_deploy`
4. Create top-level playbooks: `site.yml`, `prepare.yml`, `deploy.yml`, `cleanup.yml`

## Related PRD Sections

- Section 5: Functional Requirements -- "Lightweight Configuration API"
- Section 6: Technical Architecture & Constraints -- `openshift-install` wrapping, modular architecture

## Domain References

- Ansible Best Practices: https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html
- Ansible Collection Structure: https://docs.ansible.com/ansible/latest/dev_guide/developing_collections.html
