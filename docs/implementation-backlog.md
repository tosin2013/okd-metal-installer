# OKD-Metal MVP Implementation Backlog

**Generated from**: 13 ADRs in `docs/adrs/`
**Governed by**: Architectural rules in `rules/architectural-rules.json`
**Scope**: MVP (v0.1.0) per PRD.md Section 7

---

## Phase 0: Project Scaffold (Foundation)
**Goal**: Establish Ansible collection structure and shared configuration.
**Governing ADRs**: ADR-001
**Governing Rules**: ARCH-001, ARCH-002

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P0-01 | Create Ansible collection directory layout | `roles/`, `playbooks/`, `inventory/`, `group_vars/`, `host_vars/`, `files/`, `templates/` | 001 | Critical |
| P0-02 | Create `ansible.cfg` | Configure defaults: forks, inventory path, roles path, vault settings | 001 | Critical |
| P0-03 | Create `requirements.yml` | Declare Ansible collection dependencies: `amazon.aws`, `community.general`, `ansible.posix` | 001 | Critical |
| P0-04 | Create `group_vars/all.yml` | Shared variables: `cluster_name`, `base_domain`, `coreos_variant`, `disconnected`, SSH key path, pull secret path | 001, 008, 009 | Critical |
| P0-05 | Create example inventories | `inventory/examples/sno.ini`, `inventory/examples/compact.ini`, `inventory/examples/ha.ini` with documented host_vars | 006 | High |
| P0-06 | Create top-level playbooks | `site.yml` (full deploy), `prepare.yml` (pre-deploy), `deploy.yml` (provision), `cleanup.yml` (teardown) | 001 | High |

---

## Phase 1: Pre-flight and Ignition Generation (Core)
**Goal**: Validate inputs and generate Ignition configurations.
**Governing ADRs**: ADR-003, ADR-006, ADR-008, ADR-010
**Governing Rules**: ARCH-003, TECH-001, PROC-001, SEC-002

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P1-01 | Create `roles/preflight/` | Validate: OS variant vs ISO vs openshift-install compatibility, inventory sanity, credential availability, network reachability | 008, 006 | Critical |
| P1-02 | Create topology detection logic | `roles/preflight/tasks/detect_topology.yml` -- count masters/workers, set `cluster_topology` fact (sno/compact/ha) | 006 | Critical |
| P1-03 | Create `roles/ignition_generate/` | Template `install-config.yaml.j2`, invoke `openshift-install create ignition-configs` or `create single-node-ignition-config` | 010, 003 | Critical |
| P1-04 | Template `install-config.yaml.j2` | Support all topology variants, configurable pull secret, SSH key, network CIDR, cluster/service networks, image content sources | 010, 006, 009 | Critical |
| P1-05 | Add bootstrap-in-place logic | Detect SNO/compact topology and generate BIP-compatible Ignition configs | 003 | High |
| P1-06 | Add config lifecycle management | Detect expired Ignition certs (24h), archive old configs, regenerate on demand | 010 | Medium |

---

## Phase 2: Network Configuration (Networking)
**Goal**: Generate and validate per-host network configurations.
**Governing ADRs**: ADR-005
**Governing Rules**: PROC-002

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P2-01 | Create `roles/network_configure/` | Role to compile NMState-like YAML to `.nmconnection` files | 005 | High |
| P2-02 | Define host_vars network schema | Document schema: interfaces, bonds, VLANs, static IPs, routes, DNS servers | 005 | High |
| P2-03 | Create `.nmconnection` Jinja2 templates | Templates for: ethernet, bond, vlan, bridge connection profiles | 005 | High |
| P2-04 | Add network validation tasks | Check for IP conflicts, missing gateways, unreachable DNS, duplicate MACs | 005 | Medium |
| P2-05 | Add optional `nmstatectl` path | If `nmstatectl` is available, use it for compilation; otherwise fall back to templates | 005 | Low |

---

## Phase 3: ISO Customization (Boot Media)
**Goal**: Build customized FCOS/SCOS ISOs with discovery agent and network config.
**Governing ADRs**: ADR-002, ADR-008
**Governing Rules**: TECH-003, TECH-001

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P3-01 | Create `roles/iso_customize/` | Role to download base ISO and customize with coreos-installer | 002 | Critical |
| P3-02 | Implement discovery agent script | `files/discovery-agent.sh` -- hardware telemetry, phone-home, coreos-installer install, reboot | 002 | Critical |
| P3-03 | Add ISO download tasks | Download FCOS or SCOS ISO based on `coreos_variant` variable with checksum verification | 002, 008 | High |
| P3-04 | Embed network keyfiles | Pass `.nmconnection` files via `coreos-installer iso customize --network-keyfile` | 002, 005 | High |
| P3-05 | Add CA certificate injection | Embed custom CA certs for disconnected mirror registry trust | 002, 009 | Medium |
| P3-06 | Add ISO URL lookup table | `defaults/main.yml` with FCOS/SCOS ISO download URLs by version | 008 | Medium |

---

