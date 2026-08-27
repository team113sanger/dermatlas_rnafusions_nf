# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] - 2026-08-27
### Added
- `.github/workflows/publish-assets.yml` publishes `assets/` to GitHub Releases as
  `projectify_asset_bundle.tar.gz` (and a `.sha256` of it) on every push to `master` and
  `develop` - as the rolling `master-latest` and `develop-latest` pre-releases - and on
  every `X.Y.Z` tag. `dermanager projectify` fetches assets from those release URLs
  instead of the GitHub API, which needs no token and is not rate limited. See
  "Asset release bundles" in the README.

### Changed
- **Breaking (assets):** `rna_fusions.config` now takes project locations from `source_me.sh`
  (`BAMS_DIR`, `RNA_SAMPLE_LIST_ONE_PER_PATIENT`, `RNA_SAMPLE_LIST_FINAL_DECISION`,
  `SAMPLE_LIST_VERSION_FILE`, `ANALYSIS_LOG_API_URL`) rather than building them from
  `PROJECT_DIR`. Needs a `source_me.sh` exporting the new variables.
- `run_rna_fusions.sh` sources the project's own `./source_me.sh` (checking it exists first)
  and aborts up front, naming the variable, if one it needs is unexported.
- The `farm22` profile no longer sets `PROJECT_DIR`-shaped defaults; `sample_metadata`,
  `cohort_slug`, `analysis_log_api_url`, `sample_list_version` and `analysis_pipeline_slug`
  are declared in the global `params` block instead.

### Fixed
- `bam_path` globbed `bam/` but the directory is `bams`, so it matched nothing and runs
  completed "successfully" with no output.
- `slack_webhook_url = "${SLACK_WEBHOOK_URL}"` in the asset config defeated the
  `System.getenv(...) ?: null` fallback, yielding the truthy string `[:]` when unset.
- The execution report landed in `./results/pipeline_info` relative to the launch directory
  instead of under `outdir`.
- `bam_path` glob advice in the README, `main.nf` and the user docs: the documented `*.bam*`
  form matches nothing usable under `size: 2`.

## [0.4.0] - 2026-06-24
### Added
- BAM input mode: new `bam_path` parameter accepts a glob of indexed BAMs (and their
  `.bai` indexes). A new `BAM_TO_FASTQ` process unwinds each BAM back to paired-end reads
  with `samtools` before STAR-Fusion. The patient id (PRID) is derived from the BAM
  filename (prefix before the first dot), so `sample_metadata` is not required in this mode.
- Run reporting on `workflow.onComplete` via `lib/Utils.groovy` (`Utils.reportRun`). All
  reporting is best-effort and never changes the pipeline's exit status:
  - Optional Slack notifications on success/failure when `slack_webhook_url` is set
    (run reference, pipeline version and duration; on failure also the failed process,
    work directory and Nextflow log path).
  - Optional append of a run record to the versioned-cohort-analysis-log API when
    `analysis_log_api_url` is set, keyed by `cohort_slug` / `analysis_pipeline_slug` with
    `sample_list_version` and pipeline version.
  - `is_stub` parameter to skip all reporting for stub/test runs.


### Changed
- Exactly one input mode must now be set: the pipeline errors immediately if both or neither
  of `fastq_path` / `bam_path` are provided. `fastq_path` no longer has a default value and
  must be set explicitly when using FASTQ input.
- Project home moved to GitHub (`github.com/team113sanger/dermatlas_rnafusions_nf`); manifest
  `homePage` and the example wrapper scripts were updated accordingly.

## [0.3.0] - 2026-04-17
### Added
- Update pipeline structure to allow multiple subcohort post-processing in one via a list structure.
  Nested data structure `subcohorts = [subcohort_name_1: [...], subcohort_name_2: [...]]` where each
  subcohort's attributes are encoded in a map. Each subcohort is merged and plotted independently
  under its own sub-directory of `outdir`.

### Changed
- **Breaking:** `sample_list` is no longer a top-level parameter. It must now be supplied per
  subcohort as `subcohorts.<name>.sample_list`. Existing configs using a top-level `--sample_list`
  will have it silently ignored.
- `study_id` is now validated at workflow start — the pipeline will error out immediately if it
  is not set, rather than producing output files prefixed with `null_`.

### Fixed
- Fix `Invalid method invocation 'call'` closure error when combining subcohort sample lists with
  collected STAR-Fusion outputs. The collected list was being spread into the tuple by `.combine()`;
  it is now wrapped so it is passed as a single element.

## [0.2.4] - 2025-11-06
### Added
- Update `post_process.nf` module to tag `0.6.3`
	
## [0.2.3] - 2025-10-06
### Added
- Add asset files for easy staging of fastq's and running fusions

## [0.2.2] - 2024-07-18
### Fixed 
- Changed plot export directory to correctly publish summaries.

## [0.2.1] - 2024-07-18
### Fixed 
- Resource request for SUMMARY_PLOTS_AND_TABLES step on Farm22.

## [0.2.0] - 2024-07-03
### Added
- End-to-end analysis from fastq to output summary plots.

## [0.1.0]
- Initial release for running star-fusion