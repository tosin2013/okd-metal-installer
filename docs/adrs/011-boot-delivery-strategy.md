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

Implement three boot delivery modes, selectable per-host via the Ansible inventory variable `boot_method`:

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

### Mode 3: Hetzner Robot (`boot_method: hetzner`)

For Hetzner dedicated servers that lack Redfish/IPMI virtual media, the Hetzner Robot API provides an alternative automation path:

1. Ansible registers an SSH public key with the Hetzner Robot API (if not already registered)
2. Activates the Hetzner Linux rescue system via `POST /boot/{server-ip}/rescue`
3. Performs a hardware reset via `POST /reset/{server-ip}` to boot into rescue
4. Waits for the rescue system to become reachable via SSH
5. **Wipes all disks** in the rescue system to prevent boot order confusion on multi-disk servers (critical for servers with multiple NVMe drives)
6. Downloads the customized ISO from the jumpbox's config HTTP server to the rescue system via `wget`
7. Writes the ISO directly to the target boot disk using `dd`
8. Deactivates rescue mode via `DELETE /boot/{server-ip}/rescue`
9. Hardware resets the server to boot CoreOS from the written disk
10. Waits for the CoreOS node to become reachable via SSH

Required per-host inventory variables for Hetzner mode:
- `hetzner_robot_user`: Robot webservice username (recommend Ansible Vault)
- `hetzner_robot_password`: Robot webservice password (recommend Ansible Vault)
- `hetzner_ssh_key_fingerprint`: Fingerprint of the SSH key registered with Robot
- `dest_device`: Target disk device path (e.g., `/dev/nvme0n1`)

**Multi-disk consideration**: Hetzner auction/dedicated servers frequently have multiple identical drives. The disk wipe step (introduced after a failed first deployment) ensures that only the target disk contains bootable data, preventing EFI boot order confusion after `coreos-installer install` rewrites the partition table during bootstrap-in-place.

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
- Hetzner mode enables full automation for Hetzner dedicated servers without Redfish
- Per-host selection allows mixed environments (some nodes Redfish, some manual, some Hetzner)
- `community.general.redfish_command` is a mature, well-tested Ansible module
- Ansible pause provides a clean operator handoff point without breaking the playbook flow
- No custom BMC tooling to maintain; leverages standard Redfish protocol and vendor APIs

### Negative

- Manual mode requires operator presence during deployment
- Redfish behavior varies across BMC vendors; edge cases may require vendor-specific workarounds
- BMC credentials must be securely managed (Ansible Vault recommended)
- Virtual media ISO URL must be HTTP-reachable from the BMC network (network topology constraint)
- No IPMI fallback for servers with IPMI but not Redfish (could be added later)
- Hetzner mode requires the jumpbox HTTP server to be reachable from the rescue system (same Hetzner network)
- Hetzner Robot API credentials grant broad server control -- must be vaulted

## Implementation Plan

1. Create `roles/boot_deliver/` Ansible role with `boot_method` conditional branching
2. Implement manual path with `ansible.builtin.pause` and informational `debug` messages
3. Implement Redfish path using `community.general.redfish_command` for virtual media insert, boot device set, and power control
4. Implement Hetzner path using `ansible.builtin.uri` for Robot API calls and SSH for rescue system operations
5. Add BMC/API credential variables to inventory schema and document Vault usage
6. Add post-boot SSH reachability check as validation gate
7. Integrate into `playbooks/site.yml` after ISO customization step

## Related ADRs

- ADR-001: Ansible-first orchestration (boot delivery is an Ansible role)
- ADR-002: Custom discovery agent and boot media (produces the ISO to deliver)
- ADR-010: Ignition configuration generation (Ignition embedded in ISO)

## Domain References

- DMTF Redfish specification: https://www.dmtf.org/standards/redfish
- Ansible redfish_command module: https://docs.ansible.com/ansible/latest/collections/community/general/redfish_command_module.html
- Ansible redfish_info module: https://docs.ansible.com/ansible/latest/collections/community/general/redfish_info_module.html
- Hetzner Robot API documentation: https://robot.your-server.de/doc/webservice/en.html
