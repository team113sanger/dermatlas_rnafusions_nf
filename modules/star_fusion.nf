process STAR_FUSION {
    publishDir path: "${params.outdir}/${meta.patient_id}", 
               mode: "${params.publish_dir_mode}",
               overwrite: "true"

    input:
    tuple val(meta), path(read1), path(read2)
    path(CTAT_GENOME_LIB)

    output:
    tuple val(meta), path("star-fusion.fusion_predictions*.tsv"), emit: star_outputs
    tuple val(meta), path("FusionInspector-validate/*"), optional: true, emit: fusion_inspector
    tuple val(meta), path("FusionInspector-validate/finspector.FusionInspector.fusions.abridged.tsv.annotated.coding_effect"), optional: true, emit: fusion_summary
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
