---
name: clarify-writing
description: Read a LaTeX draft section as a well-educated economist encountering the topic for the first time, and produce a numbered list of conceptual clarity issues. Constructive seminar audience tone. Use when the user wants critical reader feedback on a draft section's argument and logic.
argument-hint: "<sec:label> [draft.tex]"
---

# Clarify Writing: Critical Reader Feedback on a Draft Section

Read a LaTeX draft section in the context of what precedes it and critique it from the perspective of a sharp, well-educated economist who has never thought about the topic before. Focus on what is unclear.

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

## 3. Read the draft up to the target section

1. Read the `.tex` file and identify the body content — everything between `\begin{document}` and the target `\label{<section_label>}`. Skip the preamble (package imports, macro definitions, formatting commands before `\begin{document}`). Ignore lines starting with `%` (LaTeX comments) — these are author notes, not rendered text.
2. If the body `\input{}`s other `.tex` files that appear before the target section (e.g., earlier section files), read those too, so you understand what has been established.
3. Do NOT read content after the target section. You are simulating a reader encountering this section for the first time, with only the preceding rendered text as context.

## 4. Extract the target section

1. Locate `\label{<section_label>}`.
2. Extract all text from that line up to (but not including) the next `\label{sec:...}` occurrence.
3. This is the section under review.
4. If the label is not found, tell the user and stop.

## 5. Adopt the reader persona

You are a well-educated economist at a constructive seminar. You are:
- **Smart but uninitiated**: You have strong training in economics and statistics, but you have never studied this specific topic. You do not know the institutional details, the data sources, or the policy environment unless the paper tells you.
- **Genuinely curious**: You want to understand the argument. When something is unclear, you flag it because you want to follow along, not because you want to score points.
- **Attentive**: You expect every sentence to earn its place. You notice when terms are undefined, when logical steps are skipped, or when claims lack support — but you raise these as questions, not accusations.
- **Constructive**: Your goal is to make the paper better. You point out where the reader will struggle and, where possible, suggest what would help.

## 6. Critique the section

Work through the section carefully, paragraph by paragraph. Identify every point where a reader matching the persona above would stumble, object, or lose the thread. Focus exclusively on conceptual clarity:

- **Undefined or under-defined terms**: A concept is introduced without adequate definition. The reader must guess what it means.
- **Logical gaps**: The argument jumps from A to C without establishing B. An implication is stated as obvious when it is not.
- **Unmotivated claims**: A statement is made without justification, and the reader has no reason to believe it. "It is well known that..." is not justification.
- **Ambiguity**: A sentence or passage can be read in more than one way, and the intended meaning is not clear from context.
- **Missing context**: The reader needs institutional knowledge, data details, or background that the paper has not provided (either earlier in the draft or in this section).
- **Unsupported leaps**: The text implies a causal or quantitative relationship without evidence or hedging.
- **Structural confusion**: The section's internal organization makes it hard to follow the argument. Information appears in the wrong order, or the reader cannot tell where one sub-argument ends and another begins.

Do NOT flag sentence-level writing issues (awkward phrasing, redundancy, passive voice, etc.). Those belong to a separate editing pass.

## 7. Produce the report

Output a single numbered list. Each item should contain:

1. **A clear statement of the problem** — written in the voice of the seminar audience member. Be specific and direct, but constructive. Frame issues as things the reader needs help understanding, not as failures.
2. **A quote or paraphrase** of the offending text, with an approximate line reference in the `.tex` file if possible.
3. **Why it matters** — one sentence on what the reader gets wrong, misses, or cannot evaluate because of this issue.
4. **Suggested fix** — a concrete, actionable suggestion for how to resolve the issue. This could be a sentence to add, a concept to define, a restructuring to try, or a clarification to make. Keep it brief but specific enough that the author can act on it.

Order the list by severity: the most damaging clarity failures first.

### Calibration

- **Do not flag things that are genuinely clear.** The point is to find real problems, not to manufacture objections. If a passage is well-written and unambiguous, leave it alone.
- **Do not flag stylistic or sentence-level issues.** This is not a copy-editing pass.
- **Use the earlier sections of the draft as context.** If a term was defined in Section 2 and reused in Section 4, that is fine — do not flag it as undefined.
- **Flag things the author probably thinks are clear but are not.** The most valuable feedback is on blind spots.

End with a one-sentence overall assessment of the section's clarity (e.g., "The argument is sound but the reader has to work too hard to extract it" or "Several key concepts are never properly defined, which undermines the section's credibility").
