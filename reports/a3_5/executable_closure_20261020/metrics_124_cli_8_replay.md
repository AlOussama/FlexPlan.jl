# Metriken und CLI-Replay

| Datenstrom | IDs | JSON-Zeilen | geprüfte CSV-Zeilen |
|---|---:|---:|---:|
| historical | 124 | 68861 | 68861 |
| fresh | 124 | 61272 | 61272 |

Alle 124 IDs haben einen separaten Eintrag im `independent_metric_results.json`. Für mathematische/physische/wirtschaftliche Größen werden Rohdaten und Entscheidungen in Python/NumPy neu ausgewertet. G3-q aus tatsächlich gelösten Modellen sind Witness-Daten, deren Kegelprodukte, signierte Rekonstruktion und Restbudgets unabhängig geprüft werden. Eigenvektoren werden über ihren Unterraum statt ihr Vorzeichen verglichen. Laufzeit-/Solverattribute sind Exportkonsistenzchecks; keine unabhängig erneute Messung historischer Zeiten. Ein Metrik-Wert mit Status unzulässig, undefiniert oder fehlend wird nicht in einen PASS der physikalischen Domäne umgedeutet.

Die acht echten CLI-Aktionen sind `run_formulation_suite`, `reconstruct_strength_matrices`, `evaluate_strength_metrics`, `verify_certificates`, `compare_formulations`, `assess_planning_results`, `benchmark_conic_scaling`, `export_paper_a_evidence`. Frische Ausgabepfade, tatsächliche Argumente und Prozesscodes stehen in `execution.json` und im Reproduktionsmanifest. Exit 0 der Suite bedeutet nicht, dass jeder Solverlauf optimal ist: {'optimal': 108, 'infeasible': 36, 'numerical_inconclusive': 18}.

Die Exportkorrektur betrifft ausschließlich die Einheit von `A.connection_violation`, `B.G3_edges_complete`, `B.G3_valid`. 4/4 fokussierte Tests bestanden. Der erneute vollständige Metrikexport am Fix-SHA wird zeilenweise gegen den Originalexport geprüft; einzig diese Einheiten und die provenance-bedingte AP3_SHA dürfen sich ändern. Originale bleiben erhalten. Alle negativen CLI-Prozesse (unbekannte Aktion, fehlende Eingabe, bestehender Output) müssen ungleich 0 enden.
