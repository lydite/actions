#!/usr/bin/env bash
# The fold every shard-matrix action performs, in one place: find each shard's
# report directory and fold it with a lydite command. What varies between the
# callers is which documents identify a shard's report directory, which lydite
# subcommand reads them, and whether the component subdirectories are copied in;
# the finding, the reporting and the exit status do not, and a second copy of
# them is a second place for the shapes below to be got wrong.
#
# A plain script rather than a composite action, invoked as
# `"${ACTION_PATH}/../.github/actions/fold/fold.sh"` from `merge`, `record` and
# `mutation-merge`'s own steps. A nested `uses:` reference to a composite action
# here carries its own ref, which GitHub resolves independently of the ref the
# consumer pinned the outer action to — so a consumer naming `merge@<sha>` would
# still run whatever code that nested ref points at when the job runs, with the
# job's token in scope, and the pin would fix nothing. `github.action_path` is
# the caller's directory inside the checkout GitHub already fetched to resolve
# the outer action, so this sibling path is always the caller's own ref.
#
# Every value arrives through the environment, because interpolating `${{ }}`
# into a run body is a script-injection vector: DIR, REPORTS, DOC_NAMES,
# COPY_COMPONENTS, COMMAND, EXTRA_ARGS, BRANCH, ERROR_MESSAGE.
#
# `COMMAND` and `EXTRA_ARGS` are word-split deliberately: a caller writes them
# as a literal in its own `env:` block, so the words are the interface, not text
# arriving from a fork. `BRANCH` is the opposite and is passed as one quoted
# argument: it is a value a caller forwards from its own input, so a space in it
# is part of the branch name, and splitting on it would let whatever supplied
# that input append arguments of its own to a command running in the one job
# holding `contents: write`. Anything flowing from another action's input
# belongs in a variable of its own, never folded into EXTRA_ARGS.
#
# It assumes lydite is already on PATH — `lydite/actions/setup` puts it there.
#
# Every uppercase name below is one of those environment inputs, never a
# misspelled local, which is the whole of what SC2153 reports here.
# shellcheck disable=SC2153
set -euo pipefail
shopt -s nullglob

# Found by the documents rather than by the directory layout, because the
# layout is not ours to predict: actions/download-artifact gives an artifact its
# own subdirectory only when the pattern matched more than one, and extracts a
# lone match straight into `path`. A repository planning one shard, or one scan
# job, therefore leaves its document directly under ${REPORTS}, where a `*/`
# glob never looks — it finds that shard's per-component log directories instead
# and folds one of those, recording nothing while staying green saying so. Depth
# 2 reaches both shapes and stops above the per-component directories, which
# hold logs and coverage reports rather than any document.
#
# `merge-multiple: true` on the download that produced ${REPORTS} is not the
# fix: it puts every shard's `measurements.json` at one path, and the per-shard
# separation it collapses is what completeness is decided from.
read -r -a doc_names <<< "${DOC_NAMES}"
find_names=()
for name in "${doc_names[@]}"; do
  if [ "${#find_names[@]}" -gt 0 ]; then
    find_names+=(-o)
  fi
  find_names+=(-name "${name}")
done

args=()
dirs=()
while IFS= read -r dir; do
  args+=(--reports "${dir}")
  dirs+=("${dir}")
done < <(find "${REPORTS%/}" -maxdepth 2 \
           \( "${find_names[@]}" \) \
           -exec dirname {} \; | sort -u)
if [ "${#dirs[@]}" -eq 0 ]; then
  echo "::error::${ERROR_MESSAGE}"
  exit 1
fi

# Named out loud: a fold reading a directory nobody meant it to folds something
# and says nothing, and what tells that apart from a fold that read the right
# one is which paths were there to be read.
printf 'folding %s\n' "${dirs[@]}"

# Each shard's component subdirectories are copied in first. The folded rows
# carry the shards' own `log` paths, and `publish` resolves those against the
# directory it is given — this one. Without the copy a red component's row in
# the comment names a log that is in an artifact `publish` deliberately never
# downloads, and carries no tail at all. A fold nothing publishes needs no copy.
#
# The component subdirectories of each shard that was found, rather than a glob
# of a fixed depth: a lone shard's sit directly under ${REPORTS}, and every
# other shard's one level below that.
out="${DIR%/}/.lydite-reports"
if [ "${COPY_COMPONENTS}" = "true" ]; then
  mkdir -p "${out}"
  for dir in "${dirs[@]}"; do
    for logs in "${dir}"/*/; do
      cp -R "${logs}" "${out}/"
    done
  done
fi

# The verdict over the whole repository is this step's, so the exit code is
# re-raised rather than only reported. The caller's upload runs on `always()`,
# so a failing fold still reaches the comment.
read -r -a command_words <<< "${COMMAND}"
read -r -a extra_args <<< "${EXTRA_ARGS:-}"
if [ -n "${BRANCH:-}" ]; then
  extra_args+=(--branch "${BRANCH}")
fi
status=0
lydite "${command_words[@]}" --dir "${DIR}" "${args[@]}" "${extra_args[@]}" || status=$?
echo "lydite ${COMMAND} exited ${status}"
exit "${status}"
