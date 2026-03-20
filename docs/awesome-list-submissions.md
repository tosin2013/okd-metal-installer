# Awesome list submissions for okd-metal-installer

Reference for submitting okd-metal-installer to curated awesome lists. Use one PR per list; do not bulk-submit.

## PR description template

Use this in each PR to explain value:

> okd-metal-installer automates bare-metal OKD (community Kubernetes) deployment using Ansible. It avoids PXE boot infrastructure by using static discovery ISOs and Bootstrap-in-Place architecture. Supports SNO, compact, and HA topologies; Route 53 DNS; NMState networking; and disconnected/air-gapped mode. Relevant for sysadmins and DevOps teams provisioning Kubernetes on physical servers.

---

## 1. alexellis/awesome-baremetal (1.9k stars)

- **Upstream:** [alexellis/awesome-baremetal](https://github.com/alexellis/awesome-baremetal)
- **Section:** Self-hosted tools for bare-metal management
- **Format:** `[Name](link) - "quote from GitHub repo or website"`
- **Alphabetical:** Insert after "netboot.xyz" (before "pixiecore")

**Entry:**

```markdown
* [okd-metal-installer](https://github.com/tosin2013/okd-metal-installer) - "Ansible-driven bare-metal provisioning for OKD using static ISOs and Bootstrap-in-Place, eliminating PXE boot infrastructure"
```

---

## 2. awesome-foss/awesome-sysadmin (33k stars)

- **Upstream:** [awesome-foss/awesome-sysadmin](https://github.com/awesome-foss/awesome-sysadmin)
- **Section:** Deployment Automation
- **Format:** ``[`Name`](homepage) - Short description. ([Source Code](link)) `License` `Language` ``
- **Alphabetical:** Insert in order (e.g. after "Overcast")
- **PR template:** [.github/PULL_REQUEST_TEMPLATE.md](https://github.com/awesome-foss/awesome-sysadmin/blob/master/.github/PULL_REQUEST_TEMPLATE.md)

**Entry:**

```markdown
- [`okd-metal-installer`](https://github.com/tosin2013/okd-metal-installer) - Ansible-driven bare-metal provisioning for OKD (community Kubernetes) via static ISOs and Bootstrap-in-Place. ([Source Code](https://github.com/tosin2013/okd-metal-installer)) `Apache-2.0` `Jinja`
```

---

## 3. wmariuss/awesome-devops (4k stars)

- **Upstream:** [wmariuss/awesome-devops](https://github.com/wmariuss/awesome-devops)
- **Section:** Automation & Orchestration
- **Format:** `[RESOURCE](LINK) - DESCRIPTION.` (must end with a period)
- **Alphabetical:** Insert after "OctoDNS" or "Nomad"

**Entry:**

```markdown
- [okd-metal-installer](https://github.com/tosin2013/okd-metal-installer) - Ansible-driven bare-metal provisioning for OKD using static ISOs and Bootstrap-in-Place architecture.
```

---

## 4. collabnix/kubetools (optional)

- **Upstream:** [collabnix/kubetools](https://github.com/collabnix/kubetools)
- **Section:** Cluster Management (table format)
- **decision-crafters fork:** [decision-crafters/kubetools](https://github.com/decision-crafters/kubetools)

**Entry (table row):**

| Sr No | Tool Name | Description with URL | GitHub Popularity |
| 55 | okd-metal-installer | [Ansible-driven bare-metal OKD provisioning via static ISOs and Bootstrap-in-Place](https://github.com/tosin2013/okd-metal-installer) | ![Github Stars](https://img.shields.io/github/stars/tosin2013/okd-metal-installer) |

---

## Execution workflow

1. Fork the upstream repo into the decision-crafters org (GitHub UI: Fork → select organization).
2. Clone the fork: `git clone https://github.com/decision-crafters/<repo>.git`
3. Create branch: `git checkout -b add-okd-metal-installer`
4. Add the entry in the correct section and position.
5. Commit and push: `git push origin add-okd-metal-installer`
6. Open a PR from `decision-crafters/<repo>:add-okd-metal-installer` to `upstream:master` (or `main`).
