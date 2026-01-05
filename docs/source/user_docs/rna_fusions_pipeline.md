
# Nextflow: RNA fusions pipeline

RNA Fusion calling and post-processing for DERMATLAS can be run mostly with a two nextflow pipelines in a largely "set-and-forget" manner.This document contains an overview of how to configure and run these pipelines. A more detailed explanation of the pipeline inputs and requirements for running can be found within the dermatlas\_rna\_fusions.nf project [README](https://gitlab.internal.sanger.ac.uk/DERMATLAS/analysis-methods/dermatlas_rnafusions_nf/-/blob/develop/README.md?ref_type=heads). A more detailed explanation of how to run StarFusion manually and interpret its key results can be found here [DERMATLAS - Information about the STAR-Fusion version and references used for DERMATLAS analysis](/spaces/CAS/pages/68912708/DERMATLAS+-+Information+about+the+STAR-Fusion+version+and+references+used+for+DERMATLAS+analysis)

## Workflow Overview:

**1) Staging raw reads** 
**2) Generating the cohort config file** 
**3) Running the pipeline**

## Workflow Steps:

First, we need to download the raw read data that we will use for the analysis. We will do this using HGIs irods-to-lustre tool:  a pipeline which can stage merge and unwind aligned seqeuncing data from irods. This workflow assumes you have setup your project using projectify and [Dermatlas analysis setup (v1.0.0](/spaces/CAS/pages/156434559/Dermatlas+analysis+setup+v1.0.0)). If this is the case should have an RNA project directory that looks something like this:

```bash
.
├── analysis
├── commands
├── fastq
├── logs
├── metadata
├── resources -> /lustre/scratch127/casm/projects/dermatlas/resources
├── scripts
└── source_me.sh
```

If you follow along the steps detailed in [Dermatlas analysis setup (v1.0.0)#StagingFastqs(RNA)](/spaces/CAS/pages/156434559/Dermatlas+analysis+setup+v1.0.0#Dermatlasanalysissetup(v1.0.0)-StagingFastqs(RNA))  then this should poplulate your fastq directory with paired end fastq data with names indicating each sample's Sanger ID. For example:

```bash
├── 7348STDY13944490_1.fastq.gz
├── 7348STDY13944490_2.fastq.gz
├── 7348STDY13944490.fastq.gz
├── 7348STDY13944491_1.fastq.gz
├── 7348STDY13944491_2.fastq.gz
├── 7348STDY13944491.fastq.gz
├── 7348STDY13944492_1.fastq.gz
├── 7348STDY13944492_2.fastq.gz
```

The staging pipeline will have also populated several files within metadata . The key one for our purposes is `metadata/samples_noduplicates.csv`   
which contains the mappings of Sanger sample IDs to Dermatlas PDIDs. For example

7348STDY13944490 → PR62424a

Once your fastq data is downloaded via irods-to-lustre, please ensure you cleanup the **crams,** **merged crams** and nextflow **work** directories created by the staging pipeline as these files are often large and won't be of any use for work downstream.

```bash
cd $PROJECT_DIR
rm -rf merged_crams
rm -rf crams
rm -rf work
```

Now, we can proceed with generating a configuration file for the RNA fusions pipeline run. This config file by default fetches a sample list created by dermatlas RNA ingestion. 

**${STUDY}-analysed\_one\_samp\_ppat\_sampnames.tsv** which contains QC passing samples (one per patient). Variable such as ${PROJECT\_DIR} and ${STUDY} are stored within the project **source\_me.sh** file and interpreted by nextflow at runtime.You can modify the set of samples that are analysed by the pipeline by modifying this list

**Example config file:**

```json
params {
    fastq_path = "${PROJECT_DIR}/fastq/**_{1,2}.fastq.gz"
    sample_metadata = "${METADATA_DIR}/samples_noduplicates.tsv"
    outdir = "${ANALYSIS_DIR}/star-fusion"
    sample_list = "/lustre/scratch127/casm/projects/dermatlas/base_dir/biosample_manifests/${STUDY}-analysed_one_samp_ppat_sampnames.tsv"
    ctat_lib = "/lustre/scratch125/casm/teams/team113/resources/references/dermatlas/star_fusion/GRCh38_gencode_v37_CTAT_lib_Mar012021.plug-n-play/ctat_genome_lib_build_dir"
    study_id = "${STUDY}"
}

```

**Launching the nextflow pipeline**

Once you have your inputs you can prepare to launch the pipeline by modifying and saving this wrapper script in your project commands directory. You will need to update the path to your config file and your desired log file locations. 

In this script the "`-r"`  option specifies which version of the pipeline you'd like to run. Normally you should select the latest version (currently **0.2.2**)

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


source source_me.sh
CONFIG="${PROJECT_DIR}/commands/rna_fusion.config"

# Load module dependencies
module load nextflow-23.10.0
module load /software/modules/ISG/singularity/3.11.4

nextflow pull "https://github.com/team113sanger/dermatlas_rnafusions_nf"

nextflow run "https://github.com/team113sanger/dermatlas_rnafusions_nf" \
-resume \
-c "${CONFIG}" \
-r 0.2.2 \
-profile farm22
```

If you called the script `run_rna_fusions.sh` then you'll be able to submit 

```bash
bsub < run_rna_fusions.sh
```

The bsub magic at the start of the wrapper script will send a nextflow "master job", which looks after all other jobs to the oversubscribed queue (where it can live in peace running for a long period without fear of termination). Nextflow will shortly start submitting jobs on your behalf to the relevant queues

### Troubleshooting problem nextflow runs:

 There are several reasons the RNAfusions pipeline might fail including bugs in the pipeline; issues with LSF; or misconfiguration.  In most cases (especially when you suspect a farm/ LSF failure), simply re-submitting the pipeline with

```bash
bsub < run_rna_fusions.sh
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
