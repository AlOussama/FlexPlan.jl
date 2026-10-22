# Reproduktion — vorhandener Checkout, ausschließlich neue externe Ausgabeordner

Produktionsrevision `f302b7b63e917678fb14b7cbc3cfdbc0d8c624a1`, separate Oracle-/Evidenzrevision `6b6bcd8b0f00caa3a7ee7d7e89fe1085596bd7fc`. Der publizierte Branch enthält beide unverändert; der endgültige Remote-SHA steht im additiven Publikationsbeleg. Keine automatische Ausführung eines Checkout-/Reset-/Mergebefehls. Vorher fremde Dateien inventarisieren und Schreibpfade prüfen. Das 28-Dateien-Inventar ist nur für den bestehenden Checkout eine autorisierte Ausnahme, keine allgemeine Dirty-Checkout-Freigabe.

## Laufzeit

Windows, Julia 1.10.11, JuMP 1.31.1, MathOptInterface 1.51.2, Pajarito 0.8.3, HiGHS.jl 1.24.1 / native 1.15.1, Clarabel 0.11.1, Gurobi.jl 1.9.2 / native 12.0.3, Mosek.jl 11.0.1, MosekTools 0.15.10 / native 11.0.29. Python 3 mit NumPy, Standardbibliothek einschließlich Fraction/tomllib. Verwendeter Pythonpfad: `C:/Users/User/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.

Das bestehende Manifest installieren, nicht aktualisieren. Die zwei Mosek-Pakete sind exakt gepinnt. Für eine andere vorhandene Installation den tatsächlichen Librarypfad und Lizenznutzbarkeit erneut prüfen; keine Lizenzdatei modifizieren. Auf diesem Rechner wurde Mosek mit prozesslokalem `MOSEKBINDIR=C:/Program Files/Mosek/11.0/tools/platform/win64x86/bin` gebaut. Gurobi.jl benutzt die vorhandene lokale 12.0.3-DLL. Für einen frischen Depot kann gemäß dem gepinnten `deps/build.jl` `GUROBI_JL_USE_GUROBI_JLL=false` zusammen mit `GUROBI_HOME=C:/gurobi1203/win64` und `Pkg.build("Gurobi")` erforderlich sein. Tatsächlich geladene Bibliothek/version danach erneut prüfen; JLL-Metadaten allein genügen nicht. Das ist eine Reproduktionsanweisung, keine hier behauptete zusätzliche Neuinstallation.

## Archivprüfung und Inputs

`verify_publication.py` prüft jede Datei dieses Reportpakets sowie jeden ZIP-Eintrag mit SHA256. Archiv zunächst vollständig prüfen, dann ausschließlich in einen neuen externen Ordner extrahieren. `reproduction_manifest.json` verzeichnet Original-/Publikationshashes und eventuelle Lizenz-ID-Maskierungen.

Die vorhandenen SHA-geprüften Inputs werden über `reports/a3_6/reaudit_20261021/run_suite.py` in dessen frischem externem Ausgabeordner nach `prior/` extrahiert. Die 406 A3.6-Witness-ZIP-Einträge und 381 EXEC-Einträge sind vollständig geprüft; der Reaudit-ZIP hat 130 vollständig geprüfte Einträge. Die Archive bleiben an ihren gepinnten vorhandenen Reportpfaden. `continuation/integrity/integrity.json` im neuen ZIP und die alten unveränderten Reproduktionsmanifeste benennen Pfade/Hashes.

## Frischer integrierter Lauf (PowerShell, Variablen an eigene neue Pfade anpassen)

```powershell
$repoPath = 'D:/Projekte/Code/FlexPlan_UC_GSCR'
$pythonExe = 'C:/Users/User/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$validationOut = 'D:/Downloads/A37_independent_NEW_validation'
$matrixOut = 'D:/Downloads/A37_independent_NEW_matrix'
Set-Location -LiteralPath $repoPath
$env:JULIA_NUM_THREADS = '1'
& $pythonExe reports/a3_6/reaudit_20261021/run_suite.py $repoPath $validationOut regression
& $pythonExe reports/a3_6/reaudit_20261021/run_suite.py $repoPath $validationOut exact
& julia +1.10.11 --startup-file=no --project=. test/paper_a_native_g3_solver.jl
& julia +1.10.11 --startup-file=no --project=. scripts/paper_a/qualify_native_g3.jl $repoPath $matrixOut "$validationOut/prior"
& $pythonExe scripts/paper_a/verify_native_g3.py $matrixOut "$validationOut/prior"
```

Jeden Exitcode unmittelbar prüfen. Der letzte Prüfer schreibt Residuen/Befunde; zusätzlich explizit prüfen, dass alle 46 Originalpunkte `numerical_pass=true`, alle 37 Backendidentitäten wahr, alle 37 Backendpunkte zulässig und alle `native_bound_contradiction=false` sind. Er ersetzt keine personell unabhängige Reviewentscheidung.

Für die 27/18 frischen Vergleichsexporte wurden die unveränderten A3.6-Skripte `model_inclusion.jl` und `objective_snapshots.jl` mit **absolutem** Repoargument aufgerufen; anschließend `compare_fresh.py`. Die tatsächlichen vollständigen Befehle, Argumentreihenfolgen, Exitcodes, UTC-Zeiten und Source-SHA-Manifeste sind in `operations.json` und `continuation/operations/*/command.json` im ZIP enthalten. Sie sind verbindlicher als abgekürzte Beispielbefehle.

## Diagnosen, CLI, Fehler und übrige Tests

Die archivierten technischen Treiber enthalten ihre absoluten Scratchpfade; für erneute Läufe diese auf neue Ausgabeordner ändern, keine alten Resultate überschreiben. `candidate_diagnostics.jl` prüft echte Integer-RSOC-Capabilities und Originalmodell-Solves mit Gurobi/MOSEK; `analyze_candidates.py` prüft Originalidentität und exakte Zeugen. `filter_regressions.jl`, `pajarito_gap_diagnosis.jl`, `pajarito_double_gap.jl`, `backend_negative_controls.py` und `summarize_final.py` enthalten die gezielten positiven/negativen Nachweise.

`run_final_cli_contract.py` ruft alle acht echten bestehenden CLI-Aktionen auf einem registrierten 3-Snapshot-Fall mit allen neun Formulierungen und beiden Relaxationen auf; die neun Fälle der Solvermatrix sind separat vollständig. Danach führt `raw_metric_replay.py` die unveränderten NumPy-Funktionen des alten Oracles und `independent_metric_audit.py` alle 124 Werte-/CSV-Prüfungen aus. Der vollständige alte Sympy-Treiber ist wegen fehlender Dependency gesondert als nicht ausgeführt dokumentiert; kein alter PASS wird dafür eingesetzt.

Für jede Mutation / jeden verworfenen Implementierungsversuch bleibt das Rohlog im ZIP. Drei absichtlich ungültige CLI-Aktionen erwarten Exit 1. Die früheren wirklichen Fehlversuche dürfen dagegen nicht als erfolgreiche negative Tests gezählt werden; `attempts.md` unterscheidet diese Gruppen. Keine Lizenzdateien oder nativen Binärpakete sind Bestandteil der Veröffentlichung.
