# p_max_pu-adjusted strength recomputation

- Recomputed post-hoc strength metrics from `online_schedule.csv` and `case.json` as a second evaluation option.
- Original non-availability-adjusted strength outputs were not overwritten.
- GFL exposure uses `p_block_max * na_block * p_block_max_pu`.
- GFM strength uses `b_block * na_block * p_block_max_pu`.
- `p_block_max_pu` falls back to `p_max_pu`, then `1.0` if unavailable.
- Eigenvalue metric remains `lambda_min^fin(B_t,S_t)` with `B_t = B0 + diag(Delta b_t)` and `S_t = diag(P_GFL_t)`.
- Common paper threshold: alpha = 1.5.
