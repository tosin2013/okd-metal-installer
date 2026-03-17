# 11. Boot Delivery Strategy

**Status**: Accepted
**Date**: 2026-03-17
**Domain**: Bare-Metal Provisioning, BMC Management

## Context

OKD-Metal generates customized CoreOS ISOs containing Ignition configs, discovery agents, and network configuration. Once the ISO is built, it must be delivered to the target bare-metal server and booted. The existing ADRs (002, 010) cover ISO creation and Ignition generation but do not address how the ISO reaches the target server's boot path.

Bare-metal environments vary widely in management capabilities:

- **Modern data-center hardware** (Dell iDRAC 9+, HPE iLO 5+, Supermicro X11+, Lenovo XCC) exposes Redfish APIs for remote virtual media mount and power control
- **Older or consumer-grade hardware** (Hetzner auction servers, homelabs) may lack BMC entirely or have limited IPMI without virtual media support
- **Edge deployments** may rely on physical USB boot or operator-attended console access

A single boot delivery mechanism cannot cover all scenarios. The tool must support both fully automated and operator-attended workflows.

## Decision

Implement two boot delivery modes, selectable per-host via the Ansible inventory variable `boot_method`:

### Mode 1: Manual (`boot_method: manual`) -- Default

1. Ansible generates the customized ISO and prints its file path
2. Ansible issues `ansible.builtin.pause` prompting the operator to:
   - Upload the ISO to the target server's BMC/iLO/iDRAC web console, **or**
   - Write the ISO to a USB drive and physically boot from it, **or**
   - Use any vendor-specific remote mount mechanism
3. Operator presses ENTER to confirm the server has booted from the ISO
4. Ansible continues with post-boot monitoring and validation

This mode works with any hardware regardless of BMC capabilities.

### Mode 2: Redfish (`boot_method: redfish`)

1. Ansible serves the ISO via the config HTTP server (ADR-010 / `config_serve` role)
2. Uses `community.general.redfish_command` to:
   - Insert the ISO URL as virtual media (VirtualMediaInsert)
   - Set one-time boot device to virtual CD (SetOneTimeBoot)
   - Power cycle the server (PowerForceRestart)
3. Ansible monitors boot progress via Redfish power state polling
4. Continues with post-boot validation once the node is reachable via SSH

Required per-host inventory variables for Redfish mode:
- `bmc_address`: BMC/iDRAC/iLO IP or hostname
- `bmc_user`: BMC credentials username
- `bmc_password`: BMC credentials password (recommend Ansible Vault)

### Compatible BMC Firmware (Redfish)

| Vendor | BMC | Minimum Version | Virtual Media | Notes |
|--------|-----|-----------------|---------------|-------|
| Dell | iDRAC 9 | 4.x | Yes | Full Redfish support |
| HPE | iLO 5 | 2.x | Yes | Full Redfish support |
| Supermicro | X11+ IPMI | varies | Yes | Redfish support varies by model |
| Lenovo | XCC | varies | Yes | Full Redfish support |
| Hetzner (Dell) | iDRAC 9 | 4.x | Yes | Available on Dell dedicated servers |
| Hetzner (Fujitsu) | iRMC | varies | Limited | Manual mode recommended |

## Consequences

### Positive

- Manual mode ensures OKD-Metal works on any hardware, including homelabs and auction servers
- Redfish mode enables full hands-off automation for compatible hardware
- Per-host selection allows mixed environments (some nodes Redfish, some manual)
- `community.general.redfish_command` is a mature, well-tested Ansible module
- Ansible pause provides a clean operator handoff point without breaking the playbook flow
- No custom BMC tooling to maintain; leverages standard Redfish protocol

### Negative

- Manual mode requires operator presence during deployment
- Redfish behavior varies across BMC vendors; edge cases may require vendor-specific workarounds
- BMC credentials must be securely managed (Ansible Vault recommended)
- Virtual media ISO URL must be HTTP-reachable from the BMC network (network topology constraint)
- No IPMI fallback for servers with IPMI but not Redfish (could be added later)

## Implementation Plan

1. Create `roles/boot_deliver/` Ansible role with `boot_method` conditional branching
2. Implement manual path with `ansible.builtin.pause` and informational `debug` messages
3. Implement Redfish path using `community.general.redfish_command` for virtual media insert, boot device set, and power control
4. Add BMC credential variables to inventory schema and document Vault usage
5. Add post-boot SSH reachability check as validation gate
6. Integrate into `playbooks/site.yml` after ISO customization step

## Related ADRs

- ADR-001: Ansible-first orchestration (boot delivery is an Ansible role)
- ADR-002: Custom discovery agent and boot media (produces the ISO to deliver)
- ADR-010: Ignition configuration generation (Ignition embedded in ISO)

## Domain References

- DMTF Redfish specification: https://www.dmtf.org/standards/redfish
- Ansible redfish_command module: https://docs.ansible.com/ansible/latest/collections/community/general/redfish_command_module.html
- Ansible redfish_info module: https://docs.ansible.com/ansible/latest/collections/community/general/redfish_info_module.html
