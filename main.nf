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

    if (params.bam_path) {
        // BAM input mode: accept indexed BAMs and derive the patient_id from the
        // filename, taking the prefix before the first dot so trailing tags are
        // dropped (e.g. PD1001.sample.dupmarked.bam -> PD1001). The glob should
        // match both the BAM and its .bai index (e.g. "/path/to/*.bam*").
        bams_ch = Channel.fromFilePairs(
                params.bam_path,
                size: 2,
                flat: true
            ) { file -> file.name.tokenize('.').first() }
            .map { patient_id, bam, bai -> tuple(["patient_id": patient_id], bam, bai) }

        // Unwind each BAM back to paired-end reads with samtools.
        combined_ch = BAM_TO_FASTQ(bams_ch).reads
    }
    else {
        // FASTQ input mode: match paired FASTQs by Sanger id and look up the
        // patient_id (PRID) from the sample metadata.
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