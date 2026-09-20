---
about: record/action.yml, .github/actions/fold/fold.sh
saw: implementing lydite/actions#10 (the mutate matrix in lydite-baseline.yml), branch feature/mutate-matrix-baseline
---

`record/action.yml`'s fold step passes `.github/actions/fold/fold.sh` a hardcoded
`DOC_NAMES: measurements.json scan.json` env var. `fold.sh` builds its `find -maxdepth 2 -name
...` predicate from exactly that list, so a report document whose filename is absent from
`DOC_NAMES` is invisible to the fold: its directory is never discovered, never passed to
`lydite test record` as a `--reports` argument, and its contents are dropped with no error —
`lydite test record` itself already reads any document type it recognizes from a `--reports`
directory (per lydite/lydite#112 for `mutants.json`), but that capability is gated entirely by
whether the calling composite's `DOC_NAMES` names the file first.

Concretely: adding a `mutate` job to `lydite-baseline.yml` that uploads `mutants.json` artifacts
was not sufficient on its own — `record/action.yml` needed `mutants.json` added to its
`DOC_NAMES` too, or the new job's output would upload successfully, download successfully into
`shards/`, and still never reach the recorded baseline, with no red step anywhere to say so.

Any future report type meant to reach `lydite test record` through this composite hits the same
constraint: it needs an entry in `record/action.yml`'s `DOC_NAMES`, not just a matching
`lydite test record` reader and a matching upload/download step in the workflow. `merge/action.yml`
(`measurements.json test.json`) and `mutation-merge/action.yml` (`mutation.json`) each carry
their own separate `DOC_NAMES` and are unaffected by changes to `record/action.yml`'s list.
