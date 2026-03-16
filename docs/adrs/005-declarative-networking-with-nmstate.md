# 5. Declarative Networking with NMState

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Network Configuration, Bare-Metal Provisioning

## Context

Bare-metal OKD deployments frequently require complex network configurations: bonded interfaces, VLANs, static IPs, and multi-NIC setups. These configurations must be applied before the cluster forms -- the discovery ISO must boot with the correct networking to phone home and download Ignition configs.

Kubernetes NMState provides a declarative API for network configuration that can be pre-compiled into NetworkManager `.nmconnection` files. These files can be embedded directly into the FCOS live ISO, ensuring correct networking from first boot.

## Decision

Use NMState-compatible declarative network definitions to generate `.nmconnection` files that are embedded into the discovery ISO. The approach:

1. Users define network configuration per-host in Ansible `host_vars` using a simplified NMState-like YAML schema
2. An Ansible role (`network_configure`) compiles these definitions into `.nmconnection` files using `nmstatectl` or Jinja2 templates
3. The `.nmconnection` files are passed to the `iso_customize` role for embedding via `coreos-installer iso customize --network-keyfile`
4. Post-installation, the full NMState operator can optionally manage ongoing network state

## Consequences

### Positive

- Network configuration is declarative and version-controlled alongside the rest of the cluster definition
- `.nmconnection` files are applied at boot time, before any cluster services start
- Supports complex topologies: bonds, VLANs, bridges, static routes
- `coreos-installer` natively supports `--network-keyfile` for embedding network config
- No runtime dependency on external network configuration services during initial boot

### Negative

- nmconnection file format is less human-readable than NMState YAML; the compilation step adds complexity
- Must validate network configs before ISO generation (a broken network config means an unbootable ISO)
- Different NIC naming across hardware vendors requires per-host customization
- NMState tooling (`nmstatectl`) may not be available on all operator workstations; may need a container-based approach

## Implementation Plan

1. Create `roles/network_configure/` Ansible role
2. Define host_vars schema for network definitions (interfaces, bonds, VLANs, IPs, routes, DNS)
3. Implement Jinja2 templates for `.nmconnection` file generation as the primary path
4. Add optional `nmstatectl` compilation path for users with the tool available
5. Add validation tasks to check network config sanity (IP conflicts, missing gateways, etc.)
6. Integrate output directory with `iso_customize` role's network-keyfile input

## Related PRD Sections

- Section 5: "Declarative Networking"
- Section 6: NMState integration details

## Domain References

- NMState: https://nmstate.io/
- NetworkManager connection profiles: https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html
- coreos-installer --network-keyfile: https://coreos.github.io/coreos-installer/cmd/iso/#coreos-installer-iso-customize
