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
- `bam_path`: glob matching a set of indexed BAMs **and** their `.bai` index files, e.g. `"/path/to/bams/**bam{,.bai}"`. Each BAM is unwound back to paired-end reads with `samtools` before STAR-Fusion. The patient id (PRID) is derived directly from the BAM filename, taking the prefix before the first dot (`PD1001.sample.dupmarked.bam` -> `PD1001`), so `sample_metadata` is not required in this mode.

    The glob must match **exactly two files per sample** — BAMs are paired by `Channel.fromFilePairs(..., size: 2)`, which silently drops any sample matching one file or three or more. In the Dermatlas layout each sample lives in its own subdirectory alongside `.bam.bas` and `.bam.met.gz` files, so `**` is needed to descend into those subdirectories and the `{,.bai}` brace is needed to exclude the other siblings. A looser glob such as `"/path/to/bams/*.bam*"` matches nothing usable and produces a run that succeeds with no output.
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

The recommended way to launch this pipeline is using a wrapper script (e.g. `bsub < my_wrapper.sh`) that submits nextflow as a job and records the version (**e.g.** `-r 0.4.0`)  and the `.config` parameter file supplied for a run.

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
-r 0.4.0 \
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

## Projectify integration

In production this pipeline is launched from a Dermatlas *projectify directory* using the
wrapper and config in [`assets/`](assets/). Those two files are copied into the project's
`commands/` directory and take every project-specific location from the project's
`source_me.sh`, so the pipeline stays agnostic about the directory layout it runs in.

Submit from the project directory — `cd <project_dir> && bsub ... < commands/run_rna_fusions.sh` —
so that the job starts there and the wrapper finds `./source_me.sh`. It cannot locate the project
from `$BASH_SOURCE`, because `bsub <` spools the script from stdin.

### Reporting opt-ins

Two explicit toggles decide whether a run reports anywhere. They are defined and exported in
the **OPT-IN REPORTING** section of `assets/run_rna_fusions.sh` (never by `source_me.sh`),
default `"true"`, and are read both by the wrapper (to validate the environment before
launch) and by the pipeline's `onComplete` handler (to decide whether to make the calls):

| Toggle | `"true"` means |
| --- | --- |
| `DERMATLAS_WEBSITE_LOGGING` | record the run in the Dermatlas website analysis log, via the `dermatlas-http cohort analysis-log` CLI (>= 0.6.1; found on `PATH`, else `module load dermatlas-http`) |
| `DERMATLAS_SLACK_NOTIFICATIONS` | post a Slack message on completion (success or failure) |

Git-clone users running custom `subcohorts` typically set both to `"false"` — no website
cohort, sample-list version or Slack webhook is then needed. When a toggle is unset (e.g.
`nextflow run` invoked directly, tests, CI) the pipeline treats it as opted out. Stub runs
(`-stub-run`, or `--is_stub`) never contact the website or Slack regardless of the toggles.

### Environment variables

The single source of truth for the environment contract is the **MANUAL ENVIRONMENT
OVERRIDES** section of [`assets/run_rna_fusions.sh`](assets/run_rna_fusions.sh): one
commented-out `export` per variable, grouped by class, each with an example value and a
note on what it feeds. In short:

- **Pipeline-essential** — always required: project locations, study/project ids, the
  subcohort sample lists.
- **Website-essential** — required only when `DERMATLAS_WEBSITE_LOGGING="true"`.
- **Slack-essential** — required only when `DERMATLAS_SLACK_NOTIFICATIONS="true"`.

The wrapper validates each class before launching nextflow, because an unset variable is
*not* a config error to Nextflow — it is silently substituted with the literal `[:]`.
Reporting variables never appear in the Nextflow configs; the completion handler reads
them from the environment.

Deliberately **not** taken from `source_me.sh`, because they belong to the pipeline rather
than to the project: the opt-in toggles, `ctat_lib`, the pipeline revision, the LSF job
group, and the subcohort names.

### Run artifacts

The wrapper owns run identity: one exported `RUN_ID` names the Nextflow log
(`logs/nextflow-<RUN_ID>.log`), execution trace (`traces/execution_trace-<RUN_ID>.txt`)
and execution report (`pipeline_info/execution_report-<RUN_ID>.html`), and is the run
reference in Slack messages. When `DERMATLAS_WEBSITE_LOGGING="true"`, the log and trace
are attached to the analysis-log record. Direct `nextflow run` invocations fall back to
timestamp-named artifacts in the default locations.

The mechanics — path ownership, fallbacks, and the `dermatlas-http` contract — are
documented in [`REPORTING_INTEGRATION_GUIDE.md`](REPORTING_INTEGRATION_GUIDE.md).

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

## Cutting a release

Cutting a new release requires a new semantic version tag, a changelog entry and
a commit of the updated version in every file that records it. 

### One-off setup, per clone

Releases go through `git hf` (HubFlow). If it is not on your `PATH`, `module load git`.
In a fresh clone, enable it once:

```bash
git hf init   # writes this clone's hubflow branch/prefix config; the defaults are correct
```

That is the only setup required.

### Steps

1. `git hf release start <version>`
2. `./.update-version.sh <version>` — sets the semantic version in every file that
   records it (`assets/run_rna_fusions.sh`, `docs/source/conf.py`, `nextflow.config`).
   Run `./.update-version.sh --help` for details. Commit the changes.
3. Update `CHANGELOG.md` and commit it.
4. `git hf release finish <version>`

## Asset release bundles

`assets/` is published to GitHub Releases as `projectify_asset_bundle.tar.gz` (plus a
`.sha256` of it) by `.github/workflows/publish-assets.yml`, so `dermanager projectify` can
fetch the files straight from the release CDN - no API call, no token, no rate limit:

```
https://github.com/team113sanger/dermatlas_rnafusions_nf/releases/download/<ref>/projectify_asset_bundle.tar.gz
```

| `<ref>` | Bundle contents | Updated |
| --- | --- | --- |
| `X.Y.Z` | `assets/` at that release tag | once, then immutable |
| `main-latest` | `assets/` at the head of `main`, i.e. the latest released state | every push to `main` |
| `develop-latest` | `assets/` at the head of `develop` | every push to `develop` |

The two `-latest` refs are fixed tags on pre-releases. Each push replaces the bundle attached
to the tag, so the download URL never changes and always serves that branch's current assets.

The tag is an **address for the bundle, not a pointer to the code it was built from**: it is
created once and stays where it is, while the assets underneath it are replaced. Fetch these
channels by URL (or `gh release download <ref>`), and read the source commit from the release
notes. Do not use `main-latest` / `develop-latest` as a git revision - `nextflow run -r`,
`git checkout`, or the release page's "Source code" links resolve them to the commit the tag
was created at, not to the head of the branch. Use `X.Y.Z` tags for that.

`releases/latest/download/...` is deliberately not used - it resolves only to the newest
non-pre-release, so it cannot address the rolling channels.

This repository is GitHub-primary. To publish a bundle for a ref that predates the workflow,
run it by hand from the GitHub Actions tab (*Publish projectify asset bundle* -> *Run
workflow*) with `ref` set to the tag or branch to build from.
