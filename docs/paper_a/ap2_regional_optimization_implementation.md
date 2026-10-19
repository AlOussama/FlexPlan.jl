# Paper A AP2: regional optimization consumer

Specification: `SPECIFICATION_READY`. Overall acceptance remains `AP2_partial` until the external AP1 interface/data gates recorded in the validation report are accepted. This document describes the implemented consumer, not a real-study approval.

## Authority and reuse

Science freeze: research-map `672a61c95525bf1d7a03cf745a754a15a23ce78b`; integration audit: `8b78fc2d0aa22012ce75b70c0cff08d7336ebe75`. FlexPlan master baseline: `991d0e99627b9bd57b3df476c66141ae6bb5163d`. AP2 starting commit: `a80c3514dd08b21caa0388918099d5771c42c426`. AP1 read-only entry: `991c34445f602df14592fdd0f51b5e67d3ddd782` (advanced from the assignment's `00b259da66f084e00d53c5dc1be4d23de145fdc1`). AP1 publication/addendum reconciliation: `32ff4525dc576af52c16298cb35ebd98f02cf8b2`, with six committed case/manifests checked by content SHA256. End reconciliation is in `reports/ap2_macro/provenance.json`.

Reuse: existing compound `(table,id)` keys, device-over-carrier template matching, installed/online/integer/relaxed block variables, UC transition counts, dispatch envelopes, storage state/terminal equations, and CAPEX annuity/FOM branch. No schema-v2 fallback template was added. SYN gets a separate physical source map; it is never converted to a GFM converter.

`REUSE_REJECTED: -PowerModels.calc_basic_susceptance_matrix as Paper-A B0 — operational DC susceptance omits the general physical positive-sequence/shunt/reduction contract.` The old path remains the historical schema-v2 diagnostic.

## Executable path

1. `parse_file(case.json)` recognizes `scientific_physical_data/1.0`, or a caller loads a Dict and calls `prepare_paper_a_data!`. Root/snapshot markers must agree; unversioned physical inputs fail closed.
2. `prepare_paper_a_data!` converts PowerModels physical powers/cost polynomial and FlexPlan block P/Q/E once. `p_block_max_MW`, native MVA/reactance, physical network primitives and normalized `b_block` stay physical/reference inputs. Already-pu inputs require `paper_a_block_units="pu_system"`.
3. `scale_paper_a_costs!` accepts a single/multinetwork AP1 case. Alternatively `scale_data!` accepts an AP1 single network with its explicit temporal record and delegates to the same cost implementation. Both paths mark applied dispatch/event weights and CAPEX conversion; repeated scaling is rejected. No 8760/N factor is inferred for AP1.
4. Add the existing hour/scenario/year dimensions if the producer JSON has none. Provide an explicit `UCGSCRBlockTemplate`, including a `(:storage,"BESS-GFM")` carrier assignment or an exact device override for a genuine BESS candidate. The optimizer never infers policy from a source class.
5. `uc_gscr_block_integration` invokes `ref_add_uc_gscr_block!`, template resolution, the existing block variables/constraints, regional expressions, G1 and the objective. AP1 defaults to integer blocks; `relax_block_variables=true` explicitly selects the LP relaxation. Historical schema-v2 retains its previous default.

The AP1 operational model supports PowerModels DCP with fixed topology and ordinary dclines. It creates voltage angles, reference constraints, branch Ohm/angle/thermal constraints and nodal balances. Candidate storage enters those balances. Raw unconverted links, switches and unsupported operational models are rejected. Operational DC equations remain separate from the positive-sequence strength matrix.

## Equation to code traceability

| Claim / interface | Frozen equation | Code location |
|---|---|---|
| PA-NET-ADM, X02/X03 | Y from physical branch r/x, charging and fixed shunts; L=-Im(Y) | `src/core/paper_a_regional.jl:network_reference` |
| PA-NET-REGRED | B0=Lrr-Lre*(Lee\Ler), or Lrr when e is empty | `paper_a_regional.jl:reduced_strength`, `network_reference`; `ref_extension.jl:ref_add_uc_gscr_block!` |
| PA-SRC-NORM, X04 | x_block=x_native*S_block/native_MVA; b=S_block/(Sbase*x_block) | `paper_a_regional.jl:validate_source`, `source_b_block` |
| PA-SRC-AUG, PA-REG-MULT | b_src=b_fix+sum(mu_str*b_block*n_on); B=B0+diag(b_src) | `src/core/paper_a_integration.jl:_paper_a_add_reference!`, `_paper_a_online_expressions!` |
| PA-SRC-NODOUBLE | fixed-in-Y source adds no online diagonal | `validate_source`, `_paper_a_add_reference!`, fixed-installed template guard |
| PA-EXP-ON/MATRIX, X05 | p_fl=sum(mu_fl*P_MW/Sbase*n_on); S=diag(p_fl) | `_paper_a_add_reference!`, `_paper_a_online_expressions!` |
| X05/X08 | n0<=n_inst<=nmax; n_on<=a_conn*n_inst | `src/core/block_variable.jl:variable_installed_blocks`, `constraint_active_blocks_le_installed` |
| X05 | p_RE<=a_res*p_block*n_on | `src/core/constraint_template.jl:constraint_uc_gscr_block_active_dispatch_bounds` |
| PA-G1 | B0ii-sum(abs(B0ij))+b_src>=g_min*p_fl | `paper_a_integration.jl:_paper_a_g1!`, called by the existing constraint template |
| X06/X07 | investment once; dispatch dt*r_dispatch*pi; events r_event*pi | `scale_paper_a_costs!`, `src/core/objective.jl:calc_uc_gscr_block_investment_cost`, `calc_uc_gscr_block_startup_shutdown_cost`; integrated objective |
| X09 | e_t=(1-loss)^dt*e_prev+dt*(eta_c*sc-sd/eta_d+inflow-outflow) | existing `src/core/storage.jl` state methods and builder terminal policies |

All data/matrices are in the reference layer. Affine JuMP objects exist only in `pm.ext[:paper_a_online][nw]` after block variables are created. Producer B0 is used only to record an independent numerical comparison; it never supplies model coefficients.

## Bounded accepted and rejected models

Accepted: symmetric inductive unit-tap AC line primitives with explicit physical/pu base identities; signed charging and physical bus shunts; verified producer inventory/grounding/source-accounting observations; distinct retained regions; explicit passive elimination with invertible Lee; multiple GFL/SYN/GFM devices in one region; block/source/device native MVA normalization; documented permanently connected fixed sources bound to a unique actual Y shunt; separate exogenous nonnegative mu factors.

An empty `passive_domain_issues` list is required evidence of the producer's inventory/grounding checks. AP2 still computes islands, reference coverage, symmetry, Z signs and reduction itself. It adds no slack-bus grounding. A floating passive island with valid retained reference/reduction is represented as such, without artificial diagonal regularization. These are input-domain checks, not external approval of physical parameters.

Rejected: transformer primitives pending a validated native transformer conversion, nonunit tap/phase/asymmetry, unknown AC endpoints, DC primitives in Y, contradictory bases, singular Lee, source-bearing eliminated nodes, missing/unverified class/interface/equivalent/time-scale/provenance, absent relevant mu, unsupported SC economics/MVA/Mvar representation, fixed-source double counting, nonzero storage marginal cost without a declared bidirectional rule. Missing real data stays missing.

`BlockFixedInstalled` on AP1 follows technical connection for binary a_conn: n_on=a_conn*n_inst. Fractional a_conn with that template is explicitly unsupported; a participation template keeps the exact inequality and lets integer constraints determine feasible counts without rounding input. Renewable GFL dispatch respects a_res even with a fixed-installed policy.

Investment/event costs multiply physical MW; dispatch polynomials are already converted once by PowerModels to currency per pu-hour. Annualized CAPEX receives no new annuity. Overnight CAPEX uses the existing annuity plus FOM once. Representative dispatch/event factors include probability once in this integrated objective. SOC uses physical duration only. The bounded AP1 cost path represents one planning year; it does not infer an annual study sampling scheme.

## Verification and external gates

Run `test/run_paper_a_ap2.jl` for grouped deterministic AP2 tests or `test/runtests.jl` for the complete repository suite. The new tests are included in the full suite. `test/paper_a_producer_gate.jl` separately records actual external cases as BLOCKED or NOT_EXECUTED when their prerequisites do not support a consumer solve. Complete commands, attempts, numerical evidence and versions are in `reports/paper_a_ap2_validation.md` and `reports/ap2_macro/`.

No G0, G3, M0, generalized spectrum, screening, TNEP or dynamic controller was implemented. No AP3/AP4 or real economic study acceptance follows from synthetic G1 solves.
