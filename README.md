# OKD-Metal Installer

Ansible-driven bare-metal provisioning for [OKD](https://www.okd.io/) (community Kubernetes distribution derived from OpenShift). OKD-Metal automates the full lifecycle of deploying OKD clusters on physical servers -- from Ignition config generation and custom ISO creation to DNS registration and network configuration.

## Key Features

- **Single-Node, Compact, and HA topologies** via declarative Ansible inventory
- **Bootstrap-in-Place** architecture eliminating the need for a dedicated bootstrap node
- **Custom discovery ISO** with embedded Ignition, SSH keys, and static network config
- **Route 53 DNS integration** for automated DNS record management
- **NMState-based networking** for declarative static IP and bond/VLAN configuration
- **FCOS / SCOS dual-OS support** (Fedora CoreOS and CentOS Stream CoreOS)
- **Disconnected / air-gapped mode** with local mirror support
- **Jumpbox VNC provisioning** for remote graphical access to the management host
- **Boot delivery** via manual ISO upload (with Ansible pause) or Redfish virtual media

## Architecture

All provisioning workflows are implemented as Ansible playbooks and roles (see [ADR-001](docs/adrs/001-use-ansible-as-primary-automation-framework.md)). There is no standalone API service -- Ansible inventory files and `group_vars`/`host_vars` define the cluster topology declaratively.

Full architectural decisions are documented in 11 ADRs under [`docs/adrs/`](docs/adrs/).

## Project Structure

```
okd-metal-installer/
├── ansible.cfg                 # Ansible configuration defaults
├── requirements.yml            # Ansible collection dependencies
├── group_vars/
│   └── all.yml                 # Shared variables (cluster, network, boot config)
├── host_vars/                  # Per-host variable overrides (network, BMC)
├── inventory/
│   ├── local.ini               # Localhost inventory for jumpbox provisioning
│   └── examples/               # Example inventories (sno, compact, ha)
├── playbooks/
│   ├── jumpbox.yml             # Jumpbox VNC/desktop + cluster tooling
│   └── site.yml                # Full OKD deployment orchestration
├── roles/
│   ├── preflight/              # Input validation + topology detection
│   ├── ignition_generate/      # install-config.yaml templating + openshift-install
│   ├── network_configure/      # NMState YAML to .nmconnection generation
│   ├── iso_customize/          # CoreOS ISO download + per-host customization
│   ├── boot_deliver/           # Manual pause or Redfish virtual media boot
│   └── jumpbox_provision/      # VNC, Xfce, firewalld, OKD CLI tools
├── files/
│   └── discovery-agent.sh      # Post-install agent embedded into ISOs
├── templates/
│   ├── install-config.yaml.j2  # OKD install-config template
│   ├── nmconnection-*.j2       # NetworkManager connection templates
│   └── ...
├── docs/
│   ├── adrs/                   # Architectural Decision Records (001-011)
│   └── implementation-backlog.md
└── rules/
    └── architectural-rules.json
```

## Prerequisites

- **Control node**: RHEL/CentOS Stream 10 (or Fedora 40+) with `ansible-core >= 2.16`
- **Python**: 3.12+
- **Target hardware**: x86_64 bare-metal servers with IPMI/BMC access
- **DNS**: AWS Route 53 hosted zone (or manual DNS for disconnected mode)
- **Pull secret**: From [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) (for SCOS) or empty JSON `{}` (for FCOS)

## Quick Start

```bash
# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml

# Provision the jumpbox with VNC, desktop, and OKD CLI tools
ansible-playbook -i inventory/local.ini playbooks/jumpbox.yml

# Deploy a single-node OKD cluster
cp inventory/examples/sno.ini inventory/mycluster.ini
# Edit inventory/mycluster.ini with your host details, IPs, and network config
ansible-playbook -i inventory/mycluster.ini playbooks/site.yml
```

### Deployment Flow

```
site.yml executes:
  1. Preflight     → validate inputs, detect topology (SNO/compact/HA)
  2. Ignition      → template install-config.yaml, generate .ign files
  3. Networking    → compile host_vars network definitions to .nmconnection
  4. ISO Customize → download CoreOS ISO, embed ignition + network + agent
  5. Boot Deliver  → manual upload (pause) or Redfish virtual media boot
```

## Architectural Decision Records

| ADR | Title |
|-----|-------|
| [001](docs/adrs/001-use-ansible-as-primary-automation-framework.md) | Use Ansible as Primary Automation Framework |
| [002](docs/adrs/002-custom-discovery-agent-and-boot-media.md) | Custom Discovery Agent and Boot Media |
| [003](docs/adrs/003-bootstrap-in-place-architecture.md) | Bootstrap-in-Place Architecture |
| [004](docs/adrs/004-route53-dns-integration.md) | Route 53 DNS Integration |
| [005](docs/adrs/005-declarative-networking-with-nmstate.md) | Declarative Networking with NMState |
| [006](docs/adrs/006-flexible-cluster-topology-support.md) | Flexible Cluster Topology Support |
| [007](docs/adrs/007-jumpbox-vnc-development-access.md) | Jumpbox VNC Development Access |
| [008](docs/adrs/008-fcos-scos-dual-os-compatibility.md) | FCOS/SCOS Dual-OS Compatibility |
| [009](docs/adrs/009-disconnected-airgapped-installation-support.md) | Disconnected/Air-Gapped Installation Support |
| [010](docs/adrs/010-ignition-configuration-generation.md) | Ignition Configuration Generation |
| [011](docs/adrs/011-boot-delivery-strategy.md) | Boot Delivery Strategy (Manual + Redfish) |

## Implementation Roadmap

The MVP implementation is tracked in a [phased backlog](docs/implementation-backlog.md) with 46 tasks across 9 phases, each referencing its governing ADRs.

**Current status:**
- Phase 0 (Scaffold) -- complete
- Phase 1 (Preflight + Ignition) -- complete
- Phase 2 (Networking) -- complete
- Phase 3 (ISO Customization) -- complete
- Phase 6 (Jumpbox + Cluster Tooling) -- complete
- Boot Delivery (ADR-011) -- complete
- Remaining: Phase 4 (Config Serve), Phase 5 (DNS), Phase 7 (Disconnected), Phase 8 (Integration)

## License

Apache License 2.0
