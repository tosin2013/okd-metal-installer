# 14. Persistent Storage Strategy

**Status**: Accepted
**Date**: 2026-03-19
**Domain**: Storage, Day-2 Operations, Cluster Infrastructure

## Context

OKD clusters on bare metal have no built-in cloud storage provider. Without a configured StorageClass, workloads cannot dynamically provision PersistentVolumeClaims (PVCs). The installer must provide an optional, topology-aware storage solution that works across SNO and HA (3+ node) deployments on Hetzner dedicated servers.

### Constraints

1. **OKD uses community-operators only** -- Red Hat's LVM Storage (LVMS) operator and OpenShift Data Foundation (ODF) are not available in the OKD OperatorHub. Only the `community-operators` CatalogSource exists.

2. **SCOS kernel limitation** -- SCOS is based on CentOS Stream 10 (kernel 6.12, el10). RHEL 10 removed the `nvme_core.multipath` kernel parameter, which OpenEBS Replicated PV Mayastor requires for its HA NVMe-oF switch-over feature. Mayastor is therefore not viable on SCOS.

3. **MinIO is no longer viable** -- MinIO removed its operator from OperatorHub starting with OpenShift 4.17, switched to AGPL-3.0 licensing, and is stripping features from the community edition in favor of the commercial AIStor product.

4. **Hetzner hardware** -- Typical servers have dual NVMe drives (e.g., 2x 512GB). The OS is installed on one disk; the other is available for storage.

### Available Operators in OKD OperatorHub (verified 2026-03-19)

| Operator | Package | Version | Relevant |
|----------|---------|---------|----------|
| OpenEBS | `openebs` | 3.0.0 | Outdated; current is 4.x via Helm |
| NFS Provisioner | `nfs-provisioner-operator` | 0.0.8 | Single point of failure |
| Volume Expander | `volume-expander-operator` | -- | Utility only |

None of the OperatorHub offerings are suitable for production storage. All storage solutions are therefore installed via **Helm**.

## Decision

### SNO (Single Node): OpenEBS LocalPV-LVM

Install OpenEBS via Helm with the LocalPV-LVM engine. This provisions dynamic, thin-provisioned PVCs backed by LVM volume groups on local NVMe disks. Minimal resource overhead, designed for single-node and edge deployments.

### HA (3+ Nodes): Rook-Ceph

Install Rook-Ceph via Helm (operator chart + cluster chart). Rook deploys a Ceph cluster that provides:

- **Block storage (RBD)** -- replicated across nodes for durability
- **File storage (CephFS)** -- shared ReadWriteMany volumes
- **Object storage (RGW)** -- optional S3-compatible API (port 8080 on OpenShift)

Rook-Ceph has official OpenShift documentation, SCCs are auto-created by the Helm charts, and it does not depend on the missing `nvme_core.multipath` kernel parameter.

### S3 Object Storage (Optional)

- **SNO**: SeaweedFS via Helm -- lightweight, Apache 2.0 licensed, S3-compatible, active project (v1.0.11, March 2026)
- **HA**: Ceph RGW via Rook -- comes for free with the Rook-Ceph deployment, no additional components

### Disk Configuration

Storage disks must be **explicitly listed** in inventory (`storage_devices` variable). There is no auto-discovery. This prevents accidental data loss from wiping the wrong disk.

- SNO: set in `group_vars/all.yml`
- HA with heterogeneous hardware: set per node in `host_vars/<node>.yml`

## Alternatives Considered

| Option | Verdict | Reason |
|--------|---------|--------|
| LVM Storage (LVMS) | Rejected | Not in OKD community-operators catalog |
| ODF (OpenShift Data Foundation) | Rejected | Red Hat product, not available on OKD |
| OpenEBS Mayastor | Rejected | Requires `nvme_core.multipath` removed in SCOS/CentOS Stream 10 |
| MinIO | Rejected | Removed from OperatorHub 4.17+, AGPL license, feature-stripping community edition |
| Longhorn | Deferred | Has OKD support docs but less battle-tested on OpenShift; needs iSCSI kernel module verification on SCOS |
| NFS Provisioner | Rejected | Single point of failure, community operator quality |
| OpenEBS via OperatorHub | Rejected | OperatorHub has v3.0.0 (MayaData era), current is 4.x |
| hostPath volumes | Rejected | Not production-safe, no dynamic provisioning |
| Local Storage Operator | Rejected | Static provisioning only, no dynamic PVCs |

## Consequences

### Positive

- Dynamic PVC provisioning for workloads on all topologies
- StorageClass set as cluster default -- workloads work without specifying storage class
- OpenEBS LocalPV-LVM is lightweight and purpose-built for SNO/edge
- Rook-Ceph provides enterprise-grade replicated storage for HA with block, file, and optional object storage
- Helm-based installation is reproducible and version-pinnable
- Explicit disk list prevents accidental data loss
- Per-node host_vars support handles heterogeneous hardware in HA clusters
- SeaweedFS fills the S3 gap left by MinIO's withdrawal from the community

