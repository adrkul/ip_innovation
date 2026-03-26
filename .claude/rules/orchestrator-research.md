---
paths:
  - "workflow/scripts/**/*.R"
  - "workflow/explorations/**"
  - "Empirics/Code/**"
  - "Simulation/Code/**"
  - "Theory/Code/**"
---

# Research Project Orchestrator (Simplified)

**For R scripts, Julia scripts, simulations, and data analysis** — use this simplified loop instead of the full multi-agent orchestrator.

## The Simple Loop

```
Plan approved → orchestrator activates
  │
  Step 1: IMPLEMENT — Execute plan steps
  │
  Step 2: VERIFY — Run code, check outputs
  │         R scripts: Rscript runs without error
  │         Julia scripts: julia runs without error, converged = true
  │         Simulations: set.seed / Random.seed! reproducibility
  │         Plots: PDF/PNG created, correct dimensions
  │         If verification fails → fix → re-verify
  │
  Step 3: SCORE — Apply quality-gates rubric
  │
  └── Score >= 80?
        YES → Done (commit when user signals)
        NO  → Fix blocking issues, re-verify, re-score
```

**No 5-round loops. No multi-agent reviews. Just: write, test, done.**

## Verification Checklist

### R Scripts
- [ ] Script runs without errors: `Rscript Empirics/Code/filename.R`
- [ ] All packages loaded at top via `library()`
- [ ] No hardcoded absolute paths
- [ ] `set.seed()` once at top if stochastic
- [ ] Output files created at expected paths in `Empirics/Figures/` or as `.rds`
- [ ] Quality score >= 80

### Julia Scripts
- [ ] Script runs without errors: `julia --project=Simulation/Code script.jl`
- [ ] `Random.seed!` present if random operations used
- [ ] No hardcoded absolute paths
- [ ] Convergence flag checked: `converged = true`
- [ ] Output saved to timestamped directory in `Simulation/Output/`
- [ ] Quality score >= 80
