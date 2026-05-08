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
#   Empirics/Figures/Main/event_study_plants_robustness_spec.tex
#   Empirics/Figures/Main/event_study_plants_robustness_sample.tex
#   Empirics/Figures/Main/event_study_plants_robustness_dist.tex

rm(list = ls())
set.seed(20260409)

library(tidyverse)
library(fixest)
library(geosphere)
library(latex2exp)

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
  summarise(opening_year = min(Year), 
            closing_year = max(Year), .groups = "drop",
            Value = mean(Value)) %>%
  rename(
    OEM         = `VP: Production Brand`,
    Country_oem = `VP: Country/Territory`,
    City_oem    = `VP: City`
  ) %>%
  left_join(country_codes, by = c("Country_oem" = "Country")) %>%
  filter(
    country_code %in% eu_iso3,
    opening_year > 2000 + EVENT_PRE,
    opening_year <= 2024 - EVENT_POST) %>% 
  #filter(closing_year >= 2024) %>% 
  filter(closing_year-opening_year > EVENT_POST) %>% 
  select(!closing_year)

# Geocoded downstream city coordinates (EU OEM plants, from geoapify)
cities_coord_down <- read_csv(
  file.path(DATA_DIR,
            "output/intmd/geocoded_by_geoapify-3_28_2025, 12_47_18 PM.csv")
) %>%
  select(`original_VP: Country/Territory`, `original_VP: City`, lat, lon) %>%
  mutate(`original_VP: Country/Territory` = toupper(`original_VP: Country/Territory`))
# Add manual geocodes for missing cities (if any)

# Manual coordinates (uppercase to match your join keys)
manual_coords <- tibble::tribble(
  ~Country_oem, ~City_oem,                ~lat, ~lon,
  "POLAND",     "ZERAN",                  52.30,       21.02,
  "ITALY",      "NAPLES",                 40.852,      14.268,
  "PORTUGAL",   "VENDAS NOVAS",           38.68,      -8.46,
  "SPAIN",      "LINARES",                38.10,      -3.63,
  "SPAIN",      "AVILA",                  40.66,      -4.70,
  "BELGIUM",    "ANTWERP",                51.22,       4.40,
  "GERMANY",    "DUSSELDORF",             51.23,       6.78
)

oem_openings <- oem_openings_raw %>%
  left_join(
    cities_coord_down %>% mutate(`original_VP: City` = toupper(`original_VP: City`)),
    by = c("Country_oem" = "original_VP: Country/Territory",
           "City_oem"    = "original_VP: City")
  ) %>%
  left_join(manual_coords, by = c("Country_oem", "City_oem")) %>%
  mutate(lat = coalesce(lat.y, lat.x), lon = coalesce(lon.y, lon.x)) %>%
  select(!c("lat.x", "lon.x", "lat.y", "lon.y")) %>%
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
 
# production_data_agg_global_name <- read_csv(
#   file.path(IHS_DIR, "Sales2024/production_agg_name_city.csv")
# ) %>% 
#   select(`VP: Production Brand`, `VP: City`, `VP: Strategic Group`) %>% distinct() 

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

# XXX max versus sum

nuts_panel <- read_csv(
  file.path(DATA_DIR, "output/final/data_analysis_final_NUTS.csv")
) %>%
  select(Supplier_PSN, Country, Part, Year, lat, lon, count_roll, appln_count, log_prod, 
         avg_up_dist, avg_down_dist, avg_inv_up_dist, avg_inv_down_dist) %>%
  # Need to aggregate patents across filing locations
  group_by(Supplier_PSN, Part, Year, lat, lon) %>%
  summarise(count_roll = sum(count_roll), 
            appln_count = sum(appln_count), 
            log_prod = mean(log_prod,na.rm=TRUE),
            avg_up_dist = mean(avg_up_dist,na.rm=TRUE),
            avg_down_dist = mean(avg_down_dist,na.rm=TRUE),
            avg_inv_up_dist = mean(avg_inv_up_dist,na.rm=TRUE),
            avg_inv_down_dist = mean(avg_inv_down_dist,na.rm=TRUE),
            .groups = "drop") %>%
  filter(!is.na(lat), !is.na(lon)) %>%
  # Pre-filter to suppliers that appear in supply_links (efficiency)
  filter(Supplier_PSN %in% unique(supply_links$Supplier_PSN))

