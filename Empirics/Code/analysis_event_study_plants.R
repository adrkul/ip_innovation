# analysis_event_study_plants.R
# Run from project root: Rscript Empirics/Code/analysis_event_study_plants.R
#
# PURPOSE: Event study — does supplier-location innovation respond to nearby OEM
#   plant openings?  Uses a TWFE design with a double-difference structure:
#     geo_treat  = 1 if inventor NUTS centroid is ≤ DIST_KM from the opening plant
#     part_treat = 1 if (Supplier_PSN, Part) has a supply linkage to the opening OEM
#     treated    = geo_treat × part_treat
#   The identifying variation is within-supplier: same firm, close vs. far locations,
#   treated vs. control parts, before vs. after opening.  Restricts to EU plants
#   (geocoded) and EU inventor NUTS cells.
#
# Requires:
#   [DATA_DIR]/output/final/data_analysis_final_NUTS.csv   (NUTS panel)
#   [IHS_DIR]/Sales2024/production_agg_name_city.csv       (OEM production by city)
#   [DATA_DIR]/output/intmd/geocoded_by_geoapify-3_28_2025, 12_47_18 PM.csv
#   [DATA_DIR]/output/intmd/IHS_PATSTAT_who_supply_who.csv
#   [DATA_DIR]/output/intmd/IHS_marklines_part_correspondence_manual.csv
#   [DATA_DIR]/output/final/IHS_to_PRODUCTION_correspondence_name.csv
#   [DATA_DIR]/other/country_codes.csv
#
# Produces:
#   Empirics/Figures/Main/event_study_plants_geo_part.pdf
#   Empirics/Figures/Main/event_study_plants_table.tex

rm(list = ls())
set.seed(20260409)

library(tidyverse)
library(fixest)
library(geosphere)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"
IHS_DIR  <- "/Users/adrkul/Library/CloudStorage/Dropbox/IHS_data"
OUT_DIR  <- "Empirics/Figures/Main"

# ── Parameters ────────────────────────────────────────────────────────────────
DIST_KM    <- 150   # geographic treatment radius (km)
EVENT_PRE  <- 4     # years before opening to include
EVENT_POST <- 10    # years after opening to include

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Plot themes
source("themes.R")

################################################################################
## 0. Country Codes and EU-27 List
################################################################################

country_codes <- read_csv(file.path(DATA_DIR, "other/country_codes.csv")) %>%
  select("Country", "Alpha-3 code") %>%
  rename(country_code = "Alpha-3 code") %>%
  mutate(
    Country = toupper(Country),
    Country = if_else(Country == "USA",                    "UNITED STATES",      Country),
    Country = if_else(Country == "UK",                     "UNITED KINGDOM",     Country),
    Country = if_else(Country == "KOREA",                  "SOUTH KOREA",        Country),
    Country = if_else(Country == "RUSSIA",                 "RUSSIAN FEDERATION", Country),
    Country = if_else(Country == "VIET NAM",               "VIETNAM",            Country),
    Country = if_else(Country == "BOSNIA AND HERZEGOVINA", "BOSNIA-HERZEGOVINA", Country)
  )

eu_iso3 <- c(
  "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST",
  "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
  "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
  "SVN", "ESP", "SWE"
)

################################################################################
## 1. OEM Plant Openings (EU, event window fits within data)
################################################################################
# opening_year = first calendar year with positive production at OEM × City.
# We cap opening_year ∈ [2000 + EVENT_PRE, 2024 - EVENT_POST] so the full
# pre- and post-windows lie within the available data range (2000–2024).

prod_city <- read_csv(
  file.path(IHS_DIR, "Sales2024/production_agg_name_city.csv")
) %>%
  pivot_longer(
    cols      = matches("^CY \\d{4}$"),
    names_to  = "Year_str",
    values_to = "Value"
  ) %>%
  mutate(
    Value = as.numeric(Value),
    Year  = as.integer(substr(Year_str, 4, 7)),
    across(c(`VP: Country/Territory`, `VP: City`, `VP: Production Brand`), toupper)
  ) %>%
  group_by(`VP: Production Brand`, `VP: Country/Territory`, `VP: City`, Year) %>%
  summarise(Value = sum(Value, na.rm = TRUE), .groups = "drop")

oem_openings_raw <- prod_city %>%
  filter(Value > 0) %>%
  group_by(`VP: Production Brand`, `VP: Country/Territory`, `VP: City`) %>%
  summarise(opening_year = min(Year), .groups = "drop") %>%
  rename(
    OEM         = `VP: Production Brand`,
    Country_oem = `VP: Country/Territory`,
    City_oem    = `VP: City`
  ) %>%
  left_join(country_codes, by = c("Country_oem" = "Country")) %>%
  filter(
    country_code %in% eu_iso3,
    opening_year > 2000 + EVENT_PRE,
    opening_year <= 2024 - EVENT_POST,
    #opening_year >= 2000 + EVENT_PRE,
    #opening_year <= 2024 - EVENT_POST
  )

# Geocoded downstream city coordinates (EU OEM plants, from geoapify)
cities_coord_down <- read_csv(
  file.path(DATA_DIR,
            "output/intmd/geocoded_by_geoapify-3_28_2025, 12_47_18 PM.csv")
) %>%
  select(`original_VP: Country/Territory`, `original_VP: City`, lat, lon) %>%
  mutate(`original_VP: Country/Territory` = toupper(`original_VP: Country/Territory`))

oem_openings <- oem_openings_raw %>%
  left_join(
    cities_coord_down %>% mutate(`original_VP: City` = toupper(`original_VP: City`)),
    by = c("Country_oem" = "original_VP: Country/Territory",
           "City_oem"    = "original_VP: City")
  ) %>%
  filter(!is.na(lat), !is.na(lon), lat != 0) %>%
  mutate(event_id = row_number()) #%>% 
  #filter(country_code %in% c("CZE","SVK","HUN","ROU","POL"))

message(sprintf("Plant-opening events (EU, full window): %d", nrow(oem_openings)))

################################################################################
## 2. Supply Linkages: Supplier_PSN × OEM × Part
################################################################################
# Replicates the linkage join from data_plant_locations_NUTS.R.
# A supplier "supplies" an OEM in part category P if there is any
# firm-to-firm connection in that part in the IHS WSW data.

supply_links = read_csv(file.path(DATA_DIR, "output/intmd/IHS_who_supply_who_down_plants.csv")) %>% 
  rename("Supplier_PSN" = "Supplier_PSN_1") %>% 
  select(Supplier_PSN, Part, `VP: Production Brand`, `VP: City`) %>% 
  mutate(
    Supplier_PSN = as.character(Supplier_PSN),
    `VP: Production Brand` = toupper(`VP: Production Brand`),
    `VP: City` = toupper(`VP: City`)
  )

message(sprintf("Supplier-OEM-part linkages: %d", nrow(supply_links)))

################################################################################
## 3. NUTS-Level Patent Panel
################################################################################
# data_analysis_final_NUTS.csv: Supplier × Part × Year × (lat, lon)
# lat/lon are NUTS3 centroids; they are non-null only for EU inventors by
# construction in data_plant_locations_NUTS.R, so no additional EU filter needed.

nuts_panel <- read_csv(
  file.path(DATA_DIR, "output/final/data_analysis_final_NUTS.csv")
) %>%
  select(Supplier_PSN, Country, Part, Year, lat, lon, count_roll, appln_count, log_prod) %>%
  filter(!is.na(lat), !is.na(lon)) %>%
  # Pre-filter to suppliers that appear in supply_links (efficiency)
  filter(Supplier_PSN %in% unique(supply_links$Supplier_PSN))

message(sprintf("NUTS panel obs (relevant suppliers): %d", nrow(nuts_panel)))

################################################################################
## 4. Construct Event-Study Panel
################################################################################
# For each opening event e (OEM_e, lat_e, lon_e, opening_year_e):
#   geo_treat:  1 if dist(NUTS centroid, plant) ≤ DIST_KM
#   part_treat: 1 if (Supplier_PSN, Part) supplies OEM_e
#   treated:    geo_treat × part_treat
#   event_time: Year - opening_year_e  ∈ [−EVENT_PRE, +EVENT_POST]
#
# We loop over events and stack, then deduplicate: if a (Supplier, Part, lat,
# lon, Year) is exposed to multiple events, we keep the event with the closest
# opening plant (most relevant event for that location).

event_panels <- map_dfr(seq_len(nrow(oem_openings)), function(i) {
  
  ev <- oem_openings[i, ]

  linked_parts_i <- supply_links %>%
    filter(`VP: Production Brand` == ev$OEM) %>% 
    filter(`VP: City` == ev$City_oem) %>% 
    select(Supplier_PSN, Part) %>%
    distinct() %>%
    mutate(part_treat = 1L)
  
  if (nrow(linked_parts_i) == 0L) return(NULL)

  nuts_panel %>%
    filter(
      Supplier_PSN %in% linked_parts_i$Supplier_PSN,
      Year >= ev$opening_year - EVENT_PRE,
      Year <= ev$opening_year + EVENT_POST
    ) %>%
    mutate(
      event_id      = ev$event_id,
      OEM_event     = ev$OEM,
      opening_year  = ev$opening_year,
      event_time    = as.integer(Year - ev$opening_year),
      # Haversine distance (km): p1 = matrix(lon, lat), p2 = single plant coord
      dist_to_plant = distHaversine(cbind(lon, lat), c(ev$lon, ev$lat)) / 1000,
      geo_treat     = as.integer(dist_to_plant <= DIST_KM),
      geo_treat_alt_a     = as.integer(dist_to_plant <= DIST_KM*2),
      geo_treat_alt_b     = as.integer(dist_to_plant <= DIST_KM*4),
    ) %>%
    left_join(linked_parts_i, by = c("Supplier_PSN", "Part")) %>%
    mutate(
      part_treat = coalesce(part_treat, 0L),
      treated    = geo_treat * part_treat,
      treated_a    = geo_treat_alt_a * part_treat,
      treated_b    = geo_treat_alt_b * part_treat,
    )
})

message(sprintf("Raw event-study observations stacked: %d", nrow(event_panels)))

# Deduplication: keep closest event per (Supplier, Part, location, Year)
event_panel <- event_panels %>%
  group_by(Supplier_PSN, Country, Part, lat, lon, Year) %>%
  slice_min(dist_to_plant, n = 1, with_ties = FALSE) %>%
  ungroup() #%>% 
  ## Duplicate events arises from multiple brands in the same factory
  #group_by(Supplier_PSN, Country, Part, lat, lon) %>%
  #filter(event_id == event_id[1]) #
  ## Perhaps fine, you want to be in the control for the other group. 

message(sprintf("After deduplication: %d observations", nrow(event_panel)))

# Sanity: print treatment cell counts
cat("\nTreatment cell summary:\n")
print(count(event_panel, geo_treat, part_treat, treated))

################################################################################
## 5. Fixed Effects
################################################################################

event_panel <- event_panel %>%
  mutate(
    # Supplier × NUTS location × Part (absorbs time-invariant heterogeneity)
    firm_city_part_fe  = paste0(Supplier_PSN, lat, lon, Part),
    # Supplier × NUTS location × Year (absorbs location-invariant heterogeneity)
    firm_city_year_fe  = paste0(Supplier_PSN, lat, lon, Year),
    # Supplier × Country × Year (absorbs location-invariant heterogeneity)
    firm_cntry_year_fe  = paste0(Supplier_PSN, Country, Year),
    # Part × NUTS location × Year (absorbs local part-specific innovation trends)
    part_city_year_fe  = paste0(Part, lat, lon, Year),
    # Part × Country × Year (absorbs local part-specific innovation trends)
    part_cntry_year_fe  = paste0(Part, Country, Year),
    # Firm × Country × Part (absorbs local firm-part-specific innovation trends)
    firm_cntry_part_fe  = paste0(Supplier_PSN, Country, Part),
    # Firm × Country × Part (absorbs local firm-part-specific innovation trends)
    firm_cntry_part_year_fe  = paste0(Supplier_PSN, Country, Part, Year),
    # Supplier × Part × Year (absorbs supplier-wide patent cycles)
    firm_part_year_fe  = paste0(Supplier_PSN, Part, Year),
    # Event × Year (isolate comparison)
    event_year_fe  = paste0(event_id, Year),
    # Cluster variable
    city_fe            = paste0(lat, lon)
  ) %>% 
  mutate(event_time_fe = as.factor(paste0(event_time))) %>% 
  mutate(event_time_fe = relevel(event_time_fe, ref = as.character(-1)))
  
clean_cells <- event_panel %>%
   group_by(Part, lat, lon, Year) %>%
   summarise(count = n()) %>%
   filter(count > 1) %>%
   select(Part, lat, lon, Year)
 
event_panel <- event_panel %>%
  semi_join(clean_cells, by = c("Part", "lat", "lon", "Year"))

################################################################################
## 6. TWFE Event-Study Regressions
################################################################################

# Spec 1: Baseline TWFE w/ Production Control
reg_1 <- fepois(
  count_roll ~ treated*event_time_fe + log_prod|
    event_year_fe + treated + firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~city_fe
)
summary(reg_1)

# Spec 1: Baseline TWFE w/ Production Control
reg_2 <- fepois(
  count_roll ~ geo_treat*part_treat*event_time_fe + log_prod|
    event_year_fe + treated + firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~city_fe
)
summary(reg_2)

################################################################################
## 7. Event-Study Coefficient Plot
################################################################################
# Extract coefficients from fixest i() models and plot with ggplot2.
# Coefficient names from i(event_time, treated, ref = -1) follow the pattern
# "event_time::VALUE:treated" in fixest.

extract_event_study_data <- function(reg, t_ref = -1, interaction_pattern = "geo_treat:part_treat:event_time_fe") {
  
  # Extract coefficient table
  coeff_table <- reg$coeftable
  
  # Filter for interaction terms
  coeff_table <- coeff_table[grepl(interaction_pattern, rownames(coeff_table)), ]
  
  # Extract years from row names
  years <- as.integer(sub(".*?(-?\\d+)$", "\\1", rownames(coeff_table)))
  
  # Create event study data frame
  event_study_df <- data.frame(
    Year = c(t_ref, years),
    Estimates = c(0, coeff_table[, 1]),
    Error = c(0, coeff_table[, 2])
  )
  
  # Add confidence intervals
  event_study_df <- event_study_df %>% 
    mutate(Lower_CI = Estimates - 1.96 * Error,
           Upper_CI = Estimates + 1.96 * Error)
  
  return(event_study_df)
  
}

event_study_df = extract_event_study_data(reg_2, interaction_pattern = "geo_treat:part_treat:event_time_fe") 

t_0 = -1*EVENT_PRE
years <- sort(unique(event_study_df$Year))

# Create the plot
p = ggplot(event_study_df %>% mutate(Type = 'Main'), aes(x = Year, y = Estimates, color = Type)) +
  geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI), width = 0.2, alpha = 1) +
  geom_point(size = 2, alpha = 1) +
  scale_color_manual(values = "steelblue") + 
  scale_fill_manual(values = "steelblue") + 
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  xlab(TeX("\\textbf{Year Relative to Plant Opening}")) +
  ylab(TeX("\\textbf{log Patent Response}")) +
  theme_line() + 
  theme(legend.position = "none") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black") +
  scale_x_continuous(
    breaks = seq(t_0, years[length(years)], 2),
    labels = as.character(seq(t_0, years[length(years)], 2)),
    limits = c(t_0 - 0.0, years[length(years)] + 0.0))

ggsave(
  "../Figures/Event_Study_Plants/event_study_plants_geo_part_a.png",
  plot = p,  width = 5.0*2.0,
  height = 5.0)   

event_study_df = extract_event_study_data(reg_1, interaction_pattern = "treated:event_time_fe")


t_0 = -1*EVENT_PRE
years <- sort(unique(event_study_df$Year))

# Create the plot
p = ggplot(event_study_df %>% mutate(Type = 'Main'), aes(x = Year, y = Estimates, color = Type)) +
  geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI), width = 0.2, alpha = 1) +
  geom_point(size = 2, alpha = 1) +
  scale_color_manual(values = "steelblue") + 
  scale_fill_manual(values = "steelblue") + 
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  xlab(TeX("\\textbf{Year Relative to Plant Opening}")) +
  ylab(TeX("\\textbf{log Patent Response}")) +
  theme_line() + 
  theme(legend.position = "none") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black") +
  scale_x_continuous(
    breaks = seq(t_0, years[length(years)], 2),
    labels = as.character(seq(t_0, years[length(years)], 2)),
    limits = c(t_0 - 0.0, years[length(years)] + 0.0))

ggsave(
  "../Figures/Event_Study_Plants/event_study_plants_geo_part_b.png",
  plot = p,  width = 5.0*2.0,
  height = 5.0)   

# 
# 
# # Create the plot
# p = ggplot(event_study_df %>% mutate(Type = 'Main'), aes(x = Year, y = Estimates, color = Type)) +
#   geom_hline(yintercept = 0, linewidth = 0.4, color = "grey60") +
#   geom_vline(xintercept = -0.5, linewidth = 0.4, linetype = "dashed",
#              color = "grey60") +
#   geom_ribbon(aes(ymin = Lower_CI, ymax = Upper_CI),
#               alpha = 0.12, color = NA) +
#   geom_line(linewidth = 0.7) +
#   geom_point(size = 1.8) +
#   scale_color_manual(values = "steelblue") + 
#   scale_fill_manual(values = "steelblue") + 
#   xlab(TeX("Year Relative to Plant Opening")) +
#   ylab(TeX("log Patent Response")) +
#   theme_line() + 
#   theme(legend.position = "none") +
#   scale_x_continuous(
#     breaks = seq(t_0, years[length(years)], 2),
#     labels = as.character(seq(t_0, years[length(years)], 2)),
#     limits = c(t_0 - 0.0, years[length(years)] + 0.0))
# 
# ggsave(
#   "../Figures/Event_Study_Plants/event_study_plants_geo_part_alt.png",
#   plot = p,  width = 5.0*2.0,
#   height = 5.0)   
