# dermatlas_rnafusions_nf

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A522.04.5-23aa62.svg?labelColor=000000)](https://www.nextflow.io/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

## Introduction

dermatlas_rnafusions_nf is a bioinformatics pipeline written in [Nextflow](http://www.nextflow.io) for identifying gene fusions in cohorts of tumors for the Dermatlas project.

## Pipeline summary

In brief, the pipeline takes a set fastq files (or indexed BAMs) from a Dermatlas cohort and
- Matches fastq files to patient metadata (PRIDs), or unwinds indexed BAMs to paired-end reads with samtools (deriving the PRID from the filename)
- Runs STAR-Fusion to identify RNA fusions
- Aggregates the results of STAR-Fusion into a merged table per subcohort
- Generates a report plotting fusion counts per sample and per gene for each subcohort


## Inputs 


### Cohort-dependent variables

Provide **exactly one** input mode, either `fastq_path` or `bam_path`:

- `fastq_path`: path to a top level directory containing a set of paired fastq files(R1 and R2). The pipeline will search for all fastq files within this directory and subdirectories. Requires `sample_metadata` to map Sanger ids to PRIDs.
- `bam_path`: glob matching a set of indexed BAMs **and** their `.bai` index files, e.g. `"/path/to/bams/*.bam*"`. Each BAM is unwound back to paired-end reads with `samtools` before STAR-Fusion. The patient id (PRID) is derived directly from the BAM filename, taking the prefix before the first dot (`PD1001.sample.dupmarked.bam` -> `PD1001`), so `sample_metadata` is not required in this mode.
- `sample_metadata`: path to a metadata file containing sample information (only used with `fastq_path`). The metadata file should be a tab-separated file with the following columns:
    - `sample`: Unique Sanger identifier for each sample
    - `sample_supplier_name`: Dermatlas sample identifier for a tumour (PRID)
- `study_id`: Unique identifier for the study. Used as a prefix on all merged tables and summary plot filenames. **Required.**
- `subcohorts`: A map of one or more subcohorts to post-process from the same set of STAR-Fusion results. Each entry has a subcohort name (used as `cohort_id` and as the output sub-directory under `outdir`) and a `sample_list` path pointing to a TSV of Dermatlas sample identifiers matching `sample_supplier_name` entries. Example:

```groovy
subcohorts = [
    "one_per_patient": [ sample_list: "/path/to/one_per_patient_sampnames.tsv" ],
    "final_decision":  [ sample_list: "/path/to/final_decision_sampnames.tsv" ]
]
```
### Cohort-independent variables

`ctat_lib` : path to a STAR-Fusion Trintity Cancer Transcriptome Analysis Toolkit (CTAT) genome build directory (a required input for STAR-Fusion)

Default reference file values supplied within the `nextflow.config` file can be overided by adding them to a local `.config` file. An example complete params file `tests/testdata/test_params.json` is supplied within this repository for demonstation.

## Usage 

The recommended way to launch this pipeline is using a wrapper script (e.g. `bsub < my_wrapper.sh`) that submits nextflow as a job and records the version (**e.g.** `-r 0.3.0`)  and the `.config` parameter file supplied for a run.

An example wrapper script:
```
#!/bin/bash
#BSUB -q oversubscribed
#BSUB -G team113-grp
#BSUB -R "select[mem>8000] rusage[mem=8000] span[hosts=1]"
#BSUB -M 8000
#BSUB -oo rna_fusions_%J.o
#BSUB -eo rna_fusions_%J.e

CONFIG="/lustre/scratch125/casm/team113da/users/jb63/nf_germline_testing/rna_fusions.config"

# Load module dependencies
module load nextflow-23.10.0
module load /software/modules/ISG/singularity/3.11.4

# Create a nextflow job that will spawn other jobs

nextflow run 'https://github.com/team113sanger/dermatlas_rnafusions_nf' \
-r 0.3.0 \
-c ${CONFIG} \
-profile farm22 
```

The pipeline can configured to run on either Sanger OpenStack secure-lustre instances or the Sanger farm22 HPC by changing the profile speicified:
`-profile secure_lustre` or `-profile farm22`. 

## Pipeline visualisation 
The flowchart below shows both supported input modes. Exactly one is used per run: either paired FASTQs matched to PRIDs via `sample_metadata`, or indexed BAMs that are unwound back to paired reads by `BAM_TO_FASTQ`. A base diagram can be regenerated with nextflow's in-built visualisation features:

```
nextflow run main.nf -preview -with-dag flowchart.mmd -params-file tests/testdata/test_params.json
```

```mermaid
flowchart TB
    subgraph " "
    v0["Channel.fromFilePairs FASTQ pairs"]
    v2["Channel.fromPath sample_metadata"]
    vb["Channel.fromFilePairs indexed BAMs"]
    v7["CTAT_GENOME_LIB"]
    v12["Channel.fromList subcohorts"]
    end
    subgraph "FUSION_ANALYSIS [FUSION_ANALYSIS]"
    vbf(["BAM_TO_FASTQ"])
    v8(["STAR_FUSION"])
    v18(["FILTER_AND_MERGE_SAMPLES"])
    v19(["SUMMARY_PLOTS_AND_TABLES"])
    v1(( ))
    v9(( ))
    end
    subgraph " "
    v20[" "]
    v21[" "]
    end
    v0 --> v1
    v2 --> v1
    v1 --> v8
    vb --> vbf
    vbf --> v8
    v7 --> v8
    v8 --> v9
    v12 --> v9
    v9 --> v18
    v18 --> v19
    v19 --> v21
    v19 --> v20
```

## Testing

This pipeline has been developed with the [nf-test](http://nf-test.com) testing framework. Unit tests and small test data are provided within the pipeline `test` subdirectory. A snapshot has been taken of the outputs of most steps in the pipeline to help detect regressions when editing. You can run all tests on openstack with:

```
nf-test test 
```
and individual tests with:
```
nf-test test tests/main.nf.test
```

For faster testing of the flow of data through the pipeline **without running any of the tools involved**, stubs have been provided to mock the results of each succesful step.
```
nextflow run main.nf \
-params-file tests/testdata/test_params.json \
-c tests/nextflow.config \
--stub-run
```


