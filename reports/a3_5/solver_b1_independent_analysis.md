# A3.5 B1 — vorläufige unabhängige Solver-/Bound-Analyse

Prüfziel: 485b637cc1998a327206c5929434bd26c6f0be16; Quellartefakt: reports/ap3_runs/20261020_macro/integer_bound_audit.json.

Der publizierte Datensatz enthält neun numerische Referenzdatensätze und differenzierte native Terminierungen. Die Tabellenwerte wurden unabhängig als Zahlen geparst und Breiten U-L nachgerechnet, aber die Solverzertifikate und primalen Modellzeuginnen wurden nicht reproduziert.

**Konsistenzbefund:** event_price_3snap (U-L=-6.50063157081604e-7); reference_24snap (U-L=-0.0000016596168279647827) haben eine negative nominelle Intervallbreite. Dies liegt im Bereich sehr kleiner Floating-point-Abweichungen, darf aber nicht als strenges mathematisches Lower/Upper-Intervall ausgegeben werden. Die neun Fälle bleiben numerische Referenzen, nicht rigoros zertifizierte globale Optima.

Der rohe Bericht enthält für bess_premium_3snap G3/conditioned_conic_suite: INFEASIBLE bei einem G0-OPTIMAL-Lauf. Das genügt nicht, um einen Backendfehler zu beweisen. Ein Originalmodell-Witness mit sämtlichen UC/Speicher/Netz/SOC-Variablen, exakter Fallidentität, MOI-Constraintinventar vor/nach Bridges und erfolgreich gelöstem integerfixiertem SOCP fehlt in diesem unabhängigen Audit.

Die numerische Relativ-Gap-Spalte wird nicht mit einem aus solverinternen, möglicherweise rebasierten Zielfunktionen stammenden reported_gap gleichgesetzt. Die Richtung und globale Gültigkeit der Bounds sind noch zu validieren. Die Tabelle independent_integer_bounds.csv enthält deshalb keine fälschlichen PASS-Certificates.

B1: unresolved. native_G3_MISOCP_solver=false (unqualified). Keinerlei automatische Umdeutung einer realen INFEASIBLE-Solverantwort in FEASIBLE.