message(sprintf("NUTS panel obs (relevant suppliers): %d", nrow(nuts_panel)))

countries = read_csv("/Users/adrkul/Downloads/coords_geocoded.csv")

nuts_panel = nuts_panel %>% 
  left_join(countries %>% select(country_name, lat, lon), by = c("lat" = "lat", "lon" = "lon")) %>% 
  rename("Country" = "country_name")

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
    # Linked to the opening OEM and city
    filter(`VP: Production Brand` == ev$OEM) %>% 
    filter(`VP: City` == ev$City_oem) %>% 
    select(Supplier_PSN, Part) %>%
    distinct() %>%
    mutate(part_treat = 1L)
  
  linked_suppliers = supply_links %>% filter(`VP: Production Brand` == ev$OEM) %>% 
    select(Supplier_PSN) %>% distinct()
  
  if (nrow(linked_parts_i) == 0L) return(NULL)

  nuts_panel %>%
    filter(
      ## XXX On and Off
      #Supplier_PSN %in% linked_parts_i$Supplier_PSN, # Supplier sells to OEM City
      Year >= ev$opening_year - EVENT_PRE,
      Year <= ev$opening_year + EVENT_POST
    ) %>%
    mutate(
      event_id      = ev$event_id,
      OEM_event     = ev$OEM,
      opening_year  = ev$opening_year,
      plant_size    = ev$Value,
      event_time    = as.integer(Year - ev$opening_year),
      # Haversine distance (km): p1 = matrix(lon, lat), p2 = single plant coord
      dist_to_plant = distHaversine(cbind(lon, lat), c(ev$lon, ev$lat)) / 1000,
      geo_treat     = as.integer(dist_to_plant <= DIST_KM),
      geo_treat_alt_a     = as.integer(dist_to_plant <= 250),
      geo_treat_alt_b     = as.integer(dist_to_plant <= 400),
    ) %>%
    left_join(linked_parts_i, by = c("Supplier_PSN", "Part")) %>%
    mutate(
      #part_treat = coalesce(part_treat, 0L),
      part_treat = coalesce(part_treat, 0L) & (Supplier_PSN %in% linked_parts_i$Supplier_PSN),
      part_treat_spill = (Part %in% linked_parts_i$Part) - part_treat,
      non_OEM_linked = !(Supplier_PSN %in% linked_suppliers$Supplier_PSN),
      part_treat_spill_alt = part_treat_spill &  non_OEM_linked,
      treated    = geo_treat * part_treat,
      treated_a    = geo_treat_alt_a * part_treat,
      treated_b    = geo_treat_alt_b * part_treat,
    )
})

message(sprintf("Raw event-study observations stacked: %d", nrow(event_panels)))


# So the event is an OEM-city opening
# To it we link all Suppliers that sell to that OEM-city
# Where some Supplier-Parts are treated because they sell to the OEM
# and some are controls because they don't sell to the OEM
# but all suppliers sell at least one part to that OEM
# Now lets look at R&D outcomes at locations near the opening

# Consider patent outcomes in some location X
# before deduplication, if location X is near multiple openings, it will appear multiple times in the event panel
# after deduplication, we keep only the closest opening for location X
# this is true for treatment and control units
# so before control included locations that were far away
# now control includes more so other firms in the same location which 
# also have a nearby plant opening, but it might be different from the one for 
# the current unit
 

# That means the control group becomes more “matched” to the local event environment, 
# because every control is interpreted relative to one specific nearby relevant opening rather than a mixture of openings.

#But it also means some potentially valid controls are discarded if they arise only in alternative event assignments.

