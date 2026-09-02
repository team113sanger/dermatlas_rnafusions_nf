# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Keywords

As of version 0.4.5 the following *keywords* are used at the start of each
changelog entry to indicate the impact of the change:

- **REPRODUCIBILITY** - a change to the pipeline's scientific processing that
  may cause the same input data to produce different scientific outputs or
  results, including changes to algorithms, tolerances, randomisation,
  scientific functionality, or output formats.
- **ROBUSTNESS** - a fix or improvement to the pipeline's scientific
  functionality that improves correctness, reliability, or the range of inputs
  that can be processed, without intentionally changing the scientific results
  of an equivalent successful analysis.
- **INTEGRATION** - a change to how the pipeline integrates with other systems
  or infrastructure, without changing its scientific processing or results.


## [Unreleased]
### Changed
- **INTEGRATION** - `STAR_FUSION` removes FusionInspector's `fi_workdir` and `chckpts_dir`
  before its outputs are collected. The `fusion_inspector` output glob matched both, so they
  were published into `results/` alongside the finspector tables; they are intermediate
  working state, not results. Also frees the space they took in the work directory. A failed
  STAR-Fusion leaves both in place for debugging.


## [0.4.9] - 2026-09-01
### Added
- **INTEGRATION** - `DERMATLAS_CLEANUP_WORK_DIR` opts out of the work-directory cleanup that
  `run_rna_fusions.sh` runs after a successful pipeline. Optional; unset means cleanup.
- **INTEGRATION** - `run_rna_fusions.sh` now leaves three artefacts in the pipeline directory
  so that a separate clean-up script can tell a live run from a finished one, including one started
  by another user and without LSF: `.lock` (an exclusive `flock` is held on it for the life of
  the run; the file is created once and never removed) plus `.completed_successfully` /
  `.completed_with_error`, cleared at launch and one written at exit. The filename is the
  state; the contents are an audit trail. See "Reclaiming disk space" in the README.

### Changed
- **INTEGRATION** - a `bkill` during `nextflow run` no longer deletes that run's work directory,
  whatever `DERMATLAS_CLEANUP_WORK_DIR` is set to. A killed run is now a failed run, and cleanup
  only ever happens after a success, so the toggle is not consulted at all. Previously the
  INT/TERM/HUP traps were dropped at the handover to `nextflow run` and never reinstated, so
  an LSF kill reached the EXIT trap with `$?` of 0 - bash runs the EXIT trap for an untrapped
  fatal signal, and `$?` is then the last *completed* command's status - and the run was
  treated as successful.
- **INTEGRATION** - The wrapper's three toggles can now be set from the environment, most specific first:
  a shell export beats `source_me.sh`, which beats the default in **OPT-IN REPORTING**.
  `DERMATLAS_WEBSITE_LOGGING` and `DERMATLAS_SLACK_NOTIFICATIONS` were previously
  ignored if present in the environment. All three accept `true/false`, `yes/no`,
  `on/off`, `1/0` in any case; an unrecognised value now fails the launch.
- **INTEGRATION** - two concurrent runs of the same cohort are now prevented rather than
  silently corrupting each other. They shared one `${PIPELINE_DIR}/work`, and the first to
  finish deleted it under the second; the second submission now fails immediately with exit
  75, naming the run that holds the directory.

## [0.4.8] - 2026-09-01
### Changed
- **INTEGRATION** - The default branch has been renamed from `master` to `main`. `publish-assets.yml` now
  triggers on pushes to `main` and publishes the rolling channel as `main-latest`; its
  `workflow_dispatch` default ref is `main` too.


## [0.4.7] - 2026-08-31
### Changed
- **INTEGRATION** - `run_rna_fusions.sh` now truncates the cohort slug to 40 characters when
  creating the Nextflow RUN_ID. For similar cohort slugs this reduces the loss
  of uniqueness.
### Fixed
- **INTEGRATION** - `git hf release finish` no longer fails on `! [rejected] develop-latest (already
  exists)`. `publish-assets.yml` force-moved the rolling `master-latest` /
  `develop-latest` tags on every push, and hubflow's `release finish` ends with
  `git push --tags`, which pushes every local tag and is rejected by any that has moved
  on the remote - aborting the release *after* master, develop and the version tag had
  been pushed and leaving `release/<version>` stranded. The rolling tags are now created
  once and never moved; only the bundle attached to them is replaced, and the release
  notes carry the commit each bundle was built from. Download URLs are addressed by tag
  name, so consumers are unaffected.
  - The README's previous per-clone workaround was ineffective and has been corrected.


