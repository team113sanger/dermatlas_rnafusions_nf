
#!/bin/bash
#BSUB -q oversubscribed
#BSUB -G team113-grp
#BSUB -R "select[mem>8000] rusage[mem=8000] span[hosts=1]"
#BSUB -M 8000

set -euo pipefail

module load IRODS
module load HGI/pipelines/irods_to_lustre/0.2.2
source ${PROJECT_DIR}/source_me.sh

# Create isolated pipeline directory
PIPELINE_DIR="${PROJECT_DIR}/stage_files"
mkdir -p "${PIPELINE_DIR}"

# Set isolated Nextflow directories
export NXF_WORK="${PIPELINE_DIR}/work"
export NXF_TEMP="${PIPELINE_DIR}/tmp"
mkdir -p "${NXF_WORK}" "${NXF_TEMP}"


irods_to_lustre \
-w "${NXF_WORK}" \
-c "${PROJECT_DIR}/commands/staging.config"