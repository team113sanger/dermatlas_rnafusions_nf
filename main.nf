
process STAR_FUSION {
    module "star-fusion/1.10.1"
    cpus 16
    memory "60G"
    publishDir path: "${params.outdir}/${meta.patient_id}", 
               mode: "${params.publish_dir_mode}",
               overwrite: "true"

    input:
    tuple val(meta), path(read1), path(read2)
    path(CTAT_GENOME_LIB)

    output:
    tuple val(meta), path("star-fusion.fusion_predictions*.tsv"), emit: star_outputs
    path("FusionInspector-validate/*"), optional: true, emit: fusion_inspector
    script:
    def TEMPDIR = "tmp"
    """
    STAR-Fusion \
    --left_fq $read1 \
    --right_fq $read2 \
    --genome_lib_dir $CTAT_GENOME_LIB \
    -O . \
    --verbose_level 2 \
    --tmpdir $TEMPDIR \
    --CPU $task.cpus \
    --FusionInspector validate \
    --examine_coding_effect \
    --denovo_reconstruct
    """
}

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
}