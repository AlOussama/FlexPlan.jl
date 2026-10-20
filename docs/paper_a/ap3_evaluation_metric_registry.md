# AP3 metric registry and independent algorithms

Machine registry: each successful evaluate_strength_metrics execution writes metric_registry.json with ID, formula/algorithm, shape, scope, units, theorem and tolerance. Final registry has 124 IDs and 68,861 records. metrics.json contains per-record provenance, snapshot/region order, value_or_null, validity_status, domain_predicates, equation_reference, independent_method, tolerance, residual and solver_status. metrics.csv contains the same provenance and JSON-valued cells (value_or_null_json, region_or_edge_json, domain_predicates_json). JSON null always accompanies an explicit missing/domain status. Horizon costs/events and run-level solver quantities occur once, snapshot_id=all; state quantities retain snapshot scope.

| Group | Executable algorithms and recorded quantities | Domain / source |
|---|---|---|
| A physical | raw branch r/x/charging stamps on native kV/system MVA base; fixed shunts once; L=-imag(Y); passive PD Schur solve; B0 plus native-MVA/reactance/mu source diagonal; independent online GFL exposure; raw producer and affine model residuals; source/capacity ledger; connection bounds; islands, retained/eliminated nodes, references and fixed-source inventories | PaperADiagnostics.reconstruct; T001/004, AP1 raw contract. No producer B0 or JuMP coefficients are used to construct matrices. Importer remains responsible for inventory/parameter eligibility. |
| A classes | symmetry, maximum positive offdiagonal, eigenvalues, inertia/nullity/rank, condition number | evaluate; PSD and PD distinct, floating islands not grounded by slack references |
| B spectral | smallest finite generalized eigenvalue using positive support and PSD zero-block pseudoinverse PLUS range projector; eigenspace, multiplicity, normalized participation, eigen/range residuals; G0 eigmin and margin | finite_spectrum; T004–006, all-zero exposure explicitly undefined; residual accuracy checked |
| B linear/conic | G1/G2 full row slacks, binding flags, false rejection; G3 endpoint q, product slacks, node budget and complete-edge/reconstruction checks; independent T018 block-scaling witness if no solver q supplied | verify_g3 and closed_sdd_witness; T011–020. Every exact nonzero edge retained. Infeasible/unknown witness is not a PASS. |
| C inverse | exact B\\p and solve residual; all Z entries by linear solves, diagonal and minimum entry; equivalent strength 1/Zii (pu and model MVA), rho_diag and rho_Zp with denominator status; M0 slack; local rank-one eigmin | T007–010, B PD and condition<=1e12; inverse sign checked separately; alpha zero/singular B explicit |
| C certificates | M1 inverse upper burden, enforced minimum-matrix and actual inverse-order residual; M2 Wp, full margins and weights; model-normalized MIIF=Zij/Zii | T021–024, no identification with external fault-time MSCR |
| C external names | SCR/ESCR/MSCR/gSCR source-qualified convention gate | not_comparable_missing_source_fault_convention for these inputs; no fabricated source-specific index |
| D updates | Woodbury vs direct solve; E=A^-1 Delta, induced infinity norm, spectral radius; finite order-1 Taylor/Neumann plus exact remainder and norm bound when norm(E)<1; actual error, trust gate, false acceptance/rejection | inverse_updates, T025–028; exploratory_noncertifying, no planning constraint or one-sided safety claim |
| E planning | installed/initial/new blocks, MW/MVA/MWh by asset/carrier/region/class; source/exposure; independent raw CAPEX, energy generation, storage discharge, no-load constant, per-block startup/shutdown prices times separate event repetitions; curtailment; PF, branch, UC, SOC, terminal, bounds/integrality residuals | AP3Pipeline.planning. Registered annualized price includes declared FOM; a separate FOM decomposition is not identifiable from case price and is labeled accordingly. No annual representativity claim. |
| E exposures | installed, online, operating magnitude and current-capability gate | physically distinct versioned diagnostics; same S_on in formulation comparison |
| F comparisons | absolute/relative cost delta with named abs(G0 cost) denominator; portfolio/location block differences; cross G0/G3/G1 feasibility, M0 failures, G1 false rejections; worst eigen/row and per-region binding frequency | compare; only same input hash/relaxation compared; differing optimal portfolios are permitted |
| F computation | model variable/integer/constraint-type counts; build/solve time; solver/primal/dual status, bound/gap and iteration/node attributes; size/edge scaling and allocation bytes | runtime attributes; unsupported values null, peak memory explicitly unavailable, build includes model compilation/first-call work; allocation bytes are not peak RSS |

