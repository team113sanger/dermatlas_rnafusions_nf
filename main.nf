#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { STAR_FUSION } from "./modules/star_fusion.nf"
include { FILTER_AND_MERGE_SAMPLES; SUMMARY_PLOTS_AND_TABLES} from "./modules/post_process.nf"

workflow FUSION_ANALYSIS{

    // Validate subcohorts parameter
    if (!params.subcohorts || params.subcohorts.isEmpty()) {
        error "ERROR: params.subcohorts must be defined with at least one subcohort. " +
              "Example: subcohorts = ['cohort_name': [sample_list: '/path/to/samples.tsv']]"
    }

    // Validate study_id — flows into every output filename, so an unset value
    // would silently produce files prefixed with "null_".
    if (!params.study_id) {
        error "ERROR: params.study_id must be set. It is used as a prefix for all merged tables and summary plots."
    }

    // Log subcohorts being processed
    log.info("Processing subcohorts: ${params.subcohorts.keySet().join(', ')}")

    ctat_genome_lib = file(params.ctat_lib, checkIfExists: true)

    reads_ch = Channel.fromFilePairs(params.fastq_path, flat: true)
    .map{ meta,read1,read2 -> tuple(["sanger_id": meta], read1, read2)}

    metadata_ch = Channel.fromPath(params.sample_metadata)
        .splitCsv(sep: "\t", header: true)
        .map { row -> tuple(["sanger_id": row.sample], ["patient_id": row.sample_supplier_name])}

    combined_ch = reads_ch
        .join(metadata_ch)
        .map { sample_id, read1, read2, patient_id ->
           tuple(sample_id + patient_id, read1, read2)
        }

    STAR_FUSION(
        combined_ch,
        ctat_genome_lib
    )

    // Collect all STAR_FUSION outputs once
    star_fusion_outputs = STAR_FUSION.out.star_fusion
        .join(STAR_FUSION.out.fusion_inspector, by: 0, remainder: true)
        .map { meta, starf_fusion, finspector ->
            ["sample_id": meta.patient_id, "star_files": starf_fusion, "finspector_files": finspector]
        }
        .collect()

    // Create channel of subcohorts from params.subcohorts map
    // Each subcohort has: name (key) and sample_list path (value.sample_list)
    subcohorts_ch = Channel.fromList(
        params.subcohorts.collect { subcohort_name, config ->
            tuple(
                ["cohort_id": subcohort_name, "study_id": params.study_id], 
                file(config.sample_list, checkIfExists: true)
            )
        }
    )

    // Combine each subcohort with all star fusion outputs.
    // Wrap the collected list so .combine() treats it as a single tuple element
    // instead of spreading each sample-map as its own element.
    merge_ch = subcohorts_ch
        .combine(star_fusion_outputs.map { samples -> [samples] })
        .map { meta, sample_list, file_list ->
            tuple(meta, file_list, sample_list)
        }

    FILTER_AND_MERGE_SAMPLES(
        merge_ch.map { meta, file_list, sample_list -> tuple(meta, file_list) },
        merge_ch.map { meta, file_list, sample_list -> sample_list }
    )
    SUMMARY_PLOTS_AND_TABLES(FILTER_AND_MERGE_SAMPLES.out.merged_starf)


}

workflow {
    FUSION_ANALYSIS()
}

workflow.onComplete {
    // Runs on both success and failure, but only after all processes have finished
    log.info "Pipeline completed at: $workflow.complete"
    if (workflow.success) {
      log.info "Pipeline finished successfully!"
    } else {
      log.error "Pipeline finished with errors!"
    }

    // Slack notification (if webhook URL is configured and not a stub run)
    def is_stub_run = Utils.parseCLIBool(params.is_stub, false)
    def _slack_url = (params.slack_webhook_url ?: '').toString().trim()
    def _cohort_slug = (params.cohort_slug ?: '').toString().trim()
    def _run_id = "${System.getenv('STUDY') ?: ''}_${System.getenv('PROJECT') ?: ''}_${System.getenv('GENOTYPE') ?: 'rna'}"
    if (_slack_url && !is_stub_run) {
      def is_success = workflow.success
      def _version = workflow.manifest.version

      boolean _sent
      if (is_success) {
        _sent = Utils.sendSlackSuccess(_slack_url, _run_id, _version, workflow.duration, _cohort_slug)
      } else {
        def _nxf_log = System.getenv('NXF_LOG_FILE') ?: ''
        _sent = Utils.sendSlackFailure(_slack_url, _run_id, _version, workflow.duration, workflow.errorReport, _nxf_log, _cohort_slug)
      }

      if (_sent) {
        log.info "Slack notification sent"
      } else {
        log.warn "Slack notification failed (pipeline result is unaffected)"
      }
    }

    // Append a run record to the cohort analysis-log (if configured and not a stub run)
    def _log_url = (params.analysis_log_api_url ?: '').toString().trim()
    if (_log_url && !is_stub_run) {
      def _run_status       = workflow.success ? 'completed' : 'failed'
      def _pipeline_slug    = (params.analysis_pipeline_slug ?: '').toString().trim()
      def _pipeline_version = workflow.manifest?.version

      // sample_list_version is a path to a file whose contents are the version number.
      def _sample_list_ver = null
      if (params.sample_list_version) {
        def _ver_file = new File(params.sample_list_version.toString())
        if (_ver_file.exists()) {
          try {
            _sample_list_ver = _ver_file.text.trim() as Integer
          } catch (NumberFormatException e) {
            log.warn "sample_list_version file '${_ver_file}' does not contain an integer; analysis-log will be skipped"
          }
        } else {
          log.warn "sample_list_version file '${params.sample_list_version}' not found; analysis-log will be skipped"
        }
      }

      if (Utils.reportCohortAnalysisLog(_log_url, _cohort_slug, _pipeline_slug,
              _run_status, _sample_list_ver, _pipeline_version)) {
        log.info "Reported analysis run for cohort '${_cohort_slug}' (${_run_status}) to analysis-log API"
      } else {
        log.warn "Failed to report analysis run for cohort '${_cohort_slug}' to analysis-log API (pipeline result is unaffected)"
      }
    }
}