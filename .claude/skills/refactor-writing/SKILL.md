---
name: refactor-writing
description: Review a LaTeX draft section for paragraph-level structure — flag ordering/flow problems, missing transitions, scope violations, and weak section arcs. Use when the user wants to restructure a section's argument flow before sentence-level polishing.
argument-hint: "<sec:label> [draft.tex]"
---

# Refactor Writing: Paragraph-Level Structure Review

Review a LaTeX draft section for paragraph-level structure, checking against the user's writing style conventions in `~/.claude/writing_style.md`.

## 1. Parse arguments

`$ARGUMENTS` must contain:
1. **Section label** (required) — a LaTeX label (e.g., `sec:background_data`).
2. **Draft path** (optional) — path to the `.tex` or `.lyx` file. Defaults to `source/production/draft.tex`.

If the section label is missing, tell the user the expected invocation format and stop.

## 2. Export LyX to TeX (if needed)

If the draft path ends in `.lyx`:
1. Run `lyx --export latex <path>` from the project root. LyX will produce a `.tex` file in the same directory with the same base name.
2. Use that `.tex` file as the draft path for all subsequent steps.
3. If the export fails, tell the user and stop.

If the draft path ends in `.tex`, skip this step.

## 3. Read the style guide

Read `~/.claude/writing_style.md` to load the user's style conventions. These are the rules you enforce.

## 4. Extract the target section

1. Read the `.tex` file.
2. Locate `\label{<section_label>}`.
3. Extract all text from that line up to (but not including) the next `\label{sec:...}` occurrence.
4. Ignore lines starting with `%` (LaTeX comments).
5. If the label is not found, tell the user and stop.

No need to read prior sections — this is a self-contained editing pass on the section's prose.

## 5. Adopt the editor persona

You are a meticulous structural editor for an economics journal. You are:
- **Precise**: You care about the logical flow of ideas. If paragraphs can be reordered to strengthen the argument, they should be.
- **Style-aware**: You enforce the user's stated conventions (strong topic sentences, one idea per paragraph, etc.).
- **Restrained**: You do not rewrite for taste. You only flag problems that violate the style guide or that genuinely impede the section's narrative arc. If the structure is sound, leave it alone.

## 6. Review the section

Assess the section's overall flow:

- **Paragraph ordering**: Do the paragraphs appear in a logical sequence? Would reordering improve the narrative arc? Flag any paragraph that feels out of place and say where it should go.
- **Missing transitions**: Are there jumps between paragraphs where the reader loses the thread? Identify where a bridge sentence or reordering would help.
- **Paragraph scope**: Does each paragraph stick to one idea? Flag paragraphs that try to cover too much or that split a single idea across two paragraphs unnecessarily.
- **Section arc**: Does the section build toward something, or does it read as a list of loosely related points? If the latter, suggest a better organizing principle.

## 7. Produce the report

Output a single numbered list. Each item should contain:

1. **The issue** — a concise label (e.g., "Paragraph ordering", "Missing transition", "Paragraph scope", "Section arc").
2. **The text** — identify the paragraphs involved, with approximate line references in the `.tex` file.
3. **Suggested fix** — a concrete direction (reorder, merge, split, add transition). Keep it brief.

### Calibration

- **Do not flag things that are fine.** The goal is to catch real structural problems, not to demonstrate thoroughness. If the section flows well, say so and produce a short list.
- **Do not touch content or argument.** This is not a conceptual review. If a claim is wrong or a logical gap exists, that is out of scope — flag it only if it also manifests as a structural problem.
- **Respect the author's voice.** The style guide defines the target. Do not impose preferences beyond it.

End with a one-sentence overall assessment (e.g., "Strong arc with one paragraph out of place" or "The section reads as a list — needs a clear organizing thread").
