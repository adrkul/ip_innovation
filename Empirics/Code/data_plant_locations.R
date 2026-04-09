# data_plant_locations.R
# Run from project root: Rscript Empirics/Code/data_plant_locations.R
#
# PURPOSE: Build supplier-OEM plant location linkages, aggregate production
#   flows to the bilateral supplier-country × buyer-country level, and compute
#   third-country proximity measures (upstream production and downstream demand)
#   used as the main outcome variables in the analysis.
#   Set PRODUCTION_AGGREGATION = TRUE to rebuild from raw IHS files (slow);
#   FALSE reads the cached aggregate CSV.
#
# Requires:
#   [DATA_DIR]/output/intmd/IHS_plant_wsw_correspondence_manual.csv
#   [DATA_DIR]/output/intmd/IHS_marklines_part_correspondence_manual.csv
#   [DATA_DIR]/output/final/IHS_to_PRODUCTION_correspondence_name.csv
#   [DATA_DIR]/output/intmd/IHS_PATSTAT_who_supply_who.csv
#   [IHS_DIR]/Sales2024/Vehicle_Sales_Export_2000_2024.csv  (if PRODUCTION_AGGREGATION = TRUE)
#   [IHS_DIR]/Sales2024/production_agg_name.csv             (if PRODUCTION_AGGREGATION = FALSE)
#   [IHS_DIR]/Sales2024/production_agg_name_IV.csv
#   [DATA_DIR]/output/final/data_buyer_patents.csv
#   [DATA_DIR]/output/final/data_supplier_patents.csv
#   [DATA_DIR]/other/country_codes.csv
#   [DATA_DIR]/other/dist_cepii.dta
#
# Produces:
#   [DATA_DIR]/output/final/cepii_distance_pairs.csv
#   [DATA_DIR]/output/final/supplier_part_destination_source.csv
#   [DATA_DIR]/output/final/supplier_aggregate_production_data.csv
#   [DATA_DIR]/output/final/supplier_OEM_production_data.csv
#   [DATA_DIR]/output/final/supplier_OEM_flows_data.csv
#   [DATA_DIR]/output/final/supplier_third_country_proximity.csv
#   [DATA_DIR]/output/final/supplier_buyer_third_country_proximity.csv
#   [DATA_DIR]/output/final/supplier_buyer_third_country_I_destination.csv
#   [DATA_DIR]/output/final/supplier_buyer_transaction_I_source.csv
#   [DATA_DIR]/output/final/supplier_buyer_transaction_I_source_min.csv
#   [DATA_DIR]/output/final/buyer_third_country_proximity.csv
#   [DATA_DIR]/output/final/OEM_country_production_data.csv
#   [DATA_DIR]/output/final/OEM_production_bilateral_data.csv

rm(list = ls())

library(tidyverse)
library(haven)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"
IHS_DIR  <- "/Users/adrkul/Library/CloudStorage/Dropbox/IHS_data"

# Set TRUE to rebuild production aggregates from raw IHS file (slow);
# FALSE reads cached CSV
PRODUCTION_AGGREGATION <- FALSE

# Fuzzy match threshold for linking IHS plants to WSW entries.
# Only observations with score_firm > MATCH_THRESHOLD and
# score_part > MATCH_THRESHOLD are kept. Threshold of 0.85 reflects the
# minimum string similarity at which manual inspection found acceptable matches.
MATCH_THRESHOLD <- 0.85

################################################################################
## OEM Production Data
################################################################################

if (PRODUCTION_AGGREGATION) {

  production_data <- read_delim(
    file.path(IHS_DIR, "Sales2024/Vehicle_Sales_Export_2000_2024.csv"),
    delim = ";", show_col_types = FALSE
  )
  write_csv(
    tibble(OEM_name = unique(production_data$`VP: Production Brand`)),
    file.path(DATA_DIR, "output/intmd/OEM_names.csv")
  )

  production_data_agg_global_name <- production_data %>%
    mutate(across(c(`VP: Country/Territory`, `VP: Sales Group`, `VP: Global Nameplate`,
                    `VP: Platform`, `VP: Program`, `VP: Strategic Group`), toupper)) %>%
    mutate(`VP: Country/Territory` = case_when(
      `VP: Country/Territory` == "RUSSIA"         ~ "RUSSIAN FEDERATION",
      `VP: Country/Territory` == "MAINLAND CHINA" ~ "CHINA",
      TRUE ~ `VP: Country/Territory`
    )) %>%
    group_by(`VP: Country/Territory`, `VP: Production Brand`, `VP: Strategic Group`,
             `VP: Global Nameplate`, `VP: Platform`, `VP: Program`) %>%
    summarise(across(matches("^CY \\d{4}$"), sum, na.rm = TRUE), .groups = "drop") %>%
    group_by(`VP: Country/Territory`, `VP: Strategic Group`,
             `VP: Production Brand`, `VP: Global Nameplate`) %>%
    summarise(across(matches("^CY \\d{4}$"), sum, na.rm = TRUE), .groups = "drop")

  write_csv(production_data_agg_global_name,
            file.path(IHS_DIR, "Sales2024/production_agg_name.csv"))

} else {

  production_data_agg_global_name <- read_csv(
    file.path(IHS_DIR, "Sales2024/production_agg_name.csv"),
    show_col_types = FALSE
  )

}

