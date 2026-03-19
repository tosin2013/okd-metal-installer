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
5. Downloads the customized ISO from the jumpbox's config HTTP server to the rescue system via `wget`
6. **Pre-dd validation**: verifies the release image embedded in `openshift-install` is pullable from the container registry (runs on the jumpbox, not rescue -- see Lessons Learned). If validation fails, the playbook aborts *before* touching any disks, leaving the server in a recoverable rescue state.
7. **Wipes all disks** to prevent boot order confusion on multi-disk servers (only after validation passes)
8. Writes the ISO to `live_iso_device` using `dd` (split into separate `dd` and `sync` tasks -- see Lessons Learned)
9. Deactivates rescue mode via `DELETE /boot/{server-ip}/rescue`
10. Hardware resets the server to boot the live CoreOS ISO from `live_iso_device`
11. The BIP Ignition fires in the live ISO environment, bootstraps the cluster (~30-45 min), then `install-to-disk.service` writes the final OS to `installation_disk`
12. On dual-disk servers, an MBR wipe service removes the bootloader from `live_iso_device` before the automatic reboot, forcing BIOS to fall through to `installation_disk`
13. Waits for the CoreOS node to become reachable via SSH on the final installed system
14. **Post-boot validation**: verifies CoreOS booted (not rescue or stale OS), Ignition was applied, and the release image is pullable from the running node

Required per-host inventory variables for Hetzner mode:
- `hetzner_robot_user`: Robot webservice username (recommend Ansible Vault)
- `hetzner_robot_password`: Robot webservice password (recommend Ansible Vault)
- `hetzner_ssh_key_fingerprint`: Fingerprint of the SSH key registered with Robot

**Disk variables for Hetzner mode (see ADR-003 for BIP architecture):**

| Variable | Purpose | Example | Default |
|----------|---------|---------|---------|
| `live_iso_device` | Disk where the ISO is `dd`'d; BIOS boots this first | `/dev/nvme0n1` | `{{ dest_device }}` |
| `installation_disk` | Disk where `install-to-disk.service` writes the final OS | `/dev/nvme1n1` | `{{ dest_device }}` |
| `dest_device` | Legacy variable, used as default for both above | `/dev/nvme0n1` | `/dev/sda` |

On single-disk servers, all three variables point to the same disk and the standard BIP flow works (boot from external media, install to local disk). On multi-disk BIOS servers where `dd` is used instead of external media, `live_iso_device` and `installation_disk` must differ.

**Multi-disk BIOS consideration**: Hetzner auction/dedicated servers frequently have multiple identical NVMe drives. When booting from a `dd`'d ISO (no USB/virtual CD), the live ISO occupies one disk and `install-to-disk.service` must write to the other. An MBR wipe systemd service (injected via a supplementary live Ignition fragment) clears the live ISO disk's bootloader after installation completes, ensuring the BIOS falls through to the installation disk on reboot.

### Mode 3b: Hetzner Robot with coreos-installer from rescue (`boot_method: hetzner`, `hetzner_install_method: rescue_install`)

An alternative path for Hetzner servers that bypasses the live ISO phase entirely:

1. Steps 1-6 same as Mode 3
2. Downloads the `coreos-installer` binary to the rescue system
3. Downloads the modified BIP Ignition from the jumpbox
4. Runs `coreos-installer install -i BIP.ign <live_iso_device>` from rescue, which writes CoreOS + BIP Ignition directly to disk
5. Deactivates rescue, hardware resets
6. BIOS boots the installed CoreOS; BIP Ignition fires on the installed system
7. `install-to-disk.service` writes to `installation_disk`, MBR wipe removes the first-boot disk's bootloader, system reboots

**Caution**: This path runs BIP on an installed system rather than a live ISO. The BIP Ignition (`bootstrap-in-place-for-live-iso.ign`) was designed for the live ISO environment. While this approach has been observed to work, it is less tested than Mode 3 and may encounter edge cases with overlay filesystem behavior or space constraints.

### Fallback: Manual VNC/KVM ISO mount

When automated boot delivery encounters issues (emergency mode, boot order problems, etc.), operators can fall back to manual ISO mounting:

1. Order a KVM Console via Hetzner Robot (Support tab, "Remote console / KVM")
2. Access the KVM web interface and use the Virtual Media feature to mount the ISO from an HTTP/SMB URL
3. Alternatively, request a USB stick -- Hetzner technicians will create a bootable USB from a provided ISO download link (free of charge)
4. Boot from the virtual CD or USB; standard single-disk BIP flow proceeds without dual-disk complexity
5. After installation, remove the virtual media or USB

