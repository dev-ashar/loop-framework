#!/usr/bin/env bash
# Disposable integration and trusted host-observation primitives.
# Callers retain shell error policy.

job_integration_repo_root() {
  git -C "${1:-.}" rev-parse --show-toplevel
}

job_integration_main_clean() {
  local root=$1
  [ -z "$(git -C "$root" diff --name-only --diff-filter=U)" ] || return 1
  [ "$(git -C "$root" rev-parse --verify -q MERGE_HEAD 2>/dev/null || true)" = "" ] || return 1
  [ "$(git -C "$root" ls-files -u)" = "" ] || return 1
  ! git -C "$root" status --porcelain=v1 | grep -Eq '^(UU|AA|DD|AU|UA|DU|UD)'
}

job_integration_order() {
  # Input is one branch per line. Sorting is the deterministic bytewise tie-break.
  LC_ALL=C sort
}

job_integration_worktree() {
  local root=$1 base=$2 run_id=$3
  [ -n "$root" ] && [ -n "$base" ] && [ -n "$run_id" ] || return 2
  git -C "$root" rev-parse --verify "$base^{commit}" >/dev/null || return 1
  local parent="$root/.loops/runs/$run_id"
  local path="$parent/integration-worktree"
  mkdir -p "$parent"
  [ ! -e "$path" ] || return 1
  git -C "$root" worktree add --detach "$path" "$base" >/dev/null
  printf '%s\n' "$path"
}

job_integration_cleanup() {
  local root=$1 path=$2
  [ -n "$root" ] && [ -n "$path" ] || return 2
  git -C "$root" worktree remove --force "$path" >/dev/null 2>&1 || {
    rm -rf "$path"
    git -C "$root" worktree prune >/dev/null 2>&1 || true
  }
  [ ! -e "$path" ]
}

job_integration_conflict_record() {
  local file=$1 base=$2 left_job=$3 left_branch=$4 right_job=$5 right_branch=$6 path=$7
  mkdir -p "$(dirname "$file")"
  printf 'integration=conflicted\nbase_sha=%s\nleft_job=%s\nleft_branch=%s\nright_job=%s\nright_branch=%s\nconflicted_path=%s\n' \
    "$base" "$left_job" "$left_branch" "$right_job" "$right_branch" "$path" > "$file"
}

# Integrate newline-delimited records: job<TAB>branch. Returns 0 on success,
# 10 on conflict, and 1 on setup or invariant failure. Source branches persist.
job_integration_run() {
  local root=$1 base=$2 run_id=$3 records=$4 evidence=${5:-$root/.loops/runs/$3/integration.conflict}
  [ -n "$root" ] && [ -n "$base" ] && [ -f "$records" ] || return 2
  job_integration_main_clean "$root" || { printf 'INTEGRATION_MAIN_DIRTY\n' >&2; return 1; }
  local wt; wt=$(job_integration_worktree "$root" "$base" "$run_id") || return 1
  local previous_job='' previous_branch='' line job branch first=1
  local rc=0
  while IFS=$'\t' read -r job branch; do
    [ -n "$job" ] || continue
    [ -n "$branch" ] || { rc=1; break; }
    git -C "$root" show-ref --verify --quiet "refs/heads/$branch" || { rc=1; break; }
    first=0
    local merge_output merge_rc
    if merge_output=$(git -C "$wt" merge --no-ff --no-edit "$branch" 2>&1); then
      merge_rc=0
    else
      merge_rc=$?
    fi
    if [ "$merge_rc" -ne 0 ]; then
        local paths
        paths=$(git -C "$wt" diff --name-only --diff-filter=U | LC_ALL=C sort)
        : > "$evidence"
        while IFS= read -r path; do
          [ -n "$path" ] || continue
          job_integration_conflict_record "$evidence" "$base" "$previous_job" "$previous_branch" "$job" "$branch" "$path"
        done <<< "$paths"
        [ -s "$evidence" ] || job_integration_conflict_record "$evidence" "$base" "$previous_job" "$previous_branch" "$job" "$branch" 'unknown'
        git -C "$wt" merge --abort >/dev/null 2>&1 || true
        job_integration_cleanup "$root" "$wt" || rc=1
        job_integration_main_clean "$root" || rc=1
        printf 'INTEGRATION_CONFLICT evidence=%s downstream=blocked\n' "$evidence"
        if [ "$rc" -eq 0 ]; then return 10; else return 1; fi
    fi
    previous_job=$job; previous_branch=$branch
  done < <(job_integration_order < "$records")
  # Each merge uses --no-ff and creates the integration commit.
  # Do not create a second empty commit after the final merge.
  job_integration_cleanup "$root" "$wt" || rc=1
  if ! job_integration_main_clean "$root"; then rc=1; fi
  if [ "$rc" -eq 0 ]; then printf 'INTEGRATION_OK downstream=allowed\n'; return 0; fi
  return "$rc"
}

