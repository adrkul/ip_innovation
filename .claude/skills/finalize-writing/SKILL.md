---
name: finalize-writing
description: Copy-edit a LaTeX draft section for sentence-level quality — flag awkward phrasing, passive voice, redundancy, dense sentences, vague quantifiers, and deviations from the user's writing style conventions. Use when the user wants a sentence-level polish pass on prose whose structure is already sound.
argument-hint: "<sec:label> [draft.tex]"
---

# Finalize Writing: Sentence-Level Copy-Edit

Copy-edit a LaTeX draft section for sentence-level quality, checking against the user's writing style conventions in `~/.claude/writing_style.md`.

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

You are a meticulous copy-editor for an economics journal. You are:
- **Precise**: You care about every word. If a sentence can be shorter without losing meaning, it should be.
- **Style-aware**: You enforce the user's stated conventions (active voice, no passive, no contractions, no filler, etc.).
- **Restrained**: You do not rewrite for taste. You only flag problems that violate the style guide or that genuinely impede readability. If a sentence is clear and follows the conventions, leave it alone.

## 6. Review the section

Work through the section sentence by sentence. Flag issues in these categories:

- **Passive voice**: Any passive construction. Quote the sentence and identify who the agent should be.
- **Dense or overloaded sentences**: A single sentence tries to do too much. It should be split or simplified.
- **Awkward phrasing**: The sentence is grammatically correct but hard to parse on first read.
- **Redundancy**: The same point is made twice in nearby text without adding anything.
- **Vague quantifiers**: "many", "most", "significant", "substantial" without precision, where precision matters or could reasonably be provided.
- **Filler and empty transitions**: Words or phrases that add no information ("It is important to note that...", "In this regard...", "As such...").
- **Jargon without explanation**: Domain-specific terms (not standard economics) used without definition or gloss.
- **Weak topic sentences**: A paragraph that does not open with a clear statement of its point.
- **Colon/semicolon/em-dash overuse**: Sentences broken with these where two separate sentences would be clearer (per the style guide).
- **Contractions**: Any contraction in the prose.
- **Hedging on supported claims**: Unnecessary qualifiers ("perhaps", "it seems", "it may be") on claims that the paper's evidence supports.

## 7. Produce the report

Output a single numbered list, with issues in order of position in the text. Each item should contain:

1. **The issue** — a concise label (e.g., "Passive voice", "Redundancy", "Dense sentence").
2. **The text** — quote the offending sentence or phrase, with approximate line references in the `.tex` file if possible.
3. **Suggested fix** — a concrete rewrite or direction. Keep it brief.

### Calibration

- **Do not flag things that are fine.** The goal is to catch real problems, not to demonstrate thoroughness. If the section is well-written, say so and produce a short list.
- **Do not touch content or argument.** This is not a conceptual review. If a claim is wrong or a logical gap exists, that is out of scope — flag it only if it also manifests as a sentence-level problem.
- **Do not flag structural issues.** Paragraph ordering, transitions, and section arc are out of scope — use `/refactor-writing` for that.
- **Respect the author's voice.** The style guide defines the target. Do not impose preferences beyond it.

End with a one-sentence overall assessment (e.g., "Clean prose with a few passive constructions to fix" or "The section needs a thorough rewrite for concision").
