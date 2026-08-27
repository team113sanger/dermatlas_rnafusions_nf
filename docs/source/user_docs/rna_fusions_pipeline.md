
# Nextflow: RNA fusions pipeline

RNA Fusion calling and post-processing for DERMATLAS can be run mostly with a two nextflow pipelines in a largely "set-and-forget" manner.This document contains an overview of how to configure and run these pipelines. A more detailed explanation of the pipeline inputs and requirements for running can be found within the dermatlas\_rna\_fusions.nf project [README](https://github.com/team113sanger/dermatlas_rnafusions_nf/blob/develop/README.md). A more detailed explanation of how to run StarFusion manually and interpret its key results can be found here [DERMATLAS - Information about the STAR-Fusion version and references used for DERMATLAS analysis](/spaces/CAS/pages/68912708/DERMATLAS+-+Information+about+the+STAR-Fusion+version+and+references+used+for+DERMATLAS+analysis)

## Workflow Overview:

**1) Staging raw reads** 
**2) Generating the cohort config file** 
**3) Running the pipeline**

## Workflow Steps:

First, we need the aligned read data for the analysis. The pipeline takes **indexed BAMs** as its default input, and staging these is handled as part of project setup (see [Dermatlas analysis setup (v1.0.0](/spaces/CAS/pages/156434559/Dermatlas+analysis+setup+v1.0.0))). If this is the case should have an RNA project directory that looks something like this:

```bash
.
├── analysis
├── bams
├── commands
├── logs
├── metadata
├── resources -> /lustre/scratch127/casm/projects/dermatlas/resources
├── scripts
└── source_me.sh
```

