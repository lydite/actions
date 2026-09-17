---
about: publish/action.yml
saw: publish/action.yml render step, lines ~105-126
---

`publish/action.yml`'s render step decides whether `${{ inputs.reports }}` holds several jobs'
artifacts or one job's, structurally rather than by looking for a document: it sets `nested=true`
only if a `lydite-reports-*` subdirectory exists directly under the reports root, and otherwise
treats the root itself as the single flat report directory — but only when that root is
non-empty (`[ -d "${root}" ] && [ -n "$(find "${root}" -mindepth 1 -print -quit)" ]`; an earlier
version of this check was `[ -d "${root}" ]` alone, which let an existing-but-empty root pass as
a valid flat report and publish a comment from nothing instead of erroring).

This is deliberately different from `merge/action.yml` and `record/action.yml`, which locate
their inputs by document name (`measurements.json`, `test.json`, `scan.json`) via `find -maxdepth
2`. `publish` cannot do that: a directory a job uploaded holding only logs and no document still
has to reach `publish` so it renders as a "missing section" rather than silently vanishing — a
missing input renders as a section saying so, per this project's own rule.
