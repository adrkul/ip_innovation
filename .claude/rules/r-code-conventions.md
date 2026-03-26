---
paths:
  - "**/*.R"
  - "Figures/**/*.R"
  - "workflow/scripts/**/*.R"
---

# R Code Standards

**Standard:** Senior Principal Data Engineer + PhD researcher quality

---

## 1. Reproducibility

- `set.seed()` called ONCE at top (YYYYMMDD format)
- All packages loaded at top via `library()` (not `require()`)
- All paths relative to repository root
- `dir.create(..., recursive = TRUE)` for output directories

## 2. Function Design

- `snake_case` naming, verb-noun pattern
- Roxygen-style documentation
- Default parameters, no magic numbers
- Named return values (lists or tibbles)

## 3. Domain Correctness

- Verify estimator formulas match paper specifications exactly
- Check that HHI and market structure measures use the correct weighting scheme (document in comments)
- Verify SE computation method (clustering level, package) matches what is reported in the paper
- Check IHS/PATSTAT data joins for many-to-many issues (always verify N before and after merge)
- Check known package bugs (document below in Common Pitfalls)

## 4. Visual Identity

```r
# --- Publication palette (neutral, journal-compatible) ---
primary_blue   <- "#2c5f8a"
accent_gray    <- "#525252"
positive_green <- "#15803d"
negative_red   <- "#b91c1c"
highlight_gold <- "#c9a84c"
```

### Custom Theme
```r
theme_paper <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      plot.title = element_text(face = "bold", size = base_size),
      legend.position = "bottom",
      strip.text = element_text(face = "bold")
    )
}
```

### Figure Dimensions for Paper

Single-column figure (half-page width):
```r
ggsave(filepath, width = 3.5, height = 3.5, units = "in", device = cairo_pdf)
```

Full-width figure:
```r
ggsave(filepath, width = 6.5, height = 4.0, units = "in", device = cairo_pdf)
```

Use `cairo_pdf` for proper Unicode and font embedding. No `bg = "transparent"` needed for paper figures.

## 5. RDS Data Pattern

**Heavy computations saved as RDS; downstream analysis scripts load pre-computed data.**

```r
saveRDS(result, file.path(OUT_DIR, "descriptive_name.rds"))
```

## 6. Common Pitfalls

| Pitfall | Impact | Prevention |
|---------|--------|------------|
| Hardcoded paths | Breaks on other machines | Use relative paths from project root |
| IHS non-ASCII firm names | Join failures | `read_csv(..., locale = locale(encoding = "UTF-8"))` |
| Many-to-many patent-firm joins | Inflated counts | Check `nrow()` before and after; use `left_join` with explicit key |
| Unweighted vs. weighted HHI | Different results | Specify weighting scheme in comment; match paper definition |
| `feols` vs `lm_robust` SE differences | Different SEs | Pin package version; document SE method used |

## 7. Line Length & Mathematical Exceptions

**Standard:** Keep lines <= 100 characters.

**Exception: Mathematical Formulas** -- lines may exceed 100 chars **if and only if:**

1. Breaking the line would harm readability of the math (influence functions, matrix ops, finite-difference approximations, formula implementations matching paper equations)
2. An inline comment explains the mathematical operation:
   ```r
   # Sieve projection: inner product of residuals onto basis functions P_k
   alpha_k <- sum(r_i * basis[, k]) / sum(basis[, k]^2)
   ```
3. The line is in a numerically intensive section (simulation loops, estimation routines, inference calculations)

**Quality Gate Impact:**
- Long lines in non-mathematical code: minor penalty (-1 to -2 per line)
- Long lines in documented mathematical sections: no penalty

## 8. Code Quality Checklist

```
[ ] Packages at top via library()
[ ] set.seed() once at top
[ ] All paths relative
[ ] Functions documented (Roxygen)
[ ] Figures: transparent bg, explicit dimensions
[ ] RDS: every computed object saved
[ ] Comments explain WHY not WHAT
```
