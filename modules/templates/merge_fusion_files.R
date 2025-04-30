library(tidyverse)
library(fs)
library(data.table)

annotated_files <- fs::dir_ls("/home/ubuntu/projects/dermatlas_rnafusions_nf/.nf-test/tests/a7387b3b0ff7ee0c63e079710b03591c/work/09/e747c6efe59da623705259297f2d7b", recurse = TRUE, 
          glob = "*finspector.FusionInspector.fusions.abridged.tsv.annotated.coding_effect")



col_ids <- c("#FusionName","JunctionReadCount","SpanningFragCount","est_J","est_S","LeftGene","LeftLocalBreakpoint","LeftBreakpoint","RightGene","RightLocalBreakpoint","RightBreakpoint",
                            "SpliceType","LargeAnchorSupport", "NumCounterFusionLeft","NumCounterFusionRight","FAR_left","FAR_right","TrinGG_Fusion","LeftBreakDinuc","LeftBreakEntropy","RightBreakDinuc","RightBreakEntropy", 
                            "FFPM","microh_brkpt_dist","num_microh_near_brkpt\r","annots","CDS_LEFT_ID","CDS_LEFT_RANGE","CDS_RIGHT_ID","CDS_RIGHT_RANGE","PROT_FUSION_TYPE", "FUSION_MODEL","FUSION_CDS","FUSION_TRANSL","PFAM_LEFT","PFAM_RIGHT")
map(annotated_files, ~fread(.x,
  sep = "\t", 
  header = TRUE, 
  quote = "", 
  stringsAsFactors = FALSE,
  check.names = TRUE,
  col.names = col_ids) |> 
  as_tibble()) |>
  list_rbind(names_to = "sample") |> 
  mutate(sample = str_remove(basename(sample), ".*\\/")) |> 
  pull(sample)