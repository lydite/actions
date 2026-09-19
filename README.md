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
      id-token: write        # the comment and review-thread relay; not a credential
      pull-requests: write   # the fallback that posts as github-actions[bot]
```

```
referral ──────────────────────┐   no needs, so the status lands in seconds
scan ──────────────────────────┤
plan ─┬─► test (matrix) ───────► merge
      └─► mutation (matrix) ───► mutation-merge
mutation-declined ─────────────┤   instead of both, when mutation: false
                               └─► publish   needs all, if: always()
```

That runs the referral, the scan, the gated suites and the mutation matrix in parallel and
renders **one standing comment** from all four. It has to be one run: the comment is assembled
from every job's reports, so they have to be artifacts of the same run.

Inputs: `dir`, `lydite-version`, `gate-coverage`, `affected`, `mutation`, `relay`. Secret:
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

**Mutation runs beside the test matrix, on the same shards.** It reuses `plan`'s output verbatim
rather than running as a phase inside `test`, since mutation and the coverage gate share a
checkout and not a compilation, and a `mutation-merge` job folds the shards' documents the same
way `merge` does — a component with no row is a shard whose job died, and there is no
repository-wide figure to compute beyond that, since survived == 0 for every component is
survived == 0 for the repository. A mutant is a full suite run, so a component's budget is its
mutant count times its own suite, and nothing inside lydite caps that: the mutation job's timeout
is 60 minutes, twice the test matrix's 30, and lydite/lydite#97 measured a 1,276-line change at
54 minutes against it — a large change can run close to that limit.

`mutation: false` declines the whole matrix in favour of a single `mutation-declined` job, which
costs no mutants run and no coverage-of-mutants signal for that run. The comment still gets a
mutation section — rendered as declined, not silently missing, since an absent section would
read as a repository whose mutants all died — see lydite/lydite#171 for what that looks like.

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

**The baseline workflow also runs a whole-repository scan.** There is no diff to scope it to on
a push to the default branch, so it passes no `diff-base` and gets the repository's standing
finding count back. `record` folds that count in alongside the coverage measurements, into the
same quality-history entry, and it does so unconditionally: a red scan does not block the run
from being recorded, because the count is the thing worth preserving, permanently, not a pass or
fail on this branch. A consumer calling `record@v1` directly rather than through
`lydite-baseline.yml` must pass its `branch` input explicitly — `record` verifies no number, so
it has nothing to infer that key from, and no default is safe to guess.

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
| `lydite/actions/mutation@v1` | mutates the components a job is responsible for, and uploads the reports |
| `lydite/actions/merge@v1` | folds every shard's report into one, and decides completeness |
| `lydite/actions/mutation-merge@v1` | folds every shard's mutation report into one, and decides completeness |
| `lydite/actions/record@v1` | lands a run's measurements as the baseline on the `lydite` branch |
| `lydite/actions/publish@v1` | renders the standing comment from the reports, posts it, and opens, answers and closes the pull request's review threads |

`review`, `scan`, `test` and `merge` each upload their `.lydite-reports` as
`lydite-reports-<name>`, and `publish` reads those back. A `test` job that holds one shard of a
matrix passes `artifact-prefix: lydite-shard` instead, so `merge` and `record` can read its
document and `publish` never renders it as a `test` section of its own — there would be one per
shard, each answering about part of the repository under one heading.

`publish` folds whatever `download-artifact` produced without asking which shape it is. A
pattern matching more than one artifact gets each its own `lydite-reports-<name>` subdirectory;
a pattern matching exactly one — the one-job pipeline, with no matrix at all — leaves that job's
contents directly under the reports directory, with no subdirectory to find. `publish` looks for
the nested shape structurally and falls back to the flat one, so a single-job pipeline needs no
different wiring than a sharded one to fold correctly.

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

**The same run also reconciles the pull request's review threads.** `publish` reads the run's
located findings from the same report directories the comment was rendered from and opens,
answers and closes one thread per line-level finding, so a change to what got found never has
to be read twice — once in the comment, once per line — to be understood. This uses the same
`relay` input as the comment: with one configured, threads are opened and closed as **lydite**;
without one, they go through the workflow's own token instead.

**A relay's answer to either surface sorts into the same three outcomes.** `409` falls back
silently — no app installed on this repository is the ordinary state, not a fault. `000` (the
relay was unreachable at all) or a `5xx` falls back too, but under a `::warning::`: a relay
outage must not fail a consumer's pull request, and must not pass unremarked either. Anything
else — a token the relay would not verify, a payload it would not read, a run whose pull request
does not match its claims — is deterministic, so retrying answers the same, and the step fails
rather than posting under the wrong byline. The one asymmetry is `403`: on the review-thread
call it falls back like an outage, because the relay re-reads a thread's id when it applies the
operation and a `403` there can be a thread that moved between the delta being computed and
being applied rather than a real rejection; on the comment call there is no such race, so a
`403` fails the step.

**A referral is not a failure.** `lydite review` runs no check. It says whether a change may
merge unattended, and a referral names no defect — it says a person has to look, and they
resolve it by commenting `/lydite clear`. With no `.lydite/exemptions.yml`, every change is
referred, which is the correct day-one state.

## Versioning

Pin the floating major, `@v1`. A release moves it to the tagged commit, so the reusable
workflow and the actions it calls always ship together.

`@v1` calls `lydite review`, `test`, `merge`, `record`, `publish`, `threads`, `mutation` and
`mutation merge`, and `record` calls `test record --branch`. Using it requires a lydite release
that ships all of those — the only lydite release today, `v0.1.0`, ships `scan`, `coverage`,
`version` and `update`, and neither `lydite-version: latest` nor `@v1` as it stands resolves any
of the rest against it. `lydite mutation`, `lydite mutation merge` and `lydite test record
--branch` do not exist in that release either, so `@v1` must not move to the commit that
introduced the mutation matrix and the branch-keyed `record` until a later lydite release
carries those commands too.
