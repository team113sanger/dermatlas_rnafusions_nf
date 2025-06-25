#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { STAR_FUSION } from "./modules/star_fusion.nf"
include { FILTER_AND_MERGE_SAMPLES} from "./modules/post_process.nf"
include { SUMMARY_PLOTS_AND_TABLES } from "./modules/post_process.nf"
workflow {
    
    ctat_genome_lib = file(params.ctat_lib, checkIfExists: true)
    sample_list = file(params.sample_list, checkIfExists: true)
    
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

    fusion_ins_ch = STAR_FUSION.out.all_outs
    .map { meta, starf_fusion, finspector ->
        ["sample_id": meta.patient_id, "star_files": starf_fusion, "finspector_files": finspector]
    }
    .collect()
    .map { file_list ->
        tuple(["study_id": params.study_id], file_list)
    }
    fusion_ins_ch.view()
    

    FILTER_AND_MERGE_SAMPLES(
        fusion_ins_ch,
        sample_list
        
    )
    SUMMARY_PLOTS_AND_TABLES(FILTER_AND_MERGE_SAMPLES.out.merged_starf)


}