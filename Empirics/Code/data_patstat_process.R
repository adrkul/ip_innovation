# data_patstat_process.R
# Run from project root: Rscript Empirics/Code/data_patstat_process.R
#
# PURPOSE: Load raw PATSTAT online portal extract CSVs, apply IPC-to-part
#   classification, aggregate to the country × year × firm × part level,
#   and write final cleaned patent datasets for the analysis pipeline.
#
# Requires (run data_patstat_collect.R first to download extracts):
#   [DATA_DIR]/patents/PATSTAT_online/extract_ihs_updated/*.csv
#   [DATA_DIR]/patents/PATSTAT_online/extract_ihs_citations_firm_updated_all/*.csv
#   [DATA_DIR]/patents/PATSTAT_online/extract_ihs_citations_firm_updated/*.csv
#   [DATA_DIR]/patents/PATSTAT_online/extract_inventors_alt/*.csv
#   [DATA_DIR]/patents/PATSTAT_online/extract_OEM/*.csv
#   [DATA_DIR]/patents/PATSTAT_online/extract_inventors_OEM/*.csv
#   [DATA_DIR]/patents/PATSTAT_online/extract_ihs_citations_OEM_updated_application_dated/*.csv
#   [DATA_DIR]/output/intmd/IPC_match_manual.csv
#   [DATA_DIR]/other/country_codes.csv
#   [DATA_DIR]/output/final/VP_Strat_Group_to_PATSTAT.csv
#
# Produces:
#   [DATA_DIR]/output/final/PATSTAT_IHS_parts_updated.csv
#   [DATA_DIR]/output/final/PATSTAT_IHS_parts_citations_updated.csv
#   [DATA_DIR]/output/final/PATSTAT_IHS_inventors_parts_updated.csv
#   [DATA_DIR]/output/final/OEM_patent_data.csv
#   [DATA_DIR]/output/final/OEM_inventor_data.csv
#   [DATA_DIR]/output/final/PATSTAT_bilateral_citations.csv

rm(list = ls())

library(tidyverse)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"

# Helper: read all CSVs (semicolon-delimited) in a directory and stack them
load_patstat_dir <- function(dir_path) {
  filenames <- list.files(dir_path, pattern = "\\.csv$")
  if (length(filenames) == 0) {
    warning("No CSV files found in: ", dir_path)
    return(tibble())
  }
  map_dfr(filenames, function(f) {
    read.csv(file.path(dir_path, f), sep = ";")
  })
}

################################################################################
## IPC to Part Classification + Country Code Lookup
################################################################################

# Manual IPC4-to-Part mapping (corrected from LLM output)
codes_matched <- read_csv(file.path(DATA_DIR, "output/intmd/IPC_match_manual.csv"),
                          show_col_types = FALSE) %>%
  select(IPC_Code_IPC4, Part_Correction) %>%
  rename(Category_2 = Part_Correction, IPC = IPC_Code_IPC4)

# 2-digit ISO country codes (for matching PATSTAT application authority codes)
country_codes_2digit <- read_csv(file.path(DATA_DIR, "other/country_codes.csv"),
                                 show_col_types = FALSE) %>%
  select(Country, `Alpha-3 code`, `Alpha-2 code`) %>%
  rename(country_code_2 = `Alpha-2 code`, country_code = `Alpha-3 code`) %>%
  # Add EP pseudo-country for European Patent Office filings
  bind_rows(tibble(Country = "Europe", country_code = "EPP", country_code_2 = "EP"))

################################################################################
## Supplier Patent Data
################################################################################

# Application-level patent data (IPC class × firm × filing year × country)
supplier_patents_raw <- load_patstat_dir(
  file.path(DATA_DIR, "patents/PATSTAT_online/extract_ihs_updated")
)

# Aggregate to country × year × supplier × part
supplier_patents <- supplier_patents_raw %>%
  mutate(psn_name = toupper(psn_name)) %>%
  left_join(codes_matched, by = c("ipc_class" = "IPC")) %>%
  group_by(appln_auth, filing_year, psn_name, Category_2) %>%
  summarise(appln_count = sum(appln_count), .groups = "drop") %>%
  left_join(country_codes_2digit, by = c("appln_auth" = "country_code_2")) %>%
  rename(Year = filing_year, Part = Category_2, Supplier_PSN = psn_name) %>%
  select(Country, country_code, Year, Supplier_PSN, Part, appln_count) %>%
  filter(!is.na(Country)) %>%  # drop WO patents (cannot be country-attributed)
  filter(!is.na(Year)) %>%
  filter(!is.na(Part))