## [0.4.6] - 2026-08-31
### Added
- **INTEGRATION** - `run_rna_fusions.sh` now reports failures that happen *before* `nextflow run` starts.
  An exit trap covers the whole setup phase - a missing environment variable, an
  unwritable directory, a failed `module load`, a failed `nextflow pull`, or an LSF kill
  (`bkill`, run/memory limit) - and re-emits the original exit status. Previously only
  the pipeline's own `onComplete` handler reported, so a job that died during setup
  failed silently; in a batch of submissions that is easy to miss.

### Fixed
- **ROBUSTNESS** - `nextflow pull` and `nextflow run` no longer write to the same log file. They shared
  `NXF_LOG_FILE`, so Nextflow rotated one to `nextflow-<RUN_ID>.log.1`; the pull now
  gets its own `nextflow-pull-<RUN_ID>.log`. The exported `NXF_LOG_FILE` still names the
  run's log, which is the one reported on completion.
- **INTEGRATION** - Run ids (and so log, trace and report filenames) no longer carry a stray trailing
  hyphen after the cohort - `..._m25-myofribroma-_20260831T161209` became
  `..._m25-myofribroma_20260831T161209`.


## [0.4.5] - 2026-08-31
### Added
- **INTEGRATION** - Explicit reporting opt-ins in `run_rna_fusions.sh`: `DERMATLAS_WEBSITE_LOGGING` and
  `DERMATLAS_SLACK_NOTIFICATIONS` (`"true"`/`"false"`). Environment checks are classed
  accordingly - opted-out runs need no cohort slug, sample-list version, API endpoint or
  Slack webhook.
- **INTEGRATION** - `run_rna_fusions.sh` now supports standalone (git-clone) execution alongside managed
  projectify runs: a usage guide and table of contents at the top, a `MANUAL ENVIRONMENT
  OVERRIDES` reference block documenting every variable, and a `SOURCE_ME="none"` mode
  for running without a `source_me.sh`.
- **INTEGRATION** - The Nextflow log, execution trace and execution report are harmonised: one `RUN_ID`
  names all three (`nextflow-<RUN_ID>.log`, `execution_trace-<RUN_ID>.txt`,
  `execution_report-<RUN_ID>.html`) and is the run reference in Slack messages.
- **INTEGRATION** - Slack messages carry the sample-list version; failure messages name the Nextflow log.

### Changed
- **INTEGRATION** - **Breaking:** run reporting is opt-in via the toggles above; exporting
  `SLACK_WEBHOOK_URL` alone no longer triggers Slack messages.
- **INTEGRATION** - **Breaking:** website logging goes through the `dermatlas-http` CLI (>= 0.6.1) against
  the `SELF_DESCRIBING_API` endpoint; `ANALYSIS_LOG_API_URL` is dropped. The Nextflow
  log and execution trace are attached to the analysis-log record. Reporting failures
  warn and never fail the run.
- **INTEGRATION** - On-completion reporting variables are decoupled from the workflow's: `cohort_slug`,
  `sample_list_version` and `slack_webhook_url` are gone from the configs (the
  completion handler reads them from the environment), leaving the config files with
  workflow inputs only.

### Fixed
- **INTEGRATION** - Stub runs (`-stub-run`) never contact the website or Slack, regardless of opt-in.
- **INTEGRATION** - `run_rna_fusions.sh` honours a `SOURCE_ME` override, and its `truncate` helper no
  longer shadows the coreutils binary.

## [0.4.4] - Skipped
Skipped to 0.4.5 to signify an integration focused release, with no new features or fixes in the pipeline itself.

## [0.4.3] - Skipped
Skipped to 0.4.5 to signify an integration focused release, with no new features or fixes in the pipeline itself.

## [0.4.2] - Skipped
Skipped to 0.4.5 to signify an integration focused release, with no new features or fixes in the pipeline itself.


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