---
about: .github/actions/fold/fold.sh, merge/action.yml, record/action.yml, mutation-merge/action.yml
saw: ef4439e (fix: the fold is a script, so a consumer's pin is the only ref that runs)
---

No form of `uses:` — relative or repo-qualified — is a safe way for one composite action in
this repository to reach another. A relative `uses: ./path` inside a composite action's own
steps resolves against the *consuming repository's* checked-out workspace at runtime, not
against the repository that defines the composite action, so it breaks immediately for every
external consumer. A repo-qualified reference (`uses: lydite/actions/.github/actions/fold@v1`)
fixes that but introduces a second problem: GitHub resolves that nested ref independently of
whatever ref the consumer pinned the *outer* action to, so a consumer pinning `merge@<sha>` for
supply-chain safety would still run whatever `v1` currently points to when the fold step runs,
with that job's token in scope — the SHA pin fixes nothing.

Both failure modes are easy to miss locally: YAML parsing, `actionlint`, `gt repo check`, and a
hand-built shellcheck/behavioral smoke test all pass regardless, because none of them simulate
an external consumer's checkout or a pinned-vs-floating ref mismatch. Both were only caught by
a posted `agtk code-review` pass on the pull request (`security`, RED then AMBER, each
corroborated by an independent run) — one per push, since fixing the first surfaced the second.

The shape that survived: shared logic between this repository's own composite actions lives as
a plain script under `.github/actions/`, invoked via `${{ github.action_path }}` from each
caller's own `run:` step (with the path passed through `env:`, never spliced into the script
body) — never through any `uses:` to another action in this repository, however it's pinned.
`github.action_path` is the caller's own directory inside whatever checkout GitHub already
fetched to resolve *that* action, so the sibling script is always the exact ref the consumer
named.
