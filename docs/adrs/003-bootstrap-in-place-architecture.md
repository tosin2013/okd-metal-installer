# 3. Bootstrap-in-Place Architecture

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Cluster Bootstrapping, OKD/OpenShift Architecture

## Context

Traditional OpenShift/OKD installations require a dedicated bootstrap node that runs the initial cluster bootstrapping process and is then discarded. This adds hardware requirements, complexity, and time to the deployment process. For Single-Node OKD (SNO) and compact (3-node) clusters, a throwaway bootstrap node is particularly wasteful.

OpenShift 4.x introduced "bootstrap-in-place" (BIP) support, where the bootstrap process runs on the node that will become part of the cluster. This is especially relevant for SNO deployments.

## Decision

Adopt bootstrap-in-place (BIP) as the default bootstrapping strategy for SNO and compact cluster topologies. For full HA clusters (3+ control plane + workers), support both BIP and traditional bootstrap depending on user preference and hardware availability.

The `openshift-install` binary will be invoked with the appropriate flags to generate BIP-compatible Ignition configs. The Ansible role wrapping `openshift-install` will detect the cluster topology from the inventory and select the correct bootstrap strategy.

## Consequences

### Positive

- Eliminates the need for a dedicated bootstrap node in SNO and compact deployments
- Reduces minimum hardware requirements by one server
- Simplifies the deployment workflow -- fewer moving parts
- Aligns with upstream OKD/OpenShift direction for edge deployments
- Faster time-to-deploy since no bootstrap node provisioning/teardown cycle

### Negative

- BIP is less mature than traditional bootstrap; may encounter edge cases
- Recovery from a failed BIP bootstrap is more complex (the node has already been partially configured)
- Must handle the interaction between BIP and the FCOS-to-SCOS pivot issue (Reference [1] in PRD)
- Full HA clusters may still benefit from traditional bootstrap for reliability

## Implementation Plan

1. Extend the `ignition_generate` role to detect topology from inventory (SNO, compact, HA)
2. Generate BIP Ignition configs for SNO using `openshift-install create single-node-ignition-config`
3. For compact clusters, generate BIP-compatible configs with appropriate `install-config.yaml` settings
4. For HA clusters, default to traditional bootstrap but allow BIP override via variable
5. Add validation tasks to verify BIP compatibility before proceeding

## Related PRD Sections

- Section 5: "Bootstrap-in-Place Architecture"
- Section 5: "Flexible Cluster Topologies"
- Section 6: FCOS/SCOS compatibility constraints

## Domain References

- OpenShift Bootstrap-in-Place: https://docs.openshift.com/container-platform/latest/installing/installing_sno/install-sno-installing-sno.html
- OKD Issue #2041 (FCOS/SCOS pivot): https://github.com/okd-project/okd/issues/2041
