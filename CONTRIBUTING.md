# Contributing

Thanks for helping to improve the OpenNMS Quick Installer.

## Workflow

Work starts from a GitHub issue.
Open one describing the bug or enhancement before you send a pull request, and reference it from the PR with a closing keyword (`Closes #123`).
Pull requests are merged with a merge commit, so keep your branch history clean and meaningful.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `<type>[scope]: <description>` with types like `feat`, `fix`, `docs`, `ci`, `chore`.

## Developer Certificate of Origin (DCO)

Every commit must be signed off (`git commit -s`), adding a `Signed-off-by:` trailer with your real name and email.
The sign-off certifies the [DCO](https://developercertificate.org/): you have the right to submit the work under this project's license.

## AI-assisted contributions

AI assistance is welcome and must be disclosed.
Commits created with AI assistance carry an additional trailer naming the agent and model, before the sign-off:

```
Assisted-by: <Agent>:<model>
Signed-off-by: Your Name <you@example.org>
```

The human signer remains responsible for reviewing the changes and for license compliance.
The `Signed-off-by` identity is always a human, never an AI.

## Testing your changes

```bash
make lint                                              # shellcheck + actionlint
make integration-test IMAGE=debian:trixie SCRIPT=bootstrap-debian.sh
make integration-test IMAGE=almalinux:9 SCRIPT=bootstrap-yum.sh
```

The integration test boots a systemd container, runs the bootstrap script unattended, and verifies the PostgreSQL and OpenNMS services plus the web UI.
CI runs the same targets across eight distributions; the `Gate` check must pass before merge.
