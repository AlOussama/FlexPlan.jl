# Test Specification

## Test group A — data/reference tests

### A1: device type classification

Input devices with:

```julia
type = "gfl"
type = "gfm"
```

Expected:

- `gfl_devices` correct;
- `gfm_devices` correct;
- `bus_gfl_devices[n]` correct;
- `bus_gfm_devices[n]` correct.

### A2: full-network indexing

Expected:

- all original buses appear;
- no reduced bus set is created.

### A3: susceptance matrix and row metrics

Given a small known \(B^0\), test:

\[
\sigma_n^{0,G}=B^0_{nn}-\sum_{j\ne n}|B^0_{nj}|.
\]

Also compute raw row sum for diagnostics.

## Test group B — block variables

### B1: installed block bounds

\[
n^0 \le n \le n^{max}.
\]

### B2: active block bounds

\[
0 \le n_a(t) \le n.
\]

### B3: relaxed mode

With `relax=true`, `n` and `na` are continuous.

### B4: integer mode follow-up

With `relax=false`, `n` and `na` are integer.

## Test group C — dispatch constraints

### C1: active-power bounds

For fixed \(n_a=2\):

\[
2p^{block,min}\le p\le 2p^{block,max}.
\]

### C2: reactive-power bounds

For AC/reactive formulations:

\[
2q^{block,min}\le q\le 2q^{block,max}.
\]

For active-power-only formulations, verify no missing `q` errors.

## Test group D — storage tests

### D1: energy capacity

For \(n=3\):

\[
e_t \le 3e^{block}.
\]

### D2: charge/discharge bounds

For \(n_a=2\):

\[
p^{ch}\le 2p^{ch,block,max}.
\]

\[
p^{dch}\le 2p^{dch,block,max}.
\]

## Test group E — gSCR Gershgorin tests

### E1: feasible case

Use:

\[
\sigma=1.0,\quad b=0.5,\quad n_a^{fm}=2,\quad g=0.1,\quad P=10,\quad n_a^{fl}=1.
\]

Expected:

\[
1+0.5\cdot2 \ge 0.1\cdot10\cdot1.
\]

### E2: infeasible case

Use:

\[
\sigma=0,\quad b=0.2,\quad n_a^{fm}=1,\quad g=0.1,\quad P=10,\quad n_a^{fl}=3.
\]

Expected infeasible unless \(n_a^{fl}\) decreases or \(n_a^{fm}\) increases.

### E3: empty bus terms

Test buses with:

- only GFL;
- only GFM;
- neither.

All constraints should be well defined.

## Test group F — global LMI tests

These are follow-up SDP tests.

### F1: PSD matrix construction

Build:

\[
M_t=B^0+\operatorname{diag}(B^{fm}_t)-gS_t.
\]

Check dimensions and symmetry.

### F2: small SDP feasibility

Use a 2-bus or 3-bus system where PSD feasibility can be checked analytically.

### F3: compare LMI and Gershgorin

Construct a case where Gershgorin implies PSD.

Construct a case where PSD holds but Gershgorin is conservative, if possible.

## Test group G — regression

Run existing FlexPlan tests.

Cases without block fields should remain unchanged.
