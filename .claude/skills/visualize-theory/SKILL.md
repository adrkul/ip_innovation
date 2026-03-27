---
name: visualize-theory
description: Scan a theoretical LaTeX draft section and identify which results could be visualized — phase diagrams, comparative statics figures, mechanism diagrams — and how an economist would want to graph them. Use when you want to know if theory results can be illustrated graphically.
argument-hint: "<sec:label> [draft.tex]"
---

# Visualize Theory: Graphical Opportunities in a Draft Section

Read a theoretical draft section and identify every result that an economist would prefer to see as a figure. For each opportunity, specify exactly what to plot, what economic insight it conveys, and whether it can be produced analytically or requires simulation.

## 1. Parse arguments

`$ARGUMENTS` must contain:
1. **Section label** (required) — a LaTeX label (e.g., `sec:theory`).
2. **Draft path** (optional) — path to the `.tex` or `.lyx` file. Defaults to `Paper/innovation_draft.lyx`.

If the section label is missing, tell the user the expected invocation format and stop.

## 2. Export LyX to TeX (if needed)

If the draft path ends in `.lyx`:
1. Run `lyx --export latex <path>` from the project root. LyX will produce a `.tex` file in the same directory with the same base name.
2. Use that `.tex` file for all subsequent steps.
3. If the export fails, tell the user and stop.

If the draft path ends in `.tex`, skip this step.

## 3. Extract the target section

1. Read the `.tex` file. Locate `\label{<section_label>}`.
2. Extract all content from that line up to (but not including) the next `\label{sec:...}` occurrence.
3. Also read the content before this section (earlier sections, preamble excluded) to understand what objects and assumptions have been established.
4. If the label is not found, tell the user and stop.

## 4. Identify visualization opportunities

Work through the section systematically. For each proposition, theorem, lemma, corollary, comparative static, or described mechanism, ask: **could this be shown as a figure?**

Check the following categories:

### 4a. Phase diagrams and equilibrium loci

- Are there equilibrium conditions that could be plotted as curves in two-dimensional space — best-response functions, isoprofit curves, zero-profit loci, fixed-point conditions?
- Would a phase diagram clarify existence, uniqueness, or local stability of equilibrium?
- Can multiplicity or corner solutions be shown as intersections or non-intersections of curves?

### 4b. Comparative statics figures

- For each signed comparative static result, can it be shown as a curve shift, a threshold crossing, or a region plot over key parameters?
- Are there parameter interactions (the effect of one parameter depends on the level of another) that a contour plot or heat map would clarify better than prose?
- Would a simple plot of an endogenous variable against a key parameter — holding others fixed — illustrate the mechanism?

### 4c. Mechanism diagrams

- Is the core economic mechanism (hold-up, spillover, screening, sorting) something that a timeline, payoff diagram, or flow diagram would clarify?
- Does the model have a matching or assignment structure that a bipartite graph or sorting diagram would convey?
- Is there a welfare comparison or efficiency wedge that an area diagram (Harberger-style) would communicate?

### 4d. Limiting and special cases

- Are there limiting cases (as a key parameter goes to 0 or ∞) where the equilibrium collapses to something familiar? A figure showing the transition anchors intuition.
- Is there a special symmetric or linear case with a clean analytical solution where the comparative static is monotone? That case is usually the right one to plot first.

## 5. Produce the report

Output a numbered list of visualization opportunities. For each:

1. **Result** — identify the proposition, lemma, comparative static, or mechanism (quote the label or a brief description).
2. **Figure type** — the kind of diagram (e.g., "phase diagram", "comparative statics plot", "payoff diagram", "contour plot over parameter space").
3. **What to plot** — axes, the curves or objects to draw, and which parameter variation to illustrate. Be concrete enough that an RA could implement it.
4. **What it reveals** — in one sentence, the economic insight the figure communicates that prose alone does not.
5. **Feasibility** — `Analytic` (closed-form expressions exist; no simulation needed), `Numerical` (requires calibrated simulation), or `Schematic` (a qualitative diagram, no numbers required).

Order by feasibility: analytic figures first, then numerical, then schematic.

After the list, write a one-paragraph summary: which result most urgently needs a figure (and why), and whether the section as a whole is under-illustrated relative to what a top-journal referee would expect.
