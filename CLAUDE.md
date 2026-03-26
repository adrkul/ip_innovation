# CLAUDE.MD — Industrial Policy for Innovation

**Project:** Industrial Policy for Innovation
**Institution:** Emory University (Economics PhD)
**Branch:** main
**Tools:** LyX/LaTeX (paper + slides), R (empirics), Julia (structural model)

---

## Core Principles

- **Plan first** — enter plan mode before non-trivial tasks; save plans to `quality_reports/plans/`
- **Verify after** — compile/run and confirm output at the end of every task
- **Single source of truth** — LyX `.lyx` is authoritative; PDF and `.tex` exports are derived. Never edit exported `.tex` files.
- **Quality gates** — nothing ships below 80/100
- **[LEARN] tags** — when corrected, save `[LEARN:category] wrong → right` to MEMORY.md

---

## Folder Structure

```
ip_innovation/
├── CLAUDE.md                    # This file
├── MEMORY.md                    # Cross-session learnings
├── Bibliography/
│   └── Bibliography_base.bib   # Single bibliography (all citations)
├── Paper/                       # Main paper draft
│   ├── innovation_draft.lyx    # MASTER DOCUMENT (authoritative source)
│   └── Sections/               # Section .lyx files
├── Slides/                      # Conference presentation slides (.lyx)
├── Theory/
│   ├── Code/                    # Julia equilibrium model scripts
│   └── Sections/               # Standalone theory scratch .lyx files
├── Empirics/
│   ├── Code/                    # R scripts (data + regression)
│   ├── Data/                    # Raw + intermediate data (GITIGNORED)
│   └── Figures/                 # Output figures
├── Simulation/
│   ├── Code/                    # Julia GMM estimation scripts
│   ├── Data/                    # Formatted GMM inputs
│   └── Output/                  # Model output (GITIGNORED)
├── Figures/                     # Shared paper figures
├── Preambles/                   # LaTeX header files
├── explorations/                # Research sandbox (60/100 quality threshold)
├── quality_reports/             # Plans, specs, logs, replication targets
├── scripts/R/                   # Utility R scripts
├── templates/                   # Session log, quality report templates
└── master_supporting_docs/      # Reference papers
```

---

## Commands

```bash
# Compile LyX paper
lyx --export pdf2 Paper/innovation_draft.lyx

# Compile individual section
lyx --export pdf2 Paper/Sections/Section_Theory_Model.lyx

# Compile conference slides (LyX)
lyx --export pdf2 Slides/SlideDeck.lyx

# Compile slides with XeLaTeX (custom preamble)
cd Slides && TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex
BIBINPUTS=..:$BIBINPUTS bibtex file
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode file.tex

# Run R script (always from project root)
Rscript Empirics/Code/analysis_main.R

# Run Julia estimation
julia --project=Simulation/Code Simulation/Code/GMM_OEM_assembly.jl

# Quality score
python3 scripts/quality_score.py Empirics/Code/analysis_main.R
python3 scripts/quality_score.py Simulation/Code/GMM_OEM_assembly.jl
```

---

## Quality Thresholds

| Score | Gate | Meaning |
|-------|------|---------|
| 80 | Commit | Good enough to save |
| 90 | Share | Ready for circulation |
| 95 | Excellence | Submission-ready |

---

## Skills Quick Reference

| Command | What It Does |
|---------|-------------|
| `/compile-latex [file]` | Compile LyX paper or Beamer slide deck |
| `/proofread [file]` | Grammar/typo/consistency review |
| `/review-paper [file]` | Comprehensive manuscript review |
| `/review-r [file]` | R code quality review |
| `/validate-bib` | Cross-reference citations against bibliography |
| `/data-analysis [dataset]` | End-to-end R analysis workflow |
| `/lit-review [topic]` | Literature search and synthesis |
| `/research-ideation [topic]` | Research questions and empirical strategies |
| `/interview-me [topic]` | Interactive research interview |
| `/commit [msg]` | Stage, commit, PR, merge |
| `/deep-audit` | Repository-wide consistency audit |
| `/learn [skill-name]` | Extract discovery into persistent skill |
| `/context-status` | Show session health and context usage |

---

## LaTeX / LyX Custom Environments

| Environment | LyX Style | Use Case |
|-------------|-----------|---------|
| `assumption` | Assumption | Market structure, identification assumptions |
| `proposition` | Proposition | Main theoretical results |
| `theorem` | Theorem | Formal existence/uniqueness results |
| `lemma` | Lemma | Supporting results |
| `corollary` | Corollary | Consequences of propositions |
| `definition` | Definition | Key economic objects |

---

## Current Project State

| Component | File | Status | Notes |
|-----------|------|--------|-------|
| Theory | `Paper/Sections/Section_Theory_Model.lyx` | Draft | Equilibrium model of innovation in supply chains |
| Empirics | `Paper/Sections/Section_Empirical_Model.lyx` | Active | IHS supply chain + PATSTAT patents |
| Simulation | `Simulation/Code/GMM_OEM_assembly.jl` | Active | Structural GMM, automotive industry |
| Paper master | `Paper/innovation_draft.lyx` | ~79pp draft | March 2026 version |
| Bibliography | `Bibliography/Bibliography_base.bib` | Active | ~960 entries |
