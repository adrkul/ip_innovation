# LyX / LaTeX Conventions

**Applies to:** `**/*.lyx`, `**/*.tex`, `Paper/**`, `Theory/Sections/**`

These conventions govern all paper writing in this project. The paper is authored in LyX; LaTeX `.tex` files are derived artifacts.

---

## 1. Single Source of Truth

- **`Paper/innovation_draft.lyx` is the master document.** It is the authoritative source for all paper content.
- PDF files (`*.pdf`) are derived. Never treat them as source.
- Exported `.tex` files are build artifacts. **Never edit `.tex` files directly** — edits will be overwritten the next time LyX exports.
- Section `.lyx` files are included into the master via LyX's "child document" mechanism. Edit section files independently; compile via the master.

---

## 2. Compilation

### Standard LyX compilation (paper)
```bash
lyx --export pdf2 Paper/innovation_draft.lyx
```
This runs LyX's internal multi-pass LaTeX pipeline (pdflatex + bibtex + pdflatex × 2). Use this for the main paper.

### Compile individual section (for quick checks)
```bash
lyx --export pdf2 Paper/Sections/Section_Theory_Model.lyx
```
Note: cross-references to other sections will be unresolved when compiling a section standalone.

### Conference slides (Beamer, LyX)
```bash
cd Slides && lyx --export pdf2 SlideDeck.lyx
```
Or if the slide deck uses a custom LaTeX preamble requiring XeLaTeX:
```bash
cd Slides && TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode deck.tex
BIBINPUTS=..:$BIBINPUTS bibtex deck
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode deck.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode deck.tex
```

---

## 3. File Hierarchy

```
Paper/
├── innovation_draft.lyx          # Master document (AUTHORITATIVE SOURCE)
└── Sections/
    ├── Section_Theory_Model.lyx        # Theory section
    ├── Section_Empirical_Model.lyx     # Empirics section
    ├── Section_Simulation.lyx          # Structural estimation section
    ├── Section_Theory_Appendix.lyx     # Theory appendix
    ├── Section_Empirical_Appendix.lyx  # Empirics appendix
    └── data_appendix.lyx               # Data appendix

Theory/
└── Sections/
    └── *.lyx                      # Standalone theory scratch files

Slides/
└── *.lyx                          # Conference presentation slides
```

---

## 4. Bibliography

- **Single bibliography file:** `Bibliography/Bibliography_base.bib`
- All citation keys follow the author-year format: `Smith2023`, `SmithJones2022`
- Never duplicate entries across `.bib` files. If you need to add a reference, add it to `Bibliography_base.bib` only.
- Run `/validate-bib` to check for broken citations and unused entries before committing.
- The bibliography path in LyX is set relative to the project root. If LyX cannot find the `.bib` file, check that the document preamble or bibliography settings point to `../../Bibliography/Bibliography_base.bib` (relative to `Paper/Sections/`) or an absolute path.

---

## 5. Cross-Reference Conventions

Use consistent label prefixes throughout the paper:

| Object | Prefix | Example |
|--------|--------|---------|
| Figure | `fig:` | `fig:supply-chain-structure` |
| Table | `tab:` | `tab:summary-stats` |
| Equation | `eq:` | `eq:gmm-objective` |
| Theorem | `thm:` | `thm:equilibrium-existence` |
| Proposition | `prop:` | `prop:offshoring-innovation` |
| Assumption | `ass:` | `ass:market-structure` |
| Lemma | `lem:` | `lem:fixed-point` |
| Section | `sec:` | `sec:theory` |

Use descriptive labels (not `fig:1`, `eq:3`). Labels must be unique across all section files.

---

## 6. Figure Inclusion

- **All figure paths are relative to the project root.** In LyX, set graphics paths accordingly.
- Final paper figures live in `Figures/` (shared) or `Empirics/Figures/` (empirics-specific).
- Example correct path in `\includegraphics`: `../../Figures/supply_chain_map.pdf`
- **Never hardcode absolute paths** in `\includegraphics` or LyX figure settings.
- Figure format: PDF for vector graphics (R/Julia output), PNG only if vector is unavailable.
- Figure dimensions for single-column: 3.5in × 3.5in; full-width: 6.5in × 4in.

---

## 7. Custom LaTeX Environments

The paper preamble (set in LyX Document → Settings → LaTeX Preamble) defines these environments:

| Environment | Purpose |
|-------------|---------|
| `assumption` | Numbered assumption block |
| `proposition` | Numbered proposition |
| `theorem` | Numbered theorem |
| `lemma` | Numbered lemma |
| `corollary` | Numbered corollary |
| `definition` | Numbered definition |

When using these in LyX, use the corresponding LyX environment rather than raw LaTeX where possible.

---

## 8. Gitignore Patterns

The following LyX/LaTeX artifacts are gitignored (do not commit):

```
*.lyx~          # LyX backup files
*.lyx#          # LyX autosave files
#*.lyx#         # LyX autosave files (alternate naming)
*.aux
*.log
*.bbl
*.blg
*.out
*.toc
*.synctex.gz
*.fls
*.fdb_latexmk
```

**Do commit:** `.lyx` source files, `Bibliography_base.bib`, final compiled PDFs of paper and slides (as submission/sharing artifacts).

---

## 9. Common Pitfalls

| Pitfall | Correct Approach |
|---------|-----------------|
| Editing exported `.tex` directly | Edit the `.lyx` source; never touch `.tex` exports |
| Absolute paths in `\includegraphics` | Use relative paths from project root |
| Duplicate bib entries | Check `Bibliography_base.bib` before adding; run `/validate-bib` |
| Committing `.lyx~` backup files | Already gitignored; do not force-add |
| Undefined references in section files | Compile from master `innovation_draft.lyx` for final check |
| Missing `\label` for equations | Label every numbered equation you may reference |