Numerical policy: default independent relative scale 1e-7, matrix spectral/row checks scaled by max(1,||B||inf), inverse-order/sign checks by max(1,||Z||inf). Inverse condition >1e12 is inconclusive. Singular support uses an eigenvalue tolerance and explicitly records projector residual. Raw residuals are retained, including boundary roundoff. Solver tolerances are separate and recorded in the runner. A zero measured residual is never substituted for an unavailable metric. Independent A3.5 must assess scaling/tolerance adequacy and any inconclusive cases.

The frozen rational tests cover singular support/range failures, all-zero exposure, PD/inverse-sign/conditioning failures, local vs G0 and G0 vs M0, fixed G1/G2 incomparability, closed-SDD boundary/non-Z failures, M1 enforcement, M2 weight gates, and E2 false safety claims. Existing AP2 source/base/availability/storage/cost tests remain in the full suite.

LOCAL matrix eigenvalue tests are also computed when B is singular; only impedance-based equivalence requires an inverse. S_op_magnitude_v1 uses absolute net storage power. E.FOM is a declared bundled-cost ledger rather than a fictitious separately priced value. Missing external fault conventions, S_I and unavailable solver attributes remain explicit non-success records. metric_coverage.json lists computed counts and statuses for every ID; positive and rejected M1 fixtures supplement the infeasible registered M1 scenarios. The full schema/CSV roundtrip and byte-identical raw-matrix replay are tested.

Large metrics.json and metrics.csv are retained locally and published losslessly as metrics-json.zip and metrics-csv.zip. metric_archive_verification.json records archive-entry and raw-file SHA256 equality. Extract before running the saved-evidence tests on a fresh clone.

## Exact exported ID inventory

The following table is generated from the final machine registry. Base is the per-record system MVA; domain status and source/theorem fields remain attached to every JSON/CSV record. A formula may compute a failed screen or an explicitly noncertifying diagnostic; a non-null value does not imply scientific acceptance.

