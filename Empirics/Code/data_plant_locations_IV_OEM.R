# data_plant_locations_IV_OEM.R
# Run from project root: Rscript Empirics/Code/data_plant_locations_IV_OEM.R
#
# PURPOSE: Construct tariff-based and Bartik demand IVs for OEM third-country
#   proximity measures. Two sets of first-stage regressions:
#   (1) Preferred spec: part tariff → upstream proximity, assembly tariff →
#       downstream proximity (feols with buyer×year FE).
#   (2) Alternative spec: part tariff in log levels, using a stacked dataset
#       where assembly-destination distance is treated as an additional part.
#   Both specifications are merged with the Bartik demand IV from data_demand_IV.R.
#
# Requires:
#   DATA_DIR and IHS_DIR defined below
#   [DATA_DIR]/output/final/buyer_third_country_proximity.csv
#   [DATA_DIR]/output/final/OEM_production_bilateral_data.csv
#   [IHS_DIR]/Sales2024/production_agg_name_IV.csv  (from data_demand_IV.R)
#   (tariff inputs loaded via data_tariffs_shared.R)
#
# Produces:
#   [DATA_DIR]/output/final/buyer_third_country_proximity_IV.csv
#   [DATA_DIR]/output/final/buyer_third_country_proximity_IV_alt.csv

rm(list = ls())

library(tidyverse)
library(fixest)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"
IHS_DIR  <- "/Users/adrkul/Library/CloudStorage/Dropbox/IHS_data"

# Load shared tariff data (produces tariff_df, eu_countries, country_codes)
source("Empirics/Code/data_tariffs_shared.R")

# Country codes with IHS-format country names (for joining with Bartik IV output)
country_codes_ihs <- country_codes %>%
  mutate(Country = toupper(Country)) %>%
  mutate(Country = case_when(
    Country == "UNITED STATES OF AMERICA" ~ "UNITED STATES",
    Country == "KOREA, REPUBLIC OF"       ~ "SOUTH KOREA",
    Country == "VIET NAM"                 ~ "VIETNAM",
    Country == "BOSNIA AND HERZEGOVINA"   ~ "BOSNIA-HERZEGOVINA",
    TRUE ~ Country
  ))

################################################################################
## Preferred Spec: Upstream IV (Part Tariff) + Downstream IV (Assembly Tariff)
################################################################################

OEM_parts <- read_csv(
  file.path(DATA_DIR, "output/final/buyer_third_country_proximity.csv"),
  show_col_types = FALSE
)

# Attach tariffs to OEM × third-country × part × year panel; fill LOCF/BOCF
production_location <- OEM_parts %>%
  mutate(country_code_tariff = if_else(country %in% eu_countries, "EPP", country)) %>%
  left_join(tariff_df,
            by = c("country_code_tariff" = "country_code",
                   "part" = "Part", "year" = "year")) %>%
  group_by(country, part) %>%
  arrange(year, .by_group = TRUE) %>%
  fill(MFN,          .direction = "downup") %>%
  fill(MFN_Assembly, .direction = "downup") %>%
  ungroup() %>%
  mutate(
    firm_cntry_year_fe = paste0(buyer, country, year),
    firm_part_year_fe  = paste0(buyer, part,    year),
    firm_cntry_fe      = paste0(buyer, country),
    cntry_year_fe      = paste0(country, year),
    firm_year_fe       = paste0(buyer, year),
    firm_cntry_part_fe = paste0(buyer, country, part),
    MFN_Part_x_Assembly = MFN * MFN_Assembly
  ) %>%
  filter(!is.na(MFN), !is.na(MFN_Assembly))

# First stage: part tariff → upstream proximity, assembly tariff → downstream
reg_IV_up   <- feols(I(log(avg_inv_up_dist))   ~ MFN          | firm_year_fe,
                     data = production_location, se = "hetero")
reg_IV_down <- feols(I(log(avg_inv_down_dist)) ~ MFN_Assembly | firm_year_fe,
                     data = production_location, se = "hetero")
reg_IV_down_alt <- feols(I(log(avg_inv_down_dist)) ~ MFN_Assembly |
                           firm_year_fe + firm_cntry_fe,
                         data = production_location, se = "hetero")

production_location <- production_location %>%
  mutate(
    log_avg_inv_up_dist_pred      = predict(reg_IV_up,       production_location),
    log_avg_inv_down_dist_pred    = predict(reg_IV_down,     production_location),
    log_avg_inv_down_alt_dist_pred = predict(reg_IV_down_alt, production_location)
  )