write_csv(supplier_patents,
          file.path(DATA_DIR, "output/final/PATSTAT_IHS_parts_updated.csv"))

################################################################################
## Supplier Citation Data
################################################################################

# Citations: all citing sources
citations_all_raw <- load_patstat_dir(
  file.path(DATA_DIR, "patents/PATSTAT_online/extract_ihs_citations_firm_updated_all")
)

# Citations: application-dated only (for APP citation variant)
citations_app_raw <- load_patstat_dir(
  file.path(DATA_DIR, "patents/PATSTAT_online/extract_ihs_citations_firm_updated")
)

# Merge sources: all citations + APP-specific citation count
supplier_citations_raw <- citations_all_raw %>%
  left_join(
    citations_app_raw %>% rename(citation_count_APP = citation_count),
    by = c("appln_filing_year", "appln_auth", "cited_firm", "ipc4")
  ) %>%
  mutate(citation_count_APP = if_else(is.na(citation_count_APP), 0,
                                      as.numeric(citation_count_APP)))

# Aggregate to country × year × supplier × part
supplier_citations <- supplier_citations_raw %>%
  mutate(cited_firm = toupper(cited_firm)) %>%
  left_join(codes_matched, by = c("ipc4" = "IPC")) %>%
  group_by(appln_auth, appln_filing_year, cited_firm, Category_2) %>%
  summarise(
    citation_count     = sum(citation_count,     na.rm = TRUE),
    citation_count_APP = sum(citation_count_APP, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(country_codes_2digit, by = c("appln_auth" = "country_code_2")) %>%
  rename(Year = appln_filing_year, Part = Category_2, Supplier_PSN = cited_firm) %>%
  select(Country, country_code, Year, Supplier_PSN, Part,
         citation_count, citation_count_APP) %>%
  filter(!is.na(Country)) %>%
  filter(!is.na(Year)) %>%
  filter(!is.na(Part))

write_csv(supplier_citations,
          file.path(DATA_DIR, "output/final/PATSTAT_IHS_parts_citations_updated.csv"))

################################################################################
## Inventor-Level Supplier Patent Data
################################################################################

supplier_inventors_raw <- load_patstat_dir(
  file.path(DATA_DIR, "patents/PATSTAT_online/extract_inventors_alt")
) %>%
  rename(PSN_names = company)

supplier_inventors <- supplier_inventors_raw %>%
  left_join(codes_matched, by = c("ipc_class" = "IPC")) %>%
  group_by(inventor_code, appln_filing_year, country, PSN_names, Category_2) %>%
  summarise(appln_count = sum(patent_count), .groups = "drop") %>%
  left_join(country_codes_2digit, by = c("country" = "country_code_2")) %>%
  rename(Year = appln_filing_year, Part = Category_2,
         Supplier_PSN = PSN_names, Inventor = inventor_code) %>%
  select(Country, country_code, Year, Supplier_PSN, Inventor, Part, appln_count) %>%
  filter(!is.na(Country)) %>%
  filter(!is.na(Year)) %>%
  filter(!is.na(Part))

write_csv(supplier_inventors,
          file.path(DATA_DIR, "output/final/PATSTAT_IHS_inventors_parts_updated.csv"))

################################################################################
## OEM Patent Data
################################################################################

# OEM name-to-PATSTAT crosswalk
OEMs <- read_csv(file.path(DATA_DIR, "output/final/VP_Strat_Group_to_PATSTAT.csv"),
                 show_col_types = FALSE)

# IPC codes corresponding to final vehicle assembly processes
ASSEMBLY_IPCs <- c("B62D", "B60K", "B60R", "B60W", "B21D", "B23K", "B29C", "B29D")

OEM_patents_raw <- load_patstat_dir(
  file.path(DATA_DIR, "patents/PATSTAT_online/extract_OEM")
)

OEM_patents <- OEM_patents_raw %>%
  mutate(psn_name = toupper(psn_name)) %>%
  left_join(OEMs %>% select(OEM, PATSTAT), by = c("psn_name" = "PATSTAT")) %>%
  left_join(codes_matched, by = c("ipc_class" = "IPC")) %>%
  mutate(Category_2 = if_else(ipc_class %in% ASSEMBLY_IPCs, "Assembly", Category_2)) %>%
  group_by(appln_auth, filing_year, OEM, Category_2) %>%
  summarise(appln_count = sum(appln_count), .groups = "drop") %>%
  left_join(country_codes_2digit, by = c("appln_auth" = "country_code_2")) %>%
  rename(Year = filing_year, Part = Category_2) %>%
  select(OEM, Country, country_code, Year, Part, appln_count) %>%
  filter(!is.na(Country)) %>%
  filter(!is.na(Year)) %>%
  filter(!is.na(Part))

write_csv(OEM_patents,
          file.path(DATA_DIR, "output/final/OEM_patent_data.csv"))

################################################################################
## OEM Inventor-Level Data
################################################################################

OEM_inventors_raw <- load_patstat_dir(
  file.path(DATA_DIR, "patents/PATSTAT_online/extract_inventors_OEM")
)

OEM_inventors <- OEM_inventors_raw %>%
  mutate(company = toupper(trimws(company, which = "right"))) %>%
  left_join(OEMs %>% select(OEM, PATSTAT), by = c("company" = "PATSTAT")) %>%
  left_join(codes_matched, by = c("ipc_class" = "IPC")) %>%
  mutate(Category_2 = if_else(ipc_class %in% ASSEMBLY_IPCs, "Assembly", Category_2)) %>%
  group_by(inventor_code, appln_filing_year, country, OEM, Category_2) %>%
  summarise(appln_count = sum(patent_count), .groups = "drop") %>%
  left_join(country_codes_2digit, by = c("country" = "country_code_2")) %>%
  rename(Year = appln_filing_year, Part = Category_2) %>%
  select(inventor_code, OEM, Country, country_code, Year, Part, appln_count) %>%
  filter(!is.na(Year)) %>%
  filter(!is.na(Part))

write_csv(OEM_inventors,
          file.path(DATA_DIR, "output/final/OEM_inventor_data.csv"))

################################################################################
## Bilateral Citation Data (Supplier Cited by OEM)
################################################################################

bilateral_raw <- load_patstat_dir(
  file.path(DATA_DIR,
            "patents/PATSTAT_online/extract_ihs_citations_OEM_updated_application_dated")
) %>%
  distinct()

bilateral_citations <- bilateral_raw %>%
  mutate(cited_firm  = toupper(cited_firm),
         citing_firm = toupper(citing_firm)) %>%
  left_join(OEMs %>% select(OEM, PATSTAT), by = c("citing_firm" = "PATSTAT")) %>%
  select(-citing_firm) %>%
  rename(citing_firm = OEM) %>%
  left_join(codes_matched, by = c("ipc4" = "IPC")) %>%
  group_by(cited_auth, citing_auth, appln_year, cited_firm, citing_firm, Category_2) %>%
  summarise(citation_count = sum(citation_count, na.rm = TRUE), .groups = "drop") %>%
  left_join(country_codes_2digit, by = c("cited_auth" = "country_code_2")) %>%
  rename(Cited_Country = Country, country_code_d = country_code) %>%
  left_join(country_codes_2digit, by = c("citing_auth" = "country_code_2")) %>%
  rename(Citing_Country = Country, country_code_o = country_code) %>%
  rename(Year = appln_year, Part = Category_2,
         Supplier_PSN = cited_firm, OEM = citing_firm,
         citations = citation_count) %>%
  select(Cited_Country, Citing_Country, country_code_o, country_code_d,
         Year, Supplier_PSN, Part, OEM, citations) %>%
  mutate(
    Citing_Country = if_else(is.na(Citing_Country), "None", Citing_Country),
    Cited_Country  = if_else(is.na(Cited_Country),  "None", Cited_Country)
  ) %>%
  filter(Part != "Other") %>%
  filter(citations > 0)

write_csv(bilateral_citations,
          file.path(DATA_DIR, "output/final/PATSTAT_bilateral_citations.csv"))

message("data_patstat_process.R complete.")