| Metric ID | Formula / executable quantity | Unit | Scope |
|---|---|---|---|
| A.affine_reconstruction_residual | max(norm(Braw-Baff),norm(Mraw-Maff),norm(praw-paff)) | pu | snapshot_region_or_edge |
| A.B | B0+Diagonal(b_fix+sum(mu_str*n_on*native_MVA/(base*x_native))) | pu | snapshot_region_or_edge |
| A.B_eigenvalues | eigvals(Symmetric(B)) | pu | snapshot_region_or_edge |
| A.B0 | Lrr-Lre*(Lee\Ler) | pu | snapshot_region_or_edge |
| A.condition | cond(B,2) | dimensionless | snapshot_region_or_edge |
| A.connection_violation | max(0,n_on-a_conn*n_inst,-n_on) | pu | snapshot_region_or_edge |
| A.exposure_roundoff_correction | max(0,-min(raw_p)); only negative solver roundoff <= tolerance projected to zero | MW_per_system_MVA | snapshot_region_or_edge |
| A.inertia | counts(lambda_B<-tau,abs(lambda_B)<=tau,lambda_B>tau) | count | snapshot_region_or_edge |
| A.L | -Im(Y) | pu | snapshot_region_or_edge |
| A.M | B-alpha*Diagonal(p) | pu | snapshot_region_or_edge |
| A.M_eigenvalues | eigvals(Symmetric(B-alpha*Diagonal(p))) | pu | snapshot_region_or_edge |
| A.network_domain | raw islands, references, retained/eliminated buses and fixed-shunt/source inventories | explicit_field_ledger | snapshot_region_or_edge |
| A.nullity | count(abs(lambda_B)<=scaled_tolerance) | count | snapshot_region_or_edge |
| A.positive_offdiagonal | max(0,max_{i!=j} Bij) | pu | snapshot_region_or_edge |
| A.producer_B0_residual | norm(B0_independent-B0_producer,Inf) | pu | snapshot_region_or_edge |
| A.rank | count(abs(lambda_B)>scaled_tolerance) | count | snapshot_region_or_edge |
| A.S_diag | sum_GFL(mu_fl*P_block_MW*n_on/base_MVA) by region | MW_per_system_MVA | snapshot_region_or_edge |
| A.schur_residual | norm(Lee*(Lee\Ler)-Ler,Inf) | pu | snapshot_region_or_edge |
| A.source_base_residual | max(abs(b_block_declared-native_MVA/(base_MVA*x_native))) | pu | snapshot_region_or_edge |
| A.source_ledger | per-asset independent installed/online/source/exposure/MW/MVA/MWh quantities | explicit_field_ledger | snapshot_region_or_edge |
| A.symmetry | norm(B-transpose(B),Inf) | pu | snapshot_region_or_edge |
| A.Y_imag | Im(Y) from reciprocal physical series and terminal charging/shunt stamps | pu | snapshot_region_or_edge |
| A.Y_real | Re(Y) from reciprocal physical series and terminal charging/shunt stamps | pu | snapshot_region_or_edge |
| A.Z_class | max_{i!=j} Bij<=tolerance | boolean | snapshot_region_or_edge |
| B.eigen_residual | norm(B*V-Diagonal(p)*V*gamma,Inf) | pu | snapshot_region_or_edge |
| B.eigenspace | positive-support scaled eigenvectors lifted through exact zero-support Schur solve | pu | snapshot_region_or_edge |
| B.G0 | eigmin(M)>=-scaled_tolerance | boolean | snapshot_region_or_edge |
| B.G0_eigmin | eigmin(B-alpha*Diagonal(p)) | pu | snapshot_region_or_edge |
| B.G1 | min(M*ones(n))>=-scaled_tolerance | boolean | snapshot_region_or_edge |
| B.G1_binding | abs.(M*ones(n))<=scaled_tolerance | boolean | snapshot_region_or_edge |
| B.G1_false_rejection | G0 && !G1 | boolean | snapshot_region_or_edge |
| B.G1_rows | (B-alpha*Diagonal(p))*ones(n) | pu | snapshot_region_or_edge |
| B.G2 | min(M*r_offline)>=-scaled_tolerance | boolean | snapshot_region_or_edge |
| B.G2_binding | abs.(M*r_offline)<=scaled_tolerance | boolean | snapshot_region_or_edge |
| B.G2_rows | (B-alpha*Diagonal(p))*r_offline | pu | snapshot_region_or_edge |
| B.G3 | complete signed edges && nonnegative q/cone products/node residues && exact reconstruction within tolerance | boolean | snapshot_region_or_edge |
| B.G3_cone_product_slacks | qij*qji-mij^2 | pu_admittance_squared | snapshot_region_or_edge |
| B.G3_edges | all exact nonzero undirected pairs (i,j), i<j | count_or_index | snapshot_region_or_edge |
| B.G3_edges_complete | unique witness edge set equals all nonzero offdiagonal pairs | pu | snapshot_region_or_edge |
| B.G3_minimum_q | minimum endpoint allocation, undefined for no edges | pu_admittance | snapshot_region_or_edge |
| B.G3_node_budget | mii-sum_j(qij) | pu_admittance | snapshot_region_or_edge |
| B.G3_q | both oriented endpoint allocations qij,qji for every signed edge | pu_admittance | snapshot_region_or_edge |
| B.G3_reconstruction_residual | norm(M-sum(embedded edge Q)-Diagonal(node_residue),Inf) | pu | snapshot_region_or_edge |
| B.G3_status | edge/witness domain and verification status | status | snapshot_region_or_edge |
| B.G3_valid | complete signed edges && nonnegative q/cone products/node residues && reconstruction within tolerance | pu | snapshot_region_or_edge |
| B.gamma | lambda_min(Sa^-1/2*(Baa-Baz*Bzz_dagger*Bza)*Sa^-1/2), with PSD and range tests | dimensionless | snapshot_region_or_edge |
| B.gamma_margin | smallest finite generalized eigenvalue minus alpha | dimensionless | snapshot_region_or_edge |
| B.multiplicity | count(abs(finite_eigenvalue-gamma)<=scaled_tolerance) | count_or_index | snapshot_region_or_edge |
| B.participation | row sums of squared critical lifted modes divided by total squared mode magnitude | dimensionless | snapshot_region_or_edge |
| B.range_residual | norm(Bzz*(Bzz_dagger*Bza)-Bza,Inf) | pu | snapshot_region_or_edge |
| C.equivalent_strength | 1/Zii | pu_admittance | snapshot_region_or_edge |
| C.equivalent_strength_MVA | base_MVA/Zii (model equivalent, not fault-qualified) | MVA_model_Thevenin_equivalent_not_fault_qualification | snapshot_region_or_edge |
| C.ESCR_external | not_comparable: source-specific fault/compensation/denominator convention is not supplied | pu | snapshot_region_or_edge |
| C.gSCR_external | not_comparable: source-specific fault/compensation/denominator convention is not supplied | pu | snapshot_region_or_edge |
| C.inverse_min | minimum(B\I) | pu_impedance | snapshot_region_or_edge |
| C.LOCAL | all local rank-one PSD tests pass | boolean | snapshot_region_or_edge |
| C.LOCAL_eigmin | [eigmin(B-alpha*pi*ei*ei') for each i] | pu_admittance | snapshot_region_or_edge |
| C.M0 | max(B\p)<=1/alpha, requiring PD/inverse-positive B and alpha>0 | boolean | snapshot_region_or_edge |
| C.M0_slack | 1/alpha-B\p, PD inverse-positive B, alpha>0 | dimensionless | snapshot_region_or_edge |
| C.M1 | B>=Bmin && inv(B)<=inv(Bmin) && inv(Bmin)*p<=1/alpha | boolean | snapshot_region_or_edge |
| C.M1_lower_violation | max(0,max(Bmin-B)) | pu_admittance | snapshot_region_or_edge |
| C.M1_order_violation | max(0,max(inv(B)-inv(Bmin))) | pu_impedance | snapshot_region_or_edge |
| C.M1_upper_burden | (Bmin\I)*p, enforced B>=Bmin | dimensionless | snapshot_region_or_edge |
| C.M2 | min(B*ones(n)-alpha*W*p)>=-scaled_tolerance | boolean | snapshot_region_or_edge |
| C.M2_rows | B*1-alpha*W*p | pu_admittance | snapshot_region_or_edge |
| C.MIIF | Zij/Zii with model Thevenin normalization | dimensionless | snapshot_region_or_edge |
| C.MSCR_external | not_comparable: source-specific fault/compensation/denominator convention is not supplied | pu | snapshot_region_or_edge |
| C.rho_diag | 1/(Zii*pi), positive denominator only | dimensionless | snapshot_region_or_edge |
| C.rho_Zp | 1/(B\p)i, positive denominator only | dimensionless | snapshot_region_or_edge |
| C.SCR_external | not_comparable: source-specific fault/compensation/denominator convention is not supplied | pu | snapshot_region_or_edge |
| C.solve_residual | norm(B*(B\p)-p,Inf) | pu | snapshot_region_or_edge |
| C.Wp | W_offline*p | MW_per_system_MVA | snapshot_region_or_edge |
| C.Z | B\I, only on PD sufficiently conditioned B | pu_impedance | snapshot_region_or_edge |
| C.Z_diag | diag(B\I) | pu_impedance | snapshot_region_or_edge |
| C.Zp | B\p | dimensionless | snapshot_region_or_edge |
| D.actual_error | opnorm(truncation-inv(A+Delta),Inf) | pu_impedance | snapshot_region_or_edge |
| D.E_norm_inf | opnorm(A^-1*Delta,Inf) | dimensionless | snapshot_region_or_edge |
| D.E2_conservative_rejection | estimated row burden fails while exact M0 passes | boolean | snapshot_region_or_edge |
| D.E2_false_acceptance | estimated row burden passes while exact M0 fails | boolean | snapshot_region_or_edge |
| D.exact_remainder_residual | norm(inv(A+Delta)-truncation-(-E)^(m+1)*(I+E)^-1*A^-1,Inf) | pu_impedance | snapshot_region_or_edge |
| D.one_sided_safety_certified | false: diagnostic does not enforce a one-sided planning margin | boolean | snapshot_region_or_edge |
| D.order | declared truncation order m | count_or_index | snapshot_region_or_edge |
| D.remainder_bound | norm(E)^(m+1)*norm(inv(A))/(1-norm(E)), norm(E)<1 | pu_impedance | snapshot_region_or_edge |
| D.series_converges | spectral_radius(E)<1 | boolean | snapshot_region_or_edge |
| D.spectral_radius | max(abs(eigvals(A^-1*Delta))) | dimensionless | snapshot_region_or_edge |
| D.status | exploratory_noncertifying or explicit inverse-domain failure | status | snapshot_region_or_edge |
| D.truncation | sum_{k=0}^m (-A^-1*Delta)^k * A^-1 | pu_impedance | snapshot_region_or_edge |
| D.trust_region_norm_valid | opnorm(E,Inf)<1 | boolean | snapshot_region_or_edge |
| D.woodbury_residual | norm(inv(A)-inv(A)*Delta*(I+inv(A)*Delta)^-1*inv(A)-inv(A+Delta),Inf) | pu_impedance | snapshot_region_or_edge |
| E.bounds_violation_blocks | max(0,n0-n_inst,n_inst-nmax,n_on-a_conn*n_inst,-n_on) | count_or_index | case_or_horizon |
| E.curtailment_MWh | sum(dispatch_weight*max(0,P_block*n_on*a_res-PG_MW)) | MWh | case_or_horizon |
| E.events | sum(event_repetitions*probability*P_block*(startup_price*SU+shutdown_price*SD)); no delta_t | declared_currency_per_represented_horizon | case_or_horizon |
| E.FOM | separate amount not identifiable; declared annualized price attribution retained | explicit_field_ledger | case_or_horizon |
| E.generation | sum(delta_t*repetitions*probability*marginal_price*PG_MW) | declared_currency_per_represented_horizon | case_or_horizon |
| E.integrality_residual | max abs(block/event count-round(count)), undefined in continuous relaxation | count_or_index | case_or_horizon |
| E.investment | sum(price_inv_per_MW*P_block*(n_inst-n0)*investment_fraction), once | declared_currency_per_represented_horizon | case_or_horizon |
| E.no_load | sum(dispatch_weight*declared constant generation-cost term) | declared_currency_per_represented_horizon | case_or_horizon |
| E.objective_residual | abs(reported_objective-investment-generation-storage-events-no_load) | declared_currency_per_represented_horizon | case_or_horizon |
| E.portfolio | per-asset n0,n_inst,n_new,MW,MVA,MWh,source class,carrier,region | explicit_field_ledger | case_or_horizon |
| E.power_balance_MW | max_bus_snapshot abs(outgoing flows-generation+storage net consumption+load) | MW | case_or_horizon |
| E.S_I_v1 | undefined without current capability and voltage normalization | pu | snapshot_region_or_edge |
| E.S_nom_v1 | sum_GFL mu_fl*P_block*n_inst/base | MW_per_system_MVA | snapshot_region_or_edge |
| E.S_on_v1 | sum_GFL mu_fl*P_block*n_on/base | MW_per_system_MVA | snapshot_region_or_edge |
| E.S_op_magnitude_v1 | sum_GFL mu_fl*abs(AC_discharge_or_generation-AC_charge)/base | MW_per_system_MVA | snapshot_region_or_edge |
| E.SOC_residual_MWh | max abs(E_t-E_prev-delta_t*(eta_charge*charge-discharge/eta_discharge)) | MWh | case_or_horizon |
| E.storage | sum(dispatch_weight*storage_price*AC_discharge_MW) | declared_currency_per_represented_horizon | case_or_horizon |
| E.terminal_residual_MWh | max abs(final energy-declared initial energy) | MWh | case_or_horizon |
| E.thermal_violation_MW | max(0,abs(branch flow)-rating) | MW | case_or_horizon |
| E.UC_transition_residual | max abs(n_on_t-n_on_prev-SU+SD) | count_or_index | case_or_horizon |
| F.barrier_iterations | actual runtime attribute barrier_iterations; unsupported values explicitly null | count_or_index | case_or_horizon |
| F.bound | actual runtime attribute bound; unsupported values explicitly null | declared_currency_per_represented_horizon | case_or_horizon |
| F.build_wall_s | actual runtime attribute build_wall_s; unsupported values explicitly null | s | case_or_horizon |
| F.complementarity_residual | abs(<primal cone point,dual cone point>) in scaled objective units | scaled_objective | snapshot_region_or_edge |
| F.dual_cone_violation | max PSD-dual negative eigenvalue or rotated-dual cone product/sign violation | dual_cone_coordinates | snapshot_region_or_edge |
| F.dual_status | actual runtime attribute dual_status; unsupported values explicitly null | status | case_or_horizon |
| F.model | actual JuMP variable/integer/typed-constraint counts | solver_metadata | case_or_horizon |
| F.nodes | actual runtime attribute nodes; unsupported values explicitly null | count_or_index | case_or_horizon |
| F.primal_status | actual runtime attribute primal_status; unsupported values explicitly null | status | case_or_horizon |
| F.relative_gap | actual runtime attribute relative_gap; unsupported values explicitly null | dimensionless | case_or_horizon |
| F.simplex_iterations | actual runtime attribute simplex_iterations; unsupported values explicitly null | count_or_index | case_or_horizon |
| F.solve_wall_s | actual runtime attribute solve_wall_s; unsupported values explicitly null | s | case_or_horizon |
| F.solver | actual runtime attribute solver; unsupported values explicitly null | status | case_or_horizon |
| F.solver_time_s | actual runtime attribute solver_time_s; unsupported values explicitly null | s | case_or_horizon |
| F.termination | actual runtime attribute termination; unsupported values explicitly null | status | case_or_horizon |
