# data_final.R
# Run from project root: Rscript Empirics/Code/data_final.R
#
# PURPOSE: Assemble the final analysis dataset. Joins supplier patent panel with
#   third-country proximity measures, tariff-based IV predictions, production
#   aggregates, and local spillover IVs. Runs first-stage regressions for the
#   production quantity and HHI instruments, and writes the complete dataset
#   used by analysis_main.R.
#
# Requires:
#   [DATA_DIR]/output/final/data_supplier_patents.csv
#   [DATA_DIR]/output/final/supplier_third_country_proximity.csv
#   [DATA_DIR]/output/final/supplier_third_country_proximity_IV_analysis.csv
#   [DATA_DIR]/output/final/supplier_aggregate_production_data.csv
#   [DATA_DIR]/output/final/local_innovation_IVs.csv
#
# Produces:
#   [DATA_DIR]/output/final/data_analysis_final.csv

rm(list = ls())

library(tidyverse)
library(fixest)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"

################################################################################
## Load and Merge Inputs
################################################################################

patents <- read_csv(
  file.path(DATA_DIR, "output/final/data_supplier_patents.csv"),
  show_col_types = FALSE
)

supplier_third_country <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_third_country_proximity.csv"),
  show_col_types = FALSE
)

# Select IV predicted values and control-function residuals from first-stage
supplier_third_country_IV <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_third_country_proximity_IV_analysis.csv"),
  show_col_types = FALSE
) %>%
  select(supplier, part, year, country,
         # "p" variant (firm×country×year FE)
         log_inv_down_dist_pred_p,        log_inv_up_dist_pred_p,
         log_inv_down_dist_x_HHI_pred_p,  log_inv_up_dist_x_HHI_pred_p,
         log_inv_down_dist_pred_resid_p,  log_inv_up_dist_pred_resid_p,
         log_inv_down_dist_x_HHI_pred_resid_p, log_inv_up_dist_x_HHI_pred_resid_p,
         # "t" variant (firm×country×part FE)
         log_inv_down_dist_pred_t,        log_inv_up_dist_pred_t,
         log_inv_down_dist_x_HHI_pred_t,  log_inv_up_dist_x_HHI_pred_t,
         log_inv_down_dist_pred_resid_t,  log_inv_up_dist_pred_resid_t,
         log_inv_down_dist_x_HHI_pred_resid_t, log_inv_up_dist_x_HHI_pred_resid_t,
         # recentered variant
         log_inv_down_dist_pred_rec,        log_inv_up_dist_pred_rec,
         log_inv_down_dist_x_HHI_pred_rec,  log_inv_up_dist_x_HHI_pred_rec,
         log_inv_down_dist_pred_resid_rec,  log_inv_up_dist_pred_resid_rec,
         log_inv_down_dist_x_HHI_pred_resid_rec, log_inv_up_dist_x_HHI_pred_resid_rec)

supplier_aggregate_production <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_aggregate_production_data.csv"),
  show_col_types = FALSE
)

K <- read_csv(
  file.path(DATA_DIR, "output/final/local_innovation_IVs.csv"),
  show_col_types = FALSE
)

# Sequential left joins with stopifnot() row-count checks after each merge.
# Row count should not increase (strict 1:1 or many:1 on the right side).
n0 <- nrow(patents)

data_analysis_final <- patents %>%
  left_join(supplier_third_country,
            by = c("Supplier_PSN" = "supplier", "Part" = "part",
                   "Year" = "year", "country_code" = "country"))
stopifnot(nrow(data_analysis_final) == n0)

data_analysis_final <- data_analysis_final %>%
  left_join(supplier_third_country_IV,
            by = c("Supplier_PSN" = "supplier", "Part" = "part",
                   "Year" = "year", "country_code" = "country"))
stopifnot(nrow(data_analysis_final) == n0)

data_analysis_final <- data_analysis_final %>%
  left_join(supplier_aggregate_production,
            by = c("Supplier_PSN", "Part", "Year"))
stopifnot(nrow(data_analysis_final) == n0)

data_analysis_final <- data_analysis_final %>%
  left_join(K, by = c("Supplier_PSN", "country_code", "Part", "Year"))
stopifnot(nrow(data_analysis_final) == n0)

################################################################################
## Derived Variables and Fixed Effects
################################################################################

