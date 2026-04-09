# data_plant_locations_IV.R
# Run from project root: Rscript Empirics/Code/data_plant_locations_IV.R
#
# PURPOSE: Construct tariff-based IVs for supplier plant location and assembly
#   production decisions. Runs a zero-stage logit of plant presence on MFN tariffs
#   and interaction with assembly tariffs. Predicted probabilities serve as the
#   supply-side IV for upstream/downstream proximity. Also runs a recentering
#   procedure (randomizing tariffs within firm×country×year) to remove mean
#   predicted location from the IV, following the recentered IV approach.
#
# Consolidates: data_plant_locations_IV.R, data_plant_locations_IV_recenter.R,
#   data_plant_locations_IV_linear.R (linear probability robustness),
#   data_plant_locations_IV_nozero.R (nonzero-only robustness).
#   IV_linear and IV_nozero are included as commented alternative specs.
#
# Requires:
#   DATA_DIR and IHS_DIR defined below
#   [DATA_DIR]/output/final/supplier_OEM_flows_data.csv
#   [DATA_DIR]/output/final/supplier_third_country_proximity.csv
#   [DATA_DIR]/output/final/cepii_distance_pairs.csv
#   [DATA_DIR]/output/final/supplier_aggregate_production_data.csv
#   (tariff inputs loaded via data_tariffs_shared.R)
#
# Produces:
#   [DATA_DIR]/output/final/supplier_third_country_proximity_IV.csv
#   [DATA_DIR]/output/final/supplier_third_country_proximity_IV_analysis.csv

rm(list = ls())

library(tidyverse)
library(fixest)
library(haven)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"
IHS_DIR  <- "/Users/adrkul/Library/CloudStorage/Dropbox/IHS_data"

# Number of randomization draws for the recentering procedure.
# Increasing this reduces simulation noise in the recentered IV.
N_RECENTER <- 5

set.seed(20260408)

# Load shared tariff data (produces tariff_df, eu_countries, country_codes)
source("data_tariffs_shared.R")

################################################################################
## Production Location Data
################################################################################

# Supplier plant production by country (presence indicator + volume)
supplier_production_location <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_OEM_flows_data.csv"),
  show_col_types = FALSE
) %>%
  group_by(Supplier_PSN, Part, Year, country_code_supplier) %>%
  summarise(Plant_Production = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  filter(Plant_Production > 0,
         !is.na(country_code_supplier),
         country_code_supplier != "NAN") %>%
  complete(country_code_supplier, nesting(Supplier_PSN, Part, Year)) %>%
  mutate(Plant_Production     = if_else(is.na(Plant_Production), 0, Plant_Production),
         Plant_Production_ind = Plant_Production > 0)

# OEM assembly production by country
supplier_demand_location <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_OEM_flows_data.csv"),
  show_col_types = FALSE
) %>%
  group_by(Supplier_PSN, Part, Year, country_code_buyer) %>%
  summarise(Assembly_Production = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  filter(Assembly_Production > 0) %>%
  complete(country_code_buyer, nesting(Supplier_PSN, Part, Year)) %>%
  mutate(Assembly_Production     = if_else(is.na(Assembly_Production), 0, Assembly_Production),
         Assembly_Production_ind = Assembly_Production > 0)

# Join and attach tariffs; fill missing tariff years with LOCF/BOCF
production_location <- supplier_production_location %>%
  left_join(supplier_demand_location,
            by = c("country_code_supplier" = "country_code_buyer",
                   "Supplier_PSN", "Year", "Part")) %>%
  group_by(Supplier_PSN, Part, Year) %>%
  mutate(Plant_Production_Total    = sum(Plant_Production,    na.rm = TRUE),
         Assembly_Production_Total = sum(Assembly_Production, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(country_code_tariff = if_else(country_code_supplier %in% eu_countries,
                                       "EPP", country_code_supplier)) %>%
  left_join(tariff_df,
            by = c("country_code_tariff" = "country_code",
                   "Part", "Year" = "year")) %>%
  group_by(country_code_supplier, Part) %>%
  arrange(Year, .by_group = TRUE) %>%
  fill(MFN,          .direction = "downup") %>%
  fill(MFN_Assembly, .direction = "downup") %>%
  ungroup() %>%
  mutate(
    firm_cntry_year_fe = paste0(Supplier_PSN, country_code_supplier, Year),
    firm_cntry_part_fe = paste0(Supplier_PSN, country_code_supplier, Part),
    cntry_year_fe      = paste0(country_code_supplier, Year),
    MFN_Part_x_Assembly = MFN * MFN_Assembly
  ) %>%
  filter(!is.na(MFN), !is.na(MFN_Assembly))

################################################################################
## Recentering Loop
################################################################################
# Randomize MFN within each firm×country×year cell N_RECENTER times and collect
# predicted probabilities. The mean over iterations is subtracted from the real
# IV predictions to recenter them around a baseline where tariffs are as-if random.

recenter_df <- tibble()

for (i in seq_len(N_RECENTER)) {

  production_location_r <- production_location %>%
    group_by(firm_cntry_year_fe) %>%
    mutate(MFN = sample(MFN, size = n(), replace = TRUE)) %>%
    ungroup() %>%
    mutate(MFN_Part_x_Assembly = MFN * MFN_Assembly)

  reg_r_plant    <- feglm(Plant_Production_ind    ~ MFN + MFN_Part_x_Assembly |
                            firm_cntry_year_fe,
                          data = production_location_r, family = "logit",
                          se = "cluster")
  reg_r_assembly <- feglm(Assembly_Production_ind ~ MFN + MFN_Part_x_Assembly |
                            firm_cntry_year_fe,
                          data = production_location_r, family = "logit",
                          se = "hetero")

  production_location_r$Plant_Production_IV_part    <-
    predict(reg_r_plant,    production_location_r) *
    (production_location_r$Plant_Production_Total > 0)

  production_location_r$Assembly_Production_IV_part <-
    predict(reg_r_assembly, production_location_r) *
    (production_location_r$Assembly_Production_Total > 0)

  # Load proximity grid once (reused each iteration)
  supplier_third_country_sub_agg <- read_csv(
    file.path(DATA_DIR, "output/final/supplier_third_country_proximity.csv"),
    show_col_types = FALSE
  )
  prod_fill <- read_csv(
    file.path(DATA_DIR, "output/final/cepii_distance_pairs.csv"),
    show_col_types = FALSE
  )

  supplier_third_country_IV_r <- supplier_third_country_sub_agg %>%
    left_join(prod_fill, by = c("country" = "country_code_o")) %>%
    left_join(
      production_location_r %>%
        select(country_code_supplier, Supplier_PSN, Part, Year,
               Plant_Production_IV_part, Assembly_Production_IV_part),
      by = c("supplier" = "Supplier_PSN", "part" = "Part",
             "year" = "Year", "country_code_d" = "country_code_supplier")
    ) %>%
    group_by(supplier, part, country, year) %>%
    mutate(
      Share_Production_p = Plant_Production_IV_part    / sum(Plant_Production_IV_part,    na.rm = TRUE),
      Share_Demand_p     = Assembly_Production_IV_part / sum(Assembly_Production_IV_part, na.rm = TRUE)
    ) %>%
    summarise(
      avg_inv_down_dist_IV_p = sum((1 / distw) * Share_Demand_p,     na.rm = TRUE),
      avg_inv_up_dist_IV_p   = sum((1 / distw) * Share_Production_p, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    left_join(
      read_csv(file.path(DATA_DIR, "output/final/supplier_aggregate_production_data.csv"),
               show_col_types = FALSE),
      by = c("supplier" = "Supplier_PSN", "part" = "Part", "year" = "Year")
    ) %>%
    mutate(
      log_inv_down_dist_IV_p       = log(avg_inv_down_dist_IV_p),
      log_inv_up_dist_IV_p         = log(avg_inv_up_dist_IV_p),
      log_inv_down_dist_x_HHI_IV_p = log_inv_down_dist_IV_p * HHI,
      log_inv_up_dist_x_HHI_IV_p   = log_inv_up_dist_IV_p   * HHI,
      iter = i
    ) %>%
    select(supplier, part, country, year,
           log_inv_down_dist_IV_p, log_inv_up_dist_IV_p,
           log_inv_down_dist_x_HHI_IV_p, log_inv_up_dist_x_HHI_IV_p,
           iter)

  recenter_df <- bind_rows(recenter_df, supplier_third_country_IV_r)

  message("Recentering iteration ", i, " of ", N_RECENTER, " complete")
}

# Average predicted values across iterations (the recentering baseline)
recenter_mean <- recenter_df %>%
  group_by(supplier, part, country, year) %>%
  summarise(
    log_inv_down_dist_IV_p_center       = mean(log_inv_down_dist_IV_p,       na.rm = TRUE),
    log_inv_up_dist_IV_p_center         = mean(log_inv_up_dist_IV_p,         na.rm = TRUE),
    log_inv_down_dist_x_HHI_IV_p_center = mean(log_inv_down_dist_x_HHI_IV_p, na.rm = TRUE),
    log_inv_up_dist_x_HHI_IV_p_center   = mean(log_inv_up_dist_x_HHI_IV_p,   na.rm = TRUE),
    .groups = "drop"
  )

################################################################################
## Zero-Stage Models (Real Data)
################################################################################

# "p" variant: firm×country×year FE — cross-sectional variation in tariff levels
reg_IV_plant_p    <- feglm(Plant_Production_ind    ~ MFN + MFN_Part_x_Assembly |
                              firm_cntry_year_fe,
                            data = production_location, family = "logit",
                            se = "cluster")

reg_IV_assembly_p <- feglm(Assembly_Production_ind ~ MFN + MFN_Part_x_Assembly |
                              firm_cntry_year_fe,
                            data = production_location, family = "logit",
                            se = "hetero")

# "t" variant: firm×country×part FE — time-series variation in tariff changes
reg_IV_plant_t    <- feglm(Plant_Production_ind    ~ MFN + MFN_Part_x_Assembly |
                              firm_cntry_part_fe,
                            data = production_location, family = "logit",
                            se = "hetero")

reg_IV_assembly_t <- feglm(Assembly_Production_ind ~ MFN + MFN_Part_x_Assembly |
                              firm_cntry_part_fe,
                            data = production_location, family = "logit",
                            se = "hetero")

production_location$Plant_Production_IV_part       <-
  predict(reg_IV_plant_p,    production_location) * (production_location$Plant_Production_Total    > 0)
production_location$Assembly_Production_IV_part    <-
  predict(reg_IV_assembly_p, production_location) * (production_location$Assembly_Production_Total > 0)
production_location$Plant_Production_IV_time       <-
  predict(reg_IV_plant_t,    production_location) * (production_location$Plant_Production_Total    > 0)
production_location$Assembly_Production_IV_time    <-
  predict(reg_IV_assembly_t, production_location) * (production_location$Assembly_Production_Total > 0)

################################################################################
## Third-Country Proximity with IV Weights
################################################################################

# Load base proximity grid (produced by data_plant_locations.R)
supplier_third_country_sub_agg <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_third_country_proximity.csv"),
  show_col_types = FALSE
)
prod_fill <- read_csv(
  file.path(DATA_DIR, "output/final/cepii_distance_pairs.csv"),
  show_col_types = FALSE
)

production_location_join <- production_location %>%
  select(country_code_supplier, Supplier_PSN, Part, Year,
         Plant_Production_IV_part, Assembly_Production_IV_part,
         Plant_Production_IV_time, Assembly_Production_IV_time)

supplier_third_country_IV <- supplier_third_country_sub_agg %>%
  left_join(prod_fill, by = c("country" = "country_code_o")) %>%
  left_join(production_location_join,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_supplier")) %>%
  group_by(supplier, part, country, year) %>%
  mutate(
    Share_Production_p = Plant_Production_IV_part       / sum(Plant_Production_IV_part,       na.rm = TRUE),
    Share_Demand_p     = Assembly_Production_IV_part    / sum(Assembly_Production_IV_part,    na.rm = TRUE),
    Share_Production_t = Plant_Production_IV_time       / sum(Plant_Production_IV_time,       na.rm = TRUE),
    Share_Demand_t     = Assembly_Production_IV_time    / sum(Assembly_Production_IV_time,    na.rm = TRUE)
  ) %>%
  summarise(
    avg_inv_down_dist_IV_p = sum((1 / distw) * Share_Demand_p,     na.rm = TRUE),
    avg_inv_up_dist_IV_p   = sum((1 / distw) * Share_Production_p, na.rm = TRUE),
    avg_inv_down_dist_IV_t = sum((1 / distw) * Share_Demand_t,     na.rm = TRUE),
    avg_inv_up_dist_IV_t   = sum((1 / distw) * Share_Production_t, na.rm = TRUE),
    .groups = "drop"
  )

# Append IV proximity back to the base proximity dataset
supplier_third_country_sub_agg_IV <- supplier_third_country_sub_agg %>%
  left_join(supplier_third_country_IV,
            by = c("supplier", "part", "country", "year"))

write_csv(supplier_third_country_sub_agg_IV,
          file.path(DATA_DIR, "output/final/supplier_third_country_proximity_IV.csv"))

################################################################################
## Analysis Dataset
################################################################################

supplier_aggregate_production_data <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_aggregate_production_data.csv"),
  show_col_types = FALSE
)

supplier_third_country_IV_analysis <- supplier_third_country_sub_agg_IV %>%
  left_join(supplier_aggregate_production_data,
            by = c("supplier" = "Supplier_PSN", "part" = "Part", "year" = "Year")) %>%
  mutate(
    firm_cntry_year_fe = paste0(supplier, country, year),
    firm_cntry_part_fe = paste0(supplier, country, part),
    part_cntry_year_fe = paste0(part,     country, year),
    cntry_year_fe      = paste0(country,  year)
  ) %>%
  mutate(
    log_inv_down_dist          = log(avg_inv_down_dist),
    log_inv_up_dist            = log(avg_inv_up_dist),
    log_inv_down_dist_x_HHI    = log_inv_down_dist * HHI,
    log_inv_up_dist_x_HHI      = log_inv_up_dist   * HHI,
    log_prod                   = log(prod_all),
    log_prod_x_HHI             = log_prod * HHI,
    log_inv_down_dist_IV_p     = log(avg_inv_down_dist_IV_p),
    log_inv_up_dist_IV_p       = log(avg_inv_up_dist_IV_p),
    log_inv_down_dist_IV_t     = log(avg_inv_down_dist_IV_t),
    log_inv_up_dist_IV_t       = log(avg_inv_up_dist_IV_t),
    log_inv_down_dist_x_HHI_IV_p = log_inv_down_dist_IV_p * HHI,
    log_inv_up_dist_x_HHI_IV_p   = log_inv_up_dist_IV_p   * HHI,
    log_inv_down_dist_x_HHI_IV_t = log_inv_down_dist_IV_t * HHI,
    log_inv_up_dist_x_HHI_IV_t   = log_inv_up_dist_IV_t   * HHI
  ) %>%
  # Attach recentered IVs and compute deviations from baseline
  left_join(recenter_mean,
            by = c("supplier", "part", "country", "year")) %>%
  mutate(
    log_inv_up_dist_IV_p_rec         = log_inv_up_dist_IV_p         - log_inv_up_dist_IV_p_center,
    log_inv_down_dist_IV_p_rec       = log_inv_down_dist_IV_p       - log_inv_down_dist_IV_p_center,
    log_inv_up_dist_x_HHI_IV_p_rec   = log_inv_up_dist_x_HHI_IV_p   - log_inv_up_dist_x_HHI_IV_p_center,
    log_inv_down_dist_x_HHI_IV_p_rec = log_inv_down_dist_x_HHI_IV_p - log_inv_down_dist_x_HHI_IV_p_center
  )

################################################################################
## First-Stage Regressions
################################################################################

# "p" variants: IV from cross-sectional tariff levels (firm×country×year FE)
reg_fs_down_p <- feols(
  log_inv_down_dist ~ log_inv_down_dist_IV_p + log_inv_up_dist_IV_p +
    log_inv_down_dist_x_HHI_IV_p + log_inv_up_dist_x_HHI_IV_p |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_up_p <- feols(
  log_inv_up_dist ~ log_inv_down_dist_IV_p + log_inv_up_dist_IV_p +
    log_inv_down_dist_x_HHI_IV_p + log_inv_up_dist_x_HHI_IV_p |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_down_x_HHI_p <- feols(
  log_inv_down_dist_x_HHI ~ log_inv_down_dist_IV_p + log_inv_up_dist_IV_p +
    log_inv_down_dist_x_HHI_IV_p + log_inv_up_dist_x_HHI_IV_p |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_up_x_HHI_p <- feols(
  log_inv_up_dist_x_HHI ~ log_inv_down_dist_IV_p + log_inv_up_dist_IV_p +
    log_inv_down_dist_x_HHI_IV_p + log_inv_up_dist_x_HHI_IV_p |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)

# "t" variants: IV from time-series tariff changes (firm×country×part FE)
reg_fs_down_t <- feols(
  log_inv_down_dist ~ log_inv_down_dist_IV_t + log_inv_up_dist_IV_t +
    log_inv_down_dist_x_HHI_IV_t + log_inv_up_dist_x_HHI_IV_t |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_up_t <- feols(
  log_inv_up_dist ~ log_inv_down_dist_IV_t + log_inv_up_dist_IV_t +
    log_inv_down_dist_x_HHI_IV_t + log_inv_up_dist_x_HHI_IV_t |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_down_x_HHI_t <- feols(
  log_inv_down_dist_x_HHI ~ log_inv_down_dist_IV_t + log_inv_up_dist_IV_t +
    log_inv_down_dist_x_HHI_IV_t + log_inv_up_dist_x_HHI_IV_t |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_up_x_HHI_t <- feols(
  log_inv_up_dist_x_HHI ~ log_inv_down_dist_IV_t + log_inv_up_dist_IV_t +
    log_inv_down_dist_x_HHI_IV_t + log_inv_up_dist_x_HHI_IV_t |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)

# Recentered IV first stages
reg_fs_down_rec <- feols(
  log_inv_down_dist ~ log_inv_down_dist_IV_p_rec + log_inv_up_dist_IV_p_rec +
    log_inv_down_dist_x_HHI_IV_p_rec + log_inv_up_dist_x_HHI_IV_p_rec |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_up_rec <- feols(
  log_inv_up_dist ~ log_inv_down_dist_IV_p_rec + log_inv_up_dist_IV_p_rec +
    log_inv_down_dist_x_HHI_IV_p_rec + log_inv_up_dist_x_HHI_IV_p_rec |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_down_x_HHI_rec <- feols(
  log_inv_down_dist_x_HHI ~ log_inv_down_dist_IV_p_rec + log_inv_up_dist_IV_p_rec +
    log_inv_down_dist_x_HHI_IV_p_rec + log_inv_up_dist_x_HHI_IV_p_rec |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)
reg_fs_up_x_HHI_rec <- feols(
  log_inv_up_dist_x_HHI ~ log_inv_down_dist_IV_p_rec + log_inv_up_dist_IV_p_rec +
    log_inv_down_dist_x_HHI_IV_p_rec + log_inv_up_dist_x_HHI_IV_p_rec |
    firm_cntry_year_fe + part_cntry_year_fe,
  data = supplier_third_country_IV_analysis,
  se = "cluster", cluster = "cntry_year_fe"
)

# Attach first-stage predicted values and residuals
supplier_third_country_IV_analysis <- supplier_third_country_IV_analysis %>%
  mutate(
    log_inv_down_dist_pred_p          = predict(reg_fs_down_p,        supplier_third_country_IV_analysis),
    log_inv_up_dist_pred_p            = predict(reg_fs_up_p,          supplier_third_country_IV_analysis),
    log_inv_down_dist_x_HHI_pred_p    = predict(reg_fs_down_x_HHI_p,  supplier_third_country_IV_analysis),
    log_inv_up_dist_x_HHI_pred_p      = predict(reg_fs_up_x_HHI_p,    supplier_third_country_IV_analysis),
    log_inv_down_dist_pred_resid_p    = log_inv_down_dist    - log_inv_down_dist_pred_p,
    log_inv_up_dist_pred_resid_p      = log_inv_up_dist      - log_inv_up_dist_pred_p,
    log_inv_down_dist_x_HHI_pred_resid_p = log_inv_down_dist_x_HHI - log_inv_down_dist_x_HHI_pred_p,
    log_inv_up_dist_x_HHI_pred_resid_p   = log_inv_up_dist_x_HHI   - log_inv_up_dist_x_HHI_pred_p,
    log_inv_down_dist_pred_t          = predict(reg_fs_down_t,        supplier_third_country_IV_analysis),
    log_inv_up_dist_pred_t            = predict(reg_fs_up_t,          supplier_third_country_IV_analysis),
    log_inv_down_dist_x_HHI_pred_t    = predict(reg_fs_down_x_HHI_t,  supplier_third_country_IV_analysis),
    log_inv_up_dist_x_HHI_pred_t      = predict(reg_fs_up_x_HHI_t,    supplier_third_country_IV_analysis),
    log_inv_down_dist_pred_resid_t    = log_inv_down_dist    - log_inv_down_dist_pred_t,
    log_inv_up_dist_pred_resid_t      = log_inv_up_dist      - log_inv_up_dist_pred_t,
    log_inv_down_dist_x_HHI_pred_resid_t = log_inv_down_dist_x_HHI - log_inv_down_dist_x_HHI_pred_t,
    log_inv_up_dist_x_HHI_pred_resid_t   = log_inv_up_dist_x_HHI   - log_inv_up_dist_x_HHI_pred_t,
    log_inv_down_dist_pred_rec        = predict(reg_fs_down_rec,      supplier_third_country_IV_analysis),
    log_inv_up_dist_pred_rec          = predict(reg_fs_up_rec,        supplier_third_country_IV_analysis),
    log_inv_down_dist_x_HHI_pred_rec    = predict(reg_fs_down_x_HHI_rec,      supplier_third_country_IV_analysis),
    log_inv_up_dist_x_HHI_pred_rec      = predict(reg_fs_up_x_HHI_rec,        supplier_third_country_IV_analysis),
    log_inv_down_dist_pred_resid_rec    = log_inv_down_dist    - log_inv_down_dist_pred_rec,
    log_inv_up_dist_pred_resid_rec      = log_inv_up_dist      - log_inv_up_dist_pred_rec,
    log_inv_down_dist_x_HHI_pred_resid_rec = log_inv_down_dist_x_HHI - log_inv_down_dist_x_HHI_pred_rec,
    log_inv_up_dist_x_HHI_pred_resid_rec   = log_inv_up_dist_x_HHI   - log_inv_up_dist_x_HHI_pred_rec,
  )

write_csv(supplier_third_country_IV_analysis,
          file.path(DATA_DIR, "output/final/supplier_third_country_proximity_IV_analysis.csv"))

message("data_plant_locations_IV.R complete.")

################################################################################
## Second-Stage Regressions
################################################################################

patents = read_csv(file.path(DATA_DIR, "output/final/data_supplier_patents.csv"))

data_analysis_final_IV = patents %>%
  select(Supplier_PSN,Part,Year,Country,country_code,count_roll,count_roll_citation,count_roll_citation_APP) %>% 
  left_join(supplier_third_country_IV_analysis, by = c("Supplier_PSN" = "supplier", "Part" = "part", "Year" = "year", "country_code" = "country"))  

reg_0_p = fepois(count_roll ~ log_prod + log_prod_x_HHI + HHI + log_inv_up_dist_pred_p + log_inv_up_dist_x_HHI_pred_p + log_inv_down_dist_pred_p + log_inv_down_dist_x_HHI_pred_p | firm_cntry_year_fe + part_cntry_year_fe, data_analysis_final_IV , se="hetero")
summary(reg_0_p)

reg_1_p = fepois(count_roll ~ log_prod + log_prod_x_HHI + HHI + log_inv_up_dist_pred_p + log_inv_up_dist_x_HHI_pred_p + log_inv_down_dist_pred_p + log_inv_down_dist_x_HHI_pred_p 
                 + log_inv_up_dist_pred_resid_p + log_inv_up_dist_x_HHI_pred_resid_p + log_inv_down_dist_pred_resid_p + log_inv_down_dist_x_HHI_pred_resid_p | firm_cntry_year_fe + part_cntry_year_fe, data_analysis_final_IV , se="hetero")
summary(reg_1_p)

reg_0_p_rec = fepois(count_roll ~ log_prod + log_prod_x_HHI + HHI + log_inv_up_dist_pred_rec + log_inv_up_dist_x_HHI_pred_rec + log_inv_down_dist_pred_rec + log_inv_down_dist_x_HHI_pred_rec | firm_cntry_year_fe + part_cntry_year_fe, 
                     data_analysis_final_IV, se="hetero")
summary(reg_0_p_rec)

reg_1_p_rec = fepois(count_roll ~ log_prod + log_prod_x_HHI + HHI + log_inv_up_dist_pred_rec + log_inv_up_dist_x_HHI_pred_rec + log_inv_down_dist_pred_rec + log_inv_down_dist_x_HHI_pred_rec 
                    + log_inv_up_dist_pred_resid_rec + log_inv_up_dist_x_HHI_pred_resid_rec + log_inv_down_dist_pred_resid_rec + log_inv_down_dist_x_HHI_pred_resid_rec | firm_cntry_year_fe + part_cntry_year_fe, 
                     data_analysis_final_IV, se="hetero")
summary(reg_1_p_rec)

reg_2_p_rec = fepois(count_roll ~ log_prod + log_prod_x_HHI + HHI + log_inv_up_dist_pred_rec + log_inv_down_dist_x_HHI_pred_rec 
                     + log_inv_up_dist_pred_resid_rec + log_inv_down_dist_x_HHI_pred_resid_rec | firm_cntry_year_fe + part_cntry_year_fe, 
                     data_analysis_final_IV, se="hetero")
summary(reg_2_p_rec)

reg_0_t = fepois(count_roll ~ log_prod + log_prod_x_HHI + HHI + log_inv_down_dist_pred_t + log_inv_down_dist_x_HHI_pred_t | firm_cntry_part_fe + part_cntry_year_fe, data_analysis_final_IV , se="hetero")
summary(reg_0_t)

reg_1_t = fepois(count_roll ~ log_prod + log_prod_x_HHI + HHI + log_inv_down_dist_pred_t + log_inv_down_dist_x_HHI_pred_t + log_inv_down_dist_pred_resid_t + log_inv_down_dist_x_HHI_pred_resid_t | firm_cntry_part_fe + part_cntry_year_fe, data_analysis_final_IV , se="hetero")
summary(reg_1_t)