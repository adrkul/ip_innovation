# data_demand_IV.R
# Run from project root: Rscript Empirics/Code/data_demand_IV.R
#
# PURPOSE: Construct a Bartik-style IV for OEM demand shocks. For each
#   vehicle model, baseline export shares (first 5 observed years) are
#   interacted with destination-country GDP per capita trends to produce
#   a predicted demand instrument that is orthogonal to supply-side shocks.
#
# Requires:
#   [IHS_DIR]/Sales2024/Vehicle_Sales_Export_2000_2024.csv
#   [DATA_DIR]/other/World_Bank_gdppc.csv
#   [IHS_DIR]/Sales2024/production_agg_name.csv  (written if PRODUCTION_AGGREGATION = TRUE)
#
# Produces:
#   [IHS_DIR]/Sales2024/production_bilateral_name.csv
#   [IHS_DIR]/Sales2024/production_agg_name_IV.csv

rm(list = ls())

library(tidyverse)
library(fixest)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"
IHS_DIR  <- "/Users/adrkul/Library/CloudStorage/Dropbox/IHS_data"

################################################################################
## Aggregate Production Data to Bilateral Level
################################################################################

production_data <- read_delim(
  file.path(IHS_DIR, "Sales2024/Vehicle_Sales_Export_2000_2024.csv"),
  delim = ";", show_col_types = FALSE
)

production_data_bilateral <- production_data %>%
  mutate(across(c(`VP: Country/Territory`, `VP: Sales Group`, `VP: Global Nameplate`,
                  `VP: Platform`, `VP: Program`,
                  `VPE: Destination Country/Territory`), toupper)) %>%
  mutate(
    `VP: Country/Territory` = case_when(
      `VP: Country/Territory` == "RUSSIA"         ~ "RUSSIAN FEDERATION",
      `VP: Country/Territory` == "MAINLAND CHINA" ~ "CHINA",
      TRUE ~ `VP: Country/Territory`
    ),
    `VPE: Destination Country/Territory` = case_when(
      `VPE: Destination Country/Territory` == "RUSSIA"         ~ "RUSSIAN FEDERATION",
      `VPE: Destination Country/Territory` == "MAINLAND CHINA" ~ "CHINA",
      TRUE ~ `VPE: Destination Country/Territory`
    )
  ) %>%
  group_by(`VP: Country/Territory`, `VP: Production Brand`, `VP: Global Nameplate`,
           `VP: Platform`, `VP: Program`, `VPE: Destination Country/Territory`) %>%
  summarise(across(matches("^CY \\d{4}$"), \(x) sum(x, na.rm = TRUE)),
            .groups = "drop") %>%
  group_by(`VP: Country/Territory`, `VP: Production Brand`, `VP: Global Nameplate`,
           `VPE: Destination Country/Territory`) %>%
  summarise(across(matches("^CY \\d{4}$"), \(x) sum(x, na.rm = TRUE)),
            .groups = "drop") %>%
  pivot_longer(cols = matches("^CY \\d{4}$"), names_to = "Year", values_to = "Value") %>%
  mutate(Value = as.numeric(Value),
         Year  = as.numeric(substr(Year, 4, 7)))

write_csv(production_data_bilateral,
          file.path(IHS_DIR, "Sales2024/production_bilateral_name.csv"))

################################################################################
## Compute Baseline Export Shares
################################################################################

# For each model × destination, average share over first 5 non-zero years.
# These fixed baseline shares ensure the IV is not driven by contemporaneous
# demand responses at the destination level.
production_data_bilateral_baseline_share <- production_data_bilateral %>%
  filter(Value != 0) %>%
  group_by(`VP: Country/Territory`, `VP: Production Brand`, `VP: Global Nameplate`,
           `VPE: Destination Country/Territory`) %>%
  arrange(Year, .by_group = TRUE) %>%
  slice_head(n = 5) %>%
  summarise(Value = sum(Value), .groups = "drop") %>%
  group_by(`VP: Country/Territory`, `VP: Production Brand`, `VP: Global Nameplate`) %>%
  mutate(Share = Value / sum(Value)) %>%
  ungroup() %>%
  select(-Value)

################################################################################
## Compute Bartik IV
################################################################################

gdppc <- read_csv(file.path(DATA_DIR, "other/World_Bank_gdppc.csv"),
                  show_col_types = FALSE) %>%
  pivot_longer(cols = matches("\\d{4}$"), names_to = "Year", values_to = "GDP_pc") %>%
  mutate(Year = as.numeric(Year)) %>%
  select(`Country Name`, Year, GDP_pc) %>%
  mutate(`Country Name` = toupper(`Country Name`)) %>%
  mutate(`Country Name` = case_when(
    `Country Name` == "CZECHIA"                              ~ "CZECH REPUBLIC",
    `Country Name` == "BOSNIA AND HERZEGOVINA"               ~ "BOSNIA-HERZEGOVINA",
    `Country Name` == "EGYPT, ARAB REP."                     ~ "EGYPT",
    `Country Name` == "IRAN, ISLAMIC REP."                   ~ "IRAN",
    `Country Name` == "SLOVAK REPUBLIC"                      ~ "SLOVAKIA",
    `Country Name` == "KOREA, REP."                          ~ "SOUTH KOREA",
    `Country Name` == "TURKIYE"                              ~ "TURKEY",
    `Country Name` == "VENEZUELA, RB"                        ~ "VENEZUELA",
    `Country Name` == "VIET NAM"                             ~ "VIETNAM",
    TRUE ~ `Country Name`
  ))
