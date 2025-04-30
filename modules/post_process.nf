process FILTER_AND_MERGE_SAMPLES {
    inputs:
    tupe val(meta), path(STAR_outputs)
    tuple val(meta), path(FusionInspector)
    
    script:
    """
    """
}