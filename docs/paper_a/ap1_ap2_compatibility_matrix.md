# AP1 1.0 → AP2 producer/consumer compatibility matrix

Producer authority: `32ff4525dc576af52c16298cb35ebd98f02cf8b2`. `case` means the multinetwork root; `sn` means `case.nw[t]`; `device` means sn.gen/storage/ne_storage[id]. Tests: P = `test/paper_a_integration.jl`; F = `test/run_paper_a_ap1_acceptance.jl`; R = `test/paper_a_producer_gate.jl`; L = retained legacy test suites. Outcomes are backed by the current validation report and raw logs; real-study approval is separate.

| Producer field/location | Unit/base | Reader and model use | Validation | PA/X and test |
|---|---|---|---|---|
| case/sn.paper_a_extension | versioned metadata | `_paper_a_validate_markers` selects opt-in consumer | exact name/version/required flag, root/snapshot agreement, no unversioned fallback | X01/X02; P/R/F |
| case/sn.block_model_schema | uc_gscr_block/2.0 | existing ref schema validator | historical absence of AP1 retains legacy semantics | X01; L/P |
| case/sn.baseMVA | MVA system base | `prepare_paper_a_data!`, `network_reference` | positive finite, snapshot/native consistency, one MW/pu conversion | PA-SRC-NORM; P/F/R (100/200/250 bases) |
| device.p_block_max, q_block_min/max, e_block, s_block | MW/Mvar/MWh/MVA before parsing, system pu after | existing `_rescale_uc_gscr_block_fields!`; dispatch and storage envelopes | once-only units marker, MW/pu identity | X04/X08/X09; P/F |
| device.p_block_max_MW | physical MW, never rescaled | investment/event coefficients and GFL exposure | compare to parsed p_block_max*Sbase | PA-EXP-ON; P/F/R |
| device.S_block_MVA/S_base_MVA | apparent block rating/system MVA | source normalization | required positive source rating; source/system base equality | PA-SRC-NORM; P/F |
| device.native_parameter_base/native_source_MVA | native base name/numerical MVA | `validate_source` | block/source/device bases only, actual native number required | PA-SRC-NORM; P/F |
| device.x_src/x_src_block_base | pu reactance on native/block bases | independent x_block=x_native*Sblock/Snative then b | positive finite, exported x_block consistency | PA-SRC-NORM; P/F |
| device.b_block | normalized pu susceptance | affine online source coefficient | compare native-base formula; never divide again by Sbase | PA-SRC-AUG; P/F |
| device.source_b_block_pu_reference | independent normalized reference | comparison only | match independently calculated b | X04; P/F/R |
| device.source_b_normalization_abs_error | producer diagnostic | retained diagnostic, not an input coefficient | consumer computes its own normalization; null not zero | X04; R/F |
| device.source_class | GFL/GFM/SYN/SC | physical incidence and coefficient maps | explicit enum; SYN own map; SC explicit unsupported case | PA-REG-COEXIST; P/F/R |
| device.grid_control_mode | gfl/gfm/not_applicable | class/mode validation | converters strict, SYN/SC not_applicable only under extension | X04; P/F/R |
| device.carrier | technology label | existing `(table,carrier)` matching and device override | no inferred formulation, unresolved template fails | X01; L/P/F |
| source_class_evidence, electrical_interface_evidence | provenance strings | `validate_source` | strict scope rejects unverified; explicit synthetic fixture scope treats declared classes as mathematical inputs only | X04; P/F/R |
| source_equivalent_type/valid/time_scale/provenance | physical source declaration | source equivalent guard | no class-to-x inference; valid voltage-behind-reactance and native/time evidence required | PA-SRC-NORM; P/F/R |
| device.mu_str/mu_fl | fixed dimensionless multipliers | strength/exposure affine expressions | relevant factor required finite nonnegative; no default 1 | PA-REG-MULT; P/F/R |
| device.fixed_strength_already_in_network | source ownership Bool | additional coefficient is zero if fixed in Y | explicit flag, no online double count | PA-SRC-NODOUBLE; P/R |
| fixed_source_permanently_connected + network.fixed_source_shunt_by_asset | connection/bus/pu shunt | fixed-in-Y reference accounting | unique actual shunt binding, fixed online template, no duplicate b_fix | PA-SRC-NODOUBLE; P |
| device.region_id/source_bus_name; physical bus.name | stable IDs | source/region incidence | device bus retained, matching bus_to_region, no eliminated source | X03/X04; P/F/R |
| device.n0/nmax/na0 | integer physical counts | existing installed/online and UC count variables | 0<=na0<=n0<=nmax; shared assets stable across snapshots | X08; L/P/F |
| investment_data_status/unpriced_requested_nmax/maximum_bound_policy | producer eligibility diagnostics | preserve exported nmax, never restore requested unpriced expansion | positive price for expansion; blocked_missing_cost cannot expand | X07/X08; P/R |
| a_conn/a_conn_provenance | technical fraction in [0,1] | na<=a_conn*n; binary fixed-installed equality | no rounding; fractional availability explicit integer/LP comparison | PA-EXP-ON; P/F |
| a_res/p_max_pu/p_min_pu | resource/dispatch fractions | renewable and thermal dispatch envelopes | resource independent of connection; GFL nameplate does not follow pg | X05; P/F |
| case.paper_a_network.branch_primitives | ohm/siemens/kV and common pu | independent passive Y assembly | units/bases/endpoints, inductive line, no unsupported transformer/tap/phase/DC | PA-NET-ADM; P/F/R |
| physical_ac_bus_order, retained/eliminated, bus_to_region | stable physical/regional order | L partition and Schur solve | full disjoint partition, unique retained region, passive eliminated nodes | PA-NET-REGRED; P/F/R |
| fixed_shunts | gs/bs system pu | one Y diagonal addition per physical shunt | inventory flags and physical sign; slack adds no grounding | PA-NET-DOMAIN; P/F/R |
| network_islands/reference_buses/passive_domain_issues | topology/inventory observations | independent components/reference/domain checks | strict scope rejects unresolved inventory; synthetic scope only permits unresolved study grounding with explicit mathematical classification | PA-NET-DOMAIN; P/F/R |
| Y_real/Y_imag/L/B0_reference/elimination_performed/schur residual | independent matrices/diagnostics | consumer reconstructs Y/L/B0 and reports differences | no reference matrix as authoritative coefficient; no inverse/regularization | X03; P/F/R |
| case.paper_a_temporal.delta_t_h/time_elapsed | physical hours | storage states and dispatch weight | positive duration equality; SOC never annual-frequency weighted | X06/X09; P/F/R |
| representative_repetitions/scenario_probability/event_repetitions | sampling factors/probability | separate dispatch/event weights | finite nonnegative, probability [0,1], scenario dimension consistency | X06; P/F/R |
| dispatch_weight/event_weight | weighted hours/event repetitions | existing integrated objective | recompute identities, scale exactly once; applied-factor guard | X06/X07; P/F |
| gen.model/ncost/cost | raw linear currency/MWh polynomial | PM power scaling, then dispatch weight | preserve nonzero marginal cost, model=2 and zero constant in bounded AP1 path | X06/X07; P/F |
| startup_cost_per_mw/shutdown_cost_per_mw | currency per physical MW per block event | existing su/sd count objective with separate event factor | nonnegative, transitions 1→4/5→2 count 3 | X06; P/F |
| cost_inv_per_mw/capex_basis | annualized or overnight currency/MW | existing CAPEX branch, physical block MW once | annualized no new annuity; overnight annuity/FOM once | X07; P/F/R |
| storage energy/efficiencies/time_elapsed | MWh/fractions/h before pu parsing | existing initial/intertemporal SOC equations | initial/terminal policy explicit, both efficiencies, 3h residual | X09; P/F |
| pypsa_cyclic_state_of_charge/storage_boundary_scope | source metadata | preserved; caller selects builder terminal policy | no automatic sliced-window cyclic assertion | X09; F and documentation |
| storage.marginal_cost | raw currency/MWh of declared billed movement | `storage_cost_policy=:discharge` bills AC-side sd only | nonzero cost rejected without explicit template policy; no charge/throughput double billing | X07/X09; P/F |
| ledger/candidate/case manifests | IDs, residuals, hashes | pinned external acceptance/provenance | exact case SHA256, independent B0, eligibility and scientific flags retained | X01/X11/X12; R/F |

Unsupported cases and consequences: dedicated SC MVA/Mvar investment, unvalidated transformer conversion, raw operational links without dcline conversion, multiple planning years in the bounded AP1 cost path, negative or undeclared storage movement pricing. They do not silently become zero-cost or legacy-model cases.

Synthetic scope is an explicit `UCGSCRBlockTemplate` option and is refused for any case not marked `dataset_kind=synthetic_regression_only`. It does not alter source evidence or producer domain flags. Matrix `symmetric_z_valid` and unresolved `passive_domain_issues` are exposed separately from study validity. Positive LP and integer-infeasibility producer results are reported separately; no hidden relaxation occurs.
