#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { STAR_FUSION } from "./modules/star_fusion.nf"
include { BAM_TO_FASTQ } from "./modules/bam_to_fastq.nf"
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

    // Validate that exactly one input mode is configured.
    if (params.bam_path && params.fastq_path) {
        error "ERROR: provide either params.bam_path or params.fastq_path, not both."
    }
    if (!params.bam_path && !params.fastq_path) {
        error "ERROR: one of params.bam_path (indexed BAMs) or params.fastq_path (paired FASTQs) must be set."
    }

    ctat_genome_lib = file(params.ctat_lib, checkIfExists: true)

    // Optional sample-universe filter. Without it, every file matched by the input
    // glob is processed, so a stray BAM left in the input directory becomes a
    // sample. With it, only files whose sample id appears in the universe TSV are
    // processed - the TSV's `sample` column is matched against the id the pipeline
    // derives per sample (the BAM filename prefix, or sample_supplier_name in FASTQ
    // mode). Membership is all that matters here; the decision columns the TSV also
    // carries are not read. Applied before BAM_TO_FASTQ and STAR_FUSION, so an
    // excluded file costs no compute.
    def sample_universe = params.all_samples
        ? (file(params.sample_universe, checkIfExists: true)
            .splitCsv(sep: "\t", header: true)
            .collect { row -> row.sample }
            .findAll { it } as Set)
        : null

    if (sample_universe != null) {
        // Empty means the file has no data rows, or - the easy mistake - no `sample`
        // column, in which case every lookup silently returned null.
        if (sample_universe.isEmpty()) {
            error "ERROR: no sample ids read from ${params.sample_universe}. " +
                  "Check the file has a header with a 'sample' column and at least one row."
        }
        log.info("Sample universe: ${sample_universe.size()} sample(s) from ${params.sample_universe}")
    }

    def in_universe = { meta -> sample_universe == null || sample_universe.contains(meta.patient_id) }

    if (params.bam_path) {
        // BAM input mode: accept indexed BAMs and derive the patient_id from the
        // filename, taking the prefix before the first dot so trailing tags are
        // dropped (e.g. PD1001.sample.dupmarked.bam -> PD1001). The glob must match
        // the BAM and its .bai index and nothing else, because size: 2 silently
        // drops any key that does not match exactly two files. Use
        // "/path/to/bams/**bam{,.bai}": ** descends into per-sample subdirectories
        // and the brace excludes sibling .bam.bas / .bam.met.gz files.
        bams_ch = Channel.fromFilePairs(
                params.bam_path,
                size: 2,
                flat: true
            ) { file -> file.name.tokenize('.').first() }
            .map { patient_id, bam, bai -> tuple(["patient_id": patient_id], bam, bai) }

        // Unwind each BAM back to paired-end reads with samtools. Filtering first
        // keeps excluded BAMs out of BAM_TO_FASTQ entirely.
        combined_ch = BAM_TO_FASTQ(
            bams_ch.filter { meta, bam, bai -> in_universe(meta) }
        ).reads
    }
    else {
        // FASTQ input mode: match paired FASTQs by Sanger id and look up the
        // patient_id (PRID) from the sample metadata.
        reads_ch = Channel.fromFilePairs(params.fastq_path, flat: true)
        .map{ meta,read1,read2 -> tuple(["sanger_id": meta], read1, read2)}

        metadata_ch = Channel.fromPath(params.sample_metadata)
            .splitCsv(sep: "\t", header: true)
            .map { row -> tuple(["sanger_id": row.sample], ["patient_id": row.sample_supplier_name])}

        // The patient_id is only known after the metadata join, so the universe
        // filter is applied to the joined channel.
        combined_ch = reads_ch
            .join(metadata_ch)
            .map { sample_id, read1, read2, patient_id ->
               tuple(sample_id + patient_id, read1, read2)
            }
            .filter { meta, read1, read2 -> in_universe(meta) }
    }

    // Warn about samples that will be processed but are absent from every
    // subcohort sample_list, and so dropped from all merged outputs. This is
    // especially relevant in BAM mode, where the patient_id is derived from the
    // filename and a naming mismatch would otherwise fail silently.
    cohort_id_set = params.subcohorts.collectMany { subcohort_name, config ->
        file(config.sample_list, checkIfExists: true).readLines()
            .collect { it.trim().split('\t')[0].trim() }
            .findAll { it }
    } as Set

    combined_ch
        .map { meta, read1, read2 -> meta.patient_id }
        .collect()
        .subscribe { processed_ids ->
            def dropped = processed_ids.unique().findAll { !cohort_id_set.contains(it) }.sort()
            if (dropped) {
                log.warn(
                    "${dropped.size()} sample(s) will be processed but are not listed in any subcohort " +
                    "sample_list, so they will be dropped from all merged outputs: ${dropped.join(', ')}"
                )
            }
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
    // Runs on both success and failure, after all processes have finished.
    // All reporting (Slack + analysis-log) is handled in one reusable call.
    Utils.reportRun(workflow, params)
}