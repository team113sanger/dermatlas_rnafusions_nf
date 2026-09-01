#!/bin/bash
#BSUB -q oversubscribed
#BSUB -G team113-grp
#BSUB -R "select[mem>8000] rusage[mem=8000] span[hosts=1]"
#BSUB -M 8000

################################################################################
# run_rna_fusions.sh - submit the Dermatlas RNA-fusions nextflow pipeline
#
# Sections ([edit] = user-editable, [skip] = owned by the script):
#   [skip] FUNCTIONS
#   [skip] FAILURE REPORTING ............. exit trap for a failed launch
#   [skip] RESERVED VARIABLES ............ the env-var classes checked below
#   [edit] ENVIRONMENT SETUP ............. SOURCE_ME: a source_me.sh, or "none"
#   [edit] OPT-IN REPORTING .............. website / Slack / work-dir toggles
#                                          (defaults; the environment overrides)
#   [edit] MANUAL ENVIRONMENT OVERRIDES .. commented exports, one per variable
#   [skip] ENVIRONMENT VALIDATION
#   [edit] RUN CONFIGURATION ............. CONFIG, REVISION, LABEL
#   [skip] FILE SYSTEM SETUP ............. RUN_ID, the .lock, log/trace/clone/cache paths
#   [skip] EXECUTION OF THE PIPELINE
#
# Usage 1 - managed (projectify) runs. The dermanager-generated source_me.sh
#   exports everything. Edit nothing; optionally flip the OPT-IN REPORTING
#   toggles.
#     cd <project_dir> && bsub ... < commands/<pipeline>/run_rna_fusions.sh
#
# Usage 2 - git-clone runs (no dermanager source_me.sh). Provide the
#   environment either way:
#     a) set SOURCE_ME="none", then uncomment and fill in MANUAL ENVIRONMENT
#        OVERRIDES; or
#     b) write your own source_me.sh - copy the MANUAL ENVIRONMENT OVERRIDES
#        block into a file, uncomment, fill in - and point SOURCE_ME at it.
#   Then point CONFIG at your own rna_fusions.config (typically with your own
#   subcohorts), and set the OPT-IN REPORTING toggles to "false" unless you
#   know your cohort's slug, sample-list version and API endpoint.
################################################################################

# -E so the ERR trap installed under FAILURE REPORTING is inherited by functions.
set -Eeuo pipefail

###################
#### FUNCTIONS ####
###################

function require_env() {
  # Check that the given environment variables are set and non-empty. The first
  # argument is a remedy hint printed after the list of missing variables. If
  # any are missing, print an error message and exit with a non-zero status.
  local remedy="$1"
  shift
  local var missing=()
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || missing+=("${var}")
  done
  if (( ${#missing[@]} )); then
    printf 'ERROR: the environment did not provide: %s\n' "${missing[*]}" >&2
    printf '%s\n' "${remedy}" >&2
    exit 1
  fi
}

function normalize_bool() {
  # Rewrite the named toggle in place as exactly "true" or "false". Permissive
  # about spelling, but an unrecognised value is an error - a typo must not
  # silently pick a side.
  local var="$1" val="${!1:-}"
  case "${val,,}" in
    true|t|yes|y|on|1)   printf -v "${var}" 'true' ;;
    false|f|no|n|off|0)  printf -v "${var}" 'false' ;;
    *)
      printf 'ERROR: %s must be a true/false value (got: "%s").\n' "${var}" "${val}" >&2
      printf 'Accepted: true/false, yes/no, on/off, 1/0 (any case). Set it in the shell, in\n' >&2
      printf 'source_me.sh, or edit the OPT-IN REPORTING section of this script.\n' >&2
      exit 1
      ;;
  esac
}

function check_for_source_me() {
  # Check that the source_me.sh about to be sourced exists and is readable.
  # If not, print an error message and exit with a non-zero status.
  local source_me="${SOURCE_ME:-./source_me.sh}"
  if [[ ! -f "${source_me}" ]]; then
    printf 'ERROR: %s not found (working directory: %s).\n' "${source_me}" "${PWD}" >&2
    printf 'Submit from the project directory, e.g.\n' >&2
    printf '  cd <project_dir> && bsub ... < commands/run_rna_fusions.sh\n' >&2
    printf '  (or go to the https://team113.sanger.ac.uk/dermatlas/cohorts/ page and re-create the run command for this pipeline for this cohort)\n' >&2
    exit 1
  fi
}

function sanitize() {
  # Sanitize a string to be filesystem-safe. Lowercase, whitespace to hyphen, remove all
  # non-alphanumeric (except for hyphens and underscores) characters.
  local input="${1:-}"
  # printf, not echo: echo's trailing newline is whitespace, and would be turned
  # into a trailing hyphen (e.g. "m25-myofribroma-_20260831T161209").
  printf '%s' "${input}" | tr '[:upper:]' '[:lower:]' | tr '[:space:]' '-' | tr -cd '[:alnum:]-_'
}

