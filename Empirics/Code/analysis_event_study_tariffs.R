# Clear environment 
rm(list = ls())

# Load packages
library(tidyverse)
library(stringr)
library(zoo)
library(fixest)
library(haven)
library(readxl)
library(concordance)

# Plot themes
source("themes.R")

# Directories
BACI <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data/trade/BACI_HS12_V202601/"
DATA_DIR <- "/Users/adrkul/Library/CloudStorage/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data"

# Settings
t_0 = 2014
t_ref = 2017
t_fin = 2024

################################################################################
## Identification
################################################################################

auto_parts <- c(
  "ADAS / AD",
  "Air Conditioning / HVAC",
  "Airbag & Safety Related Products",
  "Body / Structure / Module / Others",
  "Body Components",
  "Brake",
  "Drive Battery",
  "Driveline (Axle / Drive Shaft /",
  "Electric Powertrain Related Parts",
  "Engine (Cooling System)",
  "Engine (Fuel / Injection System)",
  "Engine (Ignition System)",
  "Engine (Intake / Exhaust System)",
  "Engine (Lubrication System)",
  "Engine (Main Engine Parts)",
  "Engine (Starter/Battery System)",
  "Engine (Valve Train System)",
  "Exterior",
  "IVI System",
  "Interior",
  "Lamp & Related Products",
  "Motor / Actuator",
  "Seat Related Products",
  "Security",
  "Steering",
  "Suspension / Subframe",
  "Switch / Connector / Harness / Other Electronics",
  "Transmission / Clutch",
  "Various ECUs",
  "Various Sensors",
  "Wheel & Tire"
)

# classify exposure to Section 232 metals tariffs (steel/aluminum)
exposure <- c(
  "Low",   # ADAS / AD – electronics/plastics
  "Medium",# HVAC – aluminum tubing, steel brackets
  "Low",   # Airbag & Safety – textiles/electronics
  "High",  # Body / Structure / Module / Others – sheet steel/aluminum
  "High",  # Body Components – panels, doors
  "High",  # Brake – rotors, calipers (steel/aluminum)
  "Medium",# Drive Battery – mainly cells but metal casings
  "High",  # Driveline – shafts, housings
  "Medium",# Electric Powertrain – cast aluminum housings
  "High",  # Engine (Cooling) – radiators, pumps (aluminum)
  "High",  # Engine (Fuel/Injection) – metal components
  "Low",   # Engine (Ignition) – electronics
  "High",  # Engine (Intake/Exhaust) – manifolds, pipes
  "High",  # Engine (Lubrication) – housings, pumps
  "High",  # Engine (Main Engine Parts) – blocks, heads
  "High",  # Engine (Starter/Battery) – housings, gears
  "High",  # Engine (Valve Train) – cams, springs
  "Medium",# Exterior – mixed materials
  "Low",   # IVI System – electronics
  "Low",   # Interior – plastics/textiles
  "Low",   # Lamp & Related – plastics/electronics
  "Medium",# Motor / Actuator – steel housings
  "Medium",# Seat Related – seat frames (steel)
  "Low",   # Security – sensors/electronics
  "High",  # Steering – column, rack (steel/aluminum)
  "High",  # Suspension / Subframe – structural metal
  "Low",   # Switch / Connector / Harness – electronics
  "High",  # Transmission / Clutch – steel/aluminum parts
  "Low",   # Various ECUs – circuit boards
  "Low",   # Various Sensors – small electronics
  "High"   # Wheel & Tire – wheel rims (steel/aluminum)
)


tariff_exposure_df = data.frame(
  Part = auto_parts,
  Exposure_to_Steel_Aluminum_Tariffs = exposure
)

tariff_exposure_df$Exposure_to_Steel_Aluminum_Tariffs <- factor(
  tariff_exposure_df$Exposure_to_Steel_Aluminum_Tariffs,
  levels = c("Low", "Medium", "High") 
)

tariff_exposure_df = tariff_exposure_df %>% 
  mutate(Exposure_to_Steel_Aluminum_Tariffs_agg = if_else(Exposure_to_Steel_Aluminum_Tariffs == "Low", 0, 1)) %>% 
  mutate(Exposure_to_Steel_Aluminum_Tariffs_high = if_else(Exposure_to_Steel_Aluminum_Tariffs == "High", 1, 0))


################################################################################
## Trade Data
################################################################################

# HS Codes to Parts
HS_codes = read_csv(file.path(DATA_DIR, 'tariffs/auto_parts_hs12_classified_2.csv')) %>% 
  rename("HS12" = "HS Code",
         "Part" = "Auto Part") %>% 
  mutate(HS12 = as.character(HS12))  %>% 
  filter(HS12 != "851989") 

