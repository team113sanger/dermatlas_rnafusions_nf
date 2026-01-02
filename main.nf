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
                ["study_id": subcohort_name],
                file(config.sample_list, checkIfExists: true)
            )
        }
    )

    // Combine each subcohort with all star fusion outputs
    merge_ch = subcohorts_ch
        .combine(star_fusion_outputs)
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