## Phase 4: Config Serving (Infrastructure)
**Goal**: Serve Ignition configs and ISOs to booting nodes.
**Governing ADRs**: ADR-010, ADR-002
**Governing Rules**: SEC-002

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P4-01 | Create `roles/config_serve/` | Deploy nginx to serve Ignition configs and ISOs on configurable port | 010 | High |
| P4-02 | Stage Ignition configs | Copy generated configs to nginx document root with 0600 permissions | 010 | High |
| P4-03 | Stage custom ISO | Copy generated ISO to nginx document root for PXE/HTTP boot | 002 | Medium |
| P4-04 | Add TLS support | Optional TLS termination for secure config serving | 010 | Low |

---

## Phase 5: DNS Configuration (Cloud Integration)
**Goal**: Automate DNS record creation in Route 53.
**Governing ADRs**: ADR-004
**Governing Rules**: SEC-001

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P5-01 | Create `roles/dns_configure/` | Role for Route 53 DNS record management | 004 | High |
| P5-02 | Add A record creation tasks | Create api, api-int, *.apps, and per-node A records | 004 | High |
| P5-03 | Add PTR record creation tasks | Optional reverse DNS records | 004 | Medium |
| P5-04 | Add AWS credential validation | Pre-flight check for Route 53 zone access and IAM permissions | 004 | High |
| P5-05 | Document required IAM policy | Least-privilege IAM policy for Route 53 operations | 004 | Medium |

---

## Phase 6: Jumpbox Provisioning (Development)
**Goal**: Automate jumpbox setup for development and cluster management.
**Governing ADRs**: ADR-007

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P6-01 | Create `roles/jumpbox_provision/` | Install VNC server, dev tools, Ansible, CLI tools | 007 | Medium |
| P6-02 | Install cluster tooling | `openshift-install`, `coreos-installer`, `oc`, `kubectl` | 007 | Medium |
| P6-03 | Configure SSH tunnel for VNC | Secure VNC access via SSH tunnel configuration | 007 | Medium |
| P6-04 | Add Hetzner API tooling | Install hcloud CLI and configure Robot API access | 007 | Low |

---

## Phase 7: Disconnected Support (Air-gap)
**Goal**: Enable fully offline installations.
**Governing ADRs**: ADR-009
**Governing Rules**: TECH-002

| Task ID | Task | Description | ADR | Priority |
|---------|------|-------------|-----|----------|
| P7-01 | Create `roles/disconnected_prepare/` | Mirror registry setup, artifact bundling | 009 | Medium |
| P7-02 | Implement `oc mirror` wrapper tasks | Populate local registry from release images | 009 | Medium |
| P7-03 | Add artifact bundling | Collect ISOs, binaries, configs into transferable tarball | 009 | Medium |
| P7-04 | Modify install-config for mirrors | Add `imageContentSources` to install-config.yaml template | 009 | Medium |
| P7-05 | Create `roles/dns_internal/` | Internal DNS role as disconnected alternative to Route 53 | 009 | Low |

---

## Phase 8: Integration and Testing
**Goal**: End-to-end integration and validation.
**Governing ADRs**: All
**Status**: Partially Complete (March 2026)

| Task ID | Task | Description | ADR | Status |
|---------|------|-------------|-----|--------|
| P8-01 | SNO integration test | End-to-end SNO deployment on Hetzner hardware -- validated 2026-03-19, bootstrap in 19 min, full install in 32 min | All | Done |
| P8-02 | Compact cluster integration test | 3-node compact cluster deployment | All | Pending |
| P8-03 | Ansible lint and validation | ansible-lint, yamllint across all roles and playbooks | 001 | Pending |
| P8-04 | Documentation | README.md with quickstart, architecture overview, variable reference | All | Pending |
| P8-05 | Example configurations | Complete example inventories and group_vars for each topology | 006 | Pending |

---

## Phase 9: Operational Hardening (Post-Deployment Lessons)
**Goal**: Harden boot delivery and bootstrap against real-world failure modes discovered during Hetzner deployments.
**Governing ADRs**: ADR-003, ADR-011, ADR-012
**Status**: Completed (March 2026)

| Task ID | Task | Description | ADR | Status |
|---------|------|-------------|-----|--------|
| P9-01 | Pre-dd release image validation | Verify `openshift-install` embedded release image is pullable from jumpbox before wiping disks; abort cleanly if stale | 011 | Done |
| P9-02 | Post-boot CoreOS validation | After SSH reachable, verify OS is CoreOS, Ignition applied, release image pullable from node | 011, 012 | Done |
| P9-03 | dd/sync task split | Replace `ansible.builtin.shell` dd with two `ansible.builtin.command` tasks (dd + sync); remove `status=progress` to prevent silent Ansible crash | 011 | Done |
| P9-04 | site.yml tag-based execution | Add tags (`preflight`, `boot`, `monitor`, etc.) to all plays for selective re-runs | 012 | Done |
| P9-05 | Boot delivery step reorder | Reorder Hetzner flow: download ISO -> validate -> wipe disks -> dd (was: wipe -> download -> dd) | 011 | Done |
| P9-06 | Upgrade openshift-install to 4.22.0-okd-scos.ec.9 | Replace stale 4.21.0-okd-scos.8 binary whose release image was garbage-collected from quay.io | 003 | Done |