# Load Bartik IV predictions (produced by data_demand_IV.R)
production_data_IV <- read_csv(
  file.path(IHS_DIR, "Sales2024/production_agg_name_IV.csv"),
  show_col_types = FALSE
) %>%
  select(Country, Brand, Model, Year,
         log_Value_1_predicted, log_Value_2_predicted, log_Value_3_predicted) %>%
  mutate(
    Value_IV      = exp(log_Value_1_predicted),   # preferred IV spec
    Value_IV_alt  = exp(log_Value_2_predicted),
    Value_IV_alt_2 = exp(log_Value_3_predicted)
  ) %>%
  select(-log_Value_1_predicted, -log_Value_2_predicted, -log_Value_3_predicted) %>%
  mutate(Brand = toupper(Brand), Model = toupper(Model))

# Pivot production data to long format and merge IV predictions
production_data_agg_global_name <- production_data_agg_global_name %>%
  pivot_longer(cols = matches("^CY \\d{4}$"), names_to = "Year", values_to = "Value") %>%
  mutate(Value = as.numeric(Value),
         Year  = as.numeric(substr(Year, 4, 7)),
         Brand = toupper(`VP: Production Brand`),
         Model = toupper(`VP: Global Nameplate`)) %>%
  left_join(production_data_IV,
            by = c("VP: Country/Territory" = "Country",
                   "Brand" = "Brand",
                   "Model" = "Model",
                   "Year"  = "Year")) %>%
  select(-Brand, -Model)

################################################################################
## Supplier Plant Location Data
################################################################################

matched_plant_data <- read_csv(
  file.path(DATA_DIR, "output/intmd/IHS_plant_wsw_correspondence_manual.csv"),
  show_col_types = FALSE
) %>%
  rename(PSN_matched = Supplier_PSN_1) %>%
  select(PSN_matched, Country, Match_Manual, score_firm, score_part) %>%
  filter(score_firm > MATCH_THRESHOLD) %>%
  filter(score_part > MATCH_THRESHOLD) %>%
  filter(!is.na(PSN_matched)) %>%
  filter(!is.na(Match_Manual)) %>%
  rename(Part = Match_Manual) %>%
  select(-score_firm, -score_part) %>%
  mutate(Country = toupper(Country)) %>%
  distinct()

################################################################################
## WSW Linkage and Part Categories
################################################################################

# Part categories from IHS marklines-to-WSW manual mapping
ihs_part_groups <- read_csv(
  file.path(DATA_DIR, "output/intmd/IHS_marklines_part_correspondence_manual.csv"),
  show_col_types = FALSE
)

# IHS to production model name linkage (fuzzy matched; filter to score >= 0.90)
prod_links_name <- read_csv(
  file.path(DATA_DIR, "output/final/IHS_to_PRODUCTION_correspondence_name.csv"),
  show_col_types = FALSE
) %>%
  mutate(score = if_else(`VP: Country/Territory` != COUNTRY, 0, score)) %>%
  filter(score >= 0.90)

# WSW supplier-OEM linkage with standardized part categories
data_linkages <- read_csv(
  file.path(DATA_DIR, "output/intmd/IHS_PATSTAT_who_supply_who.csv"),
  show_col_types = FALSE
) %>%
  left_join(ihs_part_groups, by = c("Part_full" = "Match_Tilte")) %>%
  select(-Part) %>%
  rename(Part = Match_Manual) %>%
  filter(Part != "Other")

################################################################################
## Country Code Lookup
################################################################################

# ISO3 codes matched to the uppercase country names used in IHS production data
country_codes <- read_csv(
  file.path(DATA_DIR, "other/country_codes.csv"),
  show_col_types = FALSE
) %>%
  select(Country, `Alpha-3 code`) %>%
  rename(country_code = `Alpha-3 code`) %>%
  mutate(Country = toupper(Country)) %>%
  mutate(Country = case_when(
    Country == "USA"                      ~ "UNITED STATES",
    Country == "UK"                       ~ "UNITED KINGDOM",
    Country == "KOREA"                    ~ "SOUTH KOREA",
    Country == "RUSSIA"                   ~ "RUSSIAN FEDERATION",
    Country == "VIET NAM"                 ~ "VIETNAM",
    Country == "BOSNIA AND HERZEGOVINA"   ~ "BOSNIA-HERZEGOVINA",
    TRUE ~ Country
  ))

# Attach country codes to buyer production data
buyer_data <- production_data_agg_global_name %>%
  mutate(country_buyer = `VP: Country/Territory`) %>%
  left_join(country_codes, by = c("country_buyer" = "Country")) %>%
  rename(country_code_buyer = country_code) %>%
  select(-country_buyer)

message("Unmatched buyer locations: ",
        round(mean(is.na(buyer_data$country_code_buyer)) * 100, 1), "%")

# Attach country codes to supplier plant data (with additional manual name fixes)
supplier_data <- matched_plant_data %>%
  filter(Part != "Other") %>%
  mutate(country_supplier = Country) %>%
  mutate(country_supplier = case_when(
    country_supplier == "MOLDOVA"                          ~ "MOLDOVA (THE REPUBLIC OF)",
    country_supplier == "MACEDONIA"                        ~ "REPUBLIC OF NORTH MACEDONIA",
    country_supplier == "RUSSIA"                           ~ "RUSSIAN FEDERATION",
    country_supplier == "SWAZILAND"                        ~ "ESWATINI",
    country_supplier == "LAO PEOPLE'S DEMOCRATIC REPUBLIC" ~ "LAO PEOPLE'S DEMOCRATIC REPUBLIC (THE)",
    country_supplier == "UNITED ARAB EMIRATES"             ~ "UNITED ARAB EMIRATES (THE)",
    TRUE ~ country_supplier
  )) %>%
  left_join(country_codes, by = c("country_supplier" = "Country")) %>%
  rename(country_code_supplier = country_code) %>%
  select(-country_supplier)

message("Unmatched supplier locations: ",
        round(mean(is.na(supplier_data$country_code_supplier)) * 100, 1), "%")

prod_links_name <- prod_links_name %>%
  left_join(country_codes, by = c("COUNTRY" = "Country"))

################################################################################
## CEPII Distance Pairs
################################################################################

data_dist <- read_dta(file.path(DATA_DIR, "other/dist_cepii.dta")) %>%
  # Update obsolete ISO3 codes
  mutate(iso_o = if_else(iso_o == "ROM", "ROU", iso_o),
         iso_d = if_else(iso_d == "ROM", "ROU", iso_d),
         iso_o = if_else(iso_o == "YUG", "SRB", iso_o),
         iso_d = if_else(iso_d == "YUG", "SRB", iso_d))

# Union of all buyer and supplier country codes in the data
final_codes <- tibble(
  country_code = c(
    buyer_data$country_code_buyer[!is.na(buyer_data$country_code_buyer)],
    supplier_data$country_code_supplier[!is.na(supplier_data$country_code_supplier)]
  ) %>% unique() %>% sort()
)

# Build o × d distance matrix restricted to countries in our data
prod_fill <- final_codes %>%
  left_join(data_dist %>% select(iso_o, iso_d, distw),
            by = c("country_code" = "iso_o"))

# Log countries with no distance data (dropped from analysis)
dropped_countries <- prod_fill %>%
  group_by(country_code) %>%
  summarise(missing = mean(is.na(distw)), .groups = "drop") %>%
  filter(missing == 1) %>%
  left_join(country_codes, by = "country_code")

message("Dropped countries (no CEPII distance): ",
        paste(dropped_countries$Country, collapse = ", "))

final_codes <- final_codes %>%
  filter(!(country_code %in% dropped_countries$country_code))

prod_fill <- prod_fill %>%
  filter(!is.na(distw)) %>%
  filter(iso_d %in% final_codes$country_code) %>%
  rename(country_code_o = country_code, country_code_d = iso_d)

# EU aggregate: average distance from all EU member states to each destination
eu_countries <- c(
  "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST",
  "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
  "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
  "SVN", "ESP", "SWE"
)

prod_fill_EU <- prod_fill %>%
  mutate(EU_o = if_else(country_code_o %in% eu_countries, 1, 0)) %>%
  group_by(EU_o, country_code_d) %>%
  summarise(distw = mean(distw), .groups = "drop") %>%
  filter(EU_o == 1) %>%
  mutate(country_code_o = "EPP") %>%
  select(country_code_o, country_code_d, distw)

prod_fill <- bind_rows(prod_fill, prod_fill_EU)

write_csv(prod_fill,
          file.path(DATA_DIR, "output/final/cepii_distance_pairs.csv"))

################################################################################
## Supplier × Part × Destination Source
################################################################################

suppliers <- sort(unique(supplier_data$PSN_matched))
parts     <- sort(unique(supplier_data$Part))
countries <- final_codes$country_code

# Full supplier × part × destination grid
supplier_part_destination <- tibble(
  expand.grid(supplier = suppliers, part = parts, country = countries,
              stringsAsFactors = FALSE)
)

# For each (supplier, part, destination) find the closest production origin
supplier_part_destination_source <- supplier_part_destination %>%
  left_join(prod_fill, by = c("country" = "country_code_d")) %>%
  left_join(supplier_data %>% mutate(match = 1),
            by = c("supplier" = "PSN_matched", "part" = "Part",
                   "country_code_o" = "country_code_supplier")) %>%
  mutate(match = if_else(is.na(match), 0, match)) %>%
  filter(match == 1) %>%
  group_by(supplier, part, country) %>%
  mutate(dist_avg = mean(distw, na.rm = TRUE)) %>%
  slice(which.min(distw)) %>%
  ungroup() %>%
  rename(dist_min = distw, country_code_buyer = country,
         country_code_supplier = country_code_o) %>%
  select(supplier, part, country_code_supplier, country_code_buyer,
         dist_min, dist_avg) %>%
  complete(supplier, part, country_code_buyer,
           fill = list(dist_min = Inf, dist_avg = Inf,
                       country_code_supplier = "NAN"))

write_csv(supplier_part_destination_source,
          file.path(DATA_DIR, "output/final/supplier_part_destination_source.csv"))

################################################################################
## Supplier-Part-Year-Buyer Production Flows
################################################################################

supplier_part_year_buyer_destination <- data_linkages %>%
  left_join(prod_links_name,
            by = c("COUNTRY", "BRAND_NAME", "MODEL")) %>%
  select(Supplier_PSN_1, Part, `VP: Production Brand`, `VP: Global Nameplate`,
         `VP: Country/Territory`, Part_full, SUPPLIERS_COMPONENT_DESCRIPTION) %>%
  distinct() %>%
  left_join(buyer_data,
            by = c("VP: Production Brand", "VP: Global Nameplate",
                   "VP: Country/Territory")) %>%
  group_by(Supplier_PSN_1, Part, Year, `VP: Strategic Group`, country_code_buyer) %>%
  summarise(
    Value         = sum(Value,         na.rm = TRUE),
    Value_IV      = sum(Value_IV,      na.rm = TRUE),
    Value_IV_alt  = sum(Value_IV_alt_2, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(!is.na(Supplier_PSN_1), !is.na(Part), !is.na(Year))

# Attach closest production origin
supplier_part_year_buyer_destination_source <- supplier_part_year_buyer_destination %>%
  left_join(supplier_part_destination_source,
            by = c("Supplier_PSN_1" = "supplier", "Part" = "part",
                   "country_code_buyer" = "country_code_buyer")) %>%
  rename(Supplier_PSN = Supplier_PSN_1, OEM = `VP: Strategic Group`)
# Note: NA country_code_supplier = no plant data for this firm
#       "NAN" country_code_supplier = firm has other plants but not for this part

################################################################################
## Production Aggregations
################################################################################

# Supplier × Part × Year aggregates (with HHI for buyer market concentration)
supplier_aggregate_production_data <- supplier_part_year_buyer_destination_source %>%
  group_by(Supplier_PSN, Part, Year, OEM) %>%
  summarise(
    Value        = sum(Value,        na.rm = TRUE),
    Value_IV     = sum(Value_IV,     na.rm = TRUE),
    Value_IV_alt = sum(Value_IV_alt, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(Supplier_PSN, Part, Year) %>%
  summarise(
    prod_all         = sum(Value),
    prod_all_IV      = sum(Value_IV),
    prod_all_IV_alt  = sum(Value_IV_alt),
    HHI              = sum((Value / prod_all)^2),
    HHI_IV           = sum((Value_IV / prod_all_IV)^2),
    HHI_IV_alt       = sum((Value_IV_alt / prod_all_IV_alt)^2),
    N_buyers         = sum(Value > 0),
    .groups = "drop"
  )

write_csv(supplier_aggregate_production_data,
          file.path(DATA_DIR, "output/final/supplier_aggregate_production_data.csv"))

# Supplier × Part × Year × OEM production
supplier_OEM_production_data <- supplier_part_year_buyer_destination_source %>%
  group_by(Supplier_PSN, Part, Year, OEM) %>%
  mutate(Value = sum(Value, na.rm = TRUE)) %>%
  ungroup()

write_csv(supplier_OEM_production_data,
          file.path(DATA_DIR, "output/final/supplier_OEM_production_data.csv"))

# Bilateral flows: Supplier × Part × Year × OEM × Origin-Country × Destination-Country
supplier_OEM_flows_data <- supplier_part_year_buyer_destination_source %>%
  group_by(Supplier_PSN, Part, Year, OEM,
           country_code_supplier, country_code_buyer) %>%
  summarise(
    Value    = sum(Value,    na.rm = TRUE),
    Value_IV = sum(Value_IV, na.rm = TRUE),
    dist_min = mean(dist_min, na.rm = TRUE),
    dist_avg = mean(dist_avg, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(supplier_OEM_flows_data,
          file.path(DATA_DIR, "output/final/supplier_OEM_flows_data.csv"))

################################################################################
## Buyer Innovation Proximity (supplier perspective)
################################################################################

buyer_patents <- read_csv(
  file.path(DATA_DIR, "output/final/data_buyer_patents.csv"),
  show_col_types = FALSE
)

# OEM share of each supplier's sales (used to weight buyer innovation proximity)
supplier_OEM_demand <- supplier_OEM_flows_data %>%
  group_by(Supplier_PSN, OEM, Part, Year) %>%
  summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  group_by(Supplier_PSN, Part, Year) %>%
  mutate(OEM_share = Value / sum(Value, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(OEM_share = if_else(is.na(OEM_share), 0, OEM_share)) %>%
  select(-Value)

# Share-weighted buyer patent counts per supplier × part × year × destination country
supplier_OEM_patents_country <- supplier_OEM_demand %>%
  left_join(buyer_patents, by = c("OEM", "Year", "Part")) %>%
  filter(!is.na(country_code)) %>%
  rename(country_code_buyer_patent = country_code) %>%
  select(Supplier_PSN, Part, Year, OEM, country_code_buyer_patent,
         count_roll, OEM_share) %>%
  group_by(Supplier_PSN, Part, Year, country_code_buyer_patent) %>%
  summarise(count_roll = sum(count_roll * OEM_share, na.rm = TRUE),
            .groups = "drop")

################################################################################
## Supplier Third-Country Proximity
################################################################################

supplier_patents_agg <- read_csv(
  file.path(DATA_DIR, "output/final/data_supplier_patents.csv"),
  show_col_types = FALSE
) %>%
  group_by(country_code, Supplier_PSN, Part) %>%
  summarise(appln_count = sum(appln_count, na.rm = TRUE), .groups = "drop")

# Aggregate production and demand by country
supplier_demand_country <- supplier_OEM_flows_data %>%
  group_by(Supplier_PSN, Part, Year, country_code_buyer) %>%
  summarise(Value_Demand = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.na(country_code_buyer))

supplier_production_country <- supplier_OEM_flows_data %>%
  group_by(Supplier_PSN, Part, Year, country_code_supplier) %>%
  summarise(Value_Production = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.na(country_code_supplier)) %>%
  filter(country_code_supplier != "NAN")

supplier_OEM_patents_total <- supplier_OEM_patents_country %>%
  group_by(Supplier_PSN, Part, Year) %>%
  summarise(count_roll_buyer_total = sum(count_roll, na.rm = TRUE),
            .groups = "drop")

# Restrict to supplier-part and supplier-country pairs with any activity
eligible_firm_part_pairs <- supplier_demand_country %>%
  group_by(Supplier_PSN, Part) %>%
  summarise(Value_Demand = sum(Value_Demand), .groups = "drop") %>%
  filter(Value_Demand > 0) %>%
  mutate(id = paste0(Supplier_PSN, Part)) %>%
  pull(id)

eligible_firm_country_pairs <- supplier_patents_agg %>%
  group_by(Supplier_PSN, country_code) %>%
  summarise(appln_count = sum(appln_count), .groups = "drop") %>%
  filter(appln_count > 0) %>%
  mutate(id = paste0(Supplier_PSN, country_code)) %>%
  pull(id)

supplier_third_country <- tibble(
  expand.grid(
    supplier = suppliers,
    part     = parts,
    country  = c(countries, "EPP"),
    year     = 2000:2024,
    stringsAsFactors = FALSE
  )
) %>%
  filter(paste0(supplier, part)    %in% eligible_firm_part_pairs) %>%
  filter(paste0(supplier, country) %in% eligible_firm_country_pairs)

# For each third country: share-weighted proximity to production and demand locations
supplier_third_country_sub_agg <- supplier_third_country %>%
  left_join(prod_fill, by = c("country" = "country_code_o")) %>%
  left_join(supplier_production_country,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_supplier")) %>%
  left_join(supplier_demand_country,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_buyer")) %>%
  left_join(supplier_OEM_patents_country,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_buyer_patent")) %>%
  group_by(supplier, part, country, year) %>%
  mutate(
    Share_Production        = Value_Production / sum(Value_Production, na.rm = TRUE),
    Share_Demand            = Value_Demand      / sum(Value_Demand,     na.rm = TRUE),
    Share_Buyer_Innovation  = count_roll        / sum(count_roll,       na.rm = TRUE)
  ) %>%
  summarise(
    avg_down_dist      = sum(distw     * Share_Demand,           na.rm = TRUE),
    avg_inv_down_dist  = sum((1/distw) * Share_Demand,           na.rm = TRUE),
    avg_up_dist        = sum(distw     * Share_Production,       na.rm = TRUE),
    avg_inv_up_dist    = sum((1/distw) * Share_Production,       na.rm = TRUE),
    avg_down_I_dist    = sum(distw     * Share_Buyer_Innovation, na.rm = TRUE),
    avg_inv_down_I_dist = sum((1/distw) * Share_Buyer_Innovation, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(supplier_OEM_patents_total,
            by = c("supplier" = "Supplier_PSN", "part" = "Part", "year" = "Year")) %>%
  mutate(count_roll_buyer_total = if_else(is.na(count_roll_buyer_total), 0,
                                          count_roll_buyer_total))

write_csv(supplier_third_country_sub_agg,
          file.path(DATA_DIR, "output/final/supplier_third_country_proximity.csv"))

################################################################################
## Supplier-Buyer Third-Country Proximity (by OEM)
################################################################################

supplier_buyer_demand_country <- supplier_OEM_flows_data %>%
  group_by(Supplier_PSN, Part, Year, OEM, country_code_buyer) %>%
  summarise(Value_Demand = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  filter(!is.na(country_code_buyer))

supplier_buyer_OEM_patents_country <- supplier_OEM_demand %>%
  left_join(buyer_patents, by = c("OEM", "Year", "Part")) %>%
  filter(!is.na(country_code)) %>%
  rename(country_code_buyer_patent = country_code) %>%
  select(Supplier_PSN, Part, Year, OEM, country_code_buyer_patent, count_roll)

supplier_buyer_third_country_sub_agg <- supplier_third_country %>%
  left_join(prod_fill, by = c("country" = "country_code_o")) %>%
  left_join(supplier_buyer_demand_country,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_buyer")) %>%
  left_join(supplier_buyer_OEM_patents_country,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_buyer_patent",
                   "OEM" = "OEM")) %>%
  group_by(supplier, part, country, year, OEM) %>%
  mutate(
    Share_Demand           = Value_Demand / sum(Value_Demand, na.rm = TRUE),
    Share_Buyer_Innovation = count_roll   / sum(count_roll,   na.rm = TRUE)
  ) %>%
  summarise(
    avg_down_dist       = sum(distw     * Share_Demand,           na.rm = TRUE),
    avg_inv_down_dist   = sum((1/distw) * Share_Demand,           na.rm = TRUE),
    avg_down_I_dist     = sum(distw     * Share_Buyer_Innovation, na.rm = TRUE),
    avg_inv_down_I_dist = sum((1/distw) * Share_Buyer_Innovation, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(!is.na(OEM)) %>%
  left_join(
    supplier_buyer_demand_country %>%
      group_by(Supplier_PSN, Part, Year, OEM) %>%
      summarise(Total_Demand = sum(Value_Demand, na.rm = TRUE), .groups = "drop"),
    by = c("supplier" = "Supplier_PSN", "part" = "Part",
           "year" = "Year", "OEM")
  ) %>%
  mutate(Total_Demand = if_else(is.na(Total_Demand), 0, Total_Demand))

write_csv(supplier_buyer_third_country_sub_agg,
          file.path(DATA_DIR, "output/final/supplier_buyer_third_country_proximity.csv"))

################################################################################
## Supplier Innovation Proximity to Buyers (by transaction)
################################################################################

supplier_patents_panel <- read_csv(
  file.path(DATA_DIR, "output/final/data_supplier_patents.csv"),
  show_col_types = FALSE
) %>%
  select(Supplier_PSN, country_code, Part, Year, count_roll)

# For each buyer × demand destination: proximity to supplier patent locations
supplier_buyer_third_country_I_source <- supplier_third_country %>%
  left_join(prod_fill, by = c("country" = "country_code_o")) %>%
  left_join(supplier_buyer_demand_country,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_buyer")) %>%
  left_join(supplier_patents_panel,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country" = "country_code")) %>%
  group_by(supplier, part, country_code_d, year, OEM) %>%
  mutate(Share_Supplier_Innovation = count_roll / sum(count_roll, na.rm = TRUE)) %>%
  summarise(
    avg_up_I_dist    = sum(distw     * Share_Supplier_Innovation, na.rm = TRUE),
    avg_inv_up_I_dist = sum((1/distw) * Share_Supplier_Innovation, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(!is.na(OEM))

write_csv(supplier_buyer_third_country_I_source,
          file.path(DATA_DIR, "output/final/supplier_buyer_third_country_I_destination.csv"))

# Attach I-source proximity to actual transaction flows
supplier_buyer_transaction_I_source <- supplier_OEM_flows_data %>%
  filter(Value > 0) %>%
  select(Supplier_PSN, Part, Year, OEM, country_code_supplier, country_code_buyer) %>%
  left_join(supplier_buyer_third_country_I_source,
            by = c("Supplier_PSN" = "supplier", "Part" = "part",
                   "Year" = "year", "country_code_buyer" = "country_code_d", 
                   "OEM" = "OEM")) 

write_csv(supplier_buyer_transaction_I_source,
          file.path(DATA_DIR, "output/final/supplier_buyer_transaction_I_source.csv"))

# Suppliers distance to their own patent locations
supplier_buyer_third_country_I_static <- supplier_third_country %>%
  left_join(prod_fill, by = c("country" = "country_code_o")) %>%
  left_join(supplier_production_country,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_supplier")) %>%
  left_join(supplier_patents_panel,
            by = c("supplier" = "Supplier_PSN", "part" = "Part",
                   "year" = "Year", "country" = "country_code")) %>%
  filter(count_roll > 0) %>%
  group_by(supplier, part, country, country_code_d) %>%
  mutate(count_roll = sum(count_roll, na.rm = TRUE)) %>%
  ungroup() %>%
  group_by(supplier, part, country_code_d) %>%
  mutate(count_roll_share = count_roll / sum(count_roll, na.rm = TRUE)) %>%
  summarise(
    avg_inv_I_proximity = sum((1/distw) * count_roll_share, na.rm = TRUE),
    min_up_I_dist       = min(distw),
    min_inv_up_I_dist   = 1 / min(distw),
    .groups = "drop"
  )

supplier_buyer_transaction_I_source_min <- supplier_OEM_flows_data %>%
  filter(Value > 0) %>%
  select(Supplier_PSN, Part, Year, OEM, country_code_supplier, country_code_buyer) %>%
  left_join(supplier_buyer_third_country_I_static,
            by = c("Supplier_PSN" = "supplier", "Part" = "part",
                   "country_code_supplier" = "country_code_d")) %>%
  select(-country_code_supplier)

write_csv(supplier_buyer_transaction_I_source_min,
          file.path(DATA_DIR, "output/final/supplier_buyer_transaction_I_source_min.csv"))

################################################################################
## OEM Third-Country Proximity
################################################################################

OEM_supplier_demand <- supplier_OEM_flows_data %>%
  group_by(Supplier_PSN, OEM, Part) %>%
  summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  group_by(OEM, Part) %>%
  mutate(supplier_share = Value / sum(Value, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(supplier_share = if_else(is.na(supplier_share), 0, supplier_share)) %>%
  select(-Value)

OEM_supplier_patents_country <- OEM_supplier_demand %>%
  left_join(supplier_patents_panel,
            by = c("Supplier_PSN", "Part")) %>%
  filter(!is.na(country_code)) %>%
  rename(country_code_supplier_patent = country_code) %>%
  select(Supplier_PSN, Part, Year, OEM, country_code_supplier_patent, count_roll) %>%
  group_by(OEM, Part, Year, country_code_supplier_patent) %>%
  summarise(count_roll = sum(count_roll*supplier_share, na.rm = TRUE), .groups = "drop")

OEM_production_data <- buyer_data %>%
  group_by(`VP: Strategic Group`, country_code_buyer, Year) %>%
  summarise(Value_Production = sum(Value, na.rm = TRUE), .groups = "drop")

OEM_production_total_data <- buyer_data %>%
  group_by(`VP: Strategic Group`, Year) %>%
  summarise(Value_Production = sum(Value, na.rm = TRUE), .groups = "drop")

OEM_input_data <- supplier_OEM_flows_data %>%
  group_by(OEM, country_code_supplier, Part, Year) %>%
  summarise(Value_Input = sum(Value, na.rm = TRUE), .groups = "drop")

OEM_supplier_count <- supplier_OEM_flows_data %>%
  group_by(OEM, Supplier_PSN, Part, Year) %>%
  summarise(Value_Input = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  filter(Value_Input > 0) %>%
  group_by(OEM, Part, Year) %>%
  summarise(N_suppliers = n_distinct(Supplier_PSN), .groups = "drop")

OEM_supplier_patents_total <- OEM_supplier_patents_country %>%
  group_by(OEM, Part, Year) %>%
  summarise(count_roll_supplier_total = sum(count_roll, na.rm = TRUE),
            .groups = "drop")

buyers   <- unique(toupper(OEM_production_data$`VP: Strategic Group`))
oem_parts <- sort(unique(OEM_input_data$Part))
oem_countries <- sort(unique(OEM_production_data$country_code_buyer))

eligible_oem_part_pairs <- OEM_input_data %>%
  group_by(OEM, Part) %>%
  summarise(Value_Input = sum(Value_Input), .groups = "drop") %>%
  filter(Value_Input > 0) %>%
  mutate(id = paste0(OEM, Part)) %>%
  pull(id)

buyer_patents <- read_csv(
  file.path(DATA_DIR, "output/final/data_buyer_patents.csv"),
  show_col_types = FALSE
)

eligible_oem_country_pairs <- buyer_patents %>%
  group_by(OEM, country_code) %>%
  summarise(appln_count = sum(appln_count), .groups = "drop") %>%
  filter(appln_count > 0) %>%
  mutate(id = paste0(OEM, country_code)) %>%
  pull(id)

buyer_third_country <- tibble(
  expand.grid(
    buyer   = buyers,
    part    = oem_parts,
    country = c(oem_countries, "EPP"),
    year    = 2000:2024,
    stringsAsFactors = FALSE
  )
) %>%
  filter(paste0(buyer, part)    %in% eligible_oem_part_pairs) %>%
  filter(paste0(buyer, country) %in% eligible_oem_country_pairs)

buyer_third_country_sub_agg <- buyer_third_country %>%
  left_join(prod_fill, by = c("country" = "country_code_o")) %>%
  left_join(OEM_production_data,
            by = c("buyer" = "VP: Strategic Group",
                   "year" = "Year", "country_code_d" = "country_code_buyer")) %>%
  left_join(OEM_input_data,
            by = c("buyer" = "OEM", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_supplier")) %>%
  left_join(OEM_supplier_patents_country,
            by = c("buyer" = "OEM", "part" = "Part",
                   "year" = "Year", "country_code_d" = "country_code_supplier_patent")) %>%
  group_by(buyer, part, country, year) %>%
  mutate(
    Share_Production        = Value_Production / sum(Value_Production, na.rm = TRUE),
    Share_Input             = Value_Input       / sum(Value_Input,      na.rm = TRUE),
    Share_Supplier_Innovation = count_roll      / sum(count_roll,       na.rm = TRUE)
  ) %>%
  summarise(
    avg_down_dist       = sum(distw     * Share_Production,        na.rm = TRUE),
    avg_inv_down_dist   = sum((1/distw) * Share_Production,        na.rm = TRUE),
    avg_up_dist         = sum(distw     * Share_Input,             na.rm = TRUE),
    avg_inv_up_dist     = sum((1/distw) * Share_Input,             na.rm = TRUE),
    avg_up_I_dist       = sum(distw     * Share_Supplier_Innovation, na.rm = TRUE),
    avg_inv_up_I_dist   = sum((1/distw) * Share_Supplier_Innovation, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(OEM_supplier_count,
            by = c("buyer" = "OEM", "part" = "Part", "year" = "Year")) %>%
  mutate(N_suppliers = if_else(is.na(N_suppliers), 0, N_suppliers)) %>%
  left_join(OEM_supplier_patents_total,
            by = c("buyer" = "OEM", "part" = "Part", "year" = "Year")) %>%
  mutate(count_roll_supplier_total = if_else(is.na(count_roll_supplier_total), 0,
                                             count_roll_supplier_total)) %>%
  left_join(OEM_production_total_data,
            by = c("buyer" = "VP: Strategic Group", "year" = "Year"))

write_csv(buyer_third_country_sub_agg,
          file.path(DATA_DIR, "output/final/buyer_third_country_proximity.csv"))

write_csv(OEM_production_data,
          file.path(DATA_DIR, "output/final/OEM_country_production_data.csv"))

################################################################################
## OEM Bilateral Production Data (for data_plant_locations_IV_OEM.R)
################################################################################

production_data_bilateral <- read_delim(
  file.path(IHS_DIR, "Sales2024/Vehicle_Sales_Export_2000_2024.csv"),
  delim = ";", show_col_types = FALSE
) %>%
  mutate(across(c(`VP: Country/Territory`, `VP: Sales Group`, `VP: Global Nameplate`,
                  `VP: Platform`, `VP: Program`, `VP: Strategic Group`,
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
  group_by(`VP: Country/Territory`, `VP: Strategic Group`, `VP: Global Nameplate`,
           `VP: Platform`, `VP: Program`, `VPE: Destination Country/Territory`) %>%
  summarise(across(matches("^CY \\d{4}$"), \(x) sum(x, na.rm = TRUE)),
            .groups = "drop") %>%
  group_by(`VP: Country/Territory`, `VP: Strategic Group`,
           `VPE: Destination Country/Territory`) %>%
  summarise(across(matches("^CY \\d{4}$"), \(x) sum(x, na.rm = TRUE)),
            .groups = "drop") %>%
  pivot_longer(cols = matches("^CY \\d{4}$"), names_to = "Year", values_to = "Value") %>%
  mutate(Value = as.numeric(Value),
         Year  = as.numeric(substr(Year, 4, 7))) %>%
  rename(Origin = `VP: Country/Territory`,
         Destination = `VPE: Destination Country/Territory`,
         OEM = `VP: Strategic Group`) %>%
  group_by(Origin, Destination, OEM, Year) %>%
  summarise(Value = sum(Value), .groups = "drop") %>%
  filter(Destination != "UNKNOWN") %>%
  filter(Value > 1000) %>%
  left_join(country_codes, by = c("Origin"      = "Country")) %>%
  rename(country_code_o = country_code) %>%
  left_join(country_codes, by = c("Destination" = "Country")) %>%
  rename(country_code_d = country_code)

write_csv(production_data_bilateral,
          file.path(DATA_DIR, "output/final/OEM_production_bilateral_data.csv"))

message("data_plant_locations.R complete.")