### Negative

- Helm dependency -- `helm` CLI must be available on the jumpbox
- OpenEBS LocalPV-LVM provides local-only storage (no cross-node replication on SNO, but acceptable since SNO is single-node)
- Rook-Ceph has significant resource overhead (4 CPU, 8GB+ RAM per node minimum)
- Disk wipe step requires SSH access to cluster nodes from the jumpbox
- VG creation for OpenEBS requires SSH to run LVM commands on nodes
- SeaweedFS is less mature than Ceph RGW for object storage

## Implementation

Implemented as `roles/storage_configure/`, integrated into `playbooks/site.yml` as Phase 9 (tag: `storage`).

Key variables:

```yaml
storage_enabled: true              # enable/disable the entire role
storage_backend: openebs-lvm       # 'openebs-lvm' or 'rook-ceph'
storage_devices: ["/dev/nvme1n1"]  # REQUIRED -- explicit disk list
storage_wipe_disks: true           # wipe disk signatures before use
storage_s3_enabled: false          # optional SeaweedFS (SNO) or RGW (HA)
storage_default_class: true        # set StorageClass as cluster default
seaweedfs_expose_route: true       # create OCP Route for external S3 access
seaweedfs_s3_anonymous_read: true  # allow anonymous Read + List
```

### Task Flow

1. Validate `storage_devices` is configured (fail fast if empty)
2. Ensure Helm is installed (auto-install if missing)
3. Wipe filesystem signatures on target disks via SSH (optional)
4. Install and configure the selected backend (OpenEBS or Rook-Ceph)
5. Optionally deploy S3 object storage (SeaweedFS or Ceph RGW)
6. Configure S3 authentication (auto-generated credentials stored in `seaweedfs-s3-credentials` secret)
7. Optionally create OpenShift Route for external S3 access (`s3.<apps_domain>`)
8. Verify: create test PVC, confirm it binds, clean up

## Validation Status

| Topology | Backend | S3 | Route | Status |
|----------|---------|------|-------|--------|
| SNO | OpenEBS LocalPV-LVM | SeaweedFS | Edge TLS | **Validated** (2026-03-19) |
| HA (3+ nodes) | Rook-Ceph | Ceph RGW | -- | **Not yet tested** |

### SNO Validation Notes (2026-03-19)

Deployed and validated on a live Hetzner SNO cluster running OKD 4.18 on SCOS (CentOS Stream 10, kernel 6.12):

- **OpenEBS LocalPV-LVM**: Helm install required disabling default sub-charts (Loki, Alloy, Mayastor, ZFS, rawfile) and granting `privileged` SCC to `openebs-lvm-node-sa`, `openebs-lvm-controller-sa`, and `openebs-localpv-provisioner` service accounts. Namespace must be labeled with `privileged` PodSecurity. DaemonSet restart required after SCC changes.
- **Disk wipe**: `sgdisk` is not available on SCOS; use `dd if=/dev/zero bs=1M count=10` instead.
- **SeaweedFS S3**: Helm chart defaults to `hostPath` volumes (`/ssd`, `/storage`) which fail on SCOS's read-only root filesystem. Solution: configure all persistence to use PVCs backed by the OpenEBS StorageClass. SeaweedFS 4.x requires S3 auth config (`-config` flag); without it, all S3 API calls are denied. Auth credentials are auto-generated and stored in a Kubernetes secret.
- **S3 Route**: Edge-terminated TLS Route exposes S3 at `s3.<apps_domain>`. Verified: bucket creation, object upload/download, anonymous read access.

## Related ADRs

- ADR-003: Bootstrap-in-place architecture (disk layout, dual-disk strategy)
- ADR-011: Boot delivery strategy (Hetzner disk management)
- ADR-013: Let's Encrypt certificate automation (Day-2 operations pattern)

## References

- OpenEBS on OpenShift: https://openebs.io/docs/Solutioning/openebs-on-kubernetes-platforms/openshift
- OpenEBS LocalPV-LVM: https://openebs.io/docs/main/user-guides/local-storage-user-guide/local-pv-lvm/lvm-installation
- Rook-Ceph on OpenShift: https://rook.io/docs/rook/v1.14/Getting-Started/ceph-openshift/
- Rook-Ceph Helm charts: https://rook.io/docs/rook/latest/Helm-Charts/ceph-cluster-chart/
- SeaweedFS operator: https://github.com/seaweedfs/seaweedfs-operator
- MinIO operator removal: https://github.com/minio/operator/issues/2359
- OpenEBS Mayastor RHEL 10 limitation: https://openebs.io/docs/user-guides/replicated-storage-user-guide/replicated-pv-mayastor/advanced-operations/ha
