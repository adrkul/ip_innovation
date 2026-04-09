# data_patents.R
# Run from project root: Rscript Empirics/Code/data_patents.R
#
# PURPOSE: Construct rolling patent counts and cumulative stocks for suppliers
#   and OEMs from cleaned PATSTAT data. Produces datasets used in the main
#   regression analysis and IV construction.
#
# Requires (produced by data_patstat_process.R):
#   [DATA_DIR]/output/final/PATSTAT_IHS_parts_updated.csv
#   [DATA_DIR]/output/final/PATSTAT_IHS_parts_citations_updated.csv
#   [DATA_DIR]/output/final/OEM_patent_data.csv
#   [DATA_DIR]/output/final/OEM_inventor_data.csv
#   [DATA_DIR]/output/final/PATSTAT_IHS_inventors_parts_updated.csv
#   [DATA_DIR]/output/final/PATSTAT_bilateral_citations.csv
#
# Produces:
#   [DATA_DIR]/output/final/data_supplier_patents.csv
#   [DATA_DIR]/output/final/data_buyer_patents.csv
#   [DATA_DIR]/output/final/data_supplier_inventors.csv
#   [DATA_DIR]/output/final/data_buyer_inventors.csv
#   [DATA_DIR]/output/final/data_supplier_buyers_citations.csv

rm(list = ls())

library(tidyverse)
library(zoo)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"

# Depreciation rate for discounted knowledge stock (standard 15% annual)
DEPRECIATION_RATE <- 0.85

################################################################################
## Supplier Patent Data
################################################################################

patents          <- read_csv(file.path(DATA_DIR, "output/final/PATSTAT_IHS_parts_updated.csv"),
                             show_col_types = FALSE)
patents_citations <- read_csv(file.path(DATA_DIR, "output/final/PATSTAT_IHS_parts_citations_updated.csv"),
                              show_col_types = FALSE)

# First year of positive observation by (supplier, country, part)
year_min <- patents %>%
  group_by(Supplier_PSN, Country, country_code, Part) %>%
  summarise(Year_min = min(Year), .groups = "drop")

df_supplier_patents <- patents %>%
  left_join(patents_citations,
            by = c("Country", "country_code", "Supplier_PSN", "Year", "Part")) %>%
  mutate(
    citation_count     = if_else(is.na(citation_count),     0, citation_count),
    citation_count_APP = if_else(is.na(citation_count_APP), 0, citation_count_APP)
  ) %>%
  filter(!is.na(appln_count)) %>%
  filter(Part != "Other") %>%
  # Fill gaps in the panel with zeros
  complete(Year, nesting(Supplier_PSN, Country, country_code, Part)) %>%
  mutate(
    appln_count        = if_else(is.na(appln_count),        0, appln_count),
    citation_count     = if_else(is.na(citation_count),     0, citation_count),
    citation_count_APP = if_else(is.na(citation_count_APP), 0, citation_count_APP)
  ) %>%
  group_by(Country, country_code, Supplier_PSN, Part) %>%
  arrange(Year) %>%
  # 5-year forward rolling sum (t to t+4) — intended as a forward-looking innovation measure
  mutate(
    count_roll             = rollapply(appln_count,        width = 5, FUN = sum, fill = 0, align = "left"),
    count_roll_citation    = rollapply(citation_count,     width = 5, FUN = sum, fill = 0, align = "left"),
    count_roll_citation_APP = rollapply(citation_count_APP, width = 5, FUN = sum, fill = 0, align = "left")
  ) %>%
  # Cumulative knowledge stock (undiscounted): stock at start of year t (excludes year t)
  mutate(
    cumulative_count = purrr::accumulate(appln_count, ~ .x * 1.00 + .y, .init = 0)[-1],
    cumulative_count = cumulative_count - appln_count
  ) %>%
  # Discounted knowledge stock (15% annual depreciation)
  mutate(
    cumulative_count_discounted = purrr::accumulate(appln_count, ~ .x * DEPRECIATION_RATE + .y, .init = 0)[-1],
    cumulative_count_discounted = cumulative_count_discounted - appln_count
  ) %>%
  # Cumulative citation stock (undiscounted) — FIX: was incorrectly using appln_count
  mutate(
    cumulative_citation = purrr::accumulate(citation_count, ~ .x * 1.00 + .y, .init = 0)[-1],
    cumulative_citation = cumulative_citation - citation_count
  ) %>%
  # Discounted citation stock — FIX: was incorrectly using cumulative_count_discounted
  mutate(
    cumulative_citation_discounted = purrr::accumulate(citation_count, ~ .x * DEPRECIATION_RATE + .y, .init = 0)[-1],
    cumulative_citation_discounted = cumulative_citation_discounted - citation_count
  ) %>%
  ungroup() %>%
  left_join(year_min,
            by = c("Supplier_PSN", "Country", "country_code", "Part")) %>%
  filter(Year <= 2024) %>%
  filter(Year >= Year_min) %>%
  select(-Year_min)

write_csv(df_supplier_patents,
          file.path(DATA_DIR, "output/final/data_supplier_patents.csv"))

################################################################################
## OEM Patent Data
################################################################################

patents_oem <- read_csv(file.path(DATA_DIR, "output/final/OEM_patent_data.csv"),
                        show_col_types = FALSE)

year_min_oem <- patents_oem %>%
  filter(appln_count > 0) %>%
  group_by(OEM, Country, country_code, Part) %>%
  summarise(Year_min = min(Year), .groups = "drop")