job_integration_gate_downstream() {
  [ "${1:-}" = conflicted ] || [ "${1:-}" = integration-conflicted ] && {
    printf 'DOWNSTREAM_BLOCKED integration-conflicted\n'; return 1; }
  printf 'DOWNSTREAM_ALLOWED\n'
}

# Approval observations are callback-only. The callback is captured at
# construction and receives the expected identity fields from the caller.
job_approval_observer_new() {
  local mode=${1:-production} callback=${2:-}
  [ "$mode" = production ] && [ -n "$callback" ] || return 1
  declare -F "$callback" >/dev/null || return 1
  JOB_APPROVAL_OBSERVER_MODE=production
  JOB_APPROVAL_OBSERVER_CALLBACK=$callback
  printf 'JOB_APPROVAL_OBSERVER_READY\n'
}

job_approval_test_adapter_new() {
  [ "${1:-}" = test-adapter ] && [ -n "${2:-}" ] || return 1
  declare -F "$2" >/dev/null || return 1
  JOB_APPROVAL_OBSERVER_MODE=test-adapter
  JOB_APPROVAL_OBSERVER_CALLBACK=$2
  printf 'JOB_APPROVAL_TEST_ADAPTER_READY\n'
}

job_approval_observation_validate() {
  local root=$1 contract=$2 run_id=$3 correlation=$4 role=$5
  [ "$role" = worker ] || { printf 'APPROVAL_OBSERVATION_INVALID field=role\n'; return 1; }
  [ "${JOB_APPROVAL_OBSERVER_MODE:-}" = production ] || {
    printf 'APPROVAL_OBSERVATION_INVALID field=provenance\n'; return 1; }
  local observation
  observation=$($JOB_APPROVAL_OBSERVER_CALLBACK "$root" "$contract" "$run_id" "$correlation" worker) || {
    printf 'APPROVAL_OBSERVATION_INVALID field=observation\n'; return 1; }
  local source got_root got_contract got_run got_corr got_role got_time extra
  IFS=$'\t' read -r source got_root got_contract got_run got_corr got_role got_time extra <<< "$observation"
  [ -z "$extra" ] || { printf 'APPROVAL_OBSERVATION_INVALID field=shape\n'; return 1; }
  [ "$source" = host-control-plane ] || { printf 'APPROVAL_OBSERVATION_INVALID field=source\n'; return 1; }
  [ "$got_root" = "$root" ] || { printf 'APPROVAL_OBSERVATION_INVALID field=root\n'; return 1; }
  [ "$got_contract" = "$contract" ] || { printf 'APPROVAL_OBSERVATION_INVALID field=contractHash\n'; return 1; }
  [ "$got_run" = "$run_id" ] || { printf 'APPROVAL_OBSERVATION_INVALID field=runId\n'; return 1; }
  [ "$got_corr" = "$correlation" ] || { printf 'APPROVAL_OBSERVATION_INVALID field=correlationId\n'; return 1; }
  [ "$got_role" = worker ] || { printf 'APPROVAL_OBSERVATION_INVALID field=role\n'; return 1; }
  [[ "$got_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
    printf 'APPROVAL_OBSERVATION_INVALID field=time\n'; return 1; }
  printf 'APPROVAL_OBSERVATION_OK\n'
}

job_approval_observe() { job_approval_observation_validate "$@"; }
job_integration() { job_integration_run "$@"; }
