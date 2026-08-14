# Releasing

Releases mark tested states of the bootstrap scripts.
Pushing a version tag triggers the Release workflow, which re-runs the quality gates and creates a **draft** GitHub Release with the scripts, a checksums file, a cosign signature, an SBOM, and build provenance attached.

## Versioning

Tags follow SemVer with a `v` prefix: `vX.Y.Z` (releases up to `2.5` used a bare `X.Y` scheme).
Classify the commits since the last tag by Conventional Commit type: `BREAKING CHANGE`/`!` bumps major, `feat` bumps minor, everything else bumps patch.
Prerelease tags (`vX.Y.Z-rc1`) are marked as prereleases automatically and never become the latest release.

## Procedure

1. Ensure `main` is green: the `Gate` check on the latest run must pass.
2. Find the last tag (`git describe --tags --abbrev=0`) and pick the next version from the commits since then.
3. Tag and push: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
4. The Release workflow runs the full quality gates, then creates the draft release with artifacts.
   Do not create the release by hand first.
5. Curate the release notes: user-facing highlights and fixes with issue/PR links, breaking changes with a migration path, no raw commit dump, chore/CI noise omitted.
6. Publish: `gh release edit vX.Y.Z --notes-file notes.md --draft=false`.

## Certified-combo pins

The bootstrap scripts pin a certified combination: `ONMS_VERSION` (OpenNMS Horizon) and `PSQL_VERSION` (PostgreSQL), defined as constants at the top of both scripts and shown as README badges.
The two pins bump independently: Horizon on its release cadence (second Wednesday of the month), PostgreSQL rarely and only within the window Horizon supports.

- Renovate authors Horizon bump PRs automatically (`renovate.json` watches OpenNMS/opennms releases) and updates both scripts and the README badge with the same version.
- PostgreSQL bumps are manual: change `PSQL_VERSION` in both scripts and the README badge, and check the new version is inside Horizon's supported range first.
- `make lint` fails when scripts and badges disagree, so partial bumps cannot merge.
- A green 8-distro matrix (`Gate`) on the bump PR is the re-certification; merging the PR certifies the new combo.
- debian.opennms.org serves only the newest release, so the deb pin breaks when upstream publishes: the weekly scheduled Integration Tests run is the expiry alarm.
  A failed scheduled run on `main` means a bump PR is due.

## Verifying artifacts

Verify the checksums file signature (cosign v3 sigstore bundle) and then the scripts against it:

```bash
cosign verify-blob \
  --bundle SHA256SUMS.sigstore.json \
  --certificate-identity-regexp 'https://github.com/opennms-forge/opennms-install/\.github/workflows/release\.yml@refs/tags/v.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  SHA256SUMS
sha256sum -c SHA256SUMS
```

Verify build provenance:

```bash
gh attestation verify bootstrap-debian.sh --repo opennms-forge/opennms-install
```

If the pipeline changes, this file changes in the same PR.
