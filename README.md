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
- **Config HTTP server** (nginx) for serving Ignition configs and ISOs to booting nodes

## Architecture

All provisioning workflows are implemented as Ansible playbooks and roles (see [ADR-001](docs/adrs/001-use-ansible-as-primary-automation-framework.md)). There is no standalone API service -- Ansible inventory files and `group_vars`/`host_vars` define the cluster topology declaratively.

Full architectural decisions are documented in 11 ADRs under [`docs/adrs/`](docs/adrs/).

## Project Structure

```
okd-metal-installer/
├── ansible.cfg                 # Ansible configuration defaults
├── requirements.yml            # Ansible collection dependencies
├── .ansible-lint               # ansible-lint configuration
├── .yamllint                   # yamllint configuration
├── group_vars/
│   └── all.yml                 # Shared variables (cluster, network, boot config)
├── host_vars/                  # Per-host variable overrides (network, BMC)
├── inventory/
│   ├── local.ini               # Localhost inventory for jumpbox provisioning
│   └── examples/               # Example inventories (sno, compact, ha)
│       ├── sno.ini
│       ├── compact.ini
│       ├── ha.ini
│       └── host_vars/          # Example per-host variable files
├── playbooks/
│   ├── jumpbox.yml             # Jumpbox VNC/desktop + cluster tooling
│   ├── site.yml                # Full OKD deployment orchestration
│   └── disconnected.yml        # Disconnected preparation (mirror + bundle)
├── roles/
│   ├── preflight/              # Input validation + topology detection
│   ├── ignition_generate/      # install-config.yaml templating + openshift-install
│   ├── network_configure/      # NMState YAML to .nmconnection generation
│   ├── iso_customize/          # CoreOS ISO download + per-host customization
│   ├── config_serve/           # nginx HTTP server for Ignition and ISOs
│   ├── dns_configure/          # Route 53 DNS record management
│   ├── dns_internal/           # dnsmasq DNS for disconnected environments
│   ├── disconnected_prepare/   # Mirror registry + release mirror + bundling
│   ├── boot_deliver/           # Manual pause or Redfish virtual media boot
│   └── jumpbox_provision/      # VNC, Xfce, firewalld, OKD CLI tools
├── files/
│   └── discovery-agent.sh      # Post-install agent embedded into ISOs
├── templates/
│   ├── install-config.yaml.j2  # OKD install-config template
│   └── nmconnection-*.j2       # NetworkManager connection templates
├── docs/
│   ├── adrs/                   # Architectural Decision Records (001-011)
│   ├── aws-iam-policy.json     # Minimum IAM policy for Route 53 DNS
│   └── implementation-backlog.md
└── rules/
    └── architectural-rules.json
```

## Prerequisites

- **Control node**: RHEL/CentOS Stream 10 (or Fedora 40+) with `ansible-core >= 2.16`
- **Python**: 3.12+ with `boto3` and `botocore` (for Route 53 DNS)
- **Target hardware**: x86_64 bare-metal servers with IPMI/BMC access
- **DNS**: AWS Route 53 hosted zone, or internal dnsmasq (disconnected mode)
- **Pull secret**: From [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) (for SCOS) or empty JSON `{}` (for FCOS)
- **Disconnected mode**: `podman` for local registry, sufficient disk for image mirroring (~20GB+)

## Quick Start

```bash
# Install required Ansible collections
ansible-galaxy collection install -r requirements.yml

# Install Python dependencies for Route 53 DNS
pip3 install boto3 botocore

# Provision the jumpbox with VNC, desktop, and OKD CLI tools
ansible-playbook -i inventory/local.ini playbooks/jumpbox.yml

# Deploy a single-node OKD cluster
cp inventory/examples/sno.ini inventory/mycluster.ini
mkdir -p host_vars
cp inventory/examples/host_vars/sno-node.yml host_vars/sno-node.yml
# Edit mycluster.ini and host_vars/sno-node.yml with your host details
ansible-playbook -i inventory/mycluster.ini playbooks/site.yml
```

### Deployment Flow

```
site.yml executes:
  0. Disconnected   -> mirror registry + release mirror (if disconnected=true)
  1. Preflight      -> validate inputs, detect topology (SNO/compact/HA)
  2. Ignition       -> template install-config.yaml, generate .ign files
  3. Networking     -> compile host_vars network definitions to .nmconnection
  4. ISO Customize  -> download CoreOS ISO, embed ignition + network + agent
  5. Config Serve   -> deploy nginx, stage ignition configs and ISOs
  6. DNS Configure  -> Route 53 (connected) or dnsmasq (disconnected)
  7. Boot Deliver   -> manual upload (pause) or Redfish virtual media boot
```

### Disconnected / Air-Gapped Deployment

For environments without internet access, run the preparation on a connected machine first:

```bash
# Step 1: On a connected jumpbox, mirror release and bundle artifacts
ansible-playbook -i inventory/mycluster.ini playbooks/disconnected.yml

# Step 2: Transfer the bundle to the air-gapped environment
scp disconnected-bundle/okd-metal-bundle-*.tar.gz airgap-jumpbox:/opt/

# Step 3: On the air-gapped jumpbox, extract and deploy
tar -xzf /opt/okd-metal-bundle-*.tar.gz -C /opt/okd-metal/
ansible-playbook -i inventory/mycluster.ini playbooks/site.yml \
  -e disconnected=true \
  -e @disconnected-output/image-content-sources.yml
```

## Variable Reference

Key variables in `group_vars/all.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `okd-metal` | OKD cluster name |
| `base_domain` | `example.com` | Base DNS domain |
| `coreos_variant` | `scos` | CoreOS variant: `fcos` or `scos` |
| `disconnected` | `false` | Enable air-gapped installation mode |
| `openshift_install_binary` | `openshift-install` | Path to openshift-install binary |
| `pull_secret_path` | `../pull-secret.json` | Path to pull secret file |
| `ssh_key_path` | `~/.ssh/id_rsa.pub` | SSH public key for node access |
| `boot_method` | `manual` | Boot delivery: `manual` or `redfish` |
| `config_serve_port` | `8080` | HTTP port for config/ISO serving |
| `route53_zone_id` | `""` | AWS Route 53 hosted zone ID (empty = skip DNS) |
| `dns_ttl` | `300` | DNS record TTL in seconds |
| `mirror_registry_host` | `""` | Local mirror registry host (disconnected mode) |
| `mirror_registry_port` | `5000` | Local mirror registry port |
| `network_type` | `OVNKubernetes` | Cluster network plugin |
| `cluster_network_cidr` | `10.128.0.0/14` | Pod network CIDR |
| `service_network_cidr` | `172.30.0.0/16` | Service network CIDR |

Per-host variables (in `host_vars/<hostname>.yml`):

| Variable | Required | Description |
|----------|----------|-------------|
| `ansible_host` | Yes | Node IP address |
| `network_interfaces` | Yes | List of network interface definitions |
| `boot_method` | No | Override per-host: `manual` or `redfish` |
| `bmc_address` | Redfish only | BMC/iDRAC/iLO IP address |
| `bmc_user` | Redfish only | BMC username |
| `bmc_password` | Redfish only | BMC password (use Ansible Vault) |

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
- Phase 4 (Config Serve) -- complete
- Phase 5 (DNS Configuration) -- complete
- Phase 6 (Jumpbox + Cluster Tooling) -- complete
- Phase 7 (Disconnected/Air-Gapped) -- complete
- Phase 8 (Integration + Lint) -- complete
- Boot Delivery (ADR-011) -- complete
- All phases complete (MVP)

## License

Apache License 2.0
