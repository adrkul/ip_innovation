---
name: compile-latex
description: Compile a LyX paper or Beamer LaTeX slide deck. Auto-detects file type. Use for compiling the paper draft or conference slides.
argument-hint: "[path to .lyx or .tex file]"
allowed-tools: ["Read", "Bash", "Glob"]
---

# Compile LyX Paper or Beamer Slides

Compiles a LyX paper file or a Beamer LaTeX slide deck with full citation resolution.

## Auto-detection

- If argument ends in `.lyx` → use `lyx --export pdf2`
- If argument ends in `.tex` and is in `Slides/` → use 3-pass XeLaTeX sequence
- If no argument given, look for `Paper/innovation_draft.lyx` (default)

---

## For LyX Paper Files

```bash
lyx --export pdf2 $ARGUMENTS
```

LyX handles multi-pass compilation internally (pdflatex + bibtex + pdflatex × 2).

**Check output for:**
- Grep log for `undefined citations` or `LaTeX Error`
- Verify PDF created: `ls -la $(dirname $ARGUMENTS)/$(basename $ARGUMENTS .lyx).pdf`
- Open PDF: `open $(dirname $ARGUMENTS)/$(basename $ARGUMENTS .lyx).pdf`

**Common LyX compilation errors:**
- `lyx: command not found` → Check `which lyx`; LyX may need to be added to PATH
- `LaTeX Error: File not found` → Check `\includegraphics` paths are relative
- `undefined citations` → Run `/validate-bib` to find missing entries

---

## For Beamer Slides (.tex in Slides/)

3-pass XeLaTeX sequence for full bibliography resolution:

```bash
cd Slides
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
BIBINPUTS=..:$BIBINPUTS bibtex $ARGUMENTS
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
TEXINPUTS=../Preambles:$TEXINPUTS xelatex -interaction=nonstopmode $ARGUMENTS.tex
```

**Check for warnings:**
- Grep for `Overfull \hbox` warnings
- Grep for `undefined citations`
- Open PDF: `open Slides/$ARGUMENTS.pdf`

**Why 3 passes?**
1. First xelatex: Creates `.aux` file with citation keys
2. bibtex: Reads `.aux`, generates `.bbl` with formatted references
3. Second xelatex: Incorporates bibliography
4. Third xelatex: Resolves all cross-references with final page numbers

**Important for slides:** Always use XeLaTeX. TEXINPUTS and BIBINPUTS are required because the Beamer theme lives in `Preambles/` and the bibliography is in `Bibliography/`.

---

## Report Results

After compilation:
- Compilation success/failure
- Number of overfull hbox warnings (paper: in body text; slides: in frames)
- Any undefined citations
- PDF page count
