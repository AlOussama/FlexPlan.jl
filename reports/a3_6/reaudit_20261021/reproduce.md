# Reproduktion des unabhängigen Reaudits

Basis: `FlexPlan.jl@1147873bf553667aec5cd7eb0e9c6f7e471b370c` plus ausschließlich
die neuen Prüfprogramme dieses Verzeichnisses. Produktionscode und Tests sind
gegenüber `910d44122a37d9ed2cca06940740b46706c73d40` identisch. Die ursprüngliche
Factory wird aus dem sauberen Original-Checkout
`D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE@485b637cc1998a327206c5929434bd26c6f0be16`
geladen. Diese lokale Voraussetzung vor einem Replay selbst nachprüfen.

Für jeden Replay einen neuen Runordner verwenden. `integrity.py` verweigert
absichtlich einen vorhandenen Zielordner. Historische Archive, vorhandene
Worktrees und frühere Runordner nicht überschreiben. Die Quelltexte enthalten
die vollständigen tatsächlich verwendeten Argumente; `execution_manifest.json`
enthält die konkreten Argumentarrays, UTC-Zeitpunkte und Exitcodes des Reaudits.

PowerShell, im neuen Auditcheckout:

```powershell
$repoRoot = (Get-Location).Path
$runRoot = 'C:/Users/User/.codex/worktrees/a36-independent-reaudit/reaudit_replay_new'
$pyExe = 'C:/Users/User/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$auditDir = Join-Path $repoRoot 'reports/a3_6/reaudit_20261021'
git -C D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE rev-parse HEAD
git -C D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE status --porcelain=v1
julia +1.10.11 --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
& $pyExe (Join-Path $auditDir 'integrity.py') $repoRoot $runRoot
& $pyExe (Join-Path $auditDir 'run_suite.py') $repoRoot $runRoot exact
& $pyExe (Join-Path $auditDir 'run_suite.py') $repoRoot $runRoot regression
& $pyExe (Join-Path $auditDir 'run_suite.py') $repoRoot $runRoot solver
& $pyExe (Join-Path $auditDir 'run_suite.py') $repoRoot $runRoot remaining_filter
```

Keine Paketupdates. Python benötigt nur die Standardbibliothek. Das Environment
wurde mit Julia 1.10.11 instanziiert; die gemessenen Paket-/Threadstände liegen
im neuen ZIP in `runtime.json`. Für einen anderen Host sind die ausdrücklich
lokalen BASE-/Wissenschafts-/Inputmanifestpfade nachweisbar anzupassen; eine
unangepasste Ausführung ist kein portabler Blindtest.

Die Modi führen folgende echten Prüfungen aus:

- `exact`: vorhandener rationaler Verifikator, vollständige exakte Ergänzung des
  originalen nativen Punktes, frische Raw-Kostenrekonstruktion und davon
  getrennter neuer Primal-/PSD-/Dual-/Inklusions-/Objective-Verifikator.
- `regression`: vollständiger kopierter Testbaum; eigene entpackte Kopie der
  historischen Evidenz; tatsächliche JuMP/MOI-Schutzsuite und Domänenmutationen.
- `solver`: minimaler Filtergegenfall, unveränderte eingefrorene OA-MIP mit
  beiden Schwellen, echte Original-/Produktionsfactory am nativen Originalmodell;
  vorhandene 45-Läufe-Matrix und neun BASE-LP-Solves; 27 frische Modelle und
  18 tatsächliche Objective-Snapshots mit anschließendem Identitätsabgleich.
- `remaining_filter`: neuer exakt zulässiger Schwellengegenfall unter 1e-12;
  das erwartete `INFEASIBLE` ist eine dokumentierte Restgrenze des Solvers.

Objective-Snapshots stoppen absichtlich vor dem Optimieren; sie zählen nicht
als Solverläufe. Ein Prozess-Exit 0 ist allein kein Solver-PASS. Maßgeblich sind
die getrennten Termination-/Primalstatus und exakten Zertifikatsprüfungen.

Vor Publikation wurde zusätzlich `verify_final_state.py REPO RUN` ausgeführt.
Dieses lokale Schutzprogramm erwartet die konkrete neue Auditbranch und die
ursprünglich gesicherten lokalen Referenzen; bei einer späteren Reproduktion
ist sein Archivbefund zu lesen, nicht ein inzwischen veränderter Branchzustand
als ursprünglicher Befund auszugeben. `finalize.py REPO RUN` erzeugt erst nach
vollständigen erfolgreichen Prozessprüfungen das Berichtspaket. Neue Laufdaten
in einem separaten Ausgabeverzeichnis veröffentlichen, das vorhandene Paket
nicht überschreiben.

Das neue ZIP kann unabhängig vom Arbeitsordner gegen alle Größen-/SHA256-Entries
im `reproduction_manifest.json` geprüft werden. Die zuvor vorhandenen zwei ZIPs
sind referenzierte, vollständig verifizierte Inputs und werden nicht dupliziert.
Das Manifest enthält zusätzlich die Hashes der neuen Skripte und Ergebnisdateien;
der nachgelagerte Publikationsreceipt ist ausdrücklich von dieser ersten
Evidenzveröffentlichung getrennt.
