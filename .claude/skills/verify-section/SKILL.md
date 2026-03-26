---
name: verify-section
description: Verify that a LaTeX draft section accurately reflects the corresponding code. Checks that all claims in the writing match the code logic and that no non-trivial code steps are undocumented. Use when the user wants to cross-check a draft section against its implementation.
argument-hint: "<sec:label> <code_path1> [code_path2 ...] [draft.tex]"
---

# Verify Draft Section Against Code

Cross-check a LaTeX draft section against the code that implements it. Produce a structured report of discrepancies and gaps.

## 1. Parse arguments

`$ARGUMENTS` must contain:
1. **Section label** (required) — a LaTeX label (e.g., `sec:background_data`).
2. **Code paths** (required) — one or more directories or individual script files (e.g., `source/analysis/background_data/ source/build/prep_analysis/sample_filter.py`).
3. **Draft path** (optional) — path to the `.tex` or `.lyx` file. Defaults to `source/production/draft.tex`.

If the section label or code paths are missing, tell the user the expected invocation format and stop.

## 2. Export LyX to TeX (if needed)

If the draft path ends in `.lyx`:
1. Run `lyx --export latex <path>` from the project root. LyX will produce a `.tex` file in the same directory with the same base name.
2. Use that `.tex` file as the draft path for all subsequent steps.
3. If the export fails, tell the user and stop.

If the draft path ends in `.tex`, skip this step.

## 3. Extract the draft section

1. Read the draft `.tex` file.
2. Locate `\label{<section_label>}`.
3. Extract all text from the `\label{<section_label>}` line up to (but not including) the next `\label{sec:...}` occurrence. This captures the full section content regardless of subsection nesting.
5. If the label is not found, tell the user and stop.

## 4. Read the code

1. For each code path in the arguments:
   - If it is a directory, read all `.py`, `.R`, `.do`, `.sql`, `.jl` files in it (recursively).
   - If it is a single file, read that file.
2. Stay scoped to the specified files/directories as the primary reading set.
3. When a draft claim maps to a function call whose implementation lives outside the specified paths, follow that import one level deep to read the function definition. Do NOT recursively chase further imports from those external files.
4. Use the Agent tool (subagent_type: Explore) if the code is extensive (many files or very long scripts) to efficiently gather the logic. Otherwise, read files directly.

## 5. Identify claims in the draft

Systematically catalog every verifiable claim in the extracted section. Claims include:

- **Numerical values**: sample sizes, percentages, thresholds, cutoffs, year ranges, counts.
- **Methodological descriptions**: "we restrict to...", "we define X as...", "we exclude...", "we merge...", "we aggregate...".
- **Variable construction**: how variables are defined, transformed, or combined.
- **Sample restrictions / filters**: any stated criteria for inclusion or exclusion.
- **Data source descriptions**: what data is used, what fields matter, what format it takes.
- **Logical flow**: the stated order of operations or pipeline steps.

Ignore:
- Pure prose with no factual content (motivation, literature references, framing).
- Forward/backward references to other sections.
- Numbers pulled in via `\input{}` from output files — verifying those is out of scope (the code presumably generates them, and the pipeline fills them in).

## 6. Cross-check claims against code

For each claim identified in step 4, determine whether the code supports it:

- **Match**: The code clearly implements what the draft says. No issue.
- **Discrepancy**: The draft says one thing, the code does something different (e.g., draft says "firms with revenue above $1M" but the code filters at $500K; draft says "winsorize at 1%" but code trims at 5%).
- **Unverifiable**: The claim relates to something outside the specified code scope, or the code is ambiguous. Note this but do not flag it as an error.

## 7. Check for undocumented code steps

Review the code for non-trivial operations that are NOT mentioned in the draft section:

- Significant sample restrictions or filters not described in the writing.
- Variable transformations (logs, winsorization, recoding, imputation) not mentioned.
- Merges, joins, or data linkages not described.
- Substantive exclusions (dropping observations, removing outliers) not documented.

Ignore:
- Boilerplate (imports, file I/O, logging, path construction).
- Trivial operations (renaming columns to match conventions, type casting, sorting).
- Code that generates outputs for other sections.

## 8. Produce the report

Output a structured report with two sections:

### Discrepancies (draft claims that do not match code)

For each discrepancy:
- **Claim**: Quote or paraphrase the draft text, with a rough line reference in the `.tex` file.
- **Code**: Cite the file and line(s) where the code differs, and describe what the code actually does.
- **Severity**: `HIGH` (factual error — the draft misstates what happens) or `LOW` (ambiguity or imprecision that could mislead a reader).

### Gaps (code steps not documented in the draft)

For each gap:
- **Code step**: Cite the file and line(s), and describe what the code does.
- **Why it matters**: Briefly explain why a reader of the draft would benefit from knowing this.
- **Severity**: `HIGH` (substantive step that changes the analysis or sample) or `LOW` (minor detail that a careful reader might want to know).

If there are no discrepancies or no gaps, say so explicitly. End with a one-sentence overall assessment (e.g., "The section is well-aligned with the code" or "Several substantive discrepancies need attention").
