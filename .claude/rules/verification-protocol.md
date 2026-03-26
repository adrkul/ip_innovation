---
paths:
  - "Paper/**"
  - "Slides/**"
  - "Empirics/Code/**"
  - "Simulation/Code/**"
  - "Theory/Code/**"
---

# Task Completion Verification Protocol

**At the end of EVERY task, Claude MUST verify the output works correctly.** This is non-negotiable.

## For LyX / LaTeX Paper:

1. Compile the master document: `lyx --export pdf2 Paper/innovation_draft.lyx`
2. Check for compilation errors in the log output
3. Open the PDF to verify figures render: `open Paper/innovation_draft.pdf` (macOS)
4. Check for overfull hbox warnings in the log
5. Verify bibliography resolves (no `??` in place of citations)
6. For section files compiled standalone: expect unresolved cross-references — this is normal

## For Conference Slides (Beamer, LyX):

1. Compile: `lyx --export pdf2 Slides/SlideDeck.lyx`
2. Open the PDF: `open Slides/SlideDeck.pdf`
3. Check for overfull hbox warnings
4. Verify figures display (spot-check 2-3 figure slides)

## For R Scripts:

1. Run from project root: `Rscript Empirics/Code/filename.R`
2. Verify output files (PDF, RDS) were created with non-zero size
3. Spot-check estimates for reasonable magnitude
4. Check that no hardcoded absolute paths triggered errors

## For Julia Scripts:

1. Run from project root: `julia --project=Simulation/Code Simulation/Code/script.jl`
2. Verify output directory created in `Simulation/Output/`
3. Check convergence flag in output: `converged = true`
4. Spot-check parameter estimates for reasonable magnitude and sign
5. Verify output file created via JLD2 (`.jld2` file exists and is non-zero)

## Common Pitfalls:

- **LyX path issues:** If `lyx` command not found, check that LyX is on PATH (`which lyx`)
- **Missing figures:** If figures missing from PDF, check relative paths in `\includegraphics`
- **Stale bibliography:** If `??` in citations, recompile (bibtex pass needed)
- **Julia project not found:** Use `julia --project=Simulation/Code` not `julia` alone

## Verification Checklist:

```
[ ] Output file created successfully (PDF, RDS, or JLD2)
[ ] No compilation/runtime errors
[ ] Figures/tables display correctly
[ ] No undefined citations or cross-references in final paper
[ ] Opened in viewer to confirm content
[ ] Reported results to user
```
