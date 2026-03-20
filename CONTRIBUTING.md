# Contributing to OKD-Metal Installer

Thank you for your interest in contributing. This project uses Ansible playbooks and roles only; changes should stay aligned with the [Architectural Decision Records](docs/adrs/).

## Prerequisites

Match the [README Prerequisites](README.md#prerequisites): control node with `ansible-core >= 2.16`, Python 3.12+ with `boto3`/`botocore` when using Route 53, and the usual OKD install inputs (pull secret, inventory, etc.).

Install collection dependencies:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Local checks

From the repository root:

```bash
ansible-lint
yamllint .
```

Fix new issues in code you touch; existing warnings may be tracked separately. Configurations live in [`.ansible-lint`](.ansible-lint) and [`.yamllint`](.yamllint).

## Pull requests

- Open PRs against the default branch (`main`) with a clear description of the change and motivation.
- Reference related ADRs or issues when applicable.
- Do not commit secrets: use [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) for BMC passwords, pull secrets, and cloud credentials. Keep example inventories free of real hostnames or keys unless they are clearly fake placeholders.

## Architecture questions

Design and trade-offs are documented under [`docs/adrs/`](docs/adrs/). Propose significant behavior changes via an ADR update or a new ADR as appropriate.

## Code of conduct

All contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
