# Releasing

Releases mark tested states of the bootstrap scripts.
There is no build artifact: users consume the scripts from the tag or from `main`.

## Versioning

Tags use an `X.Y` scheme (for example `2.5`).
Classify the commits since the last tag by Conventional Commit type to pick the next version: breaking changes bump `X`, everything else bumps `Y`.

## Procedure

1. Ensure `main` is green: the `Gate` check on the latest run must pass.
2. Pick the version from the commits since the last tag (`git describe --tags --abbrev=0`).
3. Tag the release: `git tag -a <X.Y> -m "<X.Y>" && git push origin <X.Y>`.
4. Create a GitHub Release on the tag with curated notes: user-facing highlights and fixes with issue/PR links, no raw commit dump, chore/CI noise collapsed or omitted.

## Planned

A tag-triggered release workflow with checksums, cosign signatures, and an SBOM is tracked in [#70](https://github.com/opennms-forge/opennms-install/issues/70).
This file changes in the same PR that lands it.
