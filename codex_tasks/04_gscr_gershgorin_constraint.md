# Codex Task 04 — Linear Gershgorin gSCR Constraint

## Goal

Implement the LP/MILP-compatible gSCR sufficient condition.

## Constraint

\[
\sigma_n^{0,G}
+
\sum_{k:\phi(k)=n,type(k)=gfm}
b_k^{block}n_{a,k,t}
\ge
\underline g
\sum_{i:\phi(i)=n,type(i)=gfl}
P_i^{block}n_{a,i,t}.
\]

## Requirements

- Use `gscr_sigma0_gershgorin_margin`.
- Use global `g_min`.
- Build for all buses.
- Empty sums are allowed.
- Add feasible/infeasible tests.
- Add docstrings for every new function.

## Non-goals

Do not implement global SDP/LMI yet.
