process FILTER_AND_MERGE_SAMPLES {
    container "gitlab-registry.internal.sanger.ac.uk/dermatlas/analysis-methods/dermatlas-starfusion:0.5.0"
    publishDir path: "${params.outdir}", 
               mode: "${params.publish_dir_mode}",
               overwrite: "true"
    input:
        tuple val(meta), path(STAR_outputs, stageAs: '?/*')
        tuple val(meta_Fins), path(FusionInspector_outputs, stageAs: '?/*/*')
        path(input_samples)

    output: 
        tuple val(meta), path("*_merged_star-fusion.finspector.abridged.annotated.coding_effect.tsv"), emit: merged_starf
    
    script:
    """
    # Recreate expected directory structure for R script
    
    Rscript /opt/repo/scripts/star_fusion_results_merge_from_list.R \
    --study_id "${meta.study_id}" \
    --input_samples $input_samples \
    --project_dir . \
    --outdir .
    """
    stub: 
    """
    echo stub > "${meta.study_id}_merged_star-fusion.finspector.abridged.annotated.coding_effect.tsv"
    """

}

process SUMMARY_PLOTS_AND_TABLES {
    container "gitlab-registry.internal.sanger.ac.uk/dermatlas/analysis-methods/dermatlas-starfusion:0.5.0"
    publishDir path: "${params.outdir}", 
               mode: "${params.publish_dir_mode}",
               overwrite: "true"
    input:
        tuple val(meta), path(table)
    
    output: 
        tuple val(meta), path("*.pdf"), emit: plots
        tuple val(meta), path("*.tsv"), emit: tables
    
    script:
        """
        Rscript /opt/repo/scripts/cohort_fusion_plotter_and_filter.R \
        --study_id "${meta.study_id}" \
        --table $table \
        --outdir .
        """
    stub: 
        """
        echo stub > ${meta.study_id}_cohort_summary_fusions_found.pdf
        echo stub > ${meta.study_id}_Combined_summary_ftypes_per_tot_fusfound_FILTERED.pdf
        echo stub > ${meta.study_id}_Combined_summary_ftypes_per_tot_fusfound_unfilter.pdf
        echo stub > ${meta.study_id}_FFPM_summary_by_ftype_persample.pdf
        echo stub > ${meta.study_id}_fustype_summary_persample_FILTERED.pdf
        echo stub > ${meta.study_id}_fustype_summary_persample.pdf
        echo stub > ${meta.study_id}_summary_fusfound_nsamples_noftype_FILTERED.pdf
        echo stub > ${meta.study_id}_summary_fusfound_nsamples_noftype_unfilter.pdf
        echo stub > ${meta.study_id}_summary_prop_ftypes_per_tot_fusfound_FILTERED.pdf
        echo stub > ${meta.study_id}_summary_prop_ftypes_per_tot_fusfound_unfilter.pdf
        echo stub > ${meta.study_id}_summary_fusfound_nsamples_noftype.pdf
        echo stub > ${meta.study_id}_table.FILTERED.tsv
        """
}