# Julia Code Conventions

**Applies to:** `**/*.jl`, `Theory/Code/**`, `Simulation/Code/**`

These conventions govern all Julia code in this project — theoretical equilibrium models and structural GMM estimation.

---

## 1. Reproducibility

- **Random seed:** Call `Random.seed!(YYYYMMDD)` once at the top of any script that uses random numbers. Use the current date as the seed (e.g., `Random.seed!(20260326)`). Do not use `seed = 1` or other arbitrary values.
- **Explicit imports:** List all `using` statements at the top of the file, never inside functions.
- **Relative paths only:** All file I/O uses paths relative to the project root. No hardcoded absolute paths (e.g., `/Users/adrkul/...`).
- **Output directories:** Use `mkpath("Simulation/Output/run_name/")` before writing output. Never assume the directory exists.

---

## 2. Package Management

- Each Julia subdirectory (`Theory/Code/`, `Simulation/Code/`) has its own `Project.toml` pinning exact package versions.
- Do not add packages without updating `Project.toml`.
- Activate the environment at the top of scripts: `using Pkg; Pkg.activate(@__DIR__)` — or run with `julia --project=Theory/Code script.jl`.
- Commit `Project.toml`. Do not commit `Manifest.toml` (it is gitignored).

---

## 3. Naming Conventions

- **Functions and variables:** `snake_case` (e.g., `compute_moments`, `inner_loop_tol`)
- **Types and structs:** `PascalCase` (e.g., `ModelParams`, `GMMObjective`)
- **Constants:** `ALL_CAPS` (e.g., `N_FIRMS`, `MAX_ITER`)
- **No magic numbers:** Define named constants at the top of the file.

---

## 4. GMM / Structural Estimation Conventions

These apply to scripts in `Simulation/Code/`.

### Moment Functions
- The moment function is named `compute_moments(params, data)` or `moment_conditions(params, data)`.
- It returns a vector of moment conditions (deviations from zero).
- Never compute moments inside the optimizer callback directly — always delegate to a named function.

### Objective Function
- The GMM objective is `gmm_objective(params, data, W)` where `W` is the weighting matrix.
- Returns a scalar.
- Logs iteration count and current objective value at user-specified verbosity levels.

### Saving Optimizer Output
- Save parameter estimates and diagnostics with `JLD2.jldsave("Simulation/Output/YYYYMMDD_HHMMSS_description/results.jld2"; params=..., moments=..., converged=..., obj_val=...)`.
- Never save results as raw `.csv` from Julia — use JLD2 for structured output; export summary tables from R.
- Timestamp output directories: `Dates.format(now(), "yyyymmdd_HHMMSS")`.

### Tolerance Thresholds
- **Outer loop (parameter updates):** `outer_tol = 1e-6`
- **Inner loop (fixed point / value function):** `inner_tol = 1e-8`
- **Convergence flag:** Always store and check `converged::Bool`; never assume convergence without checking.
- Document tolerance choices with a comment explaining what they imply for estimates.

### Multi-Start Optimization
- Multi-start is implemented in `multistart.jl`; do not replicate it inline in estimation scripts.
- Each start saves intermediate results; the best start (lowest objective) is the reported estimate.
- Log the number of starts, best objective, and which start achieved it.

### Parallelism
- Use `Distributed.jl` for across-start parallelism (coarse-grained; starts are independent).
- Use `Threads.jl` only for within-start parallelism on embarrassingly parallel inner loops.
- Never mix both in the same script without documenting the reason.
- Always test serial correctness before parallelizing.

---

## 5. Function Design

- Write docstrings for all exported functions using Julia's triple-quote syntax:
  ```julia
  """
      compute_moments(params, data) -> Vector{Float64}

  Compute GMM moment conditions given parameter vector `params` and data `data`.
  Returns a vector of deviations; zero vector = exact moment match.
  """
  function compute_moments(params, data)
  ```
- Functions should do one thing. If a function exceeds ~80 lines, consider splitting.
- Type-annotate function arguments when performance-critical:
  ```julia
  function inner_loop(params::Vector{Float64}, tol::Float64=1e-8)
  ```

---

## 6. Theoretical Model Scripts

These apply to scripts in `Theory/Code/`.

- Define all structural parameters in a named tuple or struct at the top:
  ```julia
  params = (rho=0.5, sigma=2.0, omega=0.8, gamma=0.3, theta=1.2, tau=1.0)
  ```
- Profit and value functions are named to match the paper notation (e.g., `π_j`, `V_firm`).
- Existence and uniqueness proofs (`exist_unique.jl`) are separate from simulation scripts.
- Equilibrium solution scripts call a named `solve_equilibrium(params)` function, not inline iteration.

---

## 7. Common Pitfalls

| Pitfall | Correct Approach |
|---------|-----------------|
| Type instability in hot loops | Use `@code_warntype` to diagnose; annotate or restructure |
| Global variable capture in parallel workers | Pass all data as function arguments; avoid global state |
| Precompilation side effects | Keep top-level code minimal; wrap in `if abspath(PROGRAM_FILE) == @__FILE__` |
| `Float64` vs `Float32` precision loss | Use `Float64` everywhere for estimation; document if lower precision is intentional |
| Not checking convergence | Always check `converged` flag before reporting estimates |
| Hardcoded worker count | Use `nworkers()` or accept as argument; never hardcode `addprocs(8)` |

---

## 8. Quality Checklist

Before committing any Julia script:

- [ ] `Random.seed!` present if any random operations used
- [ ] All imports at top level
- [ ] No hardcoded absolute paths
- [ ] `Project.toml` updated if new packages added
- [ ] Convergence flag checked and logged
- [ ] Output saved to timestamped directory in `Simulation/Output/`
- [ ] Script runs cleanly from repo root: `julia --project=Simulation/Code Simulation/Code/script.jl`
