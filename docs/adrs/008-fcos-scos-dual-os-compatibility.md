# 8. FCOS/SCOS Dual OS Compatibility Strategy

**Status**: Accepted
**Date**: 2026-03-16
**Domain**: Operating System, Platform Compatibility

## Context

OKD historically uses Fedora CoreOS (FCOS) as its node operating system. However, the project is transitioning to CentOS Stream CoreOS (SCOS) to align more closely with Red Hat OpenShift's RHCOS. This transition has introduced instability: the FCOS-to-SCOS "pivot" during bootstrap fails due to newer ext4 filesystem features in FCOS that are incompatible with the SCOS pivot process (OKD Issue #2041).

OKD-Metal must be robust to these OS-level changes and provide reliable installations regardless of the underlying CoreOS variant.

## Decision

Implement a dual-OS compatibility strategy with the following principles:

1. **OS Selection as Configuration**: The target OS (FCOS or SCOS) is an explicit Ansible variable (`coreos_variant: fcos|scos`), not auto-detected
2. **ISO Source Abstraction**: The `iso_customize` role accepts a configurable ISO download URL, defaulting to the correct URL for the selected variant
3. **Ignition Spec Versioning**: Handle Ignition specification version differences between FCOS and SCOS by detecting the required spec version and generating compatible configs
4. **Pivot Avoidance**: For SCOS deployments, prefer SCOS-native ISOs that avoid the pivot entirely, bypassing the ext4 regression
5. **Validation**: Pre-flight checks verify that the selected OS variant, ISO, and `openshift-install` binary version are compatible

## Consequences

### Positive

- Explicit OS selection prevents silent failures from mismatched components
- Pivot avoidance strategy sidesteps the known FCOS-to-SCOS regression
- Abstracted ISO sourcing makes it easy to add future OS variants
- Validation catches incompatibilities before time-consuming provisioning begins
- Clear documentation of which OS combinations are tested and supported

### Negative

- Dual OS support doubles the testing surface
- Users must understand the distinction between FCOS and SCOS and choose correctly
- Ignition spec version handling adds complexity to the configuration generation role
- The FCOS/SCOS landscape is evolving; this strategy may need frequent updates

## Implementation Plan

1. Add `coreos_variant` variable to `group_vars/all.yml` with default `scos`
2. Create ISO URL lookup table in `roles/iso_customize/defaults/main.yml`
3. Add Ignition spec version detection to `roles/ignition_generate/`
4. Implement pre-flight compatibility validation in `roles/preflight/`
5. Document supported OS/version combinations in project README
6. Add CI test matrix for both FCOS and SCOS variants

## Related PRD Sections

- Section 6: "FCOS/SCOS Compatibility"
- Section 3: Problem statement -- FCOS/SCOS regressions
- Reference [1]: OKD Issue #2041

## Domain References

- OKD Issue #2041: https://github.com/okd-project/okd/issues/2041
- Fedora CoreOS downloads: https://fedoraproject.org/coreos/download
- CentOS Stream CoreOS: https://builds.coreos.fedoraproject.org/
