# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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