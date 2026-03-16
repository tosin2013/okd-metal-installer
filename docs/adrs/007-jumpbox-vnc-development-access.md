# 7. Jumpbox with VNC for Development Access

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Development Infrastructure, Remote Access

## Context

Developing and debugging a bare-metal provisioning tool requires direct interaction with the target hardware, including visibility into boot processes, BIOS/UEFI screens, and OS installation steps. The target infrastructure is hosted on Hetzner dedicated servers, which support VNC access through their Robot API and Cloud API.

A dedicated jumpbox provides a consistent development environment isolated from the cluster nodes, with graphical access for debugging low-level boot and provisioning issues.

### Current Environment

- **Server**: Hetzner Dedicated Server (Robot API managed)
- **OS**: CentOS Stream 10 (Coughlan), kernel 6.12.0-184.el10
- **Firewall**: `nftables` installed but inactive; `firewalld` not installed
- **Desktop**: None installed
- **Ansible**: `ansible-core 2.16.16` pre-installed

## Decision

Provision the Hetzner dedicated server as the jumpbox with VNC and development tools using the `roles/jumpbox_provision/` Ansible role. The specific technology choices for this environment:

1. **VNC server**: TigerVNC -- the standard VNC implementation for RHEL/CentOS
2. **Desktop environment**: Xfce -- lightweight (~200MB vs ~2GB for GNOME), sufficient for browser and terminal access
3. **Firewall**: `firewalld` installed on top of the existing `nftables` backend (firewalld uses nftables as its backend on EL10)
4. **VNC access**: Direct port 5901/tcp (display :1) opened in firewall
5. **VNC user**: `root` (the current operator on the box)

Additionally, the jumpbox will include:

- **Ansible** and required collections (`amazon.aws`, `community.general`, `ansible.posix`)
- **`openshift-install`** binary for Ignition generation
- **`coreos-installer`** for ISO customization
- **`oc` / `kubectl`** CLI tools for cluster interaction
- **Hetzner CLI tools** for server management (Robot API)
- **Web browser** (Firefox) for OKD console and Hetzner management

The role is designed to run locally on the jumpbox itself via `ansible-playbook playbooks/jumpbox.yml -i inventory/local.ini`.

## Consequences

### Positive

- Isolates development tooling from cluster nodes; clean separation of concerns
- VNC provides graphical access for debugging boot-time issues on Hetzner hardware
- Consistent, reproducible development environment via Ansible automation
- Can serve as the HTTP server for serving Ignition configs and ISOs to booting nodes
- Hetzner's VNC support (Robot API endpoint: `boot/vnc`) integrates with remote server management
- Xfce is resource-efficient; leaves headroom for running `openshift-install` and other tooling
- `firewalld` provides a manageable firewall abstraction over `nftables`

### Negative

- VNC port 5901 is exposed directly; traffic is not encrypted without SSH tunnel or VNC+TLS
- Running a desktop environment on a server consumes memory (~300-500MB for Xfce + VNC)
- `firewalld` installation adds a service; must ensure SSH (port 22) remains accessible after enabling

## Implementation Plan

1. Create `roles/jumpbox_provision/` Ansible role
2. Install `firewalld`, enable it, ensure SSH access is preserved
3. Install Xfce desktop group and TigerVNC server
4. Configure VNC server: password, display :1, geometry, Xfce session
5. Open port 5901/tcp in firewalld
6. Enable and start VNC systemd service (`vncserver@:1`)
7. Install dev tools: `openshift-install`, `coreos-installer`, `oc`, `kubectl`
8. Add Hetzner CLI/API tooling for server management
9. Optionally configure nginx to serve ISOs and Ignition configs

## Related PRD Sections

- Section 4: User story -- "VNC access to development machine hosted on Hetzner"
- Section 5: "Jumpbox VNC Access"
- Section 6: Jumpbox architecture description
- References [2], [3]: Hetzner Cloud and Robot VNC API endpoints

## Domain References

- Hetzner Robot VNC API: https://robot.hetzner.com/doc/webservice/en.html#boot-vnc-post
- Hetzner Cloud Console API: https://docs.hetzner.cloud/reference/cloud#server-actions-request-console
- TigerVNC: https://tigervnc.org/
- Xfce: https://xfce.org/
- firewalld: https://firewalld.org/
