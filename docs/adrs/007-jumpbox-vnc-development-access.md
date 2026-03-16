# 7. Jumpbox with VNC for Development Access

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Development Infrastructure, Remote Access

## Context

Developing and debugging a bare-metal provisioning tool requires direct interaction with the target hardware, including visibility into boot processes, BIOS/UEFI screens, and OS installation steps. The target infrastructure is hosted on Hetzner dedicated servers, which support VNC access through their Robot API and Cloud API.

A dedicated jumpbox provides a consistent development environment isolated from the cluster nodes, with graphical access for debugging low-level boot and provisioning issues.

## Decision

Provision a dedicated jumpbox server with VNC and development tools pre-configured. The jumpbox serves as the Ansible control node and developer workstation for the OKD-Metal project.

The jumpbox will be provisioned via Ansible and include:

1. **VNC server** (TigerVNC or similar) for graphical remote access
2. **Ansible** and all required collections (`amazon.aws`, `community.general`)
3. **`openshift-install`** binary for Ignition generation
4. **`coreos-installer`** for ISO customization
5. **`oc` / `kubectl`** CLI tools for cluster interaction
6. **Hetzner CLI tools** for server management (Robot API, Cloud API)
7. **Web browser** for accessing the OKD console and Hetzner management interfaces

The jumpbox role (`roles/jumpbox_provision/`) will automate the complete setup.

## Consequences

### Positive

- Isolates development tooling from cluster nodes; clean separation of concerns
- VNC provides graphical access for debugging boot-time issues on Hetzner hardware
- Consistent, reproducible development environment via Ansible automation
- Can serve as the HTTP server for serving Ignition configs and ISOs to booting nodes
- Hetzner's VNC support (Robot API endpoint: `boot/vnc`) integrates with remote server management

### Negative

- Adds an additional server to provision and maintain
- VNC is not encrypted by default; must tunnel via SSH or use VNC+TLS
- Jumpbox becomes a single point of failure for the development workflow
- Resource overhead of running a graphical environment on a server

## Implementation Plan

1. Create `roles/jumpbox_provision/` Ansible role
2. Implement tasks: install VNC server, configure firewall, install dev tools
3. Add SSH tunnel configuration for secure VNC access
4. Install and configure `openshift-install`, `coreos-installer`, `oc`, `kubectl`
5. Add Hetzner CLI/API tooling for server management
6. Optionally configure nginx to serve ISOs and Ignition configs

## Related PRD Sections

- Section 4: User story -- "VNC access to development machine hosted on Hetzner"
- Section 5: "Jumpbox VNC Access"
- Section 6: Jumpbox architecture description
- References [2], [3]: Hetzner Cloud and Robot VNC API endpoints

## Domain References

- Hetzner Robot VNC API: https://robot.hetzner.com/doc/webservice/en.html#boot-vnc-post
- Hetzner Cloud Console API: https://docs.hetzner.cloud/reference/cloud#server-actions-request-console
- TigerVNC: https://tigervnc.org/
