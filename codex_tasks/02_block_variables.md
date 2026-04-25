# Codex Task 02 — Installed and Active Block Variables

## Goal

Add installed block variable \(n\) and active block variable \(n_a\).

## Equations

\[
n_k^0 \le n_k \le n_k^{max}
\]

\[
0 \le n_{a,k,t} \le n_k
\]

## Requirements

- `n` is shared across time/network snapshots.
- `na` is snapshot-specific.
- `relax=true`: continuous variables.
- `relax=false`: integer variables.
- Add tests for bounds, relaxation, and snapshot sharing.
- Add docstrings for every new function.

## Non-goals

Do not add dispatch or gSCR constraints yet.
