process BAM_TO_FASTQ {
    container "quay.io/biocontainers/samtools:1.19.2--h50ea8bc_0"

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("${meta.patient_id}_R1.fastq.gz"), path("${meta.patient_id}_R2.fastq.gz"), emit: reads

    script:
    """
    # Collate (group reads by name) before splitting so mates stay paired,
    # then stream the unwound reads out as gzipped paired-end FASTQs.
    samtools collate -@ ${task.cpus} -u -O ${bam} collate_${meta.patient_id} | \\
    samtools fastq -@ ${task.cpus} \\
        -1 ${meta.patient_id}_R1.fastq.gz \\
        -2 ${meta.patient_id}_R2.fastq.gz \\
        -0 /dev/null \\
        -s /dev/null \\
        -n
    """

    stub:
    """
    echo stub | gzip > ${meta.patient_id}_R1.fastq.gz
    echo stub | gzip > ${meta.patient_id}_R2.fastq.gz
    """
}
