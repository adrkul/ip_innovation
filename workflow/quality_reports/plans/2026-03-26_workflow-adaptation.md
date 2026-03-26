# Plan: Adapt Workflow for IP Innovation Research Project
**Status:** COMPLETED
**Date:** 2026-03-26
**Scope:** ~55 file-level operations across 10 phases

---

## Context

The `ip_innovation` repo was cloned from `pedrohcgs/claude-code-my-workflow`, a template built for academic lecture slide creation (Beamer + Quarto). The actual project is an Economics PhD thesis — "Industrial Policy for Innovation" — using LyX/LaTeX for writing, R for empirics, and Julia for structural GMM estimation. Most slide infrastructure is irrelevant and actively harmful (pollutes context, creates confusion). The existing research project lives at `~/Dropbox/Repos/Research/outsourcing_innovation` and is the reference for structure and content.

**Key decisions:**
- Bibliography: rename `outsourcing_innovation.bib` → `Bibliography_base.bib`
- Content port: structure only (no code files yet)
- LyX compilation: `lyx --export pdf2 file.lyx`

---

## Phase 1 — Deletions (Zero risk, do first)

### Skills to delete (9 directories under `.claude/skills/`)
- `deploy/`, `translate-to-quarto/`, `qa-quarto/`, `extract-tikz/`
- `create-lecture/`, `pedagogy-review/`, `visual-audit/`, `slide-excellence/`, `devils-advocate/`

### Agents to delete (6 files under `.claude/agents/`)
- `beamer-translator.md`, `quarto-critic.md`, `quarto-fixer.md`
- `pedagogy-reviewer.md`, `slide-auditor.md`, `tikz-reviewer.md`

### Rules to delete (4 files under `.claude/rules/`)
- `beamer-quarto-sync.md`, `no-pause-beamer.md`, `tikz-visual-quality.md`
- `single-source-of-truth.md` (replaced in Phase 3)

### Directories/scripts to delete
- `Quarto/` — entire directory (empty template)
- `docs/` — entire directory (GitHub Pages, not needed)
- `scripts/sync_to_docs.sh` — Quarto deployment script

---

## Phase 2 — Create Folder Structure

Create research-oriented directory tree (no files, just directories):

```
Bibliography/
Paper/
Paper/Sections/
Theory/
Theory/Code/
Theory/Sections/
Empirics/
Empirics/Code/
Empirics/Data/
Empirics/Figures/
Simulation/
Simulation/Code/
Simulation/Data/
Simulation/Output/
```

Keep existing: `Figures/`, `Slides/` (repurposed for conference slides), `Preambles/`, `explorations/`, `quality_reports/`, `scripts/`, `templates/`

Add `.gitkeep` files in `Empirics/Data/`, `Simulation/Output/` (large files will be gitignored).

---

## Phase 3 — New Rule Files (4 new files)

### 3.1 `.claude/rules/julia-code-conventions.md`
Path scope: `**/*.jl`, `Theory/Code/**`, `Simulation/Code/**`

Cover: reproducibility (`Random.seed!`), package management (`Project.toml`), GMM-specific conventions (moment function naming, optimizer output via JLD2, tolerance thresholds for inner/outer loops, parallelism with `Distributed.jl`), `snake_case` naming, docstrings, no magic numbers.

### 3.2 `.claude/rules/lyx-latex-conventions.md`
Path scope: `**/*.lyx`, `**/*.tex`, `Paper/**`, `Theory/Sections/**`

Cover: LyX compilation (`lyx --export pdf2 file.lyx`), master document structure (master `Paper/innovation_draft.lyx` includes section files via `\input`), bibliography in `Bibliography/Bibliography_base.bib`, cross-reference naming conventions (`fig:`, `eq:`, `tab:`), relative paths in `\includegraphics`, never edit exported `.tex` files directly, gitignore `*.lyx~` and `*.lyx#`.

### 3.3 `.claude/rules/data-management.md`
Path scope: `Empirics/**`, `Simulation/**`, `scripts/**/*.R`

Cover: data sources (IHS Markit supply chain, PATSTAT patents, HS-level trade data), what is gitignored (raw data in `Empirics/Data/`, large intermediate files, `Simulation/Output/`), data loading convention (path variable at top of each script), reproducibility checkpoints (pipeline order), figure tracking (commit final paper figures, gitignore diagnostics).

### 3.4 `.claude/rules/paper-structure.md` (replaces `single-source-of-truth.md`)
Path scope: `Paper/**`, `Theory/Sections/**`, `Slides/**/*.lyx`, `Bibliography/**`

Cover: SSOT is `Paper/innovation_draft.lyx`, PDF is derived (never edit `.tex` exports), section file hierarchy (Theory → theory section, Empirics → empirics section, Simulation → structural section), conference slides are a separate artifact (not auto-synced from paper), figure provenance (each figure has a canonical R/Julia source script), no derived artifacts committed.

---

## Phase 4 — Update Existing Rules (5 targeted edits)

| File | Changes |
|------|---------|
| `verification-protocol.md` | Remove Quarto/HTML section; add Julia verification (`julia script.jl` runs without error, output created); update LaTeX section for LyX |
| `orchestrator-research.md` | Update path scope to include `Empirics/Code/**`, `Simulation/Code/**`, `Theory/Code/**`; add Julia verification step |
| `replication-protocol.md` | Update path scope; change lecture-specific paths to `quality_reports/replication_targets/`; remove Stata→R pitfalls table |
| `quality-gates.md` | Update path scope; remove Quarto rubric; add LaTeX/paper rubric and Julia rubric |
| `r-code-conventions.md` | Update figure dimensions (paper not slides); update RDS pattern note; remove `bg="transparent"` pitfall |

---

## Phase 5 — Update Agents (2 targeted edits)

| File | Changes |
|------|---------|
| `domain-reviewer.md` | Update persona to IO/trade/innovation referee (AER, QJE, ReStud); add GMM code-theory alignment check in Lens 4 |
| `r-reviewer.md` | Update figure dimension checks from Beamer to paper standards |

---

## Phase 6 — Rewrite `CLAUDE.md`

Complete rewrite (file is all placeholders). New content:

- **Header:** Project, Institution (Emory Economics PhD), tools (LyX, R, Julia)
- **Folder structure:** New research tree (Paper/, Theory/, Empirics/, Simulation/, Bibliography/, Slides/)
- **Commands:** `lyx --export pdf2`, `Rscript`, `julia`, 3-pass xelatex for Slides only
- **Skills table:** Remove 9 slide skills; keep 13 research skills
- **Remove:** Beamer environments table, Quarto CSS classes table
- **Add:** LaTeX/LyX custom environments table (to populate from paper preamble), project component status table
- **SSOT principle:** "LyX `.lyx` is authoritative; PDFs are derived. Never edit exported `.tex` files."

---

## Phase 7 — Update `settings.json`

```json
// ADD:
"Bash(julia *)",
"Bash(julia --project=* *)",
"Bash(lyx *)",

// REMOVE:
"Bash(quarto render *)",
"Bash(./scripts/sync_to_docs.sh *)",
"Bash(./scripts/sync_to_docs.sh)"
```

---

## Phase 8 — Update `scripts/quality_score.py`

- **Remove:** `score_quarto()` method and `QUARTO_RUBRIC` (~120 lines)
- **Add:** `score_lyx_paper()` — checks compiled PDF existence, broken citations in `.tex` export, hardcoded paths in `\includegraphics`; uses new `LATEX_PAPER_RUBRIC`
- **Add:** `score_julia()` — syntax via `julia -e 'Meta.parse(read("file.jl", String))'`, hardcoded path detection, `Random.seed!` check; uses new `JULIA_RUBRIC`
- **Update:** `main()` dispatch to handle `.jl` and `.lyx`; fix bibliography path to look in `Bibliography/`

---

## Phase 9 — Update `compile-latex` Skill

Update `SKILL.md` to handle both use cases:
- `.lyx` file → `lyx --export pdf2`
- `.tex` file in `Slides/` → 3-pass xelatex sequence

---

## Phase 10 — Update `MEMORY.md` and `.gitignore`

### MEMORY.md additions
Add `## Project Context` section:
- `[LEARN:project]` — paper is 79-page draft `innovation_draft.lyx` with included section files
- `[LEARN:tools]` — Julia for GMM estimation, R for empirics, LyX for writing
- `[LEARN:data]` — large raw data gitignored: IHS supply chain, PATSTAT, trade data

### .gitignore additions
```
# LyX backup files
*.lyx~
*.lyx#
#*.lyx#

# Large data files (path-scoped)
Empirics/Data/**
!Empirics/Data/.gitkeep
Simulation/Data/*.csv
Simulation/Output/**
!Simulation/Output/.gitkeep

# Julia artifacts
*.ji
Manifest.toml
```

---

## Execution Order (Prioritized)

1. Phase 1 (Deletions) — cleanest start
2. Phase 2 (Folder structure) — needed before anything else
3. Phase 6 (CLAUDE.md rewrite) — highest session impact
4. Phase 7 (settings.json) — Julia needs permissions
5. Phase 3 (New rules) — governs active work immediately
6. Phase 4 (Update existing rules) — cleanup
7. Phase 5 (Update agents) — cleanup
8. Phase 9 (compile-latex skill) — functional update
9. Phase 8 (quality_score.py) — useful but not blocking
10. Phase 10 (MEMORY.md + .gitignore) — hygiene

---

## Verification

After implementation:
- `ls .claude/skills/` → only 13 research skills remain
- `ls .claude/agents/` → only 4 agents remain
- `CLAUDE.md` has no `[BRACKETED PLACEHOLDERS]`
- `lyx --export pdf2` and `julia` appear in `settings.json`
- `quality_score.py` has no `score_quarto()` method
- New directories exist: `Paper/`, `Theory/`, `Empirics/`, `Simulation/`, `Bibliography/`
- `.gitignore` covers LyX backups, large data, Julia artifacts
