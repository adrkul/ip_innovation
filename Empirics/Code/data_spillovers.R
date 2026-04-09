# data_spillovers.R
# Run from project root: Rscript Empirics/Code/data_spillovers.R
#
# PURPOSE: Construct local-innovation IV (spillover instrument) for the
#   knowledge-stock regressions. For each supplier × country × part × year,
#   computes the leave-one-out and aggregate predicted innovation from other
#   suppliers in the same country-part, instrumented by the Bartik demand IV
#   (prod_all_IV from supplier_aggregate_production_data.csv).
#
# Requires:
#   [DATA_DIR]/output/final/data_supplier_patents.csv
#   [DATA_DIR]/output/final/data_buyer_patents.csv
#   [DATA_DIR]/output/final/supplier_OEM_flows_data.csv
#   [DATA_DIR]/output/final/supplier_aggregate_production_data.csv
#
# Produces:
#   [DATA_DIR]/output/final/local_innovation_IVs.csv

rm(list = ls())

library(tidyverse)
library(fixest)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"

eu_countries <- c(
  "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST",
  "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
  "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
  "SVN", "ESP", "SWE"
)

################################################################################
## Local Innovation Aggregates
################################################################################

# Supplier-level patent panel
patents <- read_csv(
  file.path(DATA_DIR, "output/final/data_supplier_patents.csv"),
  show_col_types = FALSE
)

# Country × Part × Year totals for supplier patents
data_supplier_patents_agg <- patents %>%
  group_by(Year, country_code, Part) %>%
  summarise(count_roll_supplier = sum(count_roll, na.rm = TRUE), .groups = "drop")

# Country × Part × Year totals for buyer patents
data_buyer_patents_agg <- read_csv(
  file.path(DATA_DIR, "output/final/data_buyer_patents.csv"),
  show_col_types = FALSE
) %>%
  group_by(Year, country_code, Part) %>%
  summarise(count_roll_buyer = sum(count_roll, na.rm = TRUE), .groups = "drop")

# Combined local stock: supplier + buyer patents in same country-part-year
data_patents_agg <- data_supplier_patents_agg %>%
  full_join(data_buyer_patents_agg, by = c("Year", "country_code", "Part")) %>%
  mutate(
    count_roll_buyer    = if_else(is.na(count_roll_buyer),    0, count_roll_buyer),
    count_roll_supplier = if_else(is.na(count_roll_supplier), 0, count_roll_supplier),
    count_roll_agg      = count_roll_buyer + count_roll_supplier
  )

################################################################################
## Bartik Demand IV: Aggregate and Leave-One-Out Production
################################################################################

supplier_OEM_flows <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_OEM_flows_data.csv"),
  show_col_types = FALSE
)

# Country × Part × Year demand IV aggregates (leave-one-out removes own firm)
supplier_IV_agg <- supplier_OEM_flows %>%
  group_by(Supplier_PSN, country_code_supplier, Part, Year) %>%
  summarise(Value_IV = sum(Value_IV, na.rm = TRUE), .groups = "drop") %>%
  group_by(country_code_supplier, Part, Year) %>%
  mutate(Value_IV_agg_rm = sum(Value_IV, na.rm = TRUE) - Value_IV) %>%
  ungroup()

# EU aggregate (treat all EU members as one region under "EPP")
supplier_IV_agg_EU <- supplier_OEM_flows %>%
  filter(country_code_supplier %in% eu_countries) %>%
  group_by(Supplier_PSN, country_code_supplier, Part, Year) %>%
  summarise(Value_IV = sum(Value_IV, na.rm = TRUE), .groups = "drop") %>%
  group_by(country_code_supplier, Part, Year) %>%
  mutate(Value_IV_agg_rm = sum(Value_IV, na.rm = TRUE) - Value_IV) %>%
  mutate(country_code_supplier = "EPP") %>%
  ungroup()

supplier_IV_agg <- bind_rows(supplier_IV_agg, supplier_IV_agg_EU)

################################################################################
## Firm-Level Panel and First-Stage Regressions
################################################################################

supplier_aggregate_production <- read_csv(
  file.path(DATA_DIR, "output/final/supplier_aggregate_production_data.csv"),
  show_col_types = FALSE
)

df_firms <- patents %>%
  left_join(supplier_aggregate_production,
            by = c("Supplier_PSN", "Year", "Part")) %>%
  group_by(Country, Part, Year) %>%
  mutate(
    agg_prod_IV    = sum(prod_all_IV, na.rm = TRUE),
    agg_prod_IV_rm = agg_prod_IV - prod_all_IV   # leave-one-out
  ) %>%
  ungroup() %>%
  left_join(data_patents_agg, by = c("Year", "country_code", "Part")) %>%
  mutate(
    count_roll_rm      = count_roll_agg - count_roll,  # leave-one-out knowledge stock
    firm_cntry_part_fe = paste0(Supplier_PSN, country_code, Part),
    cntry_year_fe      = paste0(country_code, Year),
    part_year_fe       = paste0(Part, Year)
  )

# Three first-stage specifications for the local spillover IV:
# reg_1: leave-one-out knowledge ~ leave-one-out IV, firm×country×part FE
# reg_2: same + country×year and part×year FE
# reg_3: aggregate knowledge ~ aggregate IV (for robustness)
reg_1 <- feols(log(count_roll_rm) ~ log(agg_prod_IV_rm) | firm_cntry_part_fe,
               data = df_firms, se = "cluster", cluster = "cntry_year_fe")

reg_2 <- feols(log(count_roll_rm) ~ log(agg_prod_IV_rm) |
                 cntry_year_fe + part_year_fe + firm_cntry_part_fe,
               data = df_firms, se = "cluster", cluster = "cntry_year_fe")

reg_3 <- feols(log(count_roll_agg) ~ log(agg_prod_IV) |
                 cntry_year_fe + part_year_fe + firm_cntry_part_fe,
               data = df_firms, se = "cluster", cluster = "cntry_year_fe")

# Attach predicted values and control-function residuals
df_firms <- df_firms %>%
  mutate(
    log_IV_pred         = predict(reg_1, df_firms),
    log_IV_pred_b       = predict(reg_2, df_firms),
    log_IV_pred_c       = predict(reg_3, df_firms),
    log_IV_pred_resid   = log(count_roll_rm)  - log_IV_pred,
    log_IV_pred_b_resid = log(count_roll_rm)  - log_IV_pred_b,
    log_IV_pred_c_resid = log(count_roll_agg) - log_IV_pred_c
  )

################################################################################
## Write Output
################################################################################

df_export <- df_firms %>%
  select(Supplier_PSN, country_code, Part, Year,
         log_IV_pred, log_IV_pred_b, log_IV_pred_c,
         count_roll_agg,
         log_IV_pred_resid, log_IV_pred_b_resid, log_IV_pred_c_resid) %>%
  rename(
    log_K_IV_1        = log_IV_pred,
    log_K_IV_2        = log_IV_pred_b,
    log_K_IV_3        = log_IV_pred_c,
    K                 = count_roll_agg,
    log_K_IV_1_resid  = log_IV_pred_resid,
    log_K_IV_2_resid  = log_IV_pred_b_resid,
    log_K_IV_3_resid  = log_IV_pred_c_resid
  )

write_csv(df_export,
          file.path(DATA_DIR, "output/final/local_innovation_IVs.csv"))

message("data_spillovers.R complete.")
