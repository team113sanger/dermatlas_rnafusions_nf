
#!/bin/bash
#BSUB -q oversubscribed
#BSUB -G team113-grp
#BSUB -R "select[mem>8000] rusage[mem=8000] span[hosts=1]"
#BSUB -M 8000

set -euo pipefail

module load IRODS
module load HGI/pipelines/irods_to_lustre
 
irods_to_lustre \
-w "${PROJECT_DIR}/work" \
-c "${PROJECT_DIR}/commands/staging.config"