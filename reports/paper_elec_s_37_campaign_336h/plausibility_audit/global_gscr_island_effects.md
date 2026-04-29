# Global gSCR Island Effects

The reconstructed AC branch graph contains 7 connected AC islands. The reconstructed Bnet Laplacian has 7 eigenvalues with abs(lambda) <= 1.0e-8. For a pure disconnected Laplacian this is the expected one zero mode per connected island.

A full-system eigenvalue can therefore be affected by island zero modes. Global gSCR should be reported either as the minimum over electrically connected islands with positive GFL exposure or as per-island distributions. Islands without GFL exposure should not define a finite GFL-driven gSCR violation.

The saved `posthoc_strength_timeseries.csv` reports finite `gSCR_t`, `mu_t`, and node violation fields, so it appears to apply a finite-mode convention rather than simply returning the zero Laplacian mode. This audit still flags the metric for careful wording because the exact generalized-eigenvalue implementation is not present in the run artifact.

For gSCR-GERSH-1.5, the local aggregate LHS/RHS diagnostic has max utilization 1.0000000000000002. BASE has widespread local alpha=1.5 violations in the reconstructed local ratio diagnostic.