If you follow along the steps detailed in [Dermatlas analysis setup (v1.0.0)#StagingFastqs(RNA)](/spaces/CAS/pages/156434559/Dermatlas+analysis+setup+v1.0.0#Dermatlasanalysissetup(v1.0.0)-StagingFastqs(RNA))  then the project `bams` directory (exported as `${BAMS_DIR}`) will hold one subdirectory per sample, each containing an indexed BAM plus its `.bai`. The pipeline derives each sample's Dermatlas patient id (PRID) from the BAM filename, taking the prefix before the first dot, so `sample_metadata` is not required. For example:

```bash
bams
├── PR62424a
│   ├── PR62424a.sample.dupmarked.bam
│   └── PR62424a.sample.dupmarked.bam.bai
└── PR62425a
    ├── PR62425a.sample.dupmarked.bam
    └── PR62425a.sample.dupmarked.bam.bai
```

Now, we can proceed with generating a configuration file for the RNA fusions pipeline run. This config file fetches the sample lists created by dermatlas RNA ingestion. 

One of them, **${RNA\_SAMPLE\_LIST\_ONE\_PER\_PATIENT}**, contains QC passing samples (one per patient). Every project-specific location in the config comes from a variable exported by the project **source\_me.sh** (`${BAMS_DIR}`, `${ANALYSIS_DIR}`, `${RNA_SAMPLE_LIST_ONE_PER_PATIENT}`, ...) and is interpreted by nextflow at runtime, so the config file is identical across projects. You can modify the set of samples that are analysed by the pipeline by modifying the list that variable points at.

The canonical, source-controlled copies of the config and wrapper script below live in the pipeline repository under `assets/`; they are injected into your project `commands/` directory during setup.

**Example config file:**

```groovy
params {
    bam_path = "${BAMS_DIR}/**bam{,.bai}"
    outdir   = "${ANALYSIS_DIR}/star-fusion"
    ctat_lib = "/lustre/scratch127/casm/projects/dermatlas/references/star_fusion/GRCh38_gencode_v37_CTAT_lib_Mar012021.plug-n-play/ctat_genome_lib_build_dir"
    study_id = "${STUDY}"
    subcohorts = [
        "one_per_patient": [
            sample_list: "${RNA_SAMPLE_LIST_ONE_PER_PATIENT}"
        ],
        "final_decision": [
            sample_list: "${RNA_SAMPLE_LIST_FINAL_DECISION}"
        ]
    ]

    // Run reporting
    analysis_log_api_url   = "${ANALYSIS_LOG_API_URL}"
    sample_list_version    = "${SAMPLE_LIST_VERSION_FILE}"
    cohort_slug            = "${COHORT_SLUG}"
    analysis_pipeline_slug = "rnafusion_pipe"
}

```

`bam_path` is a glob matching the staged BAMs **and** their `.bai` indexes. Each BAM is
unwound back to paired-end reads before STAR-Fusion. The glob has to match *exactly* two
files per sample: `**` descends into the per-sample subdirectories, and `{,.bai}` excludes
the `.bam.bas` and `.bam.met.gz` files that sit alongside each BAM. A looser glob matches
nothing usable and the pipeline finishes "successfully" having produced no output.

:::{note}
Nextflow does not treat an unset `${...}` variable in a config as an error - it substitutes
the literal `[:]` and only warns. The `run_rna_fusions.sh` wrapper therefore checks up front
that `source_me.sh` exported everything the config needs, and refuses to launch otherwise.
:::

:::{note}
**Starting from FASTQs instead of BAMs**

Indexed BAMs are the default input. If you instead have paired FASTQs, set `fastq_path`
(a glob of the paired files, e.g. `"${PROJECT_DIR}/fastq/**_{1,2}.fastq.gz"`) in place of
`bam_path`, together with `sample_metadata` pointing at `samples_noduplicates.tsv` to map
Sanger ids to PRIDs. Provide **exactly one** of `bam_path` or `fastq_path` — the run errors
if both or neither is set. See the project README for full details.
:::

**Launching the nextflow pipeline**

Once you have your inputs you can prepare to launch the pipeline by modifying and saving this wrapper script in your project commands directory. You will need to update the path to your config file and your desired log file locations. 

In this script the "`-r"`  option specifies which version of the pipeline you'd like to run. Normally you should select the latest version (currently **0.4.0**)

**Example file:**

**run\_fusion\_calling.sh**

```bash
#!/bin/bash
#BSUB -q oversubscribed
#BSUB -G team113-grp
#BSUB -R "select[mem>8000] rusage[mem=8000] span[hosts=1]"
#BSUB -M 8000
#BSUB -oo <CHANGE_ME>/logs/rna_fusion%J.o
#BSUB -eo <CHANGE_ME>/logs/rna_fusion%J.e


source ./source_me.sh
CONFIG="${COMMANDS_DIR}/rna_fusions.config"

# Load module dependencies
module load nextflow-23.10.0
module load /software/modules/ISG/singularity/3.11.4

nextflow pull "https://github.com/team113sanger/dermatlas_rnafusions_nf"

nextflow run "https://github.com/team113sanger/dermatlas_rnafusions_nf" \
-resume \
-c "${CONFIG}" \
-r 0.4.0 \
-profile farm22
```

If you called the script `run_rna_fusions.sh` then you'll be able to submit 

```bash
cd <your_project_dir>
bsub < commands/run_rna_fusions.sh
```

(Submit from the project directory so the job starts there and the wrapper finds
`./source_me.sh`. It cannot work out where the project is from its own path: `bsub <` feeds
the script to LSF on stdin, which spools it to a temporary file.)

The bsub magic at the start of the wrapper script will send a nextflow "master job", which looks after all other jobs to the oversubscribed queue (where it can live in peace running for a long period without fear of termination). Nextflow will shortly start submitting jobs on your behalf to the relevant queues

### Troubleshooting problem nextflow runs:

 There are several reasons the RNAfusions pipeline might fail including bugs in the pipeline; issues with LSF; or misconfiguration.  In most cases (especially when you suspect a farm/ LSF failure), simply re-submitting the pipeline with

```bash
cd <your_project_dir>
bsub < commands/run_rna_fusions.sh
```

will trigger the nextflow `-resume` directive and the pipeline will pick up where it left off.

It is often worth taking a glance at the pipeline logs (<YOUR\_PROJECT\_DIR>/analysis/logs/rna\_fusions\_%J.o) to follow and see what's going on, especially if things have failed/

When jobs fail, nextflow will provide the path to the directory a failed job was run in. I'd recommend inspecting the files in here with `ls -la` and printing some of the log files for the job with

```bash
cat .command.err
cat .command.out
cat .command.sh

```

> [!IMPORTANT]
> Multiple runs
>
> Nextflow is able to keep track of past runs by creating a .nextflow directory in the current location and stores intermediate files in a work. If you want to run the same pipeline but on different cohorts (e.g. hidradenomas and hidradenocarcionmas) in parallel, please ensure that you launch each instance of the pipeline in a seperate directory - otherwise nextflow can't keep track of what is going on an report errors about "nextflow lock files "
