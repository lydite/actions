---
about: mutation/action.yml
saw: mutation/action.yml, the `state` step, the cache/restore and cache/save steps and the header comment
---

`mutation/action.yml` keeps `lydite mutation`'s state (its `--state-dir`) in its own cache entry, not
in the `~/.cache/lydite` cache the same action already restores. That existing cache is keyed on the
pin manifests (`hashFiles(...)`) and cache keys are immutable: a hit is never saved over, so verdicts
written into `~/.cache/lydite` on one attempt would never reach the next. The `state` step therefore
refuses a `state-dir` that resolves inside `~/.cache/lydite`, inside the workspace (no suite or scanner
should walk it), or under `.lydite-reports` (that directory is the uploaded artifact).

The state key is `lydite-mutation-<os>-<shard>-<github.sha>-<run_attempt>` and the restore prefix
omits the attempt. `run_attempt` is what lets a retry write: its key has nothing saved under it yet,
while prefix restore returns the newest entry an earlier attempt saved. `<shard>` is `artifact-name`
sanitised to `[A-Za-z0-9._-]`, never `component`, which is a comma list per shard. On a
`pull_request` run `github.sha` is the synthetic merge commit, so a new push deliberately restores
nothing. The save step runs under `always()` so a run that stopped at its `deadline` (lydite exits 3)
still saves.

`--state-dir` and `--deadline` are passed only when `lydite mutation --help` lists them, and the help
text is captured into a variable before `grep` because `grep -q` exiting early would fail the pipeline
under `pipefail`. `lydite.yml`'s `mutation` job and `lydite-baseline.yml`'s `mutate` job both call this
action, so both share the scheme; run on the same commit they would compute the same key.
