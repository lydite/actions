---
about: .github/workflows/ci-test.yml
saw: running actionlint against mutation/action.yml while verifying a change to it
---

`actionlint` only understands workflow files. Pointed at a composite action's `action.yml`
(`actionlint mutation/action.yml`) it parses the file as a workflow and fails with "jobs section is
missing", so it says nothing about the action's schema or its `run:` scripts. The checks that do
cover `*/action.yml` are the ones `.github/workflows/ci-test.yml` runs: a parse that asserts
`runs.using == "composite"`, and shellcheck over the scripts. A change to an action's `run:` body is
otherwise unlinted unless its script is extracted and run through shellcheck by hand.
