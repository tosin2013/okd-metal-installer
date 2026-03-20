# GitHub repository settings (manual)

These steps improve discoverability and collaboration. They are applied in the GitHub web UI for the repository owner; they cannot be committed to git.

## About / metadata

1. **Topics** — In the repository **About** section (gear icon), add 5–10 topics, for example: `okd`, `openshift`, `kubernetes`, `ansible`, `bare-metal`, `infrastructure-as-code`, `fedora-coreos`, `ignition`, `coreos`.
2. **Website** — Set **Website** to a relevant URL (e.g. [OKD](https://www.okd.io/) or project documentation) if you do not have a dedicated project site.

## Social preview

Under **Settings → General → Social preview**, upload a **1280×640** image (PNG or JPEG) with the project name and a short tagline so links shared on social platforms render clearly.

## Community

1. **Discussions** — Under **Settings → General → Features**, enable **Discussions** if you want Q&A separate from issues.
2. **Releases** — Create [semantic version tags](https://semver.org/) (e.g. `v1.0.0`) on `main` and publish **Releases** with notes; this improves trust and works well with release badges in the README.

## External visibility

- Submit the project to curated lists (e.g. [awesome-baremetal](https://github.com/alexellis/awesome-baremetal)) following each list’s contribution guidelines.
- Blog posts, dev.to articles, and posts in relevant communities are outside this repository but help SEO and adoption.
