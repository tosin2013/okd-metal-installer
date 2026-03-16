# 6. Flexible Cluster Topology Support

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Cluster Architecture, Deployment Strategy

## Context

OKD supports multiple cluster topologies with different trade-offs between resource efficiency, high availability, and operational complexity. The PRD requires support for:

- **Single-Node OKD (SNO)**: All roles on one node; minimal resources, no HA
- **Compact (3-node)**: Control plane and worker roles co-located on 3 nodes; moderate HA
- **Full HA**: 3+ dedicated control plane nodes with separate worker nodes; production-grade HA

Each topology requires different `install-config.yaml` parameters, different Ignition configs, different DNS records, and different bootstrap strategies.

## Decision

Support all three topologies through Ansible inventory-driven configuration. The topology is determined by the number and role assignment of hosts in the Ansible inventory:

- **SNO**: Inventory contains exactly 1 host with role `master`
- **Compact**: Inventory contains exactly 3 hosts with role `master` (workers are schedulable on masters)
- **Full HA**: Inventory contains 3+ hosts with role `master` and 1+ hosts with role `worker`

SNO is the default and simplest topology. The `ignition_generate` role inspects the inventory to auto-detect topology and configure `install-config.yaml` accordingly:
- SNO: `controlPlane.replicas: 1`, `compute.replicas: 0`, bootstrap-in-place enabled
- Compact: `controlPlane.replicas: 3`, `compute.replicas: 0`, `mastersSchedulable: true`
- Full HA: `controlPlane.replicas: 3`, `compute.replicas: N`, `mastersSchedulable: false`

## Consequences

### Positive

- Single inventory format supports all topologies; no separate configuration mechanisms
- Auto-detection reduces user error (miscounting nodes, mismatching config)
- SNO as default minimizes barrier to entry for homelabbers and evaluation
- Same playbooks and roles work across all topologies; logic branches are internal

### Negative

- Auto-detection heuristics may misinterpret unusual inventory configurations
- Compact cluster behavior (schedulable masters) has operational implications users must understand
- Testing matrix increases: each role/playbook must be validated against 3 topologies
- Some features (e.g., ingress HA) only apply to multi-node topologies, requiring conditional logic

## Implementation Plan

1. Define inventory group conventions: `[masters]`, `[workers]`, `[all:vars]`
2. Create topology detection logic in `roles/ignition_generate/tasks/detect_topology.yml`
3. Template `install-config.yaml` with topology-specific conditionals
4. Adjust DNS role to handle single-node vs multi-node record sets
5. Add inventory validation pre-flight checks (minimum nodes per topology, role assignments)
6. Provide example inventories for each topology in `examples/`

## Related PRD Sections

- Section 5: "Flexible Cluster Topologies"
- Section 4: User stories for SNO, edge, and homelabber deployments

## Domain References

- OKD SNO installation: https://docs.okd.io/latest/installing/installing_sno/install-sno-preparing-to-install-sno.html
- OpenShift compact clusters: https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html
