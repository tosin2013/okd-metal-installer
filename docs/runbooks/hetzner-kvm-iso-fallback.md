# Hetzner KVM/VNC ISO Mount Fallback

**When to use**: The automated Hetzner boot delivery (Mode 3) has failed due to emergency mode, boot order issues, or dual-disk complexity. This runbook describes how to manually mount and boot the OKD installation ISO using Hetzner's KVM Console.

## Prerequisites

- Access to Hetzner Robot panel (https://robot.your-server.de)
- The customized ISO is already built and served by the jumpbox nginx server
- If the jumpbox has VNC access (ADR-007), you can use it to access the Robot panel from the jumpbox desktop

## Option A: KVM Console with Virtual Media (ISO mount)

### 1. Order a KVM Console

1. Log into Hetzner Robot
2. Navigate to your server (e.g., 88.99.140.83)
3. Go to the **Support** tab
4. Select **"Remote console / KVM"**
5. In the comment field, note that you need virtual media support
6. Submit the request

**Cost**: Free for the first 3 hours. Additional 3-hour blocks cost EUR 8.40 (before VAT).

### 2. Access the KVM Console

1. Wait for the support ticket confirmation email with KVM credentials
2. Open the KVM web interface URL provided in the email
3. Log in with the provided credentials

### 3. Mount the ISO via Virtual Media

1. In the KVM console, go to the **Interfaces** tab
2. Select **Virtual Media**
3. Enter the ISO URL: `http://<jumpbox_ip>:8080/iso/<hostname>.iso`
   - Example: `http://176.9.223.218:8080/iso/sno-node.iso`
4. Wait for the ISO to load (there is no progress bar -- be patient)
5. The KVM console only supports mounting via **SMB/CIFS** protocol. If HTTP doesn't work, you may need to share the ISO via Samba on the jumpbox.

### 4. Boot from the Virtual CD

1. If the server is in rescue mode, deactivate rescue via Robot
2. Reboot the server via Robot or the KVM console
3. During BIOS POST, press the appropriate key (usually F12 or F11) to access the boot menu
4. Select the virtual CD/DVD drive
5. The CoreOS live ISO will boot

### 5. Monitor the BIP Process

With the KVM console, you can watch the boot process directly. The BIP bootstrap takes approximately 30-45 minutes.

After the ISO boots:
1. The BIP Ignition fires in the live ISO environment
2. Bootkube starts the control plane bootstrap
3. `install-to-disk.service` writes the final OS to the local disk
4. The system reboots automatically

### 6. Post-installation

1. Remove the virtual media (disconnect in the KVM console)
2. Verify the server boots from the local disk
3. Continue with bootstrap monitoring from the jumpbox:
   ```
   ansible-playbook -i inventory/sno-prod/hosts.ini playbooks/site.yml --tags monitor
   ```

## Option B: USB Stick (Hetzner Technician)

### 1. Request a USB Stick

1. Log into Hetzner Robot
2. Navigate to your server
3. Go to the **Support** tab
4. Select **"Remote console / KVM"**
5. In the comment field, provide a direct download link to the ISO:
   - `http://<jumpbox_ip>:8080/iso/<hostname>.iso`
   - Ensure the jumpbox firewall allows external access on port 8080
6. Request that technicians create a bootable USB stick from the ISO

**Cost**: The USB stick creation is free of charge. The KVM console itself follows the standard pricing above.

### 2. Boot from USB

Hetzner technicians will:
1. Download the ISO
2. Create a bootable USB stick
3. Connect it to your server along with the KVM console
4. You can then boot from the USB via the KVM console

### 3. Monitor and Complete

Same as Option A steps 5-6.

## Why This Approach Works

The standard BIP flow is designed for external boot media (USB/CD):
- The ISO boots from the virtual CD or USB (runs from RAM)
- `install-to-disk.service` writes to the local NVMe disk (which is free, not the boot device)
- No dual-disk complexity or MBR wipe needed
- No "busy partitions" error since the boot device and installation target are separate

This is the simplest and most reliable BIP deployment path. The only downside is the manual intervention required.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Virtual media fails to load | Try SMB/CIFS instead of HTTP. Set up Samba on the jumpbox. |
| Server doesn't boot from virtual CD | Access BIOS setup via KVM and change boot order to prioritize CD/USB |
| ISO is too large for virtual media | Request USB stick from Hetzner technicians instead |
| BIP fails during bootstrap | Use the KVM console to check journal logs: `journalctl -u bootkube.service` |
| install-to-disk fails | Check which disk `install-to-disk.sh` targets: `journalctl -u install-to-disk.service` |

## References

- [Hetzner KVM Console docs](https://docs.hetzner.com/robot/dedicated-server/maintenance/kvm-console/)
- [Hetzner Installing Custom Images](https://docs.hetzner.com/robot/dedicated-server/operating-systems/installing-custom-images/)
- ADR-007: Jumpbox VNC Development Access
- ADR-011: Boot Delivery Strategy (Fallback section)
