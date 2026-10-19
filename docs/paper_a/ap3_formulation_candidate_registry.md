# AP3 formulation candidate registry

Authority: C2A full dissertation e8118425adc335a99e85120d943763305f211315, frozen theorem package 2c2fce769b2ed6ffd4f1ced60c0798776acccc93, owner expanded AP3 mandate (2026-10-20). Existing AP2 B/S/M, physical import, registered parameter gates, UC/storage/network and cost functions are reused. All optimization comparisons use S_on_v1 and fixed input alpha.

| ID | Actual implementation | Frozen guarantee / prerequisites | Executable evidence |
|---|---|---|---|
| BASE | NoGSCR, unchanged planning builder | no strength constraint | nine-case suite and exact postprocessing |
| G0 | ExactPSDGSCR, affine Symmetric(M) in PSDCone | T005/006 full-space PSD, singular exposure allowed | rational boundaries, Clarabel SDP, Pajarito capability/full-case attempts, complete tiny integer SDP reference |
| G1 | existing GershgorinGSCR and AP2 row builder | T011, symmetric Z; T012 inverse positivity separately | full historical regression and same-case HiGHS LP/MILP |
| G2_identity | FixedScalingGSCR(r=1) | T013/014 equals G1 | both fixed incomparability directions; same-case LP/MILP |
| G2_degree | r_i=1+structural degree, fixed before solving | T013 sufficient; no general dominance over G1 | preregistered parameters.json, infeasibility retained |
| G3 | ExactEdgeSOCGSCR, every exact nonzero edge i<j, two q, sqrt(2)*mij RSOC, every node residue | T017 sufficient generally; T018–020 exact on complete symmetric Z class including singular/reducible boundary | signed/non-Z counterexample, missed/duplicate edge, wrong scaling, isolated row, raw witness reconstruction, SDP/SOCP comparisons |
| M0 | B\\p exact postsolve plus complete 16-assignment discrete reference | T007–010; alpha>0, B PD and inverse-positive. G0 does not imply M0 | rational 7/9,19/18 counterexample; integer_enumeration.json |
| M1 | InverseBoundGSCR: enforced componentwise B>=Bmin and inv(Bmin)*p<=1/alpha | T021/022, ordered nonsingular M-matrices; same passive offdiagonals checked with 1e-10 absolute/1e-12 relative stamp tolerance | enforced positive standalone case; false unenforced-bound case; source-free-region infeasibility; nine registered cases |
| M2_full | InteractionGSCR, W=max(0, Zref_ij/Zref_ii), diag=1 | T023/024, fixed W>=0; implies G1 and conditionally M0 | full vs neighbor tests, W sign/diagonal rejection, same-case LP/MILP |
| M2_neighbor | same W with exact structurally absent B0 edges removed, diagonal retained | less restrictive fixed interaction screen, no universal fault-safety claim | registered full/sparse parameter matrices and comparisons |
| LOCAL | all B-alpha*p_i*e_i*e_i' eigenvalues; rho_diag where inverse exists | T007 rank-one equivalence; necessary consequence of G0, insufficient converse | local-pass/G0-fail rational case |
| E2/WN | exact Woodbury, finite Neumann/Taylor, induced infinity norm and exact remainder | T025–028; diagnostic only, exploratory_noncertifying. Norm bounds do not establish the requested one-sided planning safety without another argument | convergence/outside-domain tests, actual errors and bounds, false-acceptance example and per-state diagnostics |

The offline M1 diagonal source floor is max(0.01,0.01-eigmin(B0)); it makes the reference matrix PD with margin 0.01. It is enforced on endogenous source strength, not stamped as physical grounding. MIIF reference uses B0+max(1,1-eigmin(B0))*I with margin at least 1. Both are explicit comparison certificate parameters, not empirically qualified network parameters. They can produce a restrictive or infeasible certificate. No post-optimum scaling selection occurs.

S_nom_v1 uses installed GFL nameplate; S_on_v1 uses online GFL nameplate; S_op_magnitude_v1 uses absolute AC-side operating power and is a separately named diagnostic (including storage discharge in supported inputs); S_I_v1 is blocked without current/voltage conventions. The common optimization comparison remains S_on_v1.

Native licensed solver availability is tested, not inferred from package installation. The free Pajarito/HiGHS/Clarabel path is separately probed; a capability PASS is not a full-case optimum. Only OPTIMAL with FEASIBLE_POINT is extracted. Numerical/unsupported/infeasible results remain separate. Exact small integer references are complete only for their declared finite fixture; they do not certify every larger UC instance.
