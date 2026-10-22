# Versuche, Fehler und bewusst getrennte Ergebnisse

Alle Rohlogs bleiben erhalten. Folgende Exitcodes sind echte Prozessbefunde, keine umetikettierten PASS-Meldungen. Vollständige erfolgreiche Operationsdaten stehen in `operations.json`.

| Operation | Exit | Einordnung |
|---|---:|---|
| cli_negative_existing_output | 1 | Erwartete negative CLI-Eingabe, korrekt Exit1. |
| cli_negative_missing_input | 1 | Erwartete negative CLI-Eingabe, korrekt Exit1. |
| cli_negative_unknown_action | 1 | Erwartete negative CLI-Eingabe, korrekt Exit1. |
| cli_raw_oracle | 1 | Vollständiger alter Treiber: sympy fehlt; begrenzte NumPy-Wertprüfung anschließend separat bestanden. |
| controlled_seed_unit | 1 | Temporäre Kopie hatte die zu entfernende Bridge nicht registriert; Korrektur ausschließlich im Startworkflow, finaler Lauf bestanden. |
| exact_bridge_unit | 1 | Gurobi error10020: affine Nichtnegativitätszeilen reichen dem Convexitydetektor nicht; anschließend exakt bewiesene redundante Variablebounds ergänzt. |
| final_backend_oracle_early | 1 | Prüfer erkannte die vorhandene Intervall-SlackBridge noch nicht; Nachweis erweitert, Solver unverändert. |
| final_cli_negative_existing_output | 1 | Erwartete negative CLI-Eingabe, korrekt Exit1. |
| final_cli_negative_missing_input | 1 | Erwartete negative CLI-Eingabe, korrekt Exit1. |
| final_cli_negative_unknown_action | 1 | Erwartete negative CLI-Eingabe, korrekt Exit1. |
| fresh_18_objectives | 1 | Relativer Repopfad wurde vom alten Include relativ zum Skript interpretiert; mit absolutem Pfad wiederholt. |
| fresh_27_models | 1 | Relativer Repopfad wurde vom alten Include relativ zum Skript interpretiert; mit absolutem Pfad wiederholt. |
| native_matrix_first | 1 | Julia-Docstring stand vor using; technischer Treiber repariert. |
| native_unit_first | 1 | Guard für nichtendliche skalierte Konstante und affine Behandlung variabler Objective ergänzt. |

MOSEK-Matrizen mit zwei bzw. drei TIME_LIMITs, direkte exakte Gurobi-Quadratik ohne Start mit TIME_LIMIT, raw Gurobi/MOSEK-Boundwidersprüche und Pajarito-ITERATION_LIMIT sind numerische Ergebnisse bei teilweise erfolgreichem Prozess-Exit0. Sie stehen ausdrücklich in den jeweiligen JSON-Ergebnissen und sind kein wissenschaftliches PASS.

Die erste Preflight-Probe enthielt einen Julia-Parsefehler; der unveränderte Preflight hält Fehlversuch und Korrektur fest. Ein ergänzender Summarytreiber hatte einen fehlenden optionalen Literalmodell-Hashschlüssel; er wurde vor Publikation korrigiert, ohne Solvercode oder Resultate anzupassen.