df_buyer_patents <- patents_oem %>%
  filter(!is.na(appln_count)) %>%
  filter(Part != "Other") %>%
  complete(Year, nesting(OEM, Country, country_code, Part)) %>%
  mutate(appln_count = if_else(is.na(appln_count), 0, appln_count)) %>%
  group_by(Country, country_code, OEM, Part) %>%
  arrange(Year) %>%
  mutate(
    count_roll = rollapply(appln_count, width = 5, FUN = sum, fill = 0, align = "left")
  ) %>%
  mutate(
    cumulative_count = purrr::accumulate(appln_count, ~ .x * 1.00 + .y, .init = 0)[-1],
    cumulative_count = cumulative_count - appln_count
  ) %>%
  mutate(
    cumulative_count_discounted = purrr::accumulate(appln_count, ~ .x * DEPRECIATION_RATE + .y, .init = 0)[-1],
    cumulative_count_discounted = cumulative_count_discounted - appln_count
  ) %>%
  ungroup() %>%
  left_join(year_min_oem,
            by = c("OEM", "Country", "country_code", "Part")) %>%
  filter(Year <= 2024) %>%
  filter(Year >= Year_min) %>%
  select(-Year_min)

write_csv(df_buyer_patents,
          file.path(DATA_DIR, "output/final/data_buyer_patents.csv"))

################################################################################
## Bilateral Citation Data (rolling and cumulative)
################################################################################

citations <- read_csv(file.path(DATA_DIR, "output/final/PATSTAT_bilateral_citations.csv"),
                      show_col_types = FALSE)

df_citations <- citations %>%
  group_by(Cited_Country, Citing_Country, country_code_o, country_code_d,
           Year, Supplier_PSN, Part, OEM) %>%
  summarise(citations = sum(citations, na.rm = TRUE), .groups = "drop") %>%
  complete(Year, nesting(Cited_Country, Citing_Country, country_code_o, country_code_d,
                         Supplier_PSN, Part, OEM)) %>%
  mutate(citations = if_else(is.na(citations), 0, citations)) %>%
  group_by(Cited_Country, Citing_Country, country_code_o, country_code_d,
           Supplier_PSN, Part, OEM) %>%
  arrange(Year) %>%
  mutate(
    citations_roll = rollapply(citations, width = 5, FUN = sum, fill = 0, align = "left"),
    cumulative_citations = purrr::accumulate(citations, ~ .x * 1.00 + .y, .init = 0)[-1],
    cumulative_citations_discounted = purrr::accumulate(citations, ~ .x * DEPRECIATION_RATE + .y, .init = 0)[-1],
    cumulative_citations_discounted = cumulative_citations_discounted - citations
  ) %>%
  ungroup()

write_csv(df_citations,
          file.path(DATA_DIR, "output/final/data_supplier_buyers_citations.csv"))

################################################################################
## Inventor-Level Supplier Data
################################################################################

inventors_supplier <- read_csv(file.path(DATA_DIR, "output/final/PATSTAT_IHS_inventors_parts_updated.csv"),
                               show_col_types = FALSE)

year_min_inv <- inventors_supplier %>%
  filter(appln_count > 0) %>%
  group_by(Supplier_PSN, Inventor, country_code, Part) %>%
  summarise(Year_min = min(Year), .groups = "drop")

df_supplier_inventors <- inventors_supplier %>%
  select(-Country) %>%
  filter(!is.na(appln_count)) %>%
  filter(Part != "Other") %>%
  complete(Year, nesting(Supplier_PSN, Inventor, country_code, Part)) %>%
  mutate(appln_count = if_else(is.na(appln_count), 0, appln_count)) %>%
  group_by(Supplier_PSN, Inventor, country_code, Part) %>%
  arrange(Year) %>%
  mutate(
    count_roll = rollapply(appln_count, width = 5, FUN = sum, fill = 0, align = "left")
  ) %>%
  ungroup() %>%
  left_join(year_min_inv,
            by = c("Supplier_PSN", "Inventor", "country_code", "Part")) %>%
  filter(Year <= 2024) %>%
  filter(Year >= Year_min) %>%
  select(-Year_min)

write_csv(df_supplier_inventors,
          file.path(DATA_DIR, "output/final/data_supplier_inventors.csv"))

################################################################################
## Inventor-Level OEM Data
################################################################################

inventors_buyer <- read_csv(file.path(DATA_DIR, "output/final/OEM_inventor_data.csv"),
                            show_col_types = FALSE) %>%
  rename(Inventor = inventor_code)

year_min_inv_oem <- inventors_buyer %>%
  filter(appln_count > 0) %>%
  group_by(OEM, Inventor, country_code, Part) %>%
  summarise(Year_min = min(Year), .groups = "drop")

df_buyer_inventors <- inventors_buyer %>%
  select(-Country) %>%
  filter(!is.na(appln_count)) %>%
  filter(Part != "Other") %>%
  complete(Year, nesting(OEM, Inventor, country_code, Part)) %>%
  mutate(appln_count = if_else(is.na(appln_count), 0, appln_count)) %>%
  group_by(OEM, Inventor, country_code, Part) %>%
  arrange(Year) %>%
  mutate(
    count_roll = rollapply(appln_count, width = 5, FUN = sum, fill = 0, align = "left")
  ) %>%
  ungroup() %>%
  left_join(year_min_inv_oem,
            by = c("OEM", "Inventor", "country_code", "Part")) %>%
  filter(Year <= 2024) %>%
  filter(Year >= Year_min) %>%
  select(-Year_min)

write_csv(df_buyer_inventors,
          file.path(DATA_DIR, "output/final/data_buyer_inventors.csv"))

message("data_patents.R complete.")
