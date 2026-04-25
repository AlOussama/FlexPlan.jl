# Codex Task 03 — Dispatch and Storage Constraints

## Goal

Add active and reactive dispatch constraints and storage energy constraints.

## Active power

\[
p_k^{block,min} n_{a,k,t}
\le
p_{k,t}
\le
p_k^{block,max} n_{a,k,t}.
\]

## Reactive power

\[
q_k^{block,min} n_{a,k,t}
\le
q_{k,t}
\le
q_k^{block,max} n_{a,k,t}.
\]

Use no-op methods for active-power-only formulations.

## Storage

\[
0 \le e_{k,t} \le n_k e_k^{block}.
\]

Charge/discharge bounds scale with \(n_a\).

## Tests

Add active-power, reactive no-op, storage energy, and charge/discharge tests.

## Documentation

Every function must have a docstring.
