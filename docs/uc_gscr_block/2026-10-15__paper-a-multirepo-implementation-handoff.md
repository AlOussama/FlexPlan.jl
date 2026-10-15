# Paper A — FlexPlan implementation handoff, frozen 2026-10-15

Canonical execution freeze: https://github.com/AlOussama/research-map/blob/main/docs/reports/C2_constraints/C2A_voltage_stability/publication_planning/2026-10-15__paper-a-multirepo-execution-freeze-v2.md

Science: research-map paper/c2a-system-strength-expansion-planning-v1 @ 672a61c95525bf1d7a03cf745a754a15a23ce78b
A3 audit: research-map audit/paper-a-a3-implementation-v1 @ a2193ee2312c75d4e123f446156e50df5dabdbc7 (implementation_corrections_still_required; A4_ready=false)
Implementation baseline: FlexPlan.jl master @ 189eec9941dde8ab8720d570a2a6442e2ff1aa6f
Data baseline: PyPSA2MatpowerX gsc-data-format @ cc436ddd56bbc6a5b3655059360e4ed0f284732a

**Status:** plan reference only; no A3 closure; A4_ready=false. This is not a code change.

Retain existing schema-v2 parsing, device templates, n_inst/n_on, dispatch and storage bounds, G1 Gershgorin and existing PyPSA acceptance tests. First run schema-v2 producer fixtures base_s_5_{3,6,24}snap from the pinned converter with case hashes and runtime logs; 24 snapshots span 72 hours at 3h intervals. Reconcile scale_data! annualization with Paper-A effective operating weights; never blindly multiply operation_weight=1 or double-annualize already annualized CAPEX. Work with data producer to represent retained-region Schur strength B0, normalized mu/source classes, technical connection availability, physically distinct SYN/SC/GFM sources and validated BESS power+energy cost. Add G0 PSD and independent finite generalized spectrum, G3 complete edge-SOC and a matrix-class/test harness with PSD-SOC objective/cross-feasibility equivalence; retain G1. Independently recompute M0 where B invertible, resource exposure, costs and residuals. No A4 unless all A3 and economic data gates pass. Every A4 run pins science/converter/FlexPlan SHA, source and case hashes, solver and diagnostics. Use one minimal correction branch and preserve historical tests. See canonical freeze for X01–X12 contracts, MR01–MR11 issues, H1–H4 study design, A3–A7 exit criteria.
