# AP1 parameter qualification consumer annex — 2026-10-20

Binding numerical authority: [producer annex](https://github.com/AlOussama/PyPSA2MatpowerX/blob/3b8fdb01d931225edc5f8fe1e2c200d0da288a09/docs/paper_a/parameter_qualification/parameter_qualification_annex.md), registry ID `paper_a_strang_b_v1`, version `paper_a_parameter_qualification/1.0`. Producer registry anchor **3b8fdb01d931225edc5f8fe1e2c200d0da288a09**. Registry SHA256 `a249f7a96d202798c6ff5778c1fa1571eba59a3717bac5d25b150d2a6c41bce9`; scenario SHA256 `be9d9d9aa90e9790fc7c3554bc1107777a5ba743f4f95d8f675acd9bfeb1e75a`. No second numerical parameter table is maintained here.

Use the producer's canonical files, verify their bytes, call `register_paper_a_parameters!` on the parsed object, then select template scope `:parametric_study`. Selected scenario rows are compared with actual device fields, resource profiles, costs, weights and investment fraction; the comparison is repeated at model construction. Strict and synthetic scopes reject the parametric annex. Registration is local to the data object and cannot relax another case's gates. Empirical gates and historical synthetic permission are unchanged.

The existing annualized CAPEX scaler is reused with the explicitly registered horizon fraction. Dispatch and event weights remain separate; SOC uses physical duration only. Existing physical source/base checks and integer bounds remain active. Conditional no-additional-shunt/no-embedded-source/floating-network assumptions permit only the registered diagnostic domain; hard passive network defects fail. The theorem-domain flag remains false.

Reproduce with Julia 1.10.11 and `Manifest-v1.10.toml`:

```powershell
julia +1.10.11 --startup-file=no --project=. test/run_paper_a_parameter_acceptance.jl D:/Projekte/Code/pypsatomatpowerx reports/strang_b/parametric_acceptance.json
julia +1.10.11 --startup-file=no --project=. test/run_paper_a_parameter_network_audit.jl D:/Projekte/Code/pypsatomatpowerx reports/strang_b/network_audit.json
julia +1.10.11 --startup-file=no --project=. test/run_paper_a_ap1_acceptance.jl D:/Projekte/Code/pypsatomatpowerx/data reports/strang_b/historical_producer_solver.json
julia +1.10.11 --startup-file=no --project=. test/run_paper_a_ap2.jl
julia +1.10.11 --startup-file=no --project=. test/runtests.jl
```

`reports/strang_b/parametric_acceptance.json` separates actual MILP/LP termination, objective components, power/SOC/terminal/source/exposure/B0/G1 residuals, count/connection violations and case/registry/scenario hashes. `reports/strang_b/validation.md` records actual executions and limitations. Original AP2 reports and negative producer integer cases remain unchanged. G1 and regional expressions are reused; AP3 G0/G3/M0 are not implemented here. AP3 may consume the annex-qualified inputs only under the same explicit scope; A3/AP4 and empirical approval remain open.