event_panels <- event_panels %>%
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
    # Supplier × Part × Event (absorbs supplier-wide patent cycles)
    firm_part_event_fe  = paste0(Supplier_PSN, Part, event_id),
    # Event × Year (isolate comparison)
    event_year_fe  = paste0(event_id, Year),
    firm_city_year_event_fe  = paste0(event_id, firm_city_year_fe),
    part_city_year_event_fe  = paste0(event_id, part_city_year_fe),
    part_cntry_year_event_fe  = paste0(event_id, part_cntry_year_fe),
    firm_part_year_event_fe  = paste0(event_id, firm_part_year_fe),
    firm_cntry_part_year_event_fe  = paste0(event_id, firm_cntry_part_year_fe),
    firm_cntry_part_event_fe = paste0(event_id, firm_cntry_part_fe),
    # Cluster variable
    city_fe            = paste0(lat, lon),
    city_year_fe            = paste0(lat, lon, Year),
  ) %>% 
  mutate(event_time_fe = as.factor(paste0(event_time))) %>% 
  mutate(event_time_fe = relevel(event_time_fe, ref = as.character(-1))) %>% 
  mutate(post_fe = event_time >= 0)

event_panel <- event_panels 

message(sprintf("After deduplication: %d observations", nrow(event_panel)))

# Sanity: print treatment cell counts
cat("\nTreatment cell summary:\n")
print(count(event_panel, geo_treat, geo_treat_alt_a, part_treat, treated))

clean_cells <- event_panel %>%
  group_by(part_city_year_event_fe) %>%
  summarise(count = n()) %>%
  filter(count > 1) %>%
  select(part_city_year_event_fe)

event_panel <- event_panel %>%
  semi_join(clean_cells, by = c("part_city_year_event_fe"))

cat("\nTreatment cell summary:\n")
print(count(event_panel, geo_treat, part_treat, treated))

################################################################################
## 4. First-Stage Distance Effect
################################################################################

# Spec 1: Baseline TWFE w/ Production Control

reg_dist <- feols(
  avg_down_dist ~ geo_treat*part_treat*event_time_fe|
    firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_dist)
 
# reg_dist_event_fe <- feols(
#   avg_down_dist ~ geo_treat*part_treat*event_time_fe|
#     firm_city_year_event_fe + part_city_year_event_fe,
#   data    = event_panel,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_dist_event_fe)

################################################################################
## 5. Estimation
################################################################################

reg_innov <- fepois(
  count_roll ~ geo_treat*part_treat*event_time_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data    = event_panel, 
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_innov)

################################################################################
## 5. Estimation - Robustness Main
################################################################################

reg_innov_app <- fepois(
  appln_count ~ geo_treat*part_treat*post_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_innov_app)

reg_innov_event_fe <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_city_year_event_fe + part_city_year_event_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_innov_event_fe)

# reg_innov_hdfe <- fepois(
#   count_roll ~ geo_treat*part_treat*post_fe + log_prod|
#     firm_cntry_part_year_fe + firm_city_year_fe + part_city_year_fe,
#   data    = event_panel,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_innov_hdfe)
# 
# reg_innov_hdfe_event_fe <- fepois(
#   count_roll ~ geo_treat*part_treat*post_fe + log_prod|
#     firm_cntry_part_year_event_fe + firm_city_year_event_fe + part_city_year_event_fe,
#   data    = event_panel,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_innov_hdfe_event_fe)

# reg_innov_hdfe_alt <- fepois(
#   count_roll ~ geo_treat*part_treat*post_fe + log_prod|
#     firm_part_year_fe + firm_city_year_fe + part_city_year_fe,
#   data    = event_panel,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_innov_hdfe_alt)

# reg_innov_hdfe_alt_event_fe <- fepois(
#   count_roll ~ geo_treat*part_treat*post_fe + log_prod|
#     firm_part_year_event_fe + firm_city_year_event_fe + part_city_year_event_fe,
#   data    = event_panel,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_innov_hdfe_alt_event_fe)

reg_innov_hdfe_2_event_fe <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_cntry_part_fe + firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_innov_hdfe_2_event_fe)

reg_innov_hdfe_alt_2_event_fe <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_cntry_part_event_fe + firm_city_year_event_fe + part_city_year_event_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_innov_hdfe_alt_2_event_fe)

################################################################################
## 7. Sample Restrictions
################################################################################

# Select Earliest Event Only
data_first_event = event_panel %>% 
  group_by(Supplier_PSN, Part, lat, lon) %>% 
  filter(opening_year == min(opening_year)) %>% ungroup()