function truncate_string() {
  # Truncate a string to a maximum length. If the string is longer than the max length,
  # it is truncated to the first max_length characters.
  # (Named truncate_string so it does not shadow the coreutils `truncate` binary.)
  local input="${1:-}"
  local max_length="${2:-}"
  if (( ${#input} > max_length )); then
    echo "${input:0:max_length}"
  else
    echo "${input}"
  fi
}

function set_run_id_from_label() {
  # Create a run ID derived from the date+time in an ISO 8601 timestamp but
  # filesystem-safe. A label is required and prepended to the timestamp. The label is sanitized to be filesystem-safe.
  # The format '<LABEL>_YYYYMMDDTHHMMSS'
  local label="${1:-}"
  local timestamp
  if [[ -z "${label}" ]]; then
    printf 'ERROR: set_run_id_from_label requires a label argument\n' >&2
    exit 1
  fi
  timestamp=$(date +'%Y%m%dT%H%M%S')
  local sanitized_label
  sanitized_label=$(sanitize "${label}")
  echo "${sanitized_label}_${timestamp}"
}

function set_run_id() {
  # Create a run ID derived from the date+time in an ISO 8601 timestamp but
  # filesystem-safe. If study, project, and cohort are provided (all optional),
  # they are prepended to the timestamp. 
  #
  # Cohort strings longer than 20 characters are truncated to the first 20 characters.
  #
  # Cohort strings have whitespace replaced with hyphens and all other
  # non-alphanumeric (except for hyphens and underscores) characters removed.
  #
  # The format '<STUDY>_<PROJECT>_<COHORT>_YYYYMMDDTHHMMSS'
  local study="${1:-}"
  local project="${2:-}"
  local cohort="${3:-}"
  local timestamp
  timestamp=$(date +'%Y%m%dT%H%M%S')
  if [[ -n "${study}" ]]; then
    study="${study}_"
  fi
  if [[ -n "${project}" ]]; then
    project="${project}_"
  fi
  if [[ -n "${cohort}" ]]; then
    local sanitized_cohort
    sanitized_cohort=$(sanitize "${cohort}")
    cohort="$(truncate_string "${sanitized_cohort}" 40)_"
  fi
  echo "${study}${project}${cohort}${timestamp}"
}

function json_escape() {
  # Escape a string for use as a JSON string value (Slack webhook payloads).
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

function launcher_failure_ref() {
  # How this run is referred to in a failure report, mirroring the onComplete
  # handler's run reference: the cohort slug when the environment gave us one,
  # otherwise the user's LABEL, otherwise a placeholder. Both are optional and
  # both may still be unset - the trap can fire before source_me.sh is read and
  # before RUN CONFIGURATION sets LABEL.
  # (No angle brackets in any value: Slack parses <...> as a link.)
  local ref="${COHORT_SLUG:-}"
  [[ -n "${ref}" ]] || ref="${LABEL:-}"
  [[ -n "${ref}" ]] || ref="unknown-cohort"
  printf '%s' "${ref}"
}

function launcher_failure_details() {
  # The facts of a failed launch, one "Label: value" per line, shared by the
  # stderr report and the Slack message. Every value is optional: the trap can
  # fire at any point, so each is printed only once it is knowable.
  local status="${1:-}"
  printf 'Cohort: %s\n' "$(launcher_failure_ref)"
  printf 'Study: %s\n' "${STUDY:-unset}"
  printf 'Project: %s\n' "${PROJECT:-unset}"
  printf 'Pipeline: %s\n' "${PIPELINE_SLUG:-unset}${REVISION:+ (${REVISION})}"
  printf 'Exit status: %s\n' "${status}"
  # Set by acquire_pipeline_lock when it loses the race: identifies the run that
  # legitimately owns the pipeline directory.
  if [[ -n "${_LAUNCHER_EXTRA_NOTE:-}" ]]; then
    printf '%s\n' "${_LAUNCHER_EXTRA_NOTE}"
  fi
  if [[ -n "${_LAST_ERR_CMD:-}" ]]; then
    printf 'Failed command (line %s): %s\n' "${_LAST_ERR_LINE:-?}" "${_LAST_ERR_CMD}"
  fi
  if [[ -n "${RUN_ID:-}" ]]; then
    printf 'Run id: %s\n' "${RUN_ID}"
  fi
  if [[ -n "${NXF_PULL_LOG_FILE:-}" && -f "${NXF_PULL_LOG_FILE}" ]]; then
    printf 'Nextflow pull log: %s\n' "${NXF_PULL_LOG_FILE}"
  fi
  # LSF identifies the submission far better than anything the script knows when
  # it dies early: LSB_JOBNAME carries the analysis/mission/cohort slug from the
  # bsub job name, and LS_SUBCWD is the project directory it was submitted from -
  # which may be the only identifying value present if source_me.sh never loaded.
  if [[ -n "${LSB_JOBID:-}" ]]; then
    printf 'LSF job: %s\n' "${LSB_JOBID}${LSB_JOBNAME:+ (${LSB_JOBNAME})}"
  fi
  if [[ -n "${LS_SUBCWD:-}" ]]; then
    printf 'Submitted from: %s\n' "${LS_SUBCWD}"
  fi
  printf 'Host: %s\n' "$(hostname -s 2>/dev/null || echo unknown)"
}

function launcher_failure_slack_message() {
  # The Slack message body. Single-quoted formats throughout: the backticks are
  # Slack markup, not command substitution.
  local status="${1:-}"
  printf ':octagonal_sign: *%s* failed before the pipeline was submitted - `%s`\n' \
         "${_LAUNCHER_LABEL}" "$(launcher_failure_ref)"
  printf '_Study: %s | Project: %s | Pipeline: %s_\n' \
         "${STUDY:-unset}" "${PROJECT:-unset}" "${PIPELINE_SLUG:-unset}"
  printf '```\n%s\n```' "$(launcher_failure_details "${status}")"
}

function report_launcher_failure() {
  # Report a launch that died before `nextflow run` took over, with graceful
  # degradation: stderr always (it lands in the LSF job output, so a batch of
  # submissions never fails silently), Slack additionally when the user has
  # opted in and everything needed to send is present. Each skip says why.
  local status="${1:-}" msg
  printf '\n' >&2
  printf 'ERROR: %s failed - the pipeline was never submitted.\n' "${_LAUNCHER_LABEL}" >&2
  launcher_failure_details "${status}" >&2

  if (( ${_TRAP_CAN_SLACK:-0} != 1 )); then
    printf 'NOTE: failed before the reporting opt-ins were read; no Slack message sent.\n' >&2
    return 0
  fi
  if [[ "${DERMATLAS_SLACK_NOTIFICATIONS:-false}" != "true" ]]; then
    printf 'NOTE: DERMATLAS_SLACK_NOTIFICATIONS is not "true"; no Slack message sent.\n' >&2
    return 0
  fi
  if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
    printf 'NOTE: SLACK_WEBHOOK_URL is unset; no Slack message sent.\n' >&2
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    printf 'NOTE: curl was not found on PATH; no Slack message sent.\n' >&2
    return 0
  fi
  msg="$(launcher_failure_slack_message "${status}")"
  if curl -sS -X POST --max-time 15 \
          -H 'Content-Type: application/json; charset=utf-8' \
          --data "{\"text\":\"$(json_escape "${msg}")\"}" \
          "${SLACK_WEBHOOK_URL}" >/dev/null 2>&1; then
    printf 'Slack failure notification sent.\n' >&2
  else
    printf 'NOTE: the Slack failure notification could not be sent.\n' >&2
  fi
  return 0
}

function pipeline_dir_flock_scope() {
  # Best-effort answer to "would a flock here be honoured by other nodes?". Prints
  # "cluster", "node-local" or "unknown". Never fatal: the process that actually deletes
  # data has to fail closed on this, not the launcher.
  local dir="${1:-}" line fstype opts
  command -v findmnt >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  line="$(findmnt -T "${dir}" -no FSTYPE,OPTIONS 2>/dev/null)" || { printf 'unknown'; return 0; }
  [[ -n "${line}" ]] || { printf 'unknown'; return 0; }
  read -r fstype opts <<< "${line}"
  # Lustre "localflock"/"noflock" and NFS "local_lock=all|flock" keep flock inside one
  # node, so two farm nodes would each think they own this directory.
  case ",${opts}," in
    *,localflock,*|*,noflock,*|*,local_lock=all,*|*,local_lock=flock,*)
      printf 'node-local'; return 0 ;;
  esac
  case "${fstype}" in
    lustre|nfs|nfs4|gpfs|ceph|cephfs|beegfs|glusterfs) printf 'cluster' ;;
    *)                                                 printf 'node-local' ;;
  esac
  return 0
}

function lock_holder_description() {
  # The identity a losing contender reports. Tolerant by construction: the holder
  # rewrites .lock in the instant after acquiring, so a contender arriving in that
  # window legitimately sees a blank file - say so rather than guess. Angle brackets
  # become parens because this string reaches Slack, which parses <...> as a link.
  local desc=""
  if [[ -f "${LOCK_FILE:-}" ]]; then
    desc="$(head -c 4096 -- "${LOCK_FILE}" 2>/dev/null \
            | tr -c '[:print:]' ' ' | tr '<>' '()' | tr -s ' ')"
  fi
  if [[ "${desc}" =~ [^[:space:]] ]]; then
    printf '%s' "${desc}"
  else
    printf 'unknown (the holder had not yet recorded its identity)'
  fi
}

function acquire_pipeline_lock() {
  # Take the exclusive lock on ${LOCK_FILE} and hold it for the rest of this process.
  #
  # The lock lives on the open file description, not on the file: the kernel drops it
  # when the last fd referring to it closes, including on SIGKILL or a node crash. So
  # there is never a stale lock to clean up - and ${LOCK_FILE} itself is never removed,
  # because unlinking it lets the next run create a fresh inode and lock that instead,
  # excluding nobody.
  #
  # Opened ">>", never ">": ">" truncates on open, which would destroy a live holder's
  # identity line before flock got round to telling us we lost the race.
  #
  # The fd is inherited by `nextflow run`, deliberately: the lock then means "this
  # directory is in use" rather than "a shell is alive", so an orphaned nextflow keeps
  # the directory protected from the pruner. `lsof "${LOCK_FILE}"` names the holder.
  local scope rc=0 held_ino path_ino

  if [[ -L "${LOCK_FILE}" ]]; then
    printf 'ERROR: %s is a symlink; refusing to lock or write through it.\n' "${LOCK_FILE}" >&2
    exit 1
  fi
  if [[ -e "${LOCK_FILE}" && ! -f "${LOCK_FILE}" ]]; then
    printf 'ERROR: %s exists and is not a regular file.\n' "${LOCK_FILE}" >&2
    exit 1
  fi

  scope="$(pipeline_dir_flock_scope "${PIPELINE_DIR}")"
  if [[ "${scope}" == "node-local" ]]; then
    printf 'WARNING: flock on %s looks node-local (%s).\n' "${PIPELINE_DIR}" \
           "$(findmnt -T "${PIPELINE_DIR}" -no FSTYPE,OPTIONS 2>/dev/null || echo 'unknown mount')" >&2
    printf '         Runs on other nodes will NOT exclude each other, and a work-dir\n' >&2
    printf '         pruner running elsewhere will not see this lock. Continuing anyway.\n' >&2
  fi

  # A failed redirection on `exec` exits the shell outright rather than returning
  # non-zero, so this needs no check: on_launcher_exit reports it, and
  # _HOLDS_PIPELINE_LOCK is still 0 so no sentinel is written - correct, because a
  # directory we cannot even open may be owned by a live run.
  exec {_LOCK_FD}>>"${LOCK_FILE}"
  chmod 0644 "${LOCK_FILE}" 2>/dev/null || true

  flock -n -E "${_LOCK_CONFLICT_RC}" -x "${_LOCK_FD}" || rc=$?
  if (( rc == _LOCK_CONFLICT_RC )); then
    _LAUNCHER_EXTRA_NOTE="Lock holder: $(lock_holder_description)"
    printf 'ERROR: another run already owns %s.\n' "${PIPELINE_DIR}" >&2
    printf '       %s\n' "${_LAUNCHER_EXTRA_NOTE}" >&2
    printf '       Lock file: %s\n' "${LOCK_FILE}" >&2
    printf '       Wait for that run to finish, or kill it, before submitting again.\n' >&2
    exit "${_LOCK_CONFLICT_RC}"
  elif (( rc != 0 )); then
    # flock's own sysexits codes (65, 71, ...), not ours: flock itself failed, this is
    # not contention. Reporting it as contention would send someone hunting for a run
    # that does not exist.
    printf 'ERROR: flock failed on %s (exit %s). This is NOT contention - flock may be\n' "${LOCK_FILE}" "${rc}" >&2
    printf '       unsupported on this filesystem, or the descriptor is unusable.\n' >&2
    exit 1
  fi

  # The lock is only ours if the path we opened is still the inode we locked. If .lock
  # was replaced between our open() and our flock(), we hold a lock on an orphaned inode
  # and exclude nobody.
  held_ino="$(stat -Lc '%d:%i' "/proc/self/fd/${_LOCK_FD}" 2>/dev/null || true)"
  path_ino="$(stat -c '%d:%i' "${LOCK_FILE}" 2>/dev/null || true)"
  if [[ -n "${held_ino}" && "${held_ino}" != "${path_ino}" ]]; then
    printf 'ERROR: %s was replaced or removed while it was being locked.\n' "${LOCK_FILE}" >&2
    printf '       Nothing may unlink this file: doing so breaks mutual exclusion.\n' >&2
    exit 1
  fi

  # Only now. Every exit above leaves the lock NOT held, and write_completion_sentinel
  # keys off this flag precisely so a run that lost the race cannot overwrite the state
  # of the run that legitimately owns the directory.
  _HOLDS_PIPELINE_LOCK=1

  # Publish who we are, for the next contender's error message. A truncating write, not
  # an append: the fd above is O_APPEND and cannot be rewritten through, hence the
  # separate open. Done only now, under the lock, so two runs cannot interleave here.
  printf 'run_id=%s pid=%s host=%s lsf_job=%s revision=%s flock_scope=%s started=%s\n' \
         "${RUN_ID:-unset}" "$$" "$(hostname -s 2>/dev/null || echo unknown)" \
         "${LSB_JOBID:-none}${LSB_JOBNAME:+ (${LSB_JOBNAME})}" "${REVISION:-unset}" \
         "${scope}" "$(date +'%Y-%m-%dT%H:%M:%S%z')" \
         > "${LOCK_FILE}" \
    || printf 'NOTE: could not record the lock holder in %s.\n' "${LOCK_FILE}" >&2

  # Clear the previous run's verdict, only ever while holding the lock. From here until
  # the exit trap neither sentinel exists, which a pruner must read as "in progress, or
  # died without a verdict - do not touch".
  rm -f -- "${PIPELINE_DIR}/.completed_successfully" \
           "${PIPELINE_DIR}/.completed_with_error"

  printf 'Pipeline directory locked: %s\n' "${LOCK_FILE}"
  return 0
}

function write_completion_sentinel() {
  # Record this run's verdict in ${PIPELINE_DIR} for the external work-dir pruner.
  # Exactly one of .completed_successfully / .completed_with_error exists afterwards;
  # both are absent while a run is in progress, and after one that died without
  # reaching a trap. The filename is the state - the contents are an audit line for
  # humans, and no pruning decision should parse them.
  #
  # THE GUARD: only a run that actually holds the lock may write. A run that lost the
  # race to flock exits non-zero and its trap lands here too - writing
  # .completed_with_error there would declare the other, still-running, run failed and
  # invite the pruner to delete a live work directory.
  local status="${1:-0}" name path outcome
  (( ${_HOLDS_PIPELINE_LOCK:-0} == 1 )) || return 0
  [[ -n "${PIPELINE_DIR:-}" && -d "${PIPELINE_DIR:-}" ]] || return 0

  if (( status == 0 )); then
    name=".completed_successfully"; outcome="success"
  elif (( status >= 128 )); then
    name=".completed_with_error";   outcome="killed"   # 128+n: bkill, MEMLIMIT, RUNLIMIT
  else
    name=".completed_with_error";   outcome="failed"
  fi
  path="${PIPELINE_DIR}/${name}"

  # Both, first: exactly one verdict may exist, and rm -f also drops a symlink planted
  # where the sentinel goes rather than writing through it.
  rm -f -- "${PIPELINE_DIR}/.completed_successfully" \
           "${PIPELINE_DIR}/.completed_with_error"

  # One printf, one open, one write, so a reader sees the file absent or whole. And it
  # is written while the lock is still held - the fd closes only when this process
  # exits, after this trap - so a pruner that locks before reading cannot catch it
  # part-written.
  if printf 'outcome=%s\nexit_status=%s\nrun_id=%s\nrevision=%s\nfinished=%s\nlsf_job_id=%s\nlsf_job_name=%s\nhost=%s\nwork_dir=%s\nwork_dir_disposition=%s\n' \
       "${outcome}" "${status}" "${RUN_ID:-unset}" "${REVISION:-unset}" \
       "$(date +'%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo unknown)" \
       "${LSB_JOBID:-none}" "${LSB_JOBNAME:-none}" \
       "$(hostname -s 2>/dev/null || echo unknown)" \
       "${NXF_WORK:-unset}" "${_WORK_DIR_DISPOSITION:-kept}" \
       > "${path}"
  then
    chmod 0644 "${path}" 2>/dev/null || true
    printf 'Wrote completion sentinel: %s\n' "${path}"
  else
    printf 'NOTE: could not write the completion sentinel %s.\n' "${path}" >&2
  fi
  return 0
}

function on_launcher_exit() {
  # EXIT trap. Catches the status the script is dying with, reports it, then
  # re-emits it unchanged so the LSF job still fails.
  local status="${1:-0}"
  trap - EXIT ERR INT TERM HUP     # never re-enter, whatever happens below
  set +e                           # a failure in here must not mask ${status}
  set +u                           # nor may an unset reference: under `set -u` that
                                   # kills the shell even with `set +e`
  # Before the human report: the sentinel is what the work-dir pruner reads, and
  # reporting can hang on curl or be cut short by a second signal.
  write_completion_sentinel "${status}"
  if (( status != 0 )); then
    report_launcher_failure "${status}"
  fi
  exit "${status}"
}

function cleanup_work_dir() {
  # Delete this run's work directory - hundreds of GB, and publishDir has already
  # copied out anything worth keeping (needs params.publish_dir_mode = 'copy').
  # Callers must only do this on success: a failed run keeps its work dir.
  local work="${NXF_WORK:-}"
  # Only ever the directory this script created, never an inherited NXF_WORK.
  if [[ "${work}" != "${PIPELINE_DIR}/work" ]]; then
    printf 'NOTE: refusing to delete "%s" - it is not the work directory this script created.\n' "${work}" >&2
    _WORK_DIR_DISPOSITION="not-removed-refused"
    return 0
  fi
  if [[ ! -d "${work}" ]]; then
    _WORK_DIR_DISPOSITION="absent"
    return 0
  fi
  printf 'Cleaning up work directory: %s\n' "${work}"
  if rm -rf "${work}"; then
    printf 'Work directory removed.\n'
    _WORK_DIR_DISPOSITION="removed"
  else
    printf 'NOTE: the work directory was not fully removed: %s\n' "${work}" >&2
    _WORK_DIR_DISPOSITION="partially-removed"
  fi
  return 0
}

function on_pipeline_exit() {
  # EXIT trap for the `nextflow run` phase. Reports nothing - that is
  # workflow.onComplete's job by then - and cleans up only on success, and only
  # when the run has not opted out.
  local status="${1:-0}"
  trap - EXIT INT TERM HUP         # never re-enter
  set +e                           # cleanup must not mask ${status}
  set +u                           # nor may an unset reference (see on_launcher_exit)
  if (( status == 0 )); then
    if [[ "${DERMATLAS_CLEANUP_WORK_DIR:-true}" == "true" ]]; then
      cleanup_work_dir
    else
      _WORK_DIR_DISPOSITION="kept-opted-out"
      printf 'Keeping work directory (DERMATLAS_CLEANUP_WORK_DIR=false): %s\n' "${NXF_WORK:-unset}"
    fi
  else
    _WORK_DIR_DISPOSITION="kept-failed-run"
  fi
  # After the cleanup, never before: the sentinel records what actually happened to the
  # work directory, so it must not claim "removed" for a run killed part-way through its
  # own rm -rf. Still inside the trap, so the lock fd has not closed yet.
  write_completion_sentinel "${status}"
  exit "${status}"
}

############################
#### FAILURE REPORTING  ####
############################

# Everything from here to the `trap -` before `nextflow run` is covered: if the
# script dies during setup (a missing variable, an unwritable directory, a
# failed `module load`, a failed `nextflow pull`, an LSF kill) the trap reports
# it and re-emits the exit status. Without this a batch of submissions can lose
# one to a setup error silently - `nextflow run` never starts, so the pipeline's
# own onComplete reporting never runs.
#
# Two stages, because SLACK_WEBHOOK_URL and the opt-in toggles are not known
# yet: until OPT-IN REPORTING sets _TRAP_CAN_SLACK=1 the trap reports to stderr
# only. It never sends Slack for a user who has opted out.
_LAUNCHER_LABEL="Dermatlas RNA fusions launcher"
_TRAP_CAN_SLACK=0
_LAST_ERR_CMD=""
_LAST_ERR_LINE=""

# The ERR trap only records context; the EXIT trap does the reporting, so an
# explicit `exit 1` (e.g. from require_env) is reported too, just without a
# failing command to name. The signal traps exit with 128+n so that a killed
# job (bkill, memory limit, run limit) still reaches the EXIT trap.
trap '_LAST_ERR_CMD="${BASH_COMMAND}"; _LAST_ERR_LINE="${LINENO}"' ERR
trap 'on_launcher_exit $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

############################
#### RESERVED VARIABLES ####
############################
_DEFAULT_PIPELINE_SLUG="rnafusion_pipe"
_DEFAULT_SOURCE_ME="./source_me.sh"
# The toggle values the submitting shell had, snapshotted before source_me.sh is
# read so OPT-IN REPORTING can apply them over it.
_ENV_WEBSITE_LOGGING="${DERMATLAS_WEBSITE_LOGGING:-}"
_ENV_SLACK_NOTIFICATIONS="${DERMATLAS_SLACK_NOTIFICATIONS:-}"
_ENV_CLEANUP_WORK_DIR="${DERMATLAS_CLEANUP_WORK_DIR:-}"
# Environment variables checked after sourcing source_me.sh, by class:
#  - pipeline-essential: always required to run the pipeline at all.
#  - website-essential:  required only when DERMATLAS_WEBSITE_LOGGING=true.
#  - slack-essential:    required only when DERMATLAS_SLACK_NOTIFICATIONS=true.
_PIPELINE_ENV_VARS=(PROJECT_DIR COMMANDS_DIR ANALYSIS_DIR BAMS_DIR STUDY PROJECT \
                RNA_SAMPLE_LIST_ONE_PER_PATIENT RNA_SAMPLE_LIST_FINAL_DECISION)
_WEBSITE_ENV_VARS=(COHORT_SLUG SAMPLE_LIST_VERSION_FILE SELF_DESCRIBING_API)
_SLACK_ENV_VARS=(SLACK_WEBHOOK_URL)
PIPELINE_SLUG="${RNA_FUSION_PIPELINE_SLUG:-${_DEFAULT_PIPELINE_SLUG}}"
# Pipeline-directory lock and completion sentinels. Declared here, before any trap can
# fire, so `set -u` cannot turn a trap into a second, different failure.
#   LOCK_FILE             ${PIPELINE_DIR}/.lock; set in FILE SYSTEM SETUP. Created once
#                         and never removed - its presence says only that this directory
#                         uses the scheme, never that a run is live. Only flock does.
#   _LOCK_FD              fd holding the flock. Never closed explicitly: the kernel
#                         releases the lock when this process dies, however it dies.
#   _HOLDS_PIPELINE_LOCK  1 only between a successful acquire and process exit.
#                         write_completion_sentinel refuses to write unless it is 1.
#   _LOCK_CONFLICT_RC     flock -E value, distinguishing "another run holds it" from
#                         "flock itself failed" (flock uses sysexits 64-71, so a value
#                         outside that range cannot collide).
#   _WORK_DIR_DISPOSITION what became of work/; recorded in the sentinel.
#   _LAUNCHER_EXTRA_NOTE  one extra line for the failure report (the lock holder).
LOCK_FILE=""
_LOCK_FD=""
_HOLDS_PIPELINE_LOCK=0
_LOCK_CONFLICT_RC=75
_WORK_DIR_DISPOSITION="kept"
_LAUNCHER_EXTRA_NOTE=""

###########################
#### ENVIRONMENT SETUP ####
###########################

# Path to the environment file, or "none" to skip sourcing and rely on
# MANUAL ENVIRONMENT OVERRIDES below.
SOURCE_ME=${SOURCE_ME:-"${_DEFAULT_SOURCE_ME}"}
if [[ "${SOURCE_ME}" != "none" ]]; then
  check_for_source_me
  source "${SOURCE_ME}"             # Most of the environment variables are set here
fi

############################
#### OPT-IN REPORTING   ####
############################

# Defaults for this script's toggles; edit them to change every run. Opted-out
# (and stub) runs make no network calls.
_DEFAULT_WEBSITE_LOGGING="true"        # log this run to the Dermatlas website
_DEFAULT_SLACK_NOTIFICATIONS="true"    # send a Slack message on completion
_DEFAULT_CLEANUP_WORK_DIR="true"       # delete this run's work dir after a successful run

# The environment overrides those defaults, most specific first: an export in the
# submitting shell beats one in source_me.sh, which beats the default above - so a
# one-off run can opt out without editing this file or a shared source_me.sh:
#   export DERMATLAS_CLEANUP_WORK_DIR=false
#   bsub ... < commands/<pipeline>/run_rna_fusions.sh
# (_ENV_* is the shell's value, snapshotted before the source; the bare name holds
# whatever source_me.sh went on to export.)
DERMATLAS_WEBSITE_LOGGING="${_ENV_WEBSITE_LOGGING:-${DERMATLAS_WEBSITE_LOGGING:-${_DEFAULT_WEBSITE_LOGGING}}}"
DERMATLAS_SLACK_NOTIFICATIONS="${_ENV_SLACK_NOTIFICATIONS:-${DERMATLAS_SLACK_NOTIFICATIONS:-${_DEFAULT_SLACK_NOTIFICATIONS}}}"
DERMATLAS_CLEANUP_WORK_DIR="${_ENV_CLEANUP_WORK_DIR:-${DERMATLAS_CLEANUP_WORK_DIR:-${_DEFAULT_CLEANUP_WORK_DIR}}}"

# Validated here rather than where they are used, so a typo fails the launch
# immediately rather than hours later, and everything downstream (including the
# pipeline's own onComplete handler) sees exactly "true" or "false".
normalize_bool DERMATLAS_WEBSITE_LOGGING
normalize_bool DERMATLAS_SLACK_NOTIFICATIONS
normalize_bool DERMATLAS_CLEANUP_WORK_DIR
export DERMATLAS_WEBSITE_LOGGING DERMATLAS_SLACK_NOTIFICATIONS DERMATLAS_CLEANUP_WORK_DIR

printf 'Dermatlas website logging:      %s\n' "${DERMATLAS_WEBSITE_LOGGING}"
printf 'Dermatlas Slack notifications:  %s\n' "${DERMATLAS_SLACK_NOTIFICATIONS}"
printf 'Work directory cleanup:         %s\n' "${DERMATLAS_CLEANUP_WORK_DIR}"

# Arm the failure trap's Slack channel: the toggles are now known and validated,
# and source_me.sh has had its chance to export SLACK_WEBHOOK_URL.
_TRAP_CAN_SLACK=1

######################################
#### MANUAL ENVIRONMENT OVERRIDES ####
######################################

# The full environment contract, one commented export per variable. Uncomment
# and fill in to run without a source_me.sh (SOURCE_ME="none") or to override
# individual values - anything exported here wins over source_me.sh. To write
# your own source_me.sh instead, copy this block into a file and point
# SOURCE_ME at it.
#
# Pipeline-essential (always required):
# export PROJECT_DIR=""    # e.g. "/lustre/scratch127/.../<my_project>"; the pipeline's work/log/trace dirs are created under it
# export COMMANDS_DIR=""   # e.g. "${PROJECT_DIR}/commands"; CONFIG below defaults to living beneath it
# export ANALYSIS_DIR=""   # e.g. "${PROJECT_DIR}/analysis"; results land in ${ANALYSIS_DIR}/star-fusion (config: outdir)
# export BAMS_DIR=""       # e.g. "${PROJECT_DIR}/bams"; the config globs ${BAMS_DIR}/**bam{,.bai} (config: bam_path)
# export STUDY=""          # e.g. "6740"; prefixes output filenames (config: study_id) and the run id
# export PROJECT=""        # e.g. "3016"; part of the run id
# export RNA_SAMPLE_LIST_ONE_PER_PATIENT=""  # e.g. "${PROJECT_DIR}/metadata/<cohort>_one_samp_ppat_sampnames.tsv"
# export RNA_SAMPLE_LIST_FINAL_DECISION=""   # e.g. "${PROJECT_DIR}/metadata/<cohort>_final_decision_sampnames.tsv"
#
# Website-essential (required only when DERMATLAS_WEBSITE_LOGGING="true"):
# export COHORT_SLUG=""              # e.g. "m10-cutaneous-mixed-tumour"; keys the analysis-log record
# export SAMPLE_LIST_VERSION_FILE="" # e.g. "${PROJECT_DIR}/metadata/VERSION"; a file holding one integer >= 1
# export SELF_DESCRIBING_API=""      # e.g. "https://team113.sanger.ac.uk/api/v1/resolve/"; dermatlas-http --api endpoint
#
# Slack-essential (required only when DERMATLAS_SLACK_NOTIFICATIONS="true"):
# export SLACK_WEBHOOK_URL=""        # e.g. "https://hooks.slack.com/services/T000/B000/XXXX"
#
# The DERMATLAS_* toggles do not belong here: OPT-IN REPORTING above has already
# resolved them. Set them in your shell or source_me.sh, or edit their defaults.

################################
#### ENVIRONMENT VALIDATION ####
################################

require_env 'Regenerate source_me.sh with a dermanager version that exports these variables (or export them yourself if you git-cloned the pipeline).' \
            "${_PIPELINE_ENV_VARS[@]}"
if [[ "${DERMATLAS_WEBSITE_LOGGING}" == "true" ]]; then
  require_env 'Needed because DERMATLAS_WEBSITE_LOGGING=true. Fix source_me.sh, or set DERMATLAS_WEBSITE_LOGGING="false" in this script to opt out of website logging.' \
              "${_WEBSITE_ENV_VARS[@]}"
fi
if [[ "${DERMATLAS_SLACK_NOTIFICATIONS}" == "true" ]]; then
  require_env 'Needed because DERMATLAS_SLACK_NOTIFICATIONS=true. Fix source_me.sh, or set DERMATLAS_SLACK_NOTIFICATIONS="false" in this script to opt out of Slack notifications.' \
              "${_SLACK_ENV_VARS[@]}"
fi

###########################
#### RUN CONFIGURATION ####
###########################

# Nextflow config for this run; git-clone runs point this at their own copy.
CONFIG="${COMMANDS_DIR}/${PIPELINE_SLUG}/rna_fusions.config"
# Pipeline version to run: a tag or commit hash.
REVISION="0.4.9"
# Optional. If set, RUN_ID becomes <label>_<timestamp> instead of
# <study>_<project>_<cohort>_<timestamp>.
LABEL=""

###########################
#### FILE SYSTEM SETUP ####
###########################

# Create isolated pipeline directory
PIPELINE_DIR="${PROJECT_DIR}/${PIPELINE_SLUG}"
mkdir -p "${PIPELINE_DIR}"

# Run artifacts. Both are owned by this wrapper rather than source_me.sh, so they are
# always set and need no require_env entry. Computed here, above the lock, so the lock
# file and both completion sentinels can always name this run - it depends only on
# LABEL/STUDY/PROJECT/COHORT_SLUG and touches nothing on disk.
if [[ -n "${LABEL:-}" ]]; then
  RUN_ID="$(set_run_id_from_label "${LABEL}")"
else
  RUN_ID="$(set_run_id "${STUDY:-}" "${PROJECT:-}" "${COHORT_SLUG:-}")"
fi
# One id names all of this run's artifacts: nextflow-<RUN_ID>.log,
# execution_trace-<RUN_ID>.txt, execution_report-<RUN_ID>.html, and the run
# reference in Slack messages. Exported so the pipeline's nextflow.config and
# onComplete handler can read it back.
export RUN_ID

# One launcher owns ${PIPELINE_DIR} at a time. Taken here, before anything under it is
# written, and released by the kernel when this process dies. Fails fast on contention
# rather than waiting: a second concurrent submission of the same cohort is a mistake,
# not a queue - and until now both would have shared one work/ directory, with the first
# to finish deleting it under the second.
LOCK_FILE="${PIPELINE_DIR}/.lock"
acquire_pipeline_lock

# Set isolated Nextflow directories
export NXF_WORK="${PIPELINE_DIR}/work"
export NXF_TEMP="${PIPELINE_DIR}/tmp"
mkdir -p "${NXF_WORK}" "${NXF_TEMP}"

# One git clone per revision. The shared default at ${NXF_HOME}/assets is checked
# out in place by every pull and run, so parallel runs on different revisions
# clobber each other, and its first pull of a newly published tag fails with
# "Cannot find revision". Named clones/ to keep it distinct from assets/.
export NXF_ASSETS="${PIPELINE_DIR}/clones/${REVISION}"
mkdir -p "${NXF_ASSETS}"

# Pinned, not defaulted: an LSF job inherits the submitter's profile, which may
# already set this. Nextflow's default is <work-dir>/singularity, which the
# cleanup trap deletes. Matches singularity.cacheDir in the farm22 profile.
export NXF_SINGULARITY_CACHEDIR="/lustre/scratch127/casm/projects/dermatlas/singularity_images"

# Nextflow's own log. Exported rather than passed as -log so that the pipeline can read
# the path back with System.getenv('NXF_LOG_FILE') in its onComplete handler and name it
# in the Slack message when a run fails.
LOG_DIR="${PIPELINE_DIR}/logs"
NXF_RUN_LOG_FILE="${LOG_DIR}/nextflow-run-${RUN_ID}.log"
NXF_PULL_LOG_FILE="${LOG_DIR}/nextflow-pull-${RUN_ID}.log"
# Directory for this run's execution trace; consumed by the pipeline's nextflow.config.
export TRACE_DIR="${PIPELINE_DIR}/traces"
mkdir -p "${LOG_DIR}" "${TRACE_DIR}"

###################################
#### EXECUTION OF THE PIPELINE ####
###################################

# Load module dependencies
module load nextflow-23.10.0
module load /software/modules/ISG/singularity/3.11.4

# Change to pipeline directory so .nextflow.log goes here
cd "${PIPELINE_DIR}"

NXF_LOG_FILE="${NXF_PULL_LOG_FILE}" \
  nextflow pull "https://github.com/team113sanger/dermatlas_rnafusions_nf" -r "${REVISION}"

# Hand reporting over to the pipeline: from here on a failure is reported by
# workflow.onComplete (lib/Utils.groovy), so the trap must not fire as well. Its
# replacement reports nothing and only acts on success.
trap - EXIT ERR INT TERM HUP
trap 'on_pipeline_exit $?' EXIT
# Reinstated deliberately. Without them an LSF kill during `nextflow run` reaches the
# EXIT trap with $? == 0 - bash runs the EXIT trap for an untrapped fatal signal, and $?
# is then the last *completed* command's status, not the signal's - so a killed run looks
# successful and has its work directory deleted. 128+n makes it the failure it is.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

NXF_LOG_FILE="${NXF_RUN_LOG_FILE}" \
  nextflow run "https://github.com/team113sanger/dermatlas_rnafusions_nf" \
  -resume \
  -c "${CONFIG}" \
  -r "${REVISION}" \
  -profile farm22 \
  -work-dir "${NXF_WORK}"
