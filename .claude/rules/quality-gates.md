---
paths:
  - "Paper/**"
  - "Slides/**"
  - "Empirics/Code/**"
  - "Simulation/Code/**"
  - "Theory/Code/**"
---

# Quality Gates & Scoring Rubrics

## Thresholds

- **80/100 = Commit** — good enough to save
- **90/100 = PR** — ready for sharing or deployment
- **95/100 = Excellence** — submission-ready

## LyX / LaTeX Paper (.lyx, .tex)

| Severity | Issue | Deduction |
|----------|-------|-----------|
| Critical | Compilation failure | -100 |
| Critical | Undefined citation (`??`) in body | -15 |
| Critical | Overfull hbox > 10pt in paper body | -10 |
| Critical | Equation numbering error | -10 |
| Major | Hardcoded absolute path in `\includegraphics` | -20 |
| Major | Missing cross-reference label on key equation | -5 |
| Major | Figure resolution too low for print | -5 |
| Minor | Orphaned section label (defined but never referenced) | -2 |

## R Scripts (.R)

| Severity | Issue | Deduction |
|----------|-------|-----------|
| Critical | Syntax errors | -100 |
| Critical | Domain-specific bugs (wrong formula, incorrect SE) | -30 |
| Critical | Hardcoded absolute paths | -20 |
| Major | Missing `set.seed()` in stochastic script | -10 |
| Major | Missing output (figure not saved) | -5 |
| Minor | Long lines > 100 chars (non-mathematical) | -1 per line |

## Julia Scripts (.jl)

| Severity | Issue | Deduction |
|----------|-------|-----------|
| Critical | Syntax errors | -100 |
| Critical | Convergence not checked before reporting estimates | -30 |
| Critical | Hardcoded absolute paths | -20 |
| Major | Missing `Random.seed!()` in stochastic script | -10 |
| Major | Output not saved to `Simulation/Output/` | -10 |
| Major | No `Project.toml` in script's directory | -5 |
| Minor | Type instability in hot loop (not documented) | -3 |

## Beamer Slides (.tex, .lyx in Slides/)

| Severity | Issue | Deduction |
|----------|-------|-----------|
| Critical | Compilation failure | -100 |
| Critical | Undefined citation | -15 |
| Critical | Overfull hbox > 10pt | -10 |

## Enforcement

- **Score < 80:** Block commit. List blocking issues.
- **Score < 90:** Allow commit, warn. List recommendations.
- User can override with justification.

## Quality Reports

Generated **only at merge time**. Use `templates/quality-report.md` for format.
Save to `quality_reports/merges/YYYY-MM-DD_[branch-name].md`.

## Tolerance Thresholds (Research)

| Quantity | Tolerance | Rationale |
|----------|-----------|-----------|
| Point estimates (empirics) | < 0.01 | Rounding in paper display |
| Standard errors | < 0.05 | Bootstrap/clustering variation |
| GMM parameter estimates | < 1e-4 | Numerical optimization tolerance |
| Inner loop convergence | 1e-8 | Fixed point / value function |
| Outer loop convergence | 1e-6 | Parameter update |
| Coverage rates | ± 0.01 | Monte Carlo with B replications |
