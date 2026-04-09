# data_revelio.R
# Run from project root: Rscript Empirics/Code/data_revelio.R
#
# PURPOSE: Process Revelio Labs LinkedIn employment data to construct
#   engineering workforce measures by supplier firm, country, and year.
#   Produces four output files: total workers, engineers, engineers by
#   product/process type, and engineers by auto-part category (using
#   a manually curated job-role-to-part mapping).
#
# Requires:
#   [DATA_DIR]/linkdin/revelio_position_data_updated.csv
#   [DATA_DIR]/linkdin/engineering_position_part_mapping_manual.csv
#   [DATA_DIR]/linkdin/larger_match_pool.csv
#   [DATA_DIR]/other/country_codes.csv
#
# Produces:
#   [DATA_DIR]/output/final/revelio_workers_total.csv
#   [DATA_DIR]/output/final/revelio_workers_engineers.csv
#   [DATA_DIR]/output/final/revelio_workers_engineers_type.csv
#   [DATA_DIR]/output/final/revelio_workers.csv

rm(list = ls())

library(tidyverse)
library(data.table)
library(lubridate)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"

################################################################################
## Load and Expand Position Data to Annual Panel
################################################################################

position_data <- read_csv(
  file.path(DATA_DIR, "linkdin/revelio_position_data_updated.csv"),
  show_col_types = FALSE
)

# Expand each employment spell to one row per calendar year
position_dt <- setDT(copy(as.data.table(position_data)))
position_dt[, `:=`(
  start_year = year(startdate),
  end_year   = year(enddate)
)]

expanded_data <- position_dt[
  , .(year = seq(start_year[1], end_year[1])),
  by = .(user_id, rcid, country, role_k1500_v2, role_k17000_v3, start_year, end_year)
]

df_panel <- as_tibble(expanded_data)

################################################################################
## Support Files
################################################################################

# Manual mapping of Revelio job role titles to automotive parts
df_matches_raw <- read_csv(
  file.path(DATA_DIR, "linkdin/engineering_position_part_mapping_manual.csv"),
  show_col_types = FALSE
) %>%
  mutate(Raw_Score = if_else(is.na(as.numeric(Freq)), 1, Raw_Score))

df_matches_filtered <- df_matches_raw %>%
  filter(Raw_Score > 0.6) %>%
  select(Var1, Primary_Match)

# Revelio-to-IHS firm name matching pool
firm_names <- read_csv(
  file.path(DATA_DIR, "linkdin/larger_match_pool.csv"),
  show_col_types = FALSE
)

# ISO3 code lookup with IHS-format country names
country_codes <- read_csv(
  file.path(DATA_DIR, "other/country_codes.csv"),
  show_col_types = FALSE
) %>%
  select(Country, `Alpha-3 code`) %>%
  rename(country_code = `Alpha-3 code`) %>%
  mutate(Country = toupper(Country)) %>%
  mutate(Country = case_when(
    Country == "UNITED STATES OF AMERICA" ~ "UNITED STATES",
    Country == "KOREA, REPUBLIC OF"       ~ "SOUTH KOREA",
    Country == "VIET NAM"                 ~ "VIETNAM",
    Country == "BOSNIA AND HERZEGOVINA"   ~ "BOSNIA-HERZEGOVINA",
    TRUE ~ Country
  ))

################################################################################
## Total Workers: All Positions
################################################################################

revelio_total <- df_panel %>%
  left_join(firm_names, by = "rcid") %>%
  rename(PSN = Supplier_PSN) %>%
  group_by(PSN, country, year) %>%
  summarise(n = n_distinct(user_id), .groups = "drop") %>%
  group_by(PSN, country) %>%
  mutate(n_total = sum(n)) %>%
  ungroup() %>%
  mutate(country = toupper(country)) %>%
  left_join(country_codes, by = c("country" = "Country")) %>%
  select(PSN, country_code, year, n, n_total)

write_csv(revelio_total,
          file.path(DATA_DIR, "output/final/revelio_workers_total.csv"))

################################################################################
## Engineers: Roles with "Engineer" in Title
################################################################################

revelio_engineers <- df_panel %>%
  filter(grepl("Engineer", role_k17000_v3)) %>%
  left_join(firm_names, by = "rcid") %>%
  rename(PSN = Supplier_PSN) %>%
  group_by(PSN, country, year) %>%
  summarise(n = n_distinct(user_id), .groups = "drop") %>%
  group_by(PSN, country) %>%
  mutate(n_total = sum(n)) %>%
  ungroup() %>%
  mutate(country = toupper(country)) %>%
  left_join(country_codes, by = c("country" = "Country")) %>%
  select(PSN, country_code, year, n, n_total)

# Total employees as denominator (BUG FIX: original code referenced n_0/n_0_total
# which were undefined; renamed here from n/n_total to avoid collision on join)
revelio_total_denom <- revelio_total %>%
  rename(n_0 = n, n_0_total = n_total)

revelio_engineers <- revelio_engineers %>%
  left_join(revelio_total_denom, by = c("PSN", "country_code", "year"))

write_csv(revelio_engineers,
          file.path(DATA_DIR, "output/final/revelio_workers_engineers.csv"))

################################################################################
## Engineers by Type: Product vs Process
################################################################################

type_product <- c("Product Design Engineer", "Development Engineer")
type_process <- c("Manufacturing Engineer", "Process Engineering Specialist",
                  "Production Engineer")

revelio_engineers_type <- df_panel %>%
  mutate(type = case_when(
    role_k17000_v3 %in% type_product ~ "Product",
    role_k17000_v3 %in% type_process ~ "Process",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(type)) %>%
  left_join(firm_names, by = "rcid") %>%
  rename(PSN = Supplier_PSN) %>%
  group_by(PSN, country, year, type) %>%
  summarise(n = n_distinct(user_id), .groups = "drop") %>%
  mutate(country = toupper(country)) %>%
  left_join(country_codes, by = c("country" = "Country")) %>%
  select(PSN, country_code, year, type, n) %>%
  filter(!is.na(country_code)) %>%
  pivot_wider(names_from = type, values_from = n)

write_csv(revelio_engineers_type,
          file.path(DATA_DIR, "output/final/revelio_workers_engineers_type.csv"))

################################################################################
## Engineers by Auto-Part Category
################################################################################

revelio_by_part <- df_panel %>%
  left_join(df_matches_filtered, by = c("role_k17000_v3" = "Var1")) %>%
  left_join(firm_names, by = "rcid") %>%
  rename(PSN = Supplier_PSN, Part = Primary_Match) %>%
  group_by(PSN, Part, country, year) %>%
  summarise(n = n_distinct(user_id), .groups = "drop") %>%
  group_by(PSN, Part, country) %>%
  mutate(n_total = sum(n)) %>%
  ungroup() %>%
  mutate(country = toupper(country)) %>%
  left_join(country_codes, by = c("country" = "Country")) %>%
  select(PSN, Part, country_code, year, n, n_total)

write_csv(revelio_by_part,
          file.path(DATA_DIR, "output/final/revelio_workers.csv"))

message("data_revelio.R complete.")
