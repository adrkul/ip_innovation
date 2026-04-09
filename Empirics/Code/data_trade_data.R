# data_trade_data.R
# Run from project root: Rscript Empirics/Code/data_trade_data.R
#
# PURPOSE: Process BACI HS12 bilateral trade data and aggregate to the
#   country-pair × part × year level.
#   Set TRADE_DATA_CONSTRUCT = TRUE to rebuild from raw BACI files (slow);
#   FALSE reads the cached intermediate CSV.
#
# Requires:
#   [DATA_DIR]/tariffs/auto_parts_hs12_classified_2.csv
#   [DATA_DIR]/trade/BACI_HS12_V202401/data/*.csv       (if TRADE_DATA_CONSTRUCT = TRUE)
#   [DATA_DIR]/trade/BACI_HS12_V202401/country_codes_V202401.csv
#   [DATA_DIR]/tariffs/trade_HS_parts.csv               (if TRADE_DATA_CONSTRUCT = FALSE)
#
# Produces:
#   [DATA_DIR]/tariffs/trade_HS_parts.csv               (intermediate cache)
#   [DATA_DIR]/output/final/trade_bilateral_parts.csv

rm(list = ls())

library(tidyverse)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"
BACI_DIR <- file.path(DATA_DIR, "trade/BACI_HS12_V202401")

# Set TRUE to rebuild from raw BACI CSVs; FALSE to use the cached intermediate
TRADE_DATA_CONSTRUCT <- FALSE

################################################################################
## HS12 to Part Classification
################################################################################

HS_codes <- read_csv(file.path(DATA_DIR, "tariffs/auto_parts_hs12_classified_2.csv"),
                     show_col_types = FALSE) %>%
  rename(HS12 = "HS Code", Part = "Auto Part") %>%
  mutate(HS12 = as.character(HS12)) %>%
  filter(HS12 != "851989")  # drop mis-classified electronics code

################################################################################
## BACI Trade Data
################################################################################

if (TRADE_DATA_CONSTRUCT) {

  # Filter each BACI annual file to automotive HS12 codes, then aggregate
  # to exporter × importer × year × HS12 (summing values and quantities).
  baci_files <- list.files(file.path(BACI_DIR, "data"), pattern = "\\.csv$")

  trade_data <- map_dfr(baci_files, function(f) {
    read_csv(file.path(BACI_DIR, "data", f), show_col_types = FALSE) %>%
      filter(k %in% HS_codes$HS12) %>%
      group_by(t, i, j, k) %>%
      summarise(
        v = sum(v, na.rm = TRUE),
        q = sum(q, na.rm = TRUE),
        .groups = "drop"
      )
  })

  write_csv(trade_data,
            file.path(DATA_DIR, "tariffs/trade_HS_parts.csv"))

} else {

  trade_data <- read_csv(file.path(DATA_DIR, "tariffs/trade_HS_parts.csv"),
                         show_col_types = FALSE)

}

################################################################################
## Aggregate to Country-Pair × Part × Year
################################################################################

# BACI numeric country codes → ISO3
baci_codes <- read_csv(file.path(BACI_DIR, "country_codes_V202401.csv"),
                       show_col_types = FALSE) %>%
  select(country_code, country_iso3)

trade_bilateral_parts <- trade_data %>%
  left_join(baci_codes, by = c("i" = "country_code")) %>%
  rename(country_iso3_o = country_iso3) %>%
  left_join(baci_codes, by = c("j" = "country_code")) %>%
  rename(country_iso3_d = country_iso3) %>%
  left_join(HS_codes %>% mutate(HS12 = as.numeric(HS12)), by = c("k" = "HS12")) %>%
  group_by(country_iso3_o, country_iso3_d, t, Part) %>%
  summarise(
    q = sum(q, na.rm = TRUE),
    v = sum(v, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  rename(year = t)

write_csv(trade_bilateral_parts,
          file.path(DATA_DIR, "output/final/trade_bilateral_parts.csv"))

message("data_trade_data.R complete.")
