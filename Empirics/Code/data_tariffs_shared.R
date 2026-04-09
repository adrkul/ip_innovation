# data_tariffs_shared.R
# Run from project root: source("Empirics/Code/data_tariffs_shared.R")
#
# PURPOSE: Shared tariff data loader sourced by all IV files. Produces:
#   tariff_df          — country × part × year MFN tariff rates (supplier + assembly)
#   codes              — HS12 to Part classification mapping
#   eu_countries       — ISO3 codes for EU27 member states
#   eu_countries_full  — uppercase country names for EU27
#   country_codes      — ISO3 code lookup (standard WTO name → alpha-3)
#
# Requires:
#   DATA_DIR and IHS_DIR must be defined by the calling script before source()
#   [DATA_DIR]/tariffs/auto_parts_hs12_classified_2.csv
#   [DATA_DIR]/tariffs/WTO_updated/*.csv
#   [DATA_DIR]/other/country_codes.csv
#
# NOTE: Do NOT call rm(list = ls()) here — this file is sourced, not run standalone.

library(tidyverse)
library(concordance)

################################################################################
## HS12 to Part Classification
################################################################################

# LLM-classified HS12 codes mapped to automotive parts
codes <- read_csv(file.path(DATA_DIR, "tariffs/auto_parts_hs12_classified_2.csv"),
                  show_col_types = FALSE) %>%
  rename(HS12 = "HS Code", Part = "Auto Part")

# Compute HS07 (6-digit) crosswalk for each HS12 code
codes$HS07 <- NA_character_
for (i in seq_len(nrow(codes))) {
  codes$HS07[i] <- concord(
    sourcevar = codes$HS12[i],
    origin    = "HS4",
    destination = "HS3",
    dest.digit  = 6,
    all = FALSE
  )
}

# Manually append brake and assembly final-product codes not in LLM output
assembly_brakes_rows <- tibble(
  Part           = c("Brake", "Brake",
                     rep("Assembly", 13)),
  HS12           = c("681381", "681310",
                     "870380", "870331", "870333", "870390", "870321",
                     "870324", "870332", "870340", "870322", "870323",
                     "870360", "870370", "870350"),
  Classification = "Final Product",
  HS07           = c("681381", "681310",
                     "870380", "870331", "870333", "870390", "870321",
                     "870324", "870332", "870340", "870322", "870323",
                     "870360", "870370", "870350")
)
codes <- bind_rows(assembly_brakes_rows, codes %>% mutate(HS12 = as.character(HS12))) %>%
  distinct() %>%
  filter(HS07 != "852580")  # drop mis-classified electronics code
rm(assembly_brakes_rows)
################################################################################
## WTO MFN Tariff Data
################################################################################

# Load and stack all country-year WTO MFN tariff CSVs
tariff_files <- list.files(
  file.path(DATA_DIR, "tariffs/WTO_updated"),
  pattern = "\\.csv$",
  full.names = TRUE
)

tariff_raw <- map_dfr(tariff_files, function(f) {
  read_csv(f, show_col_types = FALSE) %>%
    select(reporter_name, year, classification_version, product_code, value)
})

# Aggregate to country × part × year (mean MFN across HS07 codes in each Part)
tariff_df <- tariff_raw %>%
  mutate(product_code = as.character(product_code)) %>%
  left_join(codes, by = c("product_code" = "HS07")) %>%
  group_by(reporter_name, year, Part) %>%
  summarise(value = mean(value, na.rm = TRUE), .groups = "drop")

################################################################################
## Country Code Harmonization
################################################################################

# Standard ISO3 lookup (WTO country name → alpha-3 code)
country_codes <- read_csv(file.path(DATA_DIR, "other/country_codes.csv"),
                          show_col_types = FALSE) %>%
  select(Country, `Alpha-3 code`) %>%
  rename(country_code = `Alpha-3 code`)

# Apply manual fixes for WTO reporter names that do not match ISO standard names
tariff_df <- tariff_df %>%
  left_join(country_codes, by = c("reporter_name" = "Country")) %>%
  mutate(country_code = case_when(
    reporter_name == "United States of America"            ~ "USA",
    reporter_name == "Venezuela, Bolivarian Republic of"   ~ "VEN",
    reporter_name == "United Kingdom"                      ~ "GBR",
    reporter_name == "Türkiye"                             ~ "TUR",
    reporter_name == "Russian Federation"                  ~ "RUS",
    reporter_name == "North Macedonia"                     ~ "MKD",
    reporter_name == "Korea, Republic of"                  ~ "KOR",
    reporter_name == "European Union"                      ~ "EPP",
    reporter_name == "Chinese Taipei"                      ~ "TWN",
    TRUE ~ country_code
  )) %>%
  select(country_code, Part, year, value)

################################################################################
## Assembly Tariff Merge
################################################################################

# Separate assembly tariffs, then attach as a column to parts tariffs.
# Assembly tariffs are used as a complement price for the interaction IV term.
tariff_df_assembly <- tariff_df %>%
  filter(Part == "Assembly") %>%
  select(country_code, year, value)

tariff_df <- tariff_df %>%
  filter(Part != "Assembly") %>%
  left_join(tariff_df_assembly,
            by = c("country_code", "year"),
            suffix = c("", "_assembly")) %>%
  rename(MFN = value, MFN_Assembly = value_assembly)

################################################################################
## EU Country Lists
################################################################################

# ISO3 codes for EU27 (used to map EU member states to the "EPP" WTO reporter)
eu_countries <- c(
  "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST",
  "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
  "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
  "SVN", "ESP", "SWE"
)

# Full uppercase country names for EU27 (used in production data string matching)
eu_countries_full <- country_codes %>%
  filter(country_code %in% eu_countries) %>%
  mutate(Country = toupper(Country)) %>%
  pull(Country)