trade_data = tibble()
directory_path =  paste0(BACI,"data")
filenames = list.files(directory_path, pattern = "\\.csv$")

for (filename in filenames) {
  
  file_path = file.path(directory_path, filename)
  df_raw = read_csv(file_path)
  df_raw = df_raw %>%
    left_join(HS_codes, by = c("k" = "HS12")) %>% 
    filter(!is.na(Part)) %>% 
    group_by(t,i,j,k,Part) %>%
    summarise(v = sum(v,na.rm = TRUE),
              q = sum(q,na.rm = TRUE))
  
  trade_data = bind_rows(trade_data, df_raw)
  
}

trade_data_event_study = trade_data %>% 
  mutate(NAFTA_i = if_else(i %in% c(842,124,484),1,0)) %>% 
  group_by(t,j,k,Part) %>%
  summarize(v_NAFTA = sum(v*NAFTA_i),
            q_NAFTA = sum(q*NAFTA_i),
            v = sum(v),
            q = sum(q)) %>% ungroup %>% 
  mutate(USA_ind = if_else(j %in% c(842),1,0)) %>% 
  mutate(NAFTA_ind = if_else(j %in% c(842,124,484),1,0)) %>% 
  left_join(tariff_exposure_df, by = c("Part" = "Part")) %>%
  mutate(Year_fe = as.factor(paste0(t))) %>% 
  mutate(Year_fe = relevel(Year_fe, ref = as.character(t_ref))) %>% 
  filter(t >= t_0) %>% 
  mutate(jt = paste(0,j,t),
         kt = paste0(k,t),
         jk = paste0(j,k))

################################################################################
## Patent Data
################################################################################

# Patent Data
patent_data = read_csv(file.path(DATA_DIR, "output/final/data_supplier_patents_2026.csv")) %>%
  left_join(tariff_exposure_df, by = c("Part" = "Part")) %>% 
  filter(Year >= t_0) %>% 
  filter(Year <= t_fin) %>% 
  mutate(Year_fe = as.factor(paste0(Year))) %>% 
  mutate(Year_fe = relevel(Year_fe, ref = as.character(t_ref))) %>% 
  mutate(Country_Year_fe = paste0(Country,Year_fe),
         Country_Part_fe = paste0(Country,Part),
         Part_Year_fe = paste0(Part,Year_fe),
         Firm_Country_fe = paste0(Supplier_PSN,Country),
         Firm_Year_fe = paste0(Supplier_PSN,Year_fe),
         Firm_Part_fe = paste0(Supplier_PSN,Part)) %>% ungroup() %>% 
  mutate(USA_ind = country_code == "USA") 

################################################################################
## Production Data
################################################################################

# Supplier Production Data
supplier_exposure = read_csv(file.path(DATA_DIR, "output/final/supplier_aggregate_production_data.csv")) %>% 
  select(Supplier_PSN, Part, Year, prod_all) %>% 
  filter(Year <= t_ref) %>%
  left_join(tariff_exposure_df, by = c("Part" = "Part")) %>% 
  group_by(Supplier_PSN) %>% 
  summarise(exposure = sum(prod_all*Exposure_to_Steel_Aluminum_Tariffs_agg,na.rm = TRUE)/sum(prod_all,na.rm = TRUE)) %>% ungroup()

################################################################################
## Workers Data
################################################################################

df_workers_technical = read_csv(file.path(DATA_DIR, "output/final/revelio_workers_engineers.csv")) %>% 
  rename("workers_technical" = "n",
         "workers_technical_total" = "n_total") 

df_workers_education = read_csv(file.path(DATA_DIR, "output/final/revelio_workers_education.csv")) %>% 
  select(!n_total) %>%
  rename("workers_education" = "n") %>% 
  filter(!is.na(highest_degree)) %>% 
  group_by(PSN,country_code, highest_degree, year) %>%
  summarise(workers_education = sum(workers_education,na.rm=TRUE)) %>% ungroup() %>%
  pivot_wider(names_from = highest_degree, values_from = workers_education, values_fill = 0) 

df_workers_technical = df_workers_technical %>% 
  left_join(df_workers_education, by = c("PSN" = "PSN", "country_code" = "country_code", "year" = "year"))

