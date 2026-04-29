# Discussion Notes

## Network decoupling and conservatism

The implemented Gershgorin constraint is local and sufficient. For each snapshot, post-hoc validation considers

```math
M_t = B_t - \alpha S_t, \qquad \mu_t = \lambda_{\min}(M_t).
```

The local constraint slack is

```math
\kappa_{i,t} = \sigma_i^G + \Delta b_{i,t} - \alpha P_{i,t}^{GFL}.
```

For a pure lossless branch Laplacian, the Gershgorin network margin may be zero at each node. The diagonal-dominance margin must then be supplied locally by online GFM strength. This makes the condition transparent but conservative, because it does not fully exploit support from the meshed network. The post-hoc eigenvalue analysis quantifies the gap between local sufficient constraints and the global matrix-strength condition.

## Computational tractability

The method preserves the MILP structure of the clustered generation-expansion problem. It requires no SDP solver and no repeated eigenvalue-gradient update inside branch-and-bound. Each scenario is solved as a single MILP. In the completed 336 h campaign, the BASE and gSCR-GERSH solve times were 0.45 min and 0.52 min, respectively.

## Planning interpretation and limitations

The gSCR constraint is a planning-level system-strength proxy. It does not replace converter-dynamic or electromagnetic-transient simulations, and the threshold must be calibrated against the converter controls and stability criteria of interest. The two-week period 03.01--16.01 is the selected stress window used in this study and should not be interpreted as full-year chronological validation.
