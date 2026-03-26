# Data Management

**Applies to:** `Empirics/**`, `Simulation/**`, `workflow/scripts/**/*.R`

This project uses large proprietary datasets. These rules govern what is committed, what is gitignored, and how data pipelines are structured for reproducibility.

---

## 1. Data Sources

| Source | Description | Location |
|--------|-------------|----------|
| **IHS Markit** | Global automotive supply chain data — firm-plant linkages, production volumes, buyer-supplier relationships | `Empirics/Data/` (gitignored) |
| **PATSTAT** | EPO patent data — applications, citations, inventor locations, IPC classifications | `Empirics/Data/` (gitignored) |
| **Trade data** | HS-level trade flows — US imports/exports, NAFTA, HS2 aggregates | `Empirics/Data/` (gitignored) |
| **WIOD** | World Input-Output Database — for macro aggregates | `Empirics/Data/` (gitignored) |
| **Revelio Labs** | Employment data for inventors and R&D workers | `Empirics/Data/` (gitignored) |

Raw data is **never committed** to the repository. It is proprietary or too large (multi-GB files). Data lives on local machine at the path defined in each script's header.

---

## 2. What Is Gitignored vs. Tracked

### NEVER commit
- `Empirics/Data/**` — all raw and intermediate data files
- `Simulation/Data/*.csv` — large formatted inputs for GMM
- `Simulation/Output/**` — model estimation output (large, regenerable)
- Any file > 50MB

### Commit with care
- `.rds` files < 50MB that are expensive to regenerate and needed by downstream scripts — document each one in the script that creates it
- Final paper figures (`Figures/*.pdf`, `Empirics/Figures/*.pdf`) — commit final versions used in the paper

### Always commit
- All R scripts (`Empirics/Code/*.R`)
- All Julia scripts (`Simulation/Code/*.jl`, `Theory/Code/*.jl`)
- `Project.toml` for Julia environments
- `workflow/scripts/run_pipeline.R` (master pipeline, see below)
- Bibliography and LyX source files

---

## 3. Data Loading Convention

Every R script that loads raw data defines its data path as a variable at the top of the script:

```r
# ── Paths ──────────────────────────────────────────────────────────────────
DATA_DIR  <- "Empirics/Data"        # relative to project root
OUT_DIR   <- "Empirics/Figures"
# Run from project root: Rscript Empirics/Code/analysis_main.R
```

- **Always run scripts from the project root**, not from the script's directory.
- Never use `setwd()` inside scripts.
- Use `here::here()` or explicit relative paths from project root.

For Julia scripts loading data:
```julia
DATA_DIR = joinpath(@__DIR__, "../../Empirics/Data")
OUT_DIR  = joinpath(@__DIR__, "../../Simulation/Output")
```

---

## 4. Pipeline Order

The full data pipeline runs in this order:

```
Raw data (Empirics/Data/) — external, not in repo
    │
    ├─ 1. data_patstat.R          — Process PATSTAT patent data
    ├─ 2. data_patents.R          — Aggregate patent counts
    ├─ 3. data_plant_locations.R  — Process IHS plant locations
    ├─ 4. data_price.R            — Price index data
    ├─ 5. data_revelio.R          — Employment data
    ├─ 6. data_spillovers.R       — Construct spillover measures
    ├─ 7. data_final.R            — Assemble final analysis dataset
    │
    ├─ 8. analysis_summary_stats.R — Descriptive statistics
    ├─ 9. analysis_main.R          — Main empirical specifications
    ├─ 10. analysis_intro.R        — Introduction figures
    ├─ 11. analysis_citations.R    — Patent citation analysis
    ├─ 12. analysis_measures.R     — Innovation measure construction
    ├─ 13. analysis_event_study_tariffs.R — Tariff event study
    │
    └─ 14. data_format_GMM.R      — Format data for Julia GMM estimation
         └─ GMM_OEM_assembly.jl  — Structural estimation (Julia)
              └─ data_analysis_GMM_Figures.R — GMM results figures
```

A master pipeline script at `workflow/scripts/run_pipeline.R` documents this order (created when pipeline is stable enough to run end-to-end).

---

## 5. Reproducibility Checkpoints

Mark scripts as either:

- **Safe to re-run from scratch:** Script reads only raw data or tracked `.rds` files. Re-running produces identical output.
- **Requires upstream output:** Script reads intermediate files. Document which upstream script produces them in a comment at the top.

Example header comment:
```r
# Requires: Empirics/Data/data_analysis_final.csv
#           (produced by data_final.R)
# Produces: Empirics/Figures/Main/supply_chain_map.pdf
#           Empirics/Figures/Main/hhi_trends.pdf
```

---

## 6. Figure Management

| Figure Type | Location | Committed? |
|-------------|----------|-----------|
| Final paper figures | `Figures/` or `Empirics/Figures/Main/` | Yes |
| Diagnostic/exploratory figures | `Empirics/Figures/Scratch/` | No (gitignored) |
| Introduction figures | `Empirics/Figures/Intro/` | Yes (if used in paper) |
| IV figures | `Empirics/Figures/IV/` | Yes (if used in paper) |

All figures saved by R scripts use:
```r
ggsave("Empirics/Figures/Main/figure_name.pdf", plot = p,
       width = 6.5, height = 4, units = "in", device = cairo_pdf)
```

---

## 7. Large File Alternatives

If collaborators need access to data not in the repo:
- IHS data: Provide access via institutional license
- Intermediate processed data: Share via Dropbox at `~/Dropbox/Repos/Research/outsourcing_innovation/Empirics/Data/`
- Model output: Share via Dropbox at `~/Dropbox/Repos/Research/outsourcing_innovation/Simulation/Output/`

Document data locations in `workflow/quality_reports/data-locations.md` (create when needed).
