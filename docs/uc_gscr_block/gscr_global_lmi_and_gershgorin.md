# Full-Network gSCR/ESCR Constraints

## 1. Full-network convention

The project uses the full, non-reduced network.

Let:

\[
B^0\in\mathbb R^{|\mathcal N|\times|\mathcal N|}
\]

be the real baseline susceptance/strength matrix on the original bus set.

No reduced network is introduced.

No matrix-valued optimization variable \(B_t\) is introduced in the LP/MILP implementation.

For the global SDP/LMI formulation, \(B_t\) is an affine matrix expression:

\[
B_t
=
B^0
+
\operatorname{diag}(B^{fm}_{1,t},\ldots,B^{fm}_{|\mathcal N|,t}).
\]

## 2. Grid Control Mode

Each block-enabled controllable device has physical AC-grid interface data:

\[
grid\_control\_mode(k)\in\{gfl,gfm\}.
\]

The grid-control mode is not inferred from the bus, and it is not a
formulation type.

All buses may have both GFL and GFM devices.

## 3. Online GFL capacity

\[
P_{n,t}^{fl,on}
=
\sum_{i:\phi(i)=n,\;grid\_control\_mode(i)=gfl}
P_i^{block,max}n_{a,i,t}.
\]

## 4. Online GFM strengthening contribution

\[
B_{n,t}^{fm}
=
\sum_{k:\phi(k)=n,\;grid\_control\_mode(k)=gfm}
b_k^{block}n_{a,k,t}.
\]

Here \(b_k^{block}\) is a real per-block susceptance/strength contribution.

It is not multiplied by \(P_k^{block}\) unless the data schema is later redefined.

## 5. Global full-network LMI condition

Define:

\[
S_t
=
\operatorname{diag}
\left(
P_{1,t}^{fl,on},\ldots,P_{|\mathcal N|,t}^{fl,on}
\right).
\]

Define:

\[
B_t
=
B^0
+
\operatorname{diag}(B_{1,t}^{fm},\ldots,B_{|\mathcal N|,t}^{fm}).
\]

The global gSCR LMI is:

\[
B_t-\underline g S_t \succeq 0.
\]

With `relax=true`, this is an SDP.

With `relax=false`, this is an MISDP and should be treated as an advanced follow-up.

Recommended code name:

```julia
constraint_gscr_global_lmi
```

## 6. Linear Gershgorin sufficient condition

Define:

\[
\sigma_n^{0,G}
=
B^0_{nn}
-
\sum_{j\ne n}|B^0_{nj}|.
\]

Then a sufficient linear condition for the LMI is:

\[
\sigma_n^{0,G}
+
B_{n,t}^{fm}
\ge
\underline g P_{n,t}^{fl,on},
\qquad
\forall n,t.
\]

Expanded:

\[
\sigma_n^{0,G}
+
\sum_{k:\phi(k)=n,\;grid\_control\_mode(k)=gfm}
b_k^{block}n_{a,k,t}
\ge
\underline g
\sum_{i:\phi(i)=n,\;grid\_control\_mode(i)=gfl}
P_i^{block,max}n_{a,i,t}.
\]

Recommended code name:

```julia
constraint_gscr_gershgorin_sufficient
```

## 7. Interpretation as ESCR-like per-bus condition

The linear condition can be interpreted as:

\[
\frac{\sigma_n^{0,G}+B_{n,t}^{fm}}{P_{n,t}^{fl,on}}
\ge
\underline g
\]

when \(P_{n,t}^{fl,on}>0\).

The optimization model does not use this ratio. It uses the affine inequality.

## 8. Threshold convention

Do not use inverse online capacity in the LP/MILP.

For diagnostics only:

\[
\widehat P_{n,t}^{fl,on}
=
\max(P_{n,t}^{fl,on},1\text{ MW}).
\]

## 9. Implementation order

1. Compute full-network \(B^0\).
2. Compute \(\sigma_n^{0,G}\).
3. Implement the Gershgorin sufficient LP/MILP constraint.
4. Later implement the global SDP/LMI as a separate module.
