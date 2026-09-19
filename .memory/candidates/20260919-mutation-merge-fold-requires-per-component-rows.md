---
about: .github/actions/fold/fold.sh, mutation-merge/action.yml
saw: implementing lydite/actions#9 (mutation: false input on lydite.yml), branch feature/declined-concern
---

`mutation-merge`'s fold (`lydite mutation merge`, invoked via `.github/actions/fold/fold.sh`)
does a completeness check: it compares the components declared in `.lydite/components.yml`
against which components have a row in the folded shard documents, and treats any declared
component with no row as "a shard whose job died" — a failure.

This means any document routed through `mutation-merge` must carry a row per component it
claims to speak for. A document with zero component rows — such as the one `lydite mutation
--declined` writes (one `StatusDeclined` row, no components at all) — cannot be folded through
`mutation-merge`: every declared component would read as a dead shard, turning a deliberate
decline into a false failure.

The fix used in `.github/workflows/lydite.yml`'s `mutation-declined` job: bypass the fold
entirely and upload the declined document directly under the same final artifact name
(`lydite-reports-mutation`) `mutation-merge`'s own upload step would have produced. `publish`
reads by pattern (`lydite-reports-*`) and needs no branch on which path produced the artifact.

Any future document type meant to stand in for "this concern didn't run this time" (not just
mutation) will hit the same constraint if it's ever folded through a shard-completeness path
like this one — it needs to bypass the fold, not flow through it.
