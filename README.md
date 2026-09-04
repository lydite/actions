# lydite actions

GitHub Actions for [lydite](https://github.com/lydite/lydite) — one entry point for SAST,
SCA, linting and coverage gating, run the same way locally and in CI.

## The whole of it, in one job

```yaml
name: lydite
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  lydite:
    uses: lydite/actions/.github/workflows/lydite.yml@v1
    permissions:
      contents: read
      statuses: write        # the lydite/referral commit status
      id-token: write        # the comment relay; not a credential
      pull-requests: write   # the fallback that posts as github-actions[bot]
```

That runs the referral, the scan and the gated suites in parallel and renders **one standing
comment** from all three. It has to be one run: the comment is assembled from every job's
reports, so they have to be artifacts of the same run.

Inputs: `dir`, `lydite-version`, `gate-coverage`, `affected`, `relay`. Secret:
`semgrep-token`.

## Or the pieces

Every action assumes lydite is already on `PATH`, so a workflow running more than one
installs once.

| Action | What it does |
| --- | --- |
| `lydite/actions/setup@v1` | downloads a release, verifies its checksum, puts it on `PATH` |
| `lydite/actions/review@v1` | publishes the referral verdict as the `lydite/referral` status |
| `lydite/actions/scan@v1` | runs the SAST and SCA checks over every declared component |
| `lydite/actions/test@v1` | runs each component's suite and gates its coverage |
| `lydite/actions/publish@v1` | renders the standing comment from the reports, and posts it |

`review`, `scan` and `test` each upload their `.lydite-reports` as
`lydite-reports-<name>`; `publish` reads them back.

```yaml
- uses: actions/checkout@v5
  with:
    fetch-depth: 0          # every gate resolves a merge-base
- uses: lydite/actions/setup@v1
- uses: lydite/actions/test@v1
  with:
    gate-coverage: true
    affected: true
```

## Things worth knowing before you wire it up

**`fetch-depth: 0` is not optional.** The referral is computed from `<merge-base>..HEAD`, the
coverage gate compares against the base tree, `--affected` selects from the changed paths, and
Semgrep's token-less fallback is scoped by the same merge-base. A shallow checkout resolves no
merge-base, and lydite refuses rather than quietly widening or narrowing.

**Nothing is inferred from the event.** `affected` belongs on a pull request and never on a
push to the default branch, where lydite runs every component so a missed `depends_on` edge is
caught at merge; `diff-base: auto` likewise. The reusable workflow keys both off
`github.event_name`, because the workflow knows the event and lydite does not — every signal
for "is this a pull request" is unreliable where it runs.

**`base-branch` is what fixes a stacked pull request.** Pass `github.base_ref` on a
`pull_request` event. Without it lydite discovers the repository's default branch, which is the
wrong base for a change stacked on another branch.

**The test job holds no writable token, deliberately.** It runs the repository's own suites and
whatever `setup`/`teardown` shell the declaration carries — on a pull request, the pull
request's own code. With no token that can write, the coverage baseline is not recorded, the
`record` row says so, and every run measures the base tree instead of reading one. That costs an
instrumented run per change and is the supported configuration.

**`publish` is the only action that authenticates.** `lydite publish` itself renders and posts
nothing — no network, no token, no knowledge of a hosting platform — so a developer can run it
locally and read exactly what a reviewer will see, and refining the comment never needs a
release of this repository. With `relay` set, the comment arrives as **lydite** and the job
holds no credential that can write anywhere: it presents the Actions OIDC token, and the relay
decides what may be written from the claims GitHub signed. Without one it posts as
`github-actions[bot]`. That fallback is required rather than a stopgap — a consumer who has
installed nothing still gets the surface, and the only thing they lose is whose name is on it.

**A referral is not a failure.** `lydite review` runs no check. It says whether a change may
merge unattended, and a referral names no defect — it says a person has to look, and they
resolve it by commenting `/lydite clear`. With no `.lydite/exemptions.yml`, every change is
referred, which is the correct day-one state.

## Versioning

Pin the floating major, `@v1`. A release moves it to the tagged commit, so the reusable
workflow and the actions it calls always ship together.
