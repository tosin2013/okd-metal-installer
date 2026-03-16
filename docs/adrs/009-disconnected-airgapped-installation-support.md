# 9. Disconnected and Air-gapped Installation Support

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Security, Deployment Strategy

## Context

A core requirement of OKD-Metal is supporting fully disconnected (air-gapped) environments where internet access is restricted or prohibited. This is common in government, financial, and defense sectors. The Red Hat Assisted Installer's reliance on SaaS endpoints is a primary motivator for OKD-Metal's existence.

Disconnected OKD installations require mirroring container images to a local registry, bundling all required binaries and ISOs, and ensuring no external network calls are made during provisioning.

## Decision

Design OKD-Metal for disconnected-first operation. All components must function without internet access when properly prepared. The approach:

1. **Mirror Registry**: Support `oc mirror` or `oc adm release mirror` workflows to populate a local container registry before installation
2. **Bundled Artifacts**: The Ansible playbooks support a "bundle" mode that collects all required artifacts (ISOs, binaries, images, configs) into a transferable archive
3. **No SaaS Dependencies**: Zero runtime calls to external services (no telemetry, no cloud APIs during install -- DNS is configured pre-install)
4. **Local Config Serving**: Ignition configs and ISOs are served from the jumpbox/provisioning host, not from external endpoints
5. **CA Certificate Injection**: Support embedding custom CA certificates into the discovery ISO for trust with internal registries

The `roles/disconnected_prepare/` role will handle mirror registry setup and artifact bundling. A `disconnected: true` variable gates disconnected-specific behavior across all roles.

## Consequences

### Positive

- Enables deployment in the most restrictive environments, filling the gap left by the Assisted Installer
- Forces clean separation between preparation (online) and execution (offline) phases
- No vendor lock-in or SaaS dependency
- Bundle approach enables reproducible deployments from a known-good artifact set
- Aligns with security-conscious user personas (government, finance)

### Negative

- Mirror registry setup is complex and resource-intensive (storage for container images)
- Artifact bundles can be very large (10s of GB for a full OKD release)
- Version management becomes manual: users must re-mirror when upgrading
- Testing disconnected flows requires simulating air-gapped environments
- Route 53 DNS integration (ADR-004) is incompatible with fully disconnected environments; users need an alternative internal DNS

## Implementation Plan

1. Create `roles/disconnected_prepare/` Ansible role
2. Implement `oc mirror` wrapper tasks for populating a mirror registry
3. Add artifact collection tasks (ISOs, binaries, pull secrets) into a tarball
4. Add `disconnected` variable to `group_vars/all.yml` (default: `false`)
5. Modify `install-config.yaml` template to include `imageContentSources` for mirror registry
6. Add CA certificate injection to the `iso_customize` role
7. Create a separate `roles/dns_internal/` role as a disconnected alternative to Route 53

## Related PRD Sections

- Section 2: Target Audience -- "Disconnected Environment Admins"
- Section 3: Problem statement -- SaaS dependency issues
- Section 4: User story -- "provision an OKD cluster in a fully air-gapped environment"
- Section 7: Out of scope clarifications

## Domain References

- OKD disconnected installation: https://docs.okd.io/latest/installing/disconnected_install/index.html
- oc mirror: https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-disconnected.html
