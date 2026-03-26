# Paper Structure: Single Source of Truth

**Applies to:** `Paper/**`, `Theory/Sections/**`, `Slides/**/*.lyx`, `Bibliography/**`

---

## 1. SSOT Declaration

**`Paper/innovation_draft.lyx` is the authoritative source for all paper content.**

- PDFs are derived artifacts. The submitted PDF is compiled from this master.
- Exported `.tex` files are intermediate build artifacts. Never edit them.
- If content appears in both the paper and slides, the paper is the source of record. Update the paper first; update slides separately.

---

## 2. Section File Hierarchy

The master `Paper/innovation_draft.lyx` includes section files as child documents:

```
Paper/innovation_draft.lyx (MASTER)
├── Paper/Sections/Section_Theory_Model.lyx       → Theory section
├── Paper/Sections/Section_Empirical_Model.lyx    → Empirical strategy + reduced form
├── Paper/Sections/Section_Simulation.lyx         → Structural GMM estimation
├── Paper/Sections/Section_Theory_Appendix.lyx    → Theory proofs and extensions
├── Paper/Sections/Section_Empirical_Appendix.lyx → Robustness checks, additional tables
└── Paper/Sections/data_appendix.lyx              → Data construction details
```

Scratch and exploratory section files live in `Theory/Sections/` — these are not included in the master and are not part of the submitted paper.

---

## 3. Conference Slides Are a Separate Artifact

Conference slides in `Slides/` draw conceptually from the paper but are **not automatically synchronized**. They are a distinct artifact:

- Changes to paper theory require **manual** slide updates.
- Do not assume slide content is current with the paper.
- Before a presentation, verify slide content against the current paper draft.
- Slide files follow the naming convention: `Slides/VENUE_MMDDYYYY.lyx` (e.g., `Slides/IO_Workshop_02112026.lyx`).

---

## 4. Figure Provenance Map

Every figure in the paper has a canonical source script. Document here when a figure is finalized:

| Figure | Caption (brief) | Source Script | Output Path |
|--------|-----------------|---------------|-------------|
| (add as figures are finalized) | | | |

Rules:
- A figure in the paper must be reproducible by running its source script from the project root.
- Never include a figure whose source script is lost or unknown.
- When a figure changes, update both the source script and the compiled figure file.

---

## 5. No Derived Artifacts Rule

**Do not commit:**
- `.tex` files exported by LyX from `.lyx` sources in `Paper/`
- `.aux`, `.bbl`, `.blg`, `.log` compilation artifacts
- LyX backup files (`*.lyx~`, `*.lyx#`)

**Do commit:**
- `.lyx` source files (master + all section files)
- `Bibliography/Bibliography_base.bib`
- Final compiled paper PDF (`Paper/innovation_draft.pdf`) — as a convenience for sharing
- Final conference slide PDFs (`Slides/*.pdf`)

---

## 6. Version and Draft Management

- The paper draft evolves in place (`innovation_draft.lyx`). Git history serves as version control.
- For major revisions (e.g., R&R), create a dated branch: `git checkout -b revision/2026-07-01-jpe`.
- Do not maintain parallel copies of the paper (e.g., `innovation_draft_v2.lyx`). Use git for versioning.
- Older slide versions are archived in `Slides/Archive/` — keep only the 2 most recent conferences in the main `Slides/` directory.

---

## 7. Cross-File Consistency

When the structural model in `Section_Simulation.lyx` changes:

1. Update moment conditions description in Section_Simulation
2. Update parameter table in Section_Simulation
3. Verify `Theory/Code/` Julia scripts match updated model
4. Verify `Simulation/Code/` GMM scripts match updated moment conditions
5. Rerun estimation if parameter values change
6. Update paper tables and figures that depend on estimates

The `/deep-audit` skill checks cross-file consistency. Run it before submitting or presenting.