---

## Phase 10: BIP Boot Architecture Fix (Dual-Disk BIOS)
**Goal**: Fix the BIP ISO customization to use the correct `--live-ignition` approach, implement dual-disk strategy with MBR wipe for BIOS-mode Hetzner servers, and add alternative boot paths.
**Governing ADRs**: ADR-003, ADR-011
**GitHub Issue**: [#3](https://github.com/tosin2013/okd-metal-installer/issues/3)

| Task ID | Task | Description | ADR | Status |
|---------|------|-------------|-----|--------|
| P10-01 | Switch ISO customization to `--live-ignition` | Replace `--dest-ignition` + `--dest-device` with `--live-ignition` for SNO/BIP; keep `--dest-ignition` for non-BIP topologies | 003 | Done |
| P10-02 | Add `installation_disk` variable | Separate `installationDisk` (where install-to-disk writes) from `dest_device` / `live_iso_device` for multi-disk BIOS servers | 003, 011 | Done |
| P10-03 | Patch install-to-disk.sh for `--copy-network` | Post-process BIP ignition to add `--copy-network` to `coreos-installer install` so static IP config persists | 003 | Done |
| P10-04 | Generate MBR wipe ignition fragment | Create supplementary live ignition with systemd service to wipe live ISO disk MBR after install-to-disk completes | 011 | Done |
| P10-05 | Implement `rescue_install` alternative | Add `hetzner_install_method: rescue_install` path that runs `coreos-installer install` from rescue mode (bypasses live ISO) | 011 | Done |
| P10-06 | Document VNC/KVM fallback runbook | Operational runbook for manual ISO mounting via Hetzner KVM Console virtual media | 011 | Done |
| P10-07 | Update ADR-003 with research findings | Document `--live-ignition` vs `--dest-ignition`, dual-disk BIP, network config persistence | 003 | Done |
| P10-08 | Update ADR-011 with corrected flow | Document updated Hetzner Mode 3, Mode 3b, disk variables, MBR wipe, VNC fallback | 011 | Done |

---

## Phase 11: Day-2 Post-Deployment Operations
**Goal**: Automate common post-deployment tasks for production readiness.
**Governing ADRs**: ADR-013, ADR-004
**Status**: Planned

| Task ID | Task | Description | ADR | Status |
|---------|------|-------------|-----|--------|
| P11-01 | Let's Encrypt wildcard certificate | Install cert-manager, configure DNS-01 ClusterIssuer via Route 53, issue `*.apps` wildcard cert, patch IngressController | 013 | Done |
| P11-02 | API server trusted certificate | (Optional) Issue cert for `api.<cluster>.<domain>` and patch kube-apiserver serving cert | 013 | Pending |
| P11-03 | Post-install validation playbook | Smoke tests: node Ready, all ClusterOperators Available, console reachable, OAuth functional | 012 | Pending |
| P11-04 | Cluster backup strategy | etcd snapshot automation, backup schedule, restore runbook | -- | Pending |
| P11-05 | Upgrade automation | Document and optionally automate OKD version upgrades via CVO | -- | Pending |

---

## Dependency Graph

```
Phase 0 (Scaffold)
  |
  v
Phase 1 (Ignition) -----> Phase 3 (ISO) -----> Phase 4 (Config Serve)
  |                           ^
  v                           |
Phase 2 (Networking) ---------+
  
Phase 5 (DNS) -- independent, can parallel with Phase 3/4
Phase 6 (Jumpbox) -- independent, can start anytime
Phase 7 (Disconnected) -- depends on Phase 1, 3, 4
Phase 8 (Integration) -- depends on all previous phases
Phase 11 (Day-2 Ops) -- depends on successful deployment (Phase 8)
```

---

## Summary

| Phase | Tasks | Critical | High | Medium | Low | Status |
|-------|-------|----------|------|--------|-----|--------|
| 0 - Scaffold | 6 | 4 | 2 | 0 | 0 | Done |
| 1 - Ignition | 6 | 4 | 1 | 1 | 0 | Done |
| 2 - Networking | 5 | 0 | 3 | 1 | 1 | Done |
| 3 - ISO | 6 | 2 | 2 | 2 | 0 | Done |
| 4 - Config Serve | 4 | 0 | 2 | 1 | 1 | Done |
| 5 - DNS | 5 | 0 | 3 | 2 | 0 | Done |
| 6 - Jumpbox | 4 | 0 | 0 | 3 | 1 | Partial |
| 7 - Disconnected | 5 | 0 | 0 | 4 | 1 | Done |
| 8 - Integration | 5 | 1 | 3 | 1 | 0 | Partial (SNO validated) |
| 9 - Operational Hardening | 6 | -- | -- | -- | -- | Done |
| 10 - BIP Boot Fix | 8 | -- | -- | -- | -- | Done |
| 11 - Day-2 Operations | 5 | -- | -- | -- | -- | Partial |
| **Total** | **65** | **11** | **16** | **15** | **4** | |
