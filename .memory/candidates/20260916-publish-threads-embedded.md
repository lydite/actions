---
about: publish/action.yml
saw: publish/action.yml, whole file
---

`publish/action.yml` is the single action a consumer calls for both surfaces: it renders and
posts the standing pull-request comment (`/comment` via the relay, or the workflow's own token
as fallback) AND reconciles the pull request's review threads (`/review`, same relay/fallback
split) in one action, reading both from the same `steps.render.outputs.dirs` list of report
directories. There is no separate `threads/action.yml` in this repository — unlike
`lydite/lydite`'s dogfooded `.github/actions/lydite-threads`, which is its own composite action
that `lydite-pr.yml` calls as a separate step after the comment. The shape was chosen
deliberately so a consumer's existing workflow (which only ever called `publish@v1`) does not
need to change to gain threads.

The relay classification (`409` → silent fallback, `000`/`5xx` → warned fallback, anything else →
fail the step) is shared logic between the comment's `/comment` call and the threads' `/review`
call, with one asymmetry: `/review` also treats `403` as a fall-back case (a review-comment id
that moved between the delta being computed and the relay applying it — the relay re-reads ids
at apply time), where `/comment` fails a `403` outright since it has no equivalent race.
