# AP2 regional optimization — partial implementation record
Date: 2026-10-19
Status: AP2_partial; scientific and optimization acceptance NOT established.

## Reproducible baseline and scope
- FlexPlan master: 991d0e99627b9bd57b3df476c66141ae6bb5163d.
- AP1 producer contract read at: 00b259da66f084e00d53c5dc1be4d23de145fdc1.
- Frozen science: research-map 672a61c95525bf1d7a03cf745a754a15a23ce78b.
- A3-MR audit: research-map 8b78fc2d0aa22012ce75b70c0cff08d7336ebe75.
- Branch: implementation/paper-a-ap2-regional-optimization-v1.
- Existing FlexPlan ref_extension, block_variable, block_template, constraint_template, objective and integrated builder unchanged by this partial contribution.

## Added standalone, not-yet-wired source
`src/core/paper_a_regional.jl` is a self-contained pure-Julia module; no code path of `uc_gscr_block_integration` invokes it yet.
- PA-NET-REGRED: `reduced_strength` evaluates B0 = Lrr - Lre*(Lee\\Ler) on an **already validated positive-sequence passive** L. It does not independently construct Y from AP1 branch primitives; it cannot independently audit shunt signs or grounding.
- PA-SRC-NORM: `source_b_block` implements S_block/(S_base*x_src) on an explicit assumed native source MVA base. Actual native base conversions/time-scale validity are outstanding.
- PA-SRC-AUG, PA-REG-MULT: `regional_strength` adds fixed and decision-dependent diagonal strength after passive reduction, with fixed multipliers. No automatic AP1 fixed-source inventory reconciliation is wired.
- PA-EXP-MATRIX: `online_exposure` implements regional GFL nameplate pu exposure; no JuMP expression integration yet.
- PA-EXP-ON: `assert_connection` validates bounds of numeric examples, not an optimization constraint. GFL resource availability and physical connection must later enter separate solver inequalities.
- X06: `dispatch_event_weights` derives physically distinct scalar weights; existing FlexPlan objective is still unchanged.
- X04: `validate_source` explicitly rejects mismatched SYN/GFM converter modes, unknown equivalents, and unsupported SC.

## Unimplemented required AP2 obligations
- AP1 versioned parser and on-the-wire schema migration.
- Physical positive-sequence branch primitive Y builder including phase/tap, fixed shunts, islands and grounding predicates.
- Integrating source/exposure references and availability bounds into resolved template and JuMP model.
- Cost scaling migration to dispatch_weight/event_weight, CAPEX and storage SOC audit.
- Consumer solve fixtures, legacy regression, Julia validation and AP1 fixture reconciliation.
- Source native parameter-base validation and SC MVA/Mvar cost treatment.

Do not present any standalone algebraic unit test as integrated optimization acceptance.
