---
paths:
  - "Empirics/Code/**"
  - "Simulation/Code/**"
  - "scripts/**/*.R"
---

# Replication-First Protocol

**Core principle:** Verify results match expected targets BEFORE extending or modifying.

This applies to both (1) replicating existing external papers' results with our data and (2) verifying our own results are stable across code changes.

---

## Phase 1: Inventory & Baseline

Before writing any code:

- [ ] Read the relevant paper section or existing analysis
- [ ] Inventory inputs: data files, scripts, estimated parameters, key outputs
- [ ] Record gold standard numbers (from existing paper draft or previous run):

```markdown
## Replication Targets: [Analysis Name]

| Target | Table/Figure | Value | SE/CI | Notes |
|--------|-------------|-------|-------|-------|
| Main coefficient | Table 2, Col 3 | -1.632 | (0.584) | Primary specification |
| GMM parameter σ | Table 4 | 2.14 | (0.31) | Baseline estimation |
```

- [ ] Store targets in `quality_reports/replication_targets/YYYY-MM-DD_analysis-name.md`

---

## Phase 2: Translate & Execute

- [ ] Follow `r-code-conventions.md` or `julia-code-conventions.md` for all coding standards
- [ ] Match original specification exactly (covariates, sample, clustering, SE computation)
- [ ] Save all intermediate results as RDS (R) or JLD2 (Julia)
- [ ] Document data source and vintage used

### Common Pitfalls (Empirics)

| Situation | Trap | Prevention |
|-----------|------|------------|
| IHS data encoding | Non-ASCII firm names cause join failures | Use `encoding = "UTF-8"` in `read_csv()` |
| PATSTAT matching | Patent-firm concordance has many-to-many issues | Always verify match counts before aggregating |
| HHI computation | Weighted vs. unweighted HHI gives different results | Document weighting scheme explicitly |
| Clustering | SE computation differs by package/method | Pin package version; document SE method |
| Japan IV | IHS Japan data has different coverage years | Check sample overlap explicitly |

### Common Pitfalls (GMM Estimation)

| Situation | Trap | Prevention |
|-----------|------|------------|
| Local optima | Multi-start finds different solutions | Always run multi-start; report best objective |
| Inner loop divergence | Fixed point fails to converge | Check `inner_tol`, log iteration counts |
| Weighting matrix | First-step vs. two-step weights differ | Document which step is being estimated |
| Parallel seeds | Workers have different random states | Set per-worker seed explicitly |

---

## Phase 3: Verify Match

### Tolerance Thresholds

| Type | Tolerance | Rationale |
|------|-----------|-----------|
| Observation counts (N) | Exact match | No reason for any difference |
| Point estimates (empirics) | < 0.01 in absolute value | Rounding in paper display |
| Standard errors | < 0.05 in absolute value | Bootstrap/clustering variation |
| GMM parameter estimates | < 1e-4 | Numerical optimization tolerance |
| P-values | Same significance level | Exact p may differ slightly |
| Convergence | Must be `true` | Never report estimates from non-converged runs |

### If Mismatch

**Do NOT proceed to extensions.** Isolate which step introduces the difference. Check:
1. Sample selection (N mismatch)
2. Variable construction (definition differences)
3. SE computation method
4. Numerical tolerance settings

Document investigation even if unresolved.

### Replication Report

Save to `quality_reports/replication_targets/YYYY-MM-DD_analysis-name_report.md`:

```markdown
# Replication Report: [Analysis Name]
**Date:** [YYYY-MM-DD]
**Script:** [path/to/script.R or .jl]

## Summary
- **Targets checked / Passed / Failed:** N / M / K
- **Overall:** [REPLICATED / PARTIAL / FAILED]

## Results Comparison

| Target | Expected | Ours | Diff | Status |
|--------|----------|------|------|--------|

## Discrepancies (if any)
- **Target:** X | **Investigation:** ... | **Resolution:** ...

## Environment
- R version / Julia version, key packages with versions, data vintage
```

---

## Phase 4: Only Then Extend

After replication is verified (all targets PASS or discrepancies documented):

- [ ] Commit baseline: "Verify [analysis] — all targets match"
- [ ] Now extend with new specifications, robustness checks, or model variants
- [ ] Each extension builds on the verified baseline