# Note: Taiwan has no World Bank GDP data; those destinations get NA GDP_pc
# and are excluded from the IV sum (na.rm = TRUE in summarise below).

# For each model × origin × year: Bartik IV = sum over destinations of
# (baseline share × destination GDP). The "exc" variants exclude own-country
# flows to avoid simultaneity from the production country's own demand.
production_data_IV <- production_data_bilateral %>%
  left_join(production_data_bilateral_baseline_share,
            by = c("VP: Country/Territory", "VP: Production Brand",
                   "VP: Global Nameplate", "VPE: Destination Country/Territory")) %>%
  left_join(gdppc,
            by = c("VPE: Destination Country/Territory" = "Country Name",
                   "Year")) %>%
  group_by(`VP: Country/Territory`, `VP: Production Brand`,
           `VP: Global Nameplate`, `VPE: Destination Country/Territory`) %>%
  arrange(Year, .by_group = TRUE) %>%
  filter(Value != 0) %>%
  slice(-1:-5) %>%   # drop baseline years used to construct shares
  group_by(`VP: Country/Territory`, `VP: Production Brand`,
           `VP: Global Nameplate`, Year) %>%
  summarise(
    sum_accounted     = sum(Share * (!is.na(GDP_pc))),
    Value_IV          = sum(Share * GDP_pc, na.rm = TRUE),
    sum_accounted_exc = sum(Share * (!is.na(GDP_pc) &
                              (`VP: Country/Territory` != `VPE: Destination Country/Territory`))),
    Value_IV_exc      = sum((Share * GDP_pc)[
                              `VP: Country/Territory` != `VPE: Destination Country/Territory`],
                            na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(Year < 2024, Value_IV > 0)

################################################################################
## First-Stage Regression
################################################################################

production_data_agg_global_name <- read_csv(
  file.path(IHS_DIR, "Sales2024/production_agg_name.csv"),
  show_col_types = FALSE
) %>%
  pivot_longer(cols = matches("^CY \\d{4}$"), names_to = "Year", values_to = "Value") %>%
  mutate(Year = as.numeric(substr(Year, 4, 7))) %>%
  filter(Value != 0)

IV_data <- production_data_agg_global_name %>%
  left_join(production_data_IV,
            by = c("VP: Country/Territory", "VP: Production Brand",
                   "VP: Global Nameplate", "Year")) %>%
  rename(Country = `VP: Country/Territory`,
         Brand   = `VP: Production Brand`,
         Model   = `VP: Global Nameplate`) %>%
  mutate(
    Country_Year_fe         = paste0(Country, Year),
    Brand_Country_Year_fe   = paste0(Brand, Country, Year),
    log_Value_IV            = log(Value_IV),
    log_Value_IV_exc        = log(Value_IV_exc),
    log_Value               = log(Value)
  ) %>%
  filter(Value > 100)

# Five first-stage specifications varying fixed effects and sample exclusion
reg_1 <- feols(log_Value ~ log_Value_IV               | Model,   data = IV_data,
               se = "cluster", cluster = "Brand_Country_Year_fe")
reg_2 <- feols(log_Value ~ log_Value_IV + sum_accounted | Model, data = IV_data,
               se = "cluster", cluster = "Brand_Country_Year_fe")
reg_3 <- feols(log_Value ~ log_Value_IV_exc            | Model,  data = IV_data,
               se = "cluster", cluster = "Brand_Country_Year_fe")
reg_4 <- feols(log_Value ~ log_Value_IV_exc + sum_accounted_exc | Model, data = IV_data,
               se = "cluster", cluster = "Brand_Country_Year_fe")
reg_5 <- feols(log_Value ~ log_Value_IV_exc + sum_accounted_exc | 1,    data = IV_data,
               se = "cluster", cluster = "Brand_Country_Year_fe")

# Predicted values from preferred specs (reg_4 = model FE + exc; reg_3 = model FE;
# reg_5 = no FE, used as robustness)
IV_data$log_Value_1_predicted <- predict(reg_4, IV_data)
IV_data$log_Value_2_predicted <- predict(reg_3, IV_data)
IV_data$log_Value_3_predicted <- predict(reg_5, IV_data)

IV_data <- IV_data %>%
  select(Country, `VP: Strategic Group`, Brand, Model, Year,
         log_Value_1_predicted, log_Value_2_predicted, log_Value_3_predicted)

write_csv(IV_data,
          file.path(IHS_DIR, "Sales2024/production_agg_name_IV.csv"))

message("data_demand_IV.R complete.")
