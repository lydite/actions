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

**The suites are sharded, and there is nothing to configure.** A `plan` job groups the declared
components into the sets that must run in one process — those publishing a host port in common,
or rooted at overlapping directories — and each matrix job runs one of them. That grouping is
the finest one that is safe, so a repository whose components conflict with nothing gets a job
each, and a repository declaring one component gets a single job, exactly as it would with no matrix at
all. Keeping a
conflicting pair together matters on any runner topology: two hosted-runner jobs binding 5432
are separate machines and would not collide, but self-hosted runners routinely place several
jobs on one host, and then they do.

A shard reports exactly the components it was given and nothing about any other, so every
declared component takes exactly one row across the matrix. A `merge` job folds those documents
into one, and that fold is what fails over a component with no row — a shard whose job died —
which an `unmeasured` row would otherwise let publish as a passing verdict over a repository
half of which was never tested. It is also the only thing that can compute `coverage(repo)` and
`patch(repo)`: both sum every component's counts, and a shard holding two of four would answer
about its own two under a label about the repository.

## Recording the baseline, after the merge

The pull-request workflow gates, and records nothing. To record, call the second workflow from
a push to your default branch:

```yaml
name: lydite-baseline
on:
  push:
    branches: [main]

jobs:
  baseline:
    uses: lydite/actions/.github/workflows/lydite-baseline.yml@v1
    permissions:
      contents: write   # the recording job pushes to the `lydite` branch
```

Inputs: `dir`, `lydite-version`.

**It is a separate workflow because recording is a push, and the job that measures runs your
code.** `lydite test` writes nothing to the `lydite` branch: it reads a baseline, gates against
it, and leaves what it would record in the report directory for `lydite test record` to land.
Splitting the command is not by itself enough, though — `record` verifies no number, so a branch
that can edit its own workflow and its own component declaration can still make the measuring
job emit whatever it likes, and a poisoned baseline persists and gates every later change where
a poisoned verdict is one bad run. What makes recording safe is *where* it runs. Here the code
has already merged, passed review and passed every gate; on a pull request it has not.

**Recording is worth doing because the baseline is keyed by tree.** CI builds
`refs/pull/N/merge`, a squash merge lands a commit carrying that same tree, and the next pull
request's merge-base resolves to it — so the number this workflow records is the one that pull
request already measured, and every later change reads it instead of measuring the base tree
again in a throwaway worktree. Wiring `gate-coverage` and never recording is a supported
configuration: every run stays correct, every run pays that measurement, and the `record` row
says so.

## Or the pieces

Every action assumes lydite is already on `PATH`, so a workflow running more than one
installs once.

| Action | What it does |
| --- | --- |
| `lydite/actions/setup@v1` | downloads a release, verifies its checksum, puts it on `PATH` |
| `lydite/actions/review@v1` | publishes the referral verdict as the `lydite/referral` status |
| `lydite/actions/scan@v1` | runs the SAST and SCA checks over every declared component |
| `lydite/actions/plan@v1` | emits the shard matrix, from the declaration alone |
| `lydite/actions/test@v1` | runs the suites a job is responsible for, and gates their coverage |
| `lydite/actions/merge@v1` | folds every shard's report into one, and decides completeness |
| `lydite/actions/record@v1` | lands a run's measurements as the baseline on the `lydite` branch |
| `lydite/actions/publish@v1` | renders the standing comment from the reports, and posts it |

`review`, `scan`, `test` and `merge` each upload their `.lydite-reports` as
`lydite-reports-<name>`, and `publish` reads those back. A `test` job that holds one shard of a
matrix passes `artifact-prefix: lydite-shard` instead, so `merge` and `record` can read its
document and `publish` never renders it as a `test` section of its own — there would be one per
shard, each answering about part of the repository under one heading.

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

Sharding by hand is a `plan` job whose output a matrix reads. `plan` is pure — it opens the
declaration and each component's compose file and nothing else — so this job needs no history
and no container runtime:

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    outputs:
      shards: ${{ steps.plan.outputs.shards }}
    steps:
      - uses: actions/checkout@v5
      - uses: lydite/actions/setup@v1
      - uses: lydite/actions/plan@v1
        id: plan

  test:
    needs: plan
    strategy:
      fail-fast: false      # a cancelled sibling reads as a shard that died
      matrix:
        shard: ${{ fromJSON(needs.plan.outputs.shards) }}
    runs-on: ubuntu-latest
    steps: ...              # test@v1 with component: ${{ matrix.shard.components }}
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
request's own code. Only the `record` job in `lydite-baseline.yml` may write, and it runs
nothing from the repository at all: no suite, no `setup` or `teardown` command, no compose
service. It refuses a measurement naming a tree other than the one checked out, and re-checks
completeness against the declaration read from that tree — a partial baseline is worse than
none, since any non-empty entry reads as a cache hit and the missing component is then reported
`new` on every later change, gating nothing, silently and permanently.

**A change of instrument reports `new`, and that is not a bug.** A baseline entry records what
measured it — the Go toolchain, `cargo-llvm-cov`, a workspace's own runner and coverage provider
— and an entry a different instrument wrote is a different quantity, so it is never found and
the component is reported `new` for one change instead of compared against numbers nothing
produced. Bumping any of those tools does that. So does upgrading lydite across a change to the
metric itself, which every consumer meets once as a clean miss: that run measures, records, and
the next change hits the cache again.

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