# Select Nearest Event Only
data_nearest_event = event_panel %>% 
  group_by(Supplier_PSN, Part, lat, lon) %>% 
  filter(dist_to_plant == min(dist_to_plant)) %>% ungroup()

# Collapse to one treatment per Supplier_PSN × Part × lat × lon
data_first_event_collapsed = data_first_event %>% 
  group_by(Supplier_PSN, Part, lat, lon) %>% 
  mutate(part_treat = max(part_treat),
         geo_treat = max(geo_treat)) %>% 
  filter(event_id == min(event_id))

# Collapse to one treatment per Supplier_PSN × Part × lat × lon
data_nearest_event_collapsed = data_nearest_event %>% 
  group_by(Supplier_PSN, Part, lat, lon) %>% 
  mutate(part_treat = max(part_treat),
         geo_treat = max(geo_treat)) %>% 
  filter(event_id == min(event_id))

reg_0_first_event <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data = data_first_event,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_0_first_event)

reg_0_first_event_collapsed <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data = data_first_event_collapsed,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_0_first_event_collapsed)

reg_0_nearest_event <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data = data_nearest_event,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_0_nearest_event)

reg_0_nearest_event_collapsed <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data = data_nearest_event_collapsed,
  cluster = ~ city_fe + Supplier_PSN
)
summary(reg_0_nearest_event_collapsed)

################################################################################
## 5c. Distance Test
################################################################################
 
reg_dist_comp <- fepois(
  count_roll ~ geo_treat_alt_a*part_treat*post_fe + log_prod|
  firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN)
summary(reg_dist_comp)

reg_dist_comp_2 <- fepois(
  count_roll ~ geo_treat_alt_b*part_treat*post_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN)
summary(reg_dist_comp_2)

################################################################################
## 6. Robustness Table
################################################################################

# ── Label dictionary ──────────────────────────────────────────────────────────


# Baseline: same as reg_innov but with post_fe for comparability
reg_innov_baseline <- fepois(
  count_roll ~ geo_treat*part_treat*post_fe + log_prod|
    firm_city_year_fe + part_city_year_fe,
  data    = event_panel,
  cluster = ~ city_fe + Supplier_PSN
)


plants_coef_dict <- c(
  # Outcomes
  "count_roll"    = "$\\bar{\\text{Patents}}$",
  "appln_count"   = "Patents",
  # Main effects
  "geo_treat"             = "Geo. Treated",
  "part_treatTRUE"        = "Part Treated",
  "post_feTRUE"           = "Post",
  "geo_treat_alt_a"       = "Geo. Treated (250 km)",
  "geo_treat_alt_b"       = "Geo. Treated (400 km)",
  "log_prod"              = "$\\log$ Production",
  # Two-way interactions
  "geo_treat:part_treatTRUE"          = "Geo. $\\times$ Part",
  "geo_treat:post_feTRUE"             = "Geo. $\\times$ Post",
  "part_treatTRUE:post_feTRUE"        = "Part $\\times$ Post",
  "geo_treat_alt_a:part_treatTRUE"    = "Geo.(250) $\\times$ Part",
  "geo_treat_alt_a:post_feTRUE"       = "Geo.(250) $\\times$ Post",
  "part_treatTRUE:post_feTRUE"        = "Part $\\times$ Post",
  "geo_treat_alt_b:part_treatTRUE"    = "Geo.(400) $\\times$ Part",
  "geo_treat_alt_b:post_feTRUE"       = "Geo.(400) $\\times$ Post",
  # Triple interaction (treatment effect of interest)
  "geo_treat:part_treatTRUE:post_feTRUE"       = "Geo. $\\times$ Part $\\times$ Post",
  "geo_treat:part_treat:post_feTRUE"       = "Geo. $\\times$ Part $\\times$ Post",
  "geo_treat_alt_a:part_treatTRUE:post_feTRUE" = "Geo.(250) $\\times$ Part $\\times$ Post",
  "geo_treat_alt_b:part_treatTRUE:post_feTRUE" = "Geo.(400) $\\times$ Part $\\times$ Post",
  # Fixed effects
  "firm_city_year_fe"            = "Firm $\\times$ Location $\\times$ Year",
  "part_city_year_fe"            = "Part $\\times$ Location $\\times$ Year",
  "firm_city_year_event_fe"      = "Firm $\\times$ Location $\\times$ Year $\\times$ Event",
  "part_city_year_event_fe"      = "Part $\\times$ Location $\\times$ Year $\\times$ Event",
  "firm_cntry_part_fe"           = "Firm $\\times$ Country $\\times$ Part",
  "firm_cntry_part_event_fe"     = "Firm $\\times$ Country $\\times$ Part $\\times$ Event"
)

# ── Panel A: Specification Robustness ─────────────────────────────────────────
# Baseline PPML + four specification variants; keep only the triple interaction.

spec_regs <- list(
  reg_innov_baseline,           # (1) Baseline PPML
  reg_innov_app,                # (2) Alt. outcome: patent applications (PPML)
  reg_innov_event_fe,           # (3) OLS, event-interacted FE
  reg_innov_hdfe_2_event_fe,    # (4) PPML + Firm×Country×Part FE
  reg_innov_hdfe_alt_2_event_fe, # (5) PPML + event-interacted Firm×Country×Part FE
  reg_dist_comp,
  reg_dist_comp_2
)

etable(
  spec_regs,
  keep     = c("Geo. \\$\\\\times\\$ Part \\$\\\\times\\$ Post",
               "Geo.\\(250\\) \\$\\\\times\\$ Part \\$\\\\times\\$ Post",
               "Geo.\\(400\\) \\$\\\\times\\$ Part \\$\\\\times\\$ Post"),
  dict     = plants_coef_dict,
  se.below = TRUE,
  tex      = TRUE,
  fitstat  = ~ pr2 + r2 + n,
  digits   = 3, digits.stats = 2,
  style.tex = style.tex("aer"),
  file    = "../Figures/Event_Study_Plants/event_study_plants_robustness_spec.tex",
  replace = TRUE
)

# ── Panel B: Sample Restrictions ─────────────────────────────────────────────

sample_regs <- list(
  reg_innov_baseline,           # (1) Full stacked panel (baseline)
  reg_0_first_event,            # (2) Earliest event only
  reg_0_first_event_collapsed,  # (3) Earliest event, collapsed treatment
  reg_0_nearest_event,          # (4) Nearest event only
  reg_0_nearest_event_collapsed # (5) Nearest event, collapsed treatment
)

etable(
  sample_regs,
  keep     = c("Geo. \\$\\\\times\\$ Part \\$\\\\times\\$ Post"),
  dict     = plants_coef_dict,
  se.below = TRUE,
  tex      = TRUE,
  fitstat  = ~ pr2 + n,
  digits   = 3, digits.stats = 2,
  style.tex = style.tex("aer"),
  extralines = list(
    "Sample"   = c("Full", "First Event", "First (Collapsed)",
                   "Nearest Event", "Nearest (Collapsed)")
  ),
  file    = "../Figures/Event_Study_Plants/event_study_plants_robustness_sample.tex",
  replace = TRUE
)


################################################################################
## 7. Event-Study Coefficient Plot
################################################################################

# Extract the triple-interaction coefficients for one treatment arm into a tidy
# data frame with columns: Year, Estimates, Error, Lower_CI, Upper_CI.
# The reference period (t_ref) is pinned to 0 by convention.
extract_event_study_data <- function(reg, interaction_pattern, t_ref = -1) {
  ct    <- reg$coeftable
  ct    <- ct[grepl(interaction_pattern, rownames(ct)), , drop = FALSE]
  years <- as.integer(sub(".*?(-?\\d+)$", "\\1", rownames(ct)))
  data.frame(
    Year      = c(t_ref, years),
    Estimates = c(0,     ct[, 1]),
    Error     = c(0,     ct[, 2])
  ) %>%
    mutate(
      Lower_CI = Estimates - 1.96 * Error,
      Upper_CI = Estimates + 1.96 * Error
    )
}

# Plot one or more event-study series on a single panel.
#
# series_list  — named list of data frames from extract_event_study_data
# y_label      — y-axis label (plain text; bold formatting applied internally)
# x_label      — x-axis label
# title        — optional plot title
# save_path    — if non-NULL, saves to this path via cairo_pdf
# width/height — dimensions in inches
#
# Returns the ggplot object invisibly so callers can further modify it.
plot_event_study <- function(
    series_list,
    y_label   = "Patents",
    x_label   = "Year Relative to Plant Opening",
    title     = NULL,
    save_path = NULL,
    width     = 10,
    height    = 5
) {
  palette <- c("#2c5f8a", "#b91c1c", "#15803d", "#c9a84c",
               "#525252", "#7c3aed", "#0e7490", "#92400e")

  df <- bind_rows(series_list, .id = "Series") %>%
    mutate(Series = factor(Series, levels = names(series_list)))

  x_min    <- min(df$Year)
  x_max    <- max(df$Year)
  x_breaks <- seq(x_min, x_max, by = 2)
  one_series <- length(series_list) == 1L

  p <- ggplot(df, aes(x = Year, y = Estimates, color = Series)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
    geom_vline(xintercept = 0, linetype = "dashed", color = "black") +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI), width = 0.2) +
    geom_point(size = 2) +
    scale_color_manual(
      values = setNames(palette[seq_along(series_list)], names(series_list))
    ) +
    scale_x_continuous(
      breaks = x_breaks,
      labels = as.character(x_breaks),
      limits = c(x_min, x_max)
    ) +
    labs(
      x     = TeX(paste0("\\textbf{", x_label, "}")),
      y     = TeX(paste0("\\textbf{", y_label, "}")),
      #title = title,
      color = NULL
    ) +
    theme_line() +
    theme(legend.position = if (one_series) "none" else "bottom")

  if (!is.null(save_path)) {
    # Save the plot
    ggsave(save_path, plot = p,  width = width, height = height)   
    message(sprintf("Saved: %s", save_path))
    # Save the plot
    ggsave(substr(save_path,1,nchar(save_path)-4) %>% paste0("_paper.png"), plot = p,  width = 7*1.2, height = 7)   
    message(sprintf("Saved: %s", save_path))
  }

  invisible(p)
}

# ── Extract coefficients ──────────────────────────────────────────────────────

es_direct_baseline_dist    <- extract_event_study_data(reg_0b, "geo_treat:part_treatTRUE:event_time_fe")
es_direct_baseline    <- extract_event_study_data(reg_2, "geo_treat:part_treatTRUE:event_time_fe")
es_direct_baseline_appln    <- extract_event_study_data(reg_2b, "geo_treat:part_treatTRUE:event_time_fe")
es_direct_baseline_hdfe    <- extract_event_study_data(reg_2c, "geo_treat:part_treatTRUE:event_time_fe")
es_direct_event_fe    <- extract_event_study_data(reg_3, "geo_treat:part_treatTRUE:event_time_fe")
es_direct_event_fe_appln    <- extract_event_study_data(reg_3b, "geo_treat:part_treatTRUE:event_time_fe")
es_direct_event_fe_hdfe    <- extract_event_study_data(reg_3c, "geo_treat:part_treatTRUE:event_time_fe")
es_spillover_baseline <- extract_event_study_data(reg_4, "geo_treat_other:part_other:event_time_fe")
es_spillover_event_fe <- extract_event_study_data(reg_5, "treat_other:event_time_fe")
es_spillover_alt      <- extract_event_study_data(reg_6, "geo_treat_other:part_other:event_time_fe")
es_spillover_dist_a   <- extract_event_study_data(reg_7, "geo_treat:part_treatTRUE:event_time_fe")
es_spillover_dist_b   <- extract_event_study_data(reg_7, "geo_treat):part_treatTRUE:event_time_fe")

# ── Plots ─────────────────────────────────────────────────────────────────────

# Direct effect — baseline FE vs. event-interacted FE
plot_event_study(
  list("Baseline FE" = es_direct_baseline_dist),
  title     = "Direct Effect: Supplier Patents near OEM Opening",
  y_label = "Average Distance to Assembly Plants (km)",
  save_path = file.path(OUT_DIR, "event_study_direct_dist.png")
)

# Direct effect — baseline FE vs. event-interacted FE
plot_event_study(
  list("Baseline FE" = es_direct_baseline),
  title     = "Direct Effect: Supplier Patents near OEM Opening",
  save_path = file.path(OUT_DIR, "event_study_direct.png")
)

################################################################################
## 5b. Spillover Test
################################################################################

# # 
# # # Think about this harder. 
# # event_panel_spill <- event_panel %>%
# #   group_by(part_city_year_fe) %>% 
# #   #mutate(treat_other = max(geo_treat*part_treat)-geo_treat*part_treat) %>% ungroup()
# #   mutate(geo_treat_other = max(geo_treat),
# #          part_other = max(part_treat)-part_treat) %>% ungroup()
# # 
# # 
# # reg_4 <- fepois(
# #   count_roll ~ geo_treat_other*part_other*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
# #     firm_city_year_fe + part_cntry_year_fe,
# #   data    = event_panel_spill ,
# #   cluster = ~ city_fe + Supplier_PSN
# # )
# # summary(reg_4)
# # 
# # reg_4 <- fepois(
# #   count_roll ~ geo_treat_other*part_treat_spill*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
# #     firm_city_year_fe + part_cntry_year_fe,
# #   data    = event_panel_spill ,
# #   cluster = ~ city_fe + Supplier_PSN
# # )
# # summary(reg_4)
# # 
# # reg_4 <- fepois(
# #   count_roll ~ geo_treat_other*part_treat_spill*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
# #     firm_city_year_event_fe + part_cntry_year_event_fe,
# #   data    = event_panel_spill ,
# #   cluster = ~ city_fe + Supplier_PSN
# # )
# # summary(reg_4)
# 
# event_panel_spill <- event_panel %>%
#   group_by(part_city_year_event_fe) %>% 
#   mutate(geo_treat_other = max(geo_treat) - geo_treat,
#          part_other = max(part_treat)-part_treat) %>% ungroup()
#   #mutate(treat_other = max(geo_treat*part_treat)-geo_treat*part_treat) #%>% ungroup()
#   #mutate(geo_treat_other = max(geo_treat)-geo_treat,
#   #     part_other = max(part_treat)-part_treat) %>% ungroup()
#  
# reg_5 <- fepois(
#   count_roll ~ geo_treat_other*part_treat_spill_alt*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
#     firm_city_year_event_fe + part_cntry_year_event_fe,
#   data    = event_panel_spill,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_5)
# 
# reg_5 <- fepois(
#   count_roll ~ geo_treat_other*part_treat_spill*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
#     firm_city_year_fe + part_cntry_year_fe,
#   data    = event_panel_spill,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_5)
# 
# 
# event_panel_spill <- event_panel %>%
#   group_by(part_city_year_fe) %>% 
#   mutate(geo_treat_other = max(geo_treat) - geo_treat,
#          part_other = max(part_treat)-part_treat) %>% ungroup()
# 
# reg_5 <- fepois(
#   count_roll ~ geo_treat_other*part_treat_spill*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
#     firm_city_year_fe + part_city_fe + part_year_fe,
#   data    = event_panel_spill %>% mutate(part_city_fe = paste0(Part,city_fe),part_year_fe = paste0(Part,Year)),
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_5)

# 
# 
# 
# 
# 
# reg_5 <- fepois(
#   count_roll ~ geo_treat_other*part_treat_spill*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
#     firm_city_year_event_fe + part_cntry_year_event_fe,
#   data    = event_panel_spill,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_5)
# 
# event_panel_spill <- event_panel %>%
#   group_by(part_city_year_fe) %>% 
#   #mutate(treat_other = max(geo_treat*part_treat)-geo_treat*part_treat) %>% ungroup()
#   mutate(geo_treat_other = max(geo_treat)-geo_treat,
#          part_other = max(part_treat)-part_treat) %>% ungroup()
# 
# reg_6 <- fepois(
#   count_roll ~ geo_treat_other*part_other*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
#     firm_city_year_event_fe + part_cntry_year_event_fe,
#   data    = event_panel_spill,
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_6)
# 
# reg_6b <- fepois(
#   count_roll ~ geo_treat_other*part_treat_spill*event_time_fe + geo_treat*part_treat*event_time_fe + log_prod|
#     firm_city_year_fe + part_cntry_year_fe,
#   data    = event_panel_spill %>% filter(opening_year == min(opening_year)),
#   cluster = ~ city_fe + Supplier_PSN
# )
# summary(reg_6b)