# Bartik demand IV (produced by data_demand_IV.R); aggregate to OEM × country × year
OEM_demand <- read_csv(
  file.path(IHS_DIR, "Sales2024/production_agg_name_IV.csv"),
  show_col_types = FALSE
) %>%
  left_join(country_codes_ihs, by = "Country") %>%
  rename(OEM = `VP: Strategic Group`) %>%
  group_by(country_code, OEM, Year) %>%
  summarise(Value_IV_c = sum(exp(log_Value_1_predicted), na.rm = TRUE),
            .groups = "drop") %>%
  group_by(OEM, Year) %>%
  mutate(Value_IV = sum(Value_IV_c, na.rm = TRUE)) %>%
  ungroup()

# Merge tariff IV predictions and Bartik IV into OEM proximity dataset
OEM_parts_IV <- OEM_parts %>%
  left_join(
    production_location %>%
      select(buyer, country, part, year,
             log_avg_inv_up_dist_pred, log_avg_inv_down_dist_pred,
             log_avg_inv_down_alt_dist_pred),
    by = c("buyer", "country", "part", "year")
  ) %>%
  left_join(OEM_demand,
            by = c("buyer" = "OEM", "country" = "country_code", "year" = "Year"))

write_csv(OEM_parts_IV,
          file.path(DATA_DIR, "output/final/buyer_third_country_proximity_IV.csv"))

################################################################################
## Alternative Spec: Log Tariff IV (Stacked Assembly + Parts Dataset)
################################################################################

# Reshape tariff_df so assembly tariff appears as a part row
tariff_df_alt <- bind_rows(
  tariff_df %>% select(-MFN_Assembly),
  tariff_df %>%
    filter(Part != "Assembly") %>%
    select(country_code, year, MFN = MFN_Assembly) %>%
    mutate(Part = "Assembly") %>%
    distinct()
)

# Stack: OEM upstream distance per part + OEM downstream (= assembly-destination) distance
OEM_parts_alt <- bind_rows(
  OEM_parts %>% select(buyer, part, country, year, avg_inv_up_dist),
  OEM_parts %>%
    select(buyer, country, year, avg_inv_down_dist) %>%
    distinct() %>%
    mutate(part = "Assembly") %>%
    rename(avg_inv_up_dist = avg_inv_down_dist)
)

production_location_alt <- OEM_parts_alt %>%
  mutate(country_code_tariff = if_else(country %in% eu_countries, "EPP", country)) %>%
  left_join(tariff_df_alt,
            by = c("country_code_tariff" = "country_code",
                   "part" = "Part", "year" = "year")) %>%
  group_by(country, part) %>%
  arrange(year, .by_group = TRUE) %>%
  fill(MFN, .direction = "downup") %>%
  ungroup() %>%
  mutate(
    firm_cntry_year_fe = paste0(buyer, country, year),
    firm_part_year_fe  = paste0(buyer, part,    year),
    firm_cntry_fe      = paste0(buyer, country),
    cntry_year_fe      = paste0(country, year),
    firm_year_fe       = paste0(buyer, year),
    part_year_fe       = paste0(part,   year),
    firm_cntry_part_fe = paste0(buyer, country, part)
  ) %>%
  filter(!is.na(MFN))

reg_IV_up_alt <- feols(I(log(avg_inv_up_dist)) ~ I(log(MFN)) | firm_year_fe,
                       data = production_location_alt, se = "hetero")
reg_IV_up_alt_fct <- feols(I(log(avg_inv_up_dist)) ~ I(log(MFN)) |
                              firm_cntry_year_fe + firm_part_year_fe,
                           data = production_location_alt, se = "hetero")

production_location_alt <- production_location_alt %>%
  mutate(
    log_avg_inv_up_dist_pred_alt     = predict(reg_IV_up_alt,     production_location_alt),
    log_avg_inv_up_dist_pred_alt_fct = predict(reg_IV_up_alt_fct, production_location_alt)
  )

OEM_parts_IV_alt <- OEM_parts_alt %>%
  left_join(
    production_location_alt %>%
      select(buyer, country, part, year,
             log_avg_inv_up_dist_pred_alt, log_avg_inv_up_dist_pred_alt_fct),
    by = c("buyer", "country", "part", "year")
  ) %>%
  left_join(OEM_demand,
            by = c("buyer" = "OEM", "country" = "country_code", "year" = "Year"))

write_csv(OEM_parts_IV_alt,
          file.path(DATA_DIR, "output/final/buyer_third_country_proximity_IV_alt.csv"))

message("data_plant_locations_IV_OEM.R complete.")