worker_data = df_workers_technical %>% 
  filter(year >= t_0) %>% 
  filter(year <= t_fin) %>% 
  left_join(supplier_exposure, by = c("PSN" = "Supplier_PSN")) %>% 
  filter(!is.na(exposure)) %>% 
  mutate(Year_fe = as.factor(paste0(year))) %>% 
  mutate(Year_fe = relevel(Year_fe, ref = as.character(t_ref)))  %>% 
  mutate(Country_Year_fe = paste0(country_code,Year_fe),
         Firm_Country_fe = paste0(PSN,country_code),
         Firm_Year_fe = paste0(PSN,Year_fe),
         Firm_Country_Year_fe = paste0(PSN,Year_fe,Year_fe)) %>% 
  filter(!is.na(country_code)) %>% 
  mutate(USA_ind = country_code == "USA") 

################################################################################
## Analysis - Functions
################################################################################

extract_event_study_data <- function(reg, t_ref, interaction_pattern = "Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe") {
  
  # Extract coefficient table
  coeff_table <- reg$coeftable
  
  # Filter for interaction terms
  coeff_table <- coeff_table[grepl(interaction_pattern, rownames(coeff_table)), ]
  
  # Extract years from row names
  years <- as.numeric(substr(rownames(coeff_table), 
                             nchar(rownames(coeff_table)) - 3, 
                             nchar(rownames(coeff_table))))
  
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



event_study_plot <- function(figure_name, 
                             event_study_list, 
                             type_labels,
                             colors = c("steelblue", "firebrick"),
                             legend_position = c(0.80, 0.10),
                             ylab = "\\textbf{Coefficient Estimate}",
                             xlab = "\\textbf{Year}",
                             event_y = 1.0,
                             y_lims = NULL) {
  
  # Combine data frames with offset for visual separation
  offset_increment <- 0.20
  event_study_df <- NULL
  
  for (i in seq_along(event_study_list)) {
    df <- event_study_list[[i]] %>% 
      mutate(Type = type_labels[i],
             Year_offset = Year + (i - 1) * offset_increment - offset_increment * (length(event_study_list) - 1) / 2)
    
    if (is.null(event_study_df)) {
      event_study_df <- df
    } else {
      event_study_df <- rbind(event_study_df, df)
    }
  }
  
  # Get year range
  years <- sort(unique(event_study_df$Year))
  
  # Create the plot
  p = ggplot(event_study_df, aes(x = Year_offset, y = Estimates, color = Type)) +
    geom_errorbar(aes(ymin = Lower_CI, ymax = Upper_CI), width = 0.2, alpha = 1) +
    geom_point(size = 2, alpha = 1) +
    scale_color_manual(values = colors) + 
    scale_fill_manual(values = colors) + 
    geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
    xlab(TeX(xlab)) +
    ylab(TeX(ylab)) +
    theme_line() + 
    theme(legend.position = legend_position) + 
    scale_x_continuous(
      breaks = seq(t_0, years[length(years)], 1),
      labels = as.character(seq(t_0, years[length(years)], 1)),
      limits = c(t_0 - 0.25, years[length(years)] + 0.25)) + 
    geom_vline(xintercept = 2018, linetype = "dashed", color = "black") +
    geom_vline(xintercept = 2020, linetype = "dashed", color = "seagreen") +
    annotate("text", x = 2018, y = max(event_study_df$Upper_CI)*0.80, label = "USMCA Agreement & Tariffs", angle = 90, vjust = -0.4, size = 3.5, color = "black", fontface = "bold") +
    annotate("text", x = 2020, y = max(event_study_df$Upper_CI)*0.90, label = "USMCA Ratified", angle = 90, vjust = -0.4, size = 3.5, color = "seagreen", fontface = "bold")
  
  if (!is.null(y_lims)) {
    p = p + scale_y_continuous(limits = y_lims)
  }
  
  # Save the plot
  ggsave(
    figure_name,
    plot = p,  width = 7.0*1.2,
    height = 7.0)   
  
  # Show image
  print(p)
  
}

################################################################################
## Trade Outcomes
################################################################################

reg_1 = feols(I(log(v_NAFTA)) ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | jk + jt + kt, data = trade_data_event_study, se = "hetero")
summary(reg_1)

reg_2 = feols(I(log(v_NAFTA/v)) ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | jk + jt + kt, data = trade_data_event_study, se = "hetero")
summary(reg_2)

event_study_list = list(extract_event_study_data(reg_1, t_ref, interaction_pattern = "USA_ind:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"),
                        extract_event_study_data(reg_2, t_ref, interaction_pattern = "USA_ind:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"))

event_study_plot("../Figures/Event_Study_Tariffs/imports_world.png", 
                 event_study_list, 
                 c("NAFTA Imports","NAFTA Import Share"),
                 legend_position = c(0.16, 0.91),
                 ylab = "\\beta \\textbf{: log Imports}",
                 xlab = "\\textbf{Year}",
                 event_y = 1.0)

################################################################################
## Innovation & Worker Outcomes
################################################################################

reg_1 = fepois(appln_count ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | Firm_Year_fe + Firm_Country_fe + Country_Year_fe + Country_Part_fe + Part_Year_fe + Firm_Part_fe, data = patent_data, se = "hetero")
summary(reg_1)

reg_2 = fepois(workers_technical ~ USA_ind*exposure*Year_fe | Firm_Year_fe + Firm_Country_fe + Country_Year_fe, data = worker_data, se = "hetero")
summary(reg_2)

event_study_list = list(extract_event_study_data(reg_1, t_ref, interaction_pattern = "USA_indTRUE:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"),
                        extract_event_study_data(reg_2, t_ref, interaction_pattern = "USA_indTRUE:exposure:Year_fe"))

event_study_plot("../Figures/Event_Study_Tariffs/innovation_world.png", 
                 event_study_list, 
                 c("Patents","R&D Workers"),
                 legend_position = c(0.16, 0.91),
                 ylab = "\\beta \\textbf{: log Patents}",
                 xlab = "\\textbf{Year}",
                 event_y = 1.0)


reg_3 = fepois(Doctor ~ USA_ind*exposure*Year_fe | Firm_Year_fe + Firm_Country_fe + Country_Year_fe, data = worker_data, se = "hetero")
summary(reg_3)

event_study_list = list(extract_event_study_data(reg_3, t_ref, interaction_pattern = "USA_indTRUE:exposure:Year_fe"))

event_study_plot("../Figures/Event_Study_Tariffs/doctor.png", 
                 event_study_list, 
                 c("Doctorate Workers"),
                 legend_position = c(0.16, 0.91),
                 ylab = "\\beta \\textbf{: log Employment}",
                 xlab = "\\textbf{Year}",
                 event_y = 1.0)


patent_data_hdfe = patent_data %>% 
  mutate(firm_cntry_year_fe = paste0(Supplier_PSN, Country, Year_fe)) %>%
  mutate(firm_part_year_fe = paste0(Supplier_PSN, Part, Year_fe))  

reg_1 = fepois(appln_count ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | firm_cntry_year_fe + Country_Part_fe + Part_Year_fe + Firm_Part_fe, data = patent_data_hdfe, se = "hetero")
summary(reg_1)

reg_2 = fepois(appln_count ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | Firm_Country_fe + Country_Year_fe + Country_Part_fe + firm_part_year_fe, data = patent_data_hdfe, se = "hetero")
summary(reg_2)

event_study_list = list(extract_event_study_data(reg_1, t_ref, interaction_pattern = "USA_indTRUE:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"),
                        extract_event_study_data(reg_2, t_ref, interaction_pattern = "USA_indTRUE:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"))

event_study_plot("../Figures/Event_Study_Tariffs/innovation_hdfe.png", 
                 event_study_list, 
                 c("Patents (f,c,t) Fixed Effect","Patents (f,p,t) Fixed Effect"),
                 legend_position = c(0.16, 0.91),
                 ylab = "\\beta \\textbf{: log Patents}",
                 xlab = "\\textbf{Year}",
                 event_y = 1.0)


################################################################################
## Additional Trade Outcomes -
################################################################################

trade_data_event_study_alt = trade_data %>% 
  group_by(t,i,k,Part) %>%
  summarize(v = sum(v),
            q = sum(q)) %>% ungroup %>% 
  mutate(USA_ind = if_else(i %in% c(842),1,0)) %>% 
  left_join(tariff_exposure_df, by = c("Part" = "Part")) %>%
  mutate(Year_fe = as.factor(paste0(t))) %>% 
  mutate(Year_fe = relevel(Year_fe, ref = as.character(t_ref))) %>% 
  filter(t >= t_0) %>% 
  mutate(it = paste(0,i,t),
         kt = paste0(k,t),
         ik = paste0(i,k))


reg_1 = feols(I(log(v_NAFTA/q_NAFTA)) ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | jk + jt + kt, data = trade_data_event_study, se = "hetero")
summary(reg_1)

reg_2 = feols(I(log(q_NAFTA)) ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | jk + jt + kt, data = trade_data_event_study, se = "hetero")
summary(reg_2)

event_study_list = list(extract_event_study_data(reg_1, t_ref, interaction_pattern = "USA_ind:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"),
                        extract_event_study_data(reg_2, t_ref, interaction_pattern = "USA_ind:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"))

event_study_plot("../Figures/Event_Study_Tariffs/import_margins_world.png", 
                 event_study_list, 
                 c("NAFTA Import Unit Values","NAFTA Import Quantities"),
                 legend_position = c(0.16, 0.91),
                 ylab = "\\beta \\textbf{: log Import Margins}",
                 xlab = "\\textbf{Year}",
                 event_y = 1.0)

reg_3 = feols(I(log(v)) ~ USA_ind*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | ik + it + kt, data = trade_data_event_study_alt, se = "hetero")
summary(reg_3)

event_study_list = list(extract_event_study_data(reg_3, t_ref, interaction_pattern = "USA_ind:Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"))

event_study_plot("../Figures/Event_Study_Tariffs/exports_world.png", 
                 event_study_list, 
                 c("Exports"),
                 legend_position = c(0.16, 0.91),
                 ylab = "\\beta \\textbf{: log Exports}",
                 xlab = "\\textbf{Year}",
                 event_y = 1.0)

trade_data_event_study_USA_imports = trade_data %>% 
  filter(j == 842) %>%
  group_by(t,i,k,Part) %>%
  summarise(v = sum(v,na.rm=TRUE)) %>% ungroup %>%
  mutate(NAFTA_i = if_else(i %in% c(842,124,484),1,0)) %>% 
  left_join(tariff_exposure_df, by = c("Part" = "Part")) %>%
  mutate(Year_fe = as.factor(paste0(t))) %>% 
  mutate(Year_fe = relevel(Year_fe, ref = as.character(t_ref))) %>% 
  filter(t >= t_0) %>% 
  mutate(i = paste0(i),
         it = paste0(i,t),
         kt = paste0(k,t),
         ik = paste0(i,k)) 

reg_3 = feols(I(log(v)) ~ NAFTA_i*Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | ik + it + kt, data = trade_data_event_study_USA_imports, se = "hetero")
summary(reg_3)


# CEPII distances
data_dist = read_dta(file.path(DATA_DIR, "other/dist_cepii.dta")) %>% 
  mutate(iso_o = if_else(iso_o == "ROM", "ROU", iso_o)) %>% # Update old Romania code
  mutate(iso_d = if_else(iso_d == "ROM", "ROU", iso_d)) %>%
  mutate(iso_o = if_else(iso_o == "YUG", "SRB", iso_o)) %>% # Yugoslavia as approximation for Serbia
  mutate(iso_d = if_else(iso_d == "YUG", "SRB", iso_d)) 

codes = read_csv(file.path(DATA_DIR, "trade/BACI_HS12_V202601/country_codes_V202601.csv")) %>% 
  select(country_code, country_iso3)

trade_data_dist = trade_data %>% 
  left_join(codes, by = c("i" = "country_code")) %>%
  rename(iso_o = country_iso3) %>%
  left_join(codes, by = c("j" = "country_code")) %>%
  rename(iso_d = country_iso3) %>%
  left_join(data_dist, by = c("iso_o", "iso_d")) %>%
  filter(j == 842) %>%
  group_by(t,k,Part) %>%
  summarise(dist_v = weighted.mean(distw,w=v,na.rm=TRUE),
            dist_q = weighted.mean(distw,w=q,na.rm=TRUE),) %>% ungroup() %>% 
  left_join(tariff_exposure_df, by = c("Part" = "Part")) %>%
  mutate(Year_fe = as.factor(paste0(t))) %>% 
  mutate(Year_fe = relevel(Year_fe, ref = as.character(t_ref))) %>% 
  filter(t >= t_0) %>% 
  mutate(kt = paste0(k,t))


reg_1 = feols(I((dist_v)) ~ Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | k + t, data = trade_data_dist, se = "hetero")
summary(reg_1)

reg_2 = feols(I((dist_q)) ~ Exposure_to_Steel_Aluminum_Tariffs_agg*Year_fe | k + t, data = trade_data_dist, se = "hetero")
summary(reg_2)


event_study_list = list(extract_event_study_data(reg_1, t_ref, interaction_pattern = "Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"),
                        extract_event_study_data(reg_2, t_ref, interaction_pattern = "Exposure_to_Steel_Aluminum_Tariffs_agg:Year_fe"))

event_study_plot("../Figures/Event_Study_Tariffs/import_distance.png", 
                 event_study_list, 
                 c("Average Import Distance (Value Weighted)","Average Import Distance (Quantity Weighted)"),
                 legend_position = c(0.30, 0.10),
                 ylab = "\\beta \\textbf{: Import Distance}",
                 xlab = "\\textbf{Year}",
                 event_y = 1.0)