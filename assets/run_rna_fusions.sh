#!/bin/bash
#BSUB -q oversubscribed
#BSUB -G team113-grp
#BSUB -R "select[mem>8000] rusage[mem=8000] span[hosts=1]"
#BSUB -M 8000

set -euo pipefail

# source_me.sh sits alongside this script's launch directory: the job is submitted from the
# project directory (cd <project_dir> && bsub ... < commands/run_rna_fusions.sh) and LSF
# starts the job in the submission directory. Note that `bsub <` spools the script via
# stdin, so $BASH_SOURCE points at the spool file and cannot be used to locate the project.
# The leading ./ matters: `source` searches $PATH for a bare filename.
SOURCE_ME="./source_me.sh"
if [[ ! -f "${SOURCE_ME}" ]]; then
  printf 'ERROR: %s not found (working directory: %s).\n' "${SOURCE_ME}" "${PWD}" >&2
  printf 'Submit from the project directory, e.g.\n' >&2
  printf '  cd <project_dir> && bsub ... < commands/run_rna_fusions.sh\n' >&2
  printf '  (or go to the https://team113.sanger.ac.uk/dermatlas/cohorts/ page and re-create the run command for this pipeline for this cohort)\n' >&2
  exit 1
fi
source "${SOURCE_ME}"

# Fail loudly if source_me.sh is missing anything this pipeline needs. Nextflow does not
# error on an unset variable in a config - it substitutes the literal '[:]' and only warns,
# which produces nonsense paths and a run that "succeeds" with no output.
require_env() {
  local var missing=()
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || missing+=("${var}")
  done
  if (( ${#missing[@]} )); then
    printf 'ERROR: the project source_me.sh did not export: %s\n' "${missing[*]}" >&2
    printf 'Regenerate it with a dermanager version that exports these variables.\n' >&2
    exit 1
  fi
}

require_env PROJECT_DIR COMMANDS_DIR ANALYSIS_DIR BAMS_DIR STUDY PROJECT COHORT_SLUG \
            RNA_SAMPLE_LIST_ONE_PER_PATIENT RNA_SAMPLE_LIST_FINAL_DECISION \
            SAMPLE_LIST_VERSION_FILE ANALYSIS_LOG_API_URL

CONFIG="${COMMANDS_DIR}/rna_fusions.config"
REVISION="0.4.0"

# Create isolated pipeline directory
PIPELINE_DIR="${PROJECT_DIR}/rnafusions_pipeline"
mkdir -p "${PIPELINE_DIR}"

# Set isolated Nextflow directories
export NXF_WORK="${PIPELINE_DIR}/work"
export NXF_TEMP="${PIPELINE_DIR}/tmp"
mkdir -p "${NXF_WORK}" "${NXF_TEMP}"

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