data_analysis_final <- data_analysis_final %>%
  mutate(
    # Main outcome transforms
    log_prod             = log(prod_all),
    log_prod_x_HHI       = log_prod * HHI,
    log_inv_down_dist    = log(avg_inv_down_dist),
    log_inv_up_dist      = log(avg_inv_up_dist),
    log_inv_down_I_dist  = log(avg_inv_down_I_dist),
    log_inv_down_dist_x_HHI   = log_inv_down_dist   * HHI,
    log_inv_up_dist_x_HHI     = log_inv_up_dist     * HHI,
    log_inv_down_I_dist_x_HHI = log_inv_down_I_dist * HHI,
    # Bartik demand IV transforms
    log_prod_IV              = log(prod_all_IV),
    log_prod_IV_x_HHI_IV     = log_prod_IV * HHI_IV,
    log_prod_IV_alt          = log(prod_all_IV_alt),
    log_prod_IV_x_HHI_IV_alt = log_prod_IV_alt * HHI_IV_alt,
    # Fixed effect interaction strings
    firm_cntry_year_fe = paste0(Supplier_PSN, country_code, Year),
    firm_cntry_part_fe = paste0(Supplier_PSN, country_code, Part),
    firm_part_year_fe  = paste0(Supplier_PSN, Part, Year),
    part_cntry_year_fe = paste0(Part, country_code, Year),
    cntry_year_fe      = paste0(country_code, Year),
    part_year_fe       = paste0(Part, Year)   # NOTE: was paste0(country_code,Year) in original — bug fixed
  )

################################################################################
## Production IV First-Stage
################################################################################

# First stage: log production, HHI, and interaction instrumented by their
# Bartik IV counterparts (preferred spec: firm×country×part + part×country×year FE)
reg_prod_1 <- feols(
  log_prod ~ log_prod_IV + HHI_IV + log_prod_IV_x_HHI_IV |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = data_analysis_final, se = "cluster", cluster = "cntry_year_fe"
)
reg_prod_2 <- feols(
  HHI ~ log_prod_IV + HHI_IV + log_prod_IV_x_HHI_IV |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = data_analysis_final, se = "cluster", cluster = "cntry_year_fe"
)
reg_prod_3 <- feols(
  log_prod_x_HHI ~ log_prod_IV + HHI_IV + log_prod_IV_x_HHI_IV |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = data_analysis_final, se = "cluster", cluster = "cntry_year_fe"
)

data_analysis_final <- data_analysis_final %>%
  mutate(
    log_prod_pred            = predict(reg_prod_1, data_analysis_final),
    HHI_pred                 = predict(reg_prod_2, data_analysis_final),
    log_prod_x_HHI_pred      = predict(reg_prod_3, data_analysis_final),
    log_prod_pred_resid      = log_prod       - log_prod_pred,
    HHI_pred_resid           = HHI            - HHI_pred,
    log_prod_x_HHI_pred_resid = log_prod_x_HHI - log_prod_x_HHI_pred
  )

# Alternative spec: alt IV instruments (Bartik demand via production_agg_name_IV spec 2)
reg_prod_1_alt <- feols(
  log_prod ~ log_prod_IV_alt + HHI_IV_alt + log_prod_IV_x_HHI_IV_alt |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = data_analysis_final, se = "cluster", cluster = "cntry_year_fe"
)
reg_prod_2_alt <- feols(
  HHI ~ log_prod_IV_alt + HHI_IV_alt + log_prod_IV_x_HHI_IV_alt |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = data_analysis_final, se = "cluster", cluster = "cntry_year_fe"
)
reg_prod_3_alt <- feols(
  log_prod_x_HHI ~ log_prod_IV_alt + HHI_IV_alt + log_prod_IV_x_HHI_IV_alt |
    firm_cntry_part_fe + part_cntry_year_fe,
  data = data_analysis_final, se = "cluster", cluster = "cntry_year_fe"
)

data_analysis_final <- data_analysis_final %>%
  mutate(
    log_prod_pred_alt            = predict(reg_prod_1_alt, data_analysis_final),
    HHI_pred_alt                 = predict(reg_prod_2_alt, data_analysis_final),
    log_prod_x_HHI_pred_alt      = predict(reg_prod_3_alt, data_analysis_final),
    log_prod_pred_resid_alt      = log_prod       - log_prod_pred_alt,
    HHI_pred_resid_alt           = HHI            - HHI_pred_alt,
    log_prod_x_HHI_pred_resid_alt = log_prod_x_HHI - log_prod_x_HHI_pred_alt
  )

################################################################################
## Write Output
################################################################################

write_csv(data_analysis_final,
          file.path(DATA_DIR, "output/final/data_analysis_final.csv"))

message("data_final.R complete.")
