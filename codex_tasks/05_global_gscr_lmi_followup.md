# Codex Task 05 — Global gSCR LMI Follow-up

## Goal

Add the SDP global full-network gSCR LMI as a separate advanced module.

## Constraint

\[
B_t-\underline g S_t\succeq 0.
\]

with:

\[
B_t = B^0+\operatorname{diag}(B^{fm}_t),
\]

\[
S_t=\operatorname{diag}(P^{fl,on}_t).
\]

## Requirements

- Only for `relax=true` initially.
- Use an SDP-capable solver.
- Keep separate from the Gershgorin LP/MILP path.
- Add small PSD construction tests.
- Add docstrings for every new function.

## Non-goals

Do not attempt MISDP first.
