process STAR_FUSION {
    container "docker.io/trinityctat/starfusion:1.10.1"
    publishDir path: "${params.outdir}", 
               mode: "${params.publish_dir_mode}",
               overwrite: "true"

    input:
    tuple val(meta), path(read1), path(read2)
    path(CTAT_GENOME_LIB)

    output:
    tuple val(meta), path("${meta.patient_id}/star-fusion.fusion_predictions*.tsv"), emit: star_fusion
    tuple val(meta), path("${meta.patient_id}/FusionInspector-validate/*"), optional: true, emit: fusion_inspector

    
    script:
    def TEMPDIR = "tmp"
    """
    mkdir ${meta.patient_id}
    STAR-Fusion \
    --left_fq $read1 \
    --right_fq $read2 \
    --genome_lib_dir $CTAT_GENOME_LIB \
    -O ${meta.patient_id} \
    --verbose_level 2 \
    --tmpdir $TEMPDIR \
    --CPU $task.cpus \
    --FusionInspector validate \
    --examine_coding_effect \
    --denovo_reconstruct
    """
    stub: 
    """
    mkdir -p ${meta.patient_id}/FusionInspector-validate
    echo stub > ${meta.patient_id}/star-fusion.fusion_predictions.abridged.tsv
    echo stub > ${meta.patient_id}/star-fusion.fusion_predictions_example.tsv
    echo stub > ${meta.patient_id}/star-fusion.fusion_predictions.tsv
    if [ "${meta.patient_id}" == "PD1001" ]; then
        echo stub > ${meta.patient_id}/FusionInspector-validate/finspector.FusionInspector.fusions.abridged.tsv.annotated.coding_effect
        echo stub > ${meta.patient_id}/FusionInspector-validate/finspector.spanning_reads.bam.bed,
    fi
    """
}