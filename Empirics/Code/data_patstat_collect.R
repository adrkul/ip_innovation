# data_patstat_collect.R
# Run from project root: Rscript Empirics/Code/data_patstat_collect.R
#
# PURPOSE: Build the IHS-PATSTAT firm linkage and generate batched query strings
#   for the PATSTAT online portal. Run this file to produce the linkage table
#   and to get the SQL-style name lists needed to download raw PATSTAT extracts.
#   Actual download must be done manually through the PATSTAT online portal.
#
# Requires:
#   [IHS_DIR]/WSW2018/sciences-po-wsw-profiles-169.xlsx
#   [DATA_DIR]/output/intmd/IHS_names_correspondence.csv
#   [DATA_DIR]/output/intmd/PATSTAT_names_correspondence.csv
#   [DATA_DIR]/output/final/IHS_to_PATSTAT_all_matched.csv
#
# Produces:
#   [DATA_DIR]/output/intmd/IHS_PATSTAT_who_supply_who.csv
#   Console output: batched query strings for PATSTAT portal queries

rm(list = ls())

library(tidyverse)
library(readxl)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"
IHS_DIR  <- "/Users/adrkul/Library/CloudStorage/Dropbox/IHS_data"

################################################################################
## IHS-PATSTAT Firm Linkage
################################################################################

# IHS WSW supplier-OEM relationship data
master_df <- read_excel(file.path(IHS_DIR, "WSW2018/sciences-po-wsw-profiles-169.xlsx"))

# Clean name crosswalk: IHS raw → standardized name
IHS_names     <- read_csv(file.path(DATA_DIR, "output/intmd/IHS_names_correspondence.csv"),
                          show_col_types = FALSE)
PATSTAT_names <- read_csv(file.path(DATA_DIR, "output/intmd/PATSTAT_names_correspondence.csv"),
                          show_col_types = FALSE) %>%
  mutate(Company_Name_Clean = if_else(
    Company_Name_Clean == "TE CONNECTIVITY CORPORATION",
    "TE CONNECTIVITY",
    Company_Name_Clean
  ))

# Type-1 matches only (highest quality firm-to-PSN links)
matched_PSN <- read_csv(file.path(DATA_DIR, "output/final/IHS_to_PATSTAT_all_matched.csv"),
                        show_col_types = FALSE) %>%
  filter(Match_Type == 1)

# Build wide firm-PSN linkage table (each supplier → up to 2 PATSTAT PSN names)
matched_PSN <- matched_PSN %>%
  left_join(IHS_names, by = c("Company_Name_IHS" = "Company_Name_Clean")) %>%
  rename(Supplier = Company_Name) %>%
  select(Supplier, PSN_matched) %>%
  filter(!is.na(PSN_matched)) %>%
  left_join(PATSTAT_names, by = c("PSN_matched" = "Company_Name_Clean")) %>%
  rename(PSN_name = Company_Name) %>%
  select(Supplier, PSN_name) %>%
  group_by(Supplier) %>%
  mutate(PSN_id = paste0("PSN_name", row_number())) %>%
  ungroup() %>%
  pivot_wider(names_from = PSN_id, values_from = PSN_name)

# Append PSN names to WSW linkage data
master_df <- master_df %>%
  rename(Supplier = SUPPLIER_NAME, Part_full = SUB_SECTOR, Part = MAIN_SECTOR) %>%
  left_join(matched_PSN, by = "Supplier") %>%
  rename(Supplier_PSN_1 = PSN_name1, Supplier_PSN_2 = PSN_name2)

write_csv(master_df,
          file.path(DATA_DIR, "output/intmd/IHS_PATSTAT_who_supply_who.csv"))

################################################################################
## PATSTAT Query String Generation
################################################################################

# Builds batched SQL-style name lists for the PATSTAT online search portal.
# The portal cannot handle more than ~180 names per query due to URL length limits.
# Copy each printed string into PATSTAT's applicant_name WHERE clause.

PSN_names   <- na.omit(c(unique(master_df$Supplier_PSN_1), unique(master_df$Supplier_PSN_2)))
BATCH_SIZE  <- 180
num_batches <- ceiling(length(PSN_names) / BATCH_SIZE)

for (i in seq_len(num_batches)) {
  idx   <- ((i - 1) * BATCH_SIZE + 1):min(i * BATCH_SIZE, length(PSN_names))
  chunk <- sapply(PSN_names[idx], function(x) paste0("'", x, "'"))
  cat(sprintf("\n-- Batch %d of %d --\n", i, num_batches))
  cat(paste(chunk, collapse = ","), "\n")
}

message("data_patstat_collect.R complete. Use query strings above to download PATSTAT extracts.")
