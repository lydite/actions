---
about: .github/actions/fold/action.yml, merge/action.yml, record/action.yml, mutation-merge/action.yml
saw: a628bb5 (fix: the fold is repo-qualified, and mutation resolves a stacked base)
---

A relative `uses: ./path` inside a **composite action's own steps** resolves against the
*consuming repository's* checked-out workspace at runtime, not against the repository that
defines the composite action. This is a different rule from a relative `uses:` in a *workflow*
file (which this repo's own `lydite.yml` header already documents) — the composite-action case
is easy to miss because it only breaks when an external consumer runs the action, never when
this repository's own CI checks the action.yml files structurally (`gt repo check`, the
manifest-check glob, `actionlint` on bare `action.yml` files all pass regardless).

`merge/action.yml`, `record/action.yml` and `mutation-merge/action.yml` all called the shared
`.github/actions/fold` composite action via `uses: ./.github/actions/fold` when it was first
extracted. Every local check (YAML parse, `actionlint`, `gt repo check`, a hand-built
shellcheck/behavioral smoke test) passed, because none of them simulate a real external
consumer's checkout. Only a code-review pass (`agtk code-review`, `security` reviewer, RED,
corroborated by two independent runs) caught that a consumer calling
`lydite/actions/merge@v1` has no `.github/actions/fold/action.yml` anywhere in their own tree,
so the step fails immediately for everyone outside this repository.

The fix, and the pattern any future internal composite-action-to-composite-action reference in
this repository must follow: repo-qualify and pin it exactly like every other cross-action
reference here, e.g. `uses: lydite/actions/.github/actions/fold@v1` — never a relative path,
even for an action private to this repository.
