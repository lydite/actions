---
about: .github/workflows/ci-test.yml
saw: reviewdog/action-actionlint@8b682e1e7e512151d73a6b9449cbff173846226e (v1.74.0), that commit's action.yml
---

`.github/workflows/ci-test.yml`'s actionlint step uses `reviewdog/action-actionlint`, pinned by
full commit SHA. At that commit its `runs:` block is `using: docker`, with
`image: docker://ghcr.io/reviewdog/action-actionlint:...@sha256:...` — actionlint is built into
that Docker image at a fixed version and is not downloaded at run time. So the pinned commit SHA
already pins both the wrapper action and the actionlint binary's version together; no separate
`actionlint_version` input or checksum-verified download step is needed the way
`setup/action.yml` pins lydite's own release. (This is a point worth checking directly against
the action's `action.yml` at the pinned commit rather than assuming from its inputs — a
`fail_level` input name alone does not distinguish this Docker-based version from a composite
one that fetches a binary.)

A's `.github/dependabot.yml` has a `github-actions` ecosystem watch at `directory: "/"`, which
covers every `uses:` pin across every workflow and action file in the repository automatically —
so a new SHA-pinned third-party GitHub Action needs no separate manifest entry to stay watched
for updates, unlike a tool this repository would download and checksum-verify itself.
