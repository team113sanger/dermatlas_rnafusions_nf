
#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { STAR_FUSION } from "./modules/star_fusion.nf"
workflow {
    
    ctat_genome_lib = file(params.ctat_lib)
    
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

    STAR_FUSION.out.fusion_summary
    .map { meta, result_file -> 
        // Read the content of the result file
        def content = result_file.text
        // Add sample_id as first column to each line
        def modified_content = content.readLines().collect { line ->
            "${meta.patient_id}\t${line}"
        }.join("\n")
        return modified_content
    }
    .collectFile(name: 'collated_results.tsv', keepHeader: true newLine: true)

}