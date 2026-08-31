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
#   [skip] RESERVED VARIABLES ............ the env-var classes checked below
#   [edit] ENVIRONMENT SETUP ............. SOURCE_ME: a source_me.sh, or "none"
#   [edit] OPT-IN REPORTING .............. website / Slack toggles
#   [edit] MANUAL ENVIRONMENT OVERRIDES .. commented exports, one per variable
#   [skip] ENVIRONMENT VALIDATION
#   [edit] RUN CONFIGURATION ............. CONFIG, REVISION, LABEL
#   [skip] FILE SYSTEM SETUP ............. RUN_ID, log/trace paths
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

set -euo pipefail

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

function require_bool() {
  # Assert that the named variable is exactly "true" or "false".
  local var="$1" val="${!1:-}"
  case "${val}" in
    true|false) ;;
    *)
      printf 'ERROR: %s must be exactly "true" or "false" (got: "%s").\n' "${var}" "${val}" >&2
      printf 'Edit the OPT-IN REPORTING section of this script.\n' >&2
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
  echo "${input}" | tr '[:upper:]' '[:lower:]' | tr '[:space:]' '-' | tr -cd '[:alnum:]-_'
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
    cohort="$(truncate_string "${sanitized_cohort}" 20)_"
  fi
  echo "${study}${project}${cohort}${timestamp}"
}

############################
#### RESERVED VARIABLES ####
############################
_DEFAULT_PIPELINE_SLUG="rnafusions_pipeline"
_DEFAULT_SOURCE_ME="./source_me.sh"
# Environment variables checked after sourcing source_me.sh, by class:
#  - pipeline-essential: always required to run the pipeline at all.
#  - website-essential:  required only when DERMATLAS_WEBSITE_LOGGING=true.
#  - slack-essential:    required only when DERMATLAS_SLACK_NOTIFICATIONS=true.
_PIPELINE_ENV_VARS=(PROJECT_DIR COMMANDS_DIR ANALYSIS_DIR BAMS_DIR STUDY PROJECT \
                RNA_SAMPLE_LIST_ONE_PER_PATIENT RNA_SAMPLE_LIST_FINAL_DECISION)
_WEBSITE_ENV_VARS=(COHORT_SLUG SAMPLE_LIST_VERSION_FILE SELF_DESCRIBING_API)
_SLACK_ENV_VARS=(SLACK_WEBHOOK_URL)
PIPELINE_SLUG="${RNA_FUSION_PIPELINE_SLUG:-${_DEFAULT_PIPELINE_SLUG}}"

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

# Set to "false" to opt out. Opted-out (and stub) runs make no network calls.
# Deliberately set after source_me.sh, so it can never override them.
DERMATLAS_WEBSITE_LOGGING="true"        # "true"/"false": log this run to the Dermatlas website
DERMATLAS_SLACK_NOTIFICATIONS="true"    # "true"/"false": send a Slack message on completion
export DERMATLAS_WEBSITE_LOGGING DERMATLAS_SLACK_NOTIFICATIONS

require_bool DERMATLAS_WEBSITE_LOGGING
require_bool DERMATLAS_SLACK_NOTIFICATIONS
printf 'Dermatlas website logging:      %s\n' "${DERMATLAS_WEBSITE_LOGGING}"
printf 'Dermatlas Slack notifications:  %s\n' "${DERMATLAS_SLACK_NOTIFICATIONS}"

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
REVISION="0.4.1"
# Optional. If set, RUN_ID becomes <label>_<timestamp> instead of
# <study>_<project>_<cohort>_<timestamp>.
LABEL=""

###########################
#### FILE SYSTEM SETUP ####
###########################

# Create isolated pipeline directory
PIPELINE_DIR="${PROJECT_DIR}/${PIPELINE_SLUG}"
mkdir -p "${PIPELINE_DIR}"

# Set isolated Nextflow directories
export NXF_WORK="${PIPELINE_DIR}/work"
export NXF_TEMP="${PIPELINE_DIR}/tmp"
mkdir -p "${NXF_WORK}" "${NXF_TEMP}"

# Run artifacts. Both are owned by this wrapper rather than source_me.sh, so they are
# always set and need no require_env entry.
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

# Nextflow's own log. Exported rather than passed as -log so that the pipeline can read
# the path back with System.getenv('NXF_LOG_FILE') in its onComplete handler and name it
# in the Slack message when a run fails.
export NXF_LOG_FILE="${PIPELINE_DIR}/logs/nextflow-${RUN_ID}.log"
# Directory for this run's execution trace; consumed by the pipeline's nextflow.config.
export TRACE_DIR="${PIPELINE_DIR}/traces"
mkdir -p "$(dirname "${NXF_LOG_FILE}")" "${TRACE_DIR}"

###################################
#### EXECUTION OF THE PIPELINE ####
###################################

# Load module dependencies
module load nextflow-23.10.0
module load /software/modules/ISG/singularity/3.11.4

# Change to pipeline directory so .nextflow.log goes here
cd "${PIPELINE_DIR}"

nextflow pull "https://github.com/team113sanger/dermatlas_rnafusions_nf" -r "${REVISION}"

nextflow run "https://github.com/team113sanger/dermatlas_rnafusions_nf" \
-resume \
-c "${CONFIG}" \
-r "${REVISION}" \
-profile farm22 \
-work-dir "${NXF_WORK}"