**Cost**: KVM Console is free for the first 3 hours; additional 3-hour blocks cost EUR 8.40. Virtual media requires SMB/CIFS access. If the jumpbox has VNC access (see ADR-007), operators can use it to access the Hetzner Robot panel and order KVM from there.

This fallback eliminates all dual-disk and MBR wipe complexity since the ISO boots from virtual/removable media while `install-to-disk` writes to the local NVMe disk.

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

## Lessons Learned (Deployments on 88.99.140.83, March 2026)

### 1. Pre-dd validation prevents unrecoverable state

The original step sequence wiped disks before downloading the ISO, meaning any subsequent failure (bad ISO, stale release image) left the server with blank disks and no way to recover without KVM or re-entering rescue. The revised sequence downloads and validates first, then wipes. If the release image is unpullable (e.g., garbage-collected from quay.io), the playbook aborts while the server is still in rescue with disks intact.

### 2. Hetzner rescue is minimal -- no container runtime

The Hetzner rescue system is a stripped-down Debian environment. It does **not** include `podman`, `skopeo`, or any container tooling. An initial attempt to test-pull the release image via `podman pull` on the rescue system failed with `command not found`. Release image validation must run on the **jumpbox** (which has `podman` installed), not via SSH to the rescue system. The network path to quay.io is equivalent from both systems (same Hetzner DC), so the validation result is transferable.

### 3. `dd` via `ansible.builtin.shell` crashes silently

Using `ansible.builtin.shell` with a complex SSH-piped `dd` command (including `status=progress` and chained `&& sync`) caused Ansible to exit with code 2 and no error message. This happened consistently across multiple runs. The fix:

- Split into two `ansible.builtin.command` tasks: one for `dd`, one for `sync`
- Remove `status=progress` (the progress output on stderr appears to overwhelm Ansible's output handler when piped through SSH)
- Add an explicit `timeout: 600` to the `dd` task

### 4. Post-boot validation catches wrong-OS boot

After the server reboots from the written disk, SSH becoming reachable does not guarantee CoreOS booted. The server could boot into rescue (if rescue wasn't properly deactivated) or a stale OS from a secondary disk. Post-boot validation checks `/etc/os-release` for "CoreOS", verifies `/etc/.ignition-result.json` exists, and test-pulls the release image to confirm the bootstrap chain will succeed.

### 5. Release image lifecycle is a deployment risk

The `openshift-install` binary embeds a specific release image digest. OKD SCOS releases on quay.io can be garbage-collected, causing the embedded digest to become unpullable. This breaks the entire bootstrap chain at `release-image.service` on first boot. Pre-dd validation now catches this, but operators should verify the `openshift-install` binary's embedded image is still available before starting a deployment. See ADR-003 for broader implications.

### 6. `--dest-ignition` + `--dest-device` is incompatible with BIP

The initial implementation used `coreos-installer iso customize --dest-device /dev/nvme0n1 --dest-ignition bootstrap-in-place-for-live-iso.ign`. This caused a chain of failures:

1. `--dest-device` triggered an automatic `coreos-installer install` during initramfs, writing CoreOS to the target disk and rebooting
2. After reboot, the BIP Ignition fired on the installed system
3. `install-to-disk.service` attempted `coreos-installer install` against the same disk, which failed with "found busy partitions" because the disk was mounted as the running root

The fix: switch to `--live-ignition` (equivalent to `iso ignition embed`), which embeds the BIP Ignition into the live ISO environment where the bootstrap is designed to run. See ADR-003 for the complete analysis of `--live-ignition` vs `--dest-ignition`.

### 7. BIOS-mode dual-disk servers need MBR wipe for boot fallthrough

On the Hetzner server 88.99.140.83 (BIOS/Legacy mode, two NVMe disks), the boot order is PXE first, then local disk (nvme0n1 first). When the ISO is `dd`'d to nvme0n1 and the final OS is installed to nvme1n1 by `install-to-disk.service`, the system would reboot back into the live ISO on nvme0n1 indefinitely.

The solution: inject a systemd service via a supplementary live Ignition fragment that wipes the first 512 bytes (MBR) of nvme0n1 after `install-to-disk.service` completes but before the scheduled reboot (`shutdown -r +1` provides a 1-minute window). With the MBR zeroed, BIOS skips nvme0n1 and falls through to nvme1n1 where the final OS resides.

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
