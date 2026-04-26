# Block-Based Generator and Storage Expansion Formulation

## 1. Core variables

Current project-stage UC-like scope is limited to:

- active/online block counts \(n_{a,k,t}\);
- startup block-count variables \(su_{k,t}^{block}\);
- shutdown block-count variables \(sd_{k,t}^{block}\);
- startup/shutdown block-count cost terms in the objective.

Minimum up-time and minimum down-time constraints are explicitly out of scope
for this stage.

For each expandable device \(k\):

\[
n_k = \text{installed blocks}
\]

\[
n_{a,k,t} = \text{active/online blocks at time/network }t.
\]

\[
su_{k,t}^{block} = \text{started blocks at time/network }t.
\]

\[
sd_{k,t}^{block} = \text{shut-down blocks at time/network }t.
\]

The first implementation uses continuous relaxation:

\[
n_k,n_{a,k,t}\in\mathbb R.
\]

\[
su_{k,t}^{block}, sd_{k,t}^{block}\in\mathbb R_{\ge 0}.
\]

The integer follow-up uses:

\[
n_k,n_{a,k,t}\in\mathbb Z.
\]

\[
su_{k,t}^{block}, sd_{k,t}^{block}\in\mathbb Z_{\ge 0}.
\]

## 2. Installed block bound

\[
n_k^0 \le n_k \le n_k^{\max}.
\]

## 3. Active block bound

\[
0 \le n_{a,k,t} \le n_k.
\]

## 4. Investment cost

No multiyear model is considered in the first implementation.

\[
C_k^{inv} = c_k^{block}(n_k-n_k^0).
\]

The installed count \(n_k\) is used for investment and installed capacity.

The active count \(n_{a,k,t}\) is used for operational limits and stability contributions.

## 4b. Startup/shutdown block transitions

For \(t > 1\):

\[
n_{a,k,t} - n_{a,k,t-1} = su_{k,t}^{block} - sd_{k,t}^{block}.
\]

For the first snapshot:

\[
n_{a,k,1} - n_{a,k}^{0,a} = su_{k,1}^{block} - sd_{k,1}^{block},
\]

where \(n_{a,k}^{0,a}\) is input field `na0`.

## 4c. Startup/shutdown block operation cost

\[
C^{su/sd} = \sum_{k,t}
\left(
c_k^{startup,block} \, su_{k,t}^{block}
+
c_k^{shutdown,block} \, sd_{k,t}^{block}
\right).
\]

## 5. Active-power dispatch bounds

\[
p_k^{block,min} n_{a,k,t}
\le
p_{k,t}
\le
p_k^{block,max} n_{a,k,t}.
\]

## 6. Reactive-power dispatch bounds

For formulations with reactive power:

\[
q_k^{block,min} n_{a,k,t}
\le
q_{k,t}
\le
q_k^{block,max} n_{a,k,t}.
\]

For active-power-only formulations, these constraints are no-ops, but the function hooks must exist.

## 7. Storage energy capacity

For storage-capable devices:

\[
0 \le e_{k,t} \le n_k e_k^{block}.
\]

Energy capacity scales with installed blocks \(n_k\), not active blocks \(n_{a,k,t}\).

## 8. Storage dynamics

\[
e_{k,t}
=
e_{k,t-1}
+
\eta_k^{ch}p_{k,t}^{ch}\Delta t
-
\frac{1}{\eta_k^{dch}}p_{k,t}^{dch}\Delta t.
\]

\[
p_{k,t}=p_{k,t}^{dch}-p_{k,t}^{ch}.
\]

Charge and discharge power limits scale with \(n_{a,k,t}\).
