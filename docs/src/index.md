# FlexPlan UC/gSCR Block-Expansion Documentation

```@meta
CurrentModule = FlexPlan
```

## Overview

This repository extends [FlexPlan.jl](https://github.com/Electa-Git/FlexPlan.jl) with a block-based generator/storage expansion model and full-network gSCR/ESCR security constraints, following FlexPlan/PowerModels architecture conventions.

Key design decisions:

- The full original network is used. No Kron-reduced network is introduced.
- The operational commitment variable is `na` (mathematically \(n_{a,k,t}\)) — the number of active/online blocks of device \(k\) at time period or scenario \(t\).
- Device type (`"gfl"` or `"gfm"`) is data, not a model choice.
- First implementation uses `relax = true` (continuous \(n_a\)); integer block commitment follows via `relax = false`.
- Two gSCR variants are documented and implemented:
  - global full-network SDP/LMI;
  - linear Gershgorin sufficient condition (LP/MILP-compatible; conservative upper bound on the SDP/LMI).

For the full design rationale, start with:

```text
docs/project_start/START_HERE.md
```

## Base package

FlexPlan.jl is a Julia/JuMP package to carry out transmission and distribution network planning considering AC and DC technology, storage and demand flexibility as possible expansion candidates.
The base package builds upon [PowerModels](https://github.com/lanl-ansi/PowerModels.jl) and [PowerModelsACDC](https://github.com/Electa-Git/PowerModelsACDC.jl).

## Acknowledgements

The original FlexPlan.jl package was developed as part of the European Union's Horizon 2020 research and innovation programme under the FlexPlan project (grant agreement no. 863819).

Original developers:

- Hakan Ergun (KU Leuven / EnergyVille)
- Matteo Rossini (RSE)
- Marco Rossi (RSE)
- Damien Lepage (N-Side)
- Iver Bakken Sperstad (SINTEF)
- Espen Flo Bødal (SINTEF)
- Merkebu Zenebe Degefa (SINTEF)
- Reinhilde D'Hulst (VITO / EnergyVille)

The developers thank Carleton Coffrin (Los Alamos National Laboratory) for his countless design tips.

## Citing FlexPlan.jl

If you use the base FlexPlan.jl functionality, please cite the following [publication](https://doi.org/10.1109/osmses58477.2023.10089624) ([preprint](https://doi.org/10.5281/zenodo.7705908)):

```bibtex
@inproceedings{FlexPlan.jl,
    author = {Matteo Rossini and Hakan Ergun and Marco Rossi},
    title = {{FlexPlan}.jl – An open-source {Julia} tool for holistic transmission and distribution grid planning},
    booktitle = {2023 Open Source Modelling and Simulation of Energy Systems ({OSMSES})},
    year = {2023},
    month = {mar},
    publisher = {{IEEE}},
    doi = {10.1109/osmses58477.2023.10089624},
    url = {https://doi.org/10.1109/osmses58477.2023.10089624}
}
```

## License

This code is provided under a [BSD 3-Clause License](https://github.com/AlOussama/FlexPlan.jl/blob/master/LICENSE.md).
