# 12. Bootstrap Monitoring Strategy

**Status**: Accepted
**Date**: 2026-03-17
**Domain**: Cluster Bootstrapping, Deployment Observability

## Context

The OKD bootstrap-in-place (BIP) process on bare-metal is a 30-45 minute unattended procedure with no built-in callback mechanism. During the first real SNO deployment on Hetzner dedicated hardware, the following was observed:

1. **SSH is not a reliable bootstrap indicator.** After the BIP reboot (where `coreos-installer install` writes the OS to disk and the node reboots from the installed system), SSH port 22 becomes reachable but the OKD control plane may not yet be operational. In the initial deployment, SSH connections authenticated but immediately reset, while port 6443 remained closed.

2. **Multi-disk servers can cause boot order confusion.** The target Hetzner server had two identical NVMe drives. After BIP rewrote the partition table on the primary drive, the EFI boot entries changed and the BIOS potentially booted from the stale secondary drive. This required adding a disk wipe step before ISO delivery (see ADR-011 update).

3. **Manual monitoring does not scale.** Running `openshift-install wait-for` in a separate terminal and manually checking API availability is error-prone and cannot produce structured deployment reports.

The existing playbook (`site.yml`) ended at the boot delivery phase with no automated post-boot monitoring, leaving the operator to manually verify the cluster came up.

## Decision

Implement a `bootstrap_monitor` Ansible role that runs on the jumpbox after boot delivery and provides automated, end-to-end deployment observability through five sequential phases:

### Phase 1: API Health Polling

Poll `https://api.<cluster>.<domain>:6443/healthz` using `ansible.builtin.uri` with `validate_certs: false`. Accept HTTP 200, 401, or 403 as success (the API may return 401/403 before authentication is fully configured but this confirms the API server process is running). Retry with configurable interval (default 30s) and timeout (default 20 minutes).

**Rationale**: The API healthz endpoint is the earliest reliable signal that the bootstrap is progressing. Unlike SSH, it directly indicates that etcd and kube-apiserver are functional.

### Phase 2: Wait for Bootstrap Complete

Run `openshift-install wait-for bootstrap-complete` with `async` and `poll` to avoid Ansible SSH timeout issues. This waits for the bootstrap control plane to hand off to the permanent control plane. Default timeout: 45 minutes.

### Phase 3: Wait for Install Complete

Run `openshift-install wait-for install-complete` with `async` and `poll`. This waits for the cluster version to report available and all operators to stabilize. Default timeout: 60 minutes.

### Phase 4: Cluster Validation

Run `oc get nodes`, `oc get clusterversion`, and `oc get clusteroperators` to gather the final cluster state. These commands use the generated `KUBECONFIG` from the ignition output directory.

### Phase 5: Deployment Report

Produce a structured summary showing node status, cluster version, operator health, and access URLs (API endpoint, web console). This report is displayed as an Ansible debug message.

### Rejected Alternatives

- **SSH-based monitoring**: Rejected because SSH availability does not indicate OKD health. SSH can be reachable during rescue mode, during BIP live ISO phase, and during BIP reboot -- all before the cluster is functional.
- **Node journal scraping via SSH**: Rejected as too fragile -- requires SSH to the CoreOS node which may not be configured for jumpbox access, and journal output format varies.
- **External monitoring stack (Prometheus/Grafana)**: Rejected as over-engineering for a deployment tool. The cluster's own monitoring takes over once operational.

## Consequences

### Positive

- Fully automated end-to-end deployment: `site.yml` now runs from preflight through to a validated, accessible cluster
- Structured deployment report provides actionable information (node status, operator health, access URLs)
- Clear failure points: each phase reports its result, making it obvious where a deployment stalled
- Configurable timeouts accommodate different hardware and network speeds
- Lessons learned from the first deployment are codified, not just documented

### Negative

- Adds 30-60 minutes to the playbook runtime (inherent to the bootstrap process, not overhead)
- Requires `oc` binary on the jumpbox PATH for validation commands
- API polling adds minimal load but could theoretically interfere with a struggling API server
- Async Ansible tasks are harder to debug than synchronous ones if they fail

## Implementation

1. Create `roles/bootstrap_monitor/` with defaults, tasks
2. Add Phase 7 play to `playbooks/site.yml` targeting localhost
3. Role uses `ignition_output_dir` and `ignition_work_dir` variables shared with `ignition_generate`

## Related ADRs

- ADR-003: Bootstrap-in-place architecture (the process being monitored)
- ADR-011: Boot delivery strategy (precedes this phase in the pipeline)
- ADR-010: Ignition configuration generation (produces the kubeconfig used for validation)

## Lessons Learned

### First Deployment (88.99.65.35)

1. Always wipe secondary disks before writing the boot ISO on multi-disk servers
2. SSH port reachability is necessary but not sufficient for bootstrap success
3. The `openshift-install wait-for` command is the canonical way to track progress
4. API healthz (even with 401) is the earliest machine-readable signal of bootstrap progress
5. KVM/console access is invaluable for debugging -- consider documenting how to access it for each hosting provider

### Second Deployment Cycle (88.99.140.83, March 2026)

6. **Post-boot validation belongs in `boot_deliver`, not `bootstrap_monitor`**: The `boot_deliver` role now runs three post-boot checks immediately after SSH becomes reachable -- before handing off to `bootstrap_monitor`:
   - Verify `/etc/os-release` contains "CoreOS" (not rescue or stale OS)
   - Verify `/etc/.ignition-result.json` exists (Ignition applied successfully)
   - Test-pull the release image from the booted node (bootstrap chain will succeed)

   This catches boot-into-wrong-OS scenarios 30+ minutes earlier than waiting for `bootstrap_monitor` to time out on API health checks.

7. **Pre-boot validation is equally important**: A stale release image digest caused `release-image.service` to fail on first boot, which was only visible via `journalctl` on the node. The `boot_deliver` role now validates the release image is pullable *before* writing the ISO to disk (see ADR-011). This prevents scenarios where `bootstrap_monitor` waits indefinitely for an API server that will never start.

8. **Tag-based execution enables targeted re-runs**: Adding `tags: [boot]` and `tags: [monitor]` to `site.yml` plays allows running `--tags monitor` independently to retry bootstrap monitoring without re-running the entire boot delivery sequence. This is particularly useful when a deployment stalls and the operator wants to re-check after manual intervention.
