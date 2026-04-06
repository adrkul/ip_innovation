---
name: slide-excellence
description: Multi-agent slide review (visual, pedagogy, proofreading, substance). Use for comprehensive quality check before presenting at conferences or workshops.
argument-hint: "[LYX filename]"
allowed-tools: ["Read", "Grep", "Glob", "Write", "Task"]
context: fork
---

# Slide Excellence Review

Run a comprehensive multi-dimensional review of conference slides. Multiple agents analyze the rendered PDF independently, then results are synthesized.

## Steps

### 1. Identify the File

Parse `$ARGUMENTS` for the filename. Resolve path in `Slides/`. Slide files follow the naming convention `Slides/VENUE_MMDDYYYY.lyx`. If no argument is given, list `.lyx` files in `Slides/` and ask the user which to review.

### 2. Compile PDF

Compile the `.lyx` file to PDF:

```bash
lyx --export pdf2 Slides/[FILENAME].lyx
```

This produces `Slides/[BASENAME].pdf`. If compilation fails, report the error and stop — do not proceed without a valid PDF.

### 3. Run Review Agents in Parallel

All agents work from `Slides/[BASENAME].pdf` only.

**Agent 1: Visual Audit** (slide-auditor)
- Layout, overflow, font consistency, box fatigue, spacing, figure rendering
- Save: `workflow/quality_reports/[BASENAME]_visual_audit.md`

**Agent 2: Pedagogical Review** (pedagogy-reviewer)
- 13 pedagogical patterns, narrative arc, pacing, notation clarity
- Save: `workflow/quality_reports/[BASENAME]_pedagogy_report.md`

**Agent 3: Proofreading** (proofreader)
- Grammar, typos, consistency, academic writing quality, citation format
- Save: `workflow/quality_reports/[BASENAME]_report.md`

**Agent 4: Substance Review** (domain-reviewer)
- Economics domain correctness: derivations, assumptions, claim accuracy
- Save: `workflow/quality_reports/[BASENAME]_substance_review.md`

### 4. Synthesize Combined Summary

```markdown
# Slide Excellence Review: [Filename]
Date: [YYYY-MM-DD]

## Overall Quality Score: [EXCELLENT / GOOD / NEEDS WORK / POOR]

| Dimension     | Critical | Medium | Low |
|---------------|----------|--------|-----|
| Visual/Layout |          |        |     |
| Pedagogical   |          |        |     |
| Proofreading  |          |        |     |
| Substance     |          |        |     |

### Critical Issues (Immediate Action Required)
### Medium Issues (Next Revision)
### Recommended Next Steps
```

Save the combined summary to `workflow/quality_reports/[BASENAME]_excellence_summary.md`.

## Quality Score Rubric

| Score      | Critical | Medium | Meaning                     |
|------------|----------|---------|-----------------------------|
| Excellent  | 0–2      | 0–5     | Ready to present             |
| Good       | 3–5      | 6–15    | Minor refinements            |
| Needs Work | 6–10     | 16–30   | Significant revision needed  |
| Poor       | 11+      | 31+     | Major restructuring needed   |
