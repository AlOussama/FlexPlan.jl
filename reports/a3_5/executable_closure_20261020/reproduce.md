# Reproduktion auf dem geprüften Windows-Host

Die genauen Argumentarrays, Arbeitsverzeichnisse und Exitcodes der ursprünglichen Vollregression und CLI-Kette stehen in `execution.json`. Alle verwendeten Rohdaten-/Source-/Manifestdateien sind in `input_sha256_manifest.json` verzeichnet; Wissenschaftssnapshots gesondert in `science_source_manifest.json`. `reproduction_manifest.json` bindet das verlustfreie neue Evidenzarchiv samt jedem enthaltenen Bytehash. Frühere Archive werden aus dem unveränderten AP3-SHA gelesen, nicht aus diesem neuen Archiv als Prüforacle übernommen.

Verwendete Runtime: Julia 1.10.11, genaues `Manifest-v1.10.toml`; SymPy 1.14.0, NumPy 2.5.4. Python wurde aus dem Codex-Runtimebundle verwendet; die zusätzlichen Pakete liegen isoliert in `RUN/python_deps`. Keine Abhängigkeitsaktualisierung im FlexPlan-Projekt. Pkg-Reproduktion benötigt Zugriff auf die versionierten Package-/Artifactquellen. Gurobi und MOSEK waren installiert, aber ihre tatsächlichen Solveversuche scheiterten an abgelaufenen Lizenzen.

Geprüfte Pfade:

```text
BASE = D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE
FIX  = D:/Projekte/Code/FlexPlan_A35_EXEC_REVIEW
RUN  = D:/Projekte/Code/FlexPlan_A35_EXEC_RUN
AUDIT = FIX/reports/a3_5/executable_closure_20261020
```

BASE ist detached auf `485b637cc1998a327206c5929434bd26c6f0be16`. FIX verwendet für den Metadatenexport den Codecommit `e1e075626b38b478faf57efe62e557fc94753f00`. Auditwerkzeuge stammen aus dem abschließend veröffentlichten Evidenzcommit; dieser Commit ändert keine weiteren Produktionsgleichungen. Bei anderen lokalen Pfaden die vier expliziten Rootvariablen in den mitgelieferten PowerShell-/Hilfsskripten anpassen. Die Werkzeuge sind absichtlich kein generisches Framework.

Ausführungsreihenfolge, jeweils mit neuem Outputverzeichnis:

1. Autoritäten mit `git cat-file -t`, `git show -s --format='%H %P'`, `git merge-base`, `git ls-remote` und `git status --short --branch` prüfen. Keine bestehenden Worktrees überschreiben. Producer-`git archive` exakt von `3b8fdb01d931225edc5f8fe1e2c200d0da288a09` aus `data` neu extrahieren; Originalbytes gegen das Inputmanifest prüfen.
2. `julia +1.10.11 --startup-file=no --project=. -e 'using Pkg; Pkg.status(); Pkg.instantiate()'` in BASE. Getrackte Dateien danach prüfen. Bytegleiche `test/`-Kopie nach `RUN/validation/test` legen, damit schreibende historische Tests nur neue Scratchreports erzeugen.
3. `prepare_evidence.py`: die benötigten historischen Ausgaben nach Scratch kopieren, 14 ZIPs lesen und die beiden finalen Metrikdateien dort extrahieren. `verify_inventory.py` prüft alle 1060 historischen Indexeinträge gegen Originaldatei oder verlustfreien ZIP-Eintrag. `snapshot_science.py` liest exakt die acht gepinnten Git-Blobs.
4. `execute_replay.ps1`: echte Vollregression, 4108-Evidenztests, neue 162er Suite und sechs nachgelagerte Prüfoperationen außer dem abschließenden Evidenzindex, AP1-/Parameter-/Netztests. Die achte CLI-Aktion wird in Schritt 8 ausgeführt. Die Einzelschritte laufen nacheinander und persistieren ihre Exitcodes. Solverstatus innerhalb einer Exit-0-Suite sind separat zu lesen.
5. `independent_jump_moi_audit.jl RUN/moi_final03` und `independent_domain_mutations.jl RUN BASE` mit `julia +1.10.11 --startup-file=no --project=.` aus BASE ausführen. Der MOI-Grenztest deaktiviert explizit Clarabel-Chordalzerlegung; der dazu führende Originalfehlversuch ist erhalten. Die Domänenmutation prüft zuerst die strikte Ablehnung unqualifizierter Producerinventare; numerische Stempelprüfung erfolgt anschließend explizit als Diagnose.
6. `independent_integer_b1_audit.jl BASE RUN/integer_best fixed_only_best_historical_seed` ausführen. Alle historischen Seeds werden SHA-geprüft und anschließend vollständig neu auf Zulässigkeit, Matrixgleichungen und Kosten geprüft. Für die protokollierten numerischen Skalierungsvarianten wurde dasselbe Skript ohne drittes Argument nach `RUN/integer_final` ausgeführt.
7. Für B1: `b1_exact_native_repro.jl BASE RUN` → `b1_transfer_full_witness.jl RUN` → `b1_exact_native_repro.jl BASE RUN`. Der zweite Native-Repro liest den vollständigen Zeugen und prüft ihn nach den tatsächlichen MOI-Variablenbrücken. Die erste Solvefolge darf ohne Pointdatei ausgeführt werden. Der native Aufruf verwendet die originale `solve!`-Funktion; der Hook ändert nur die Verbosität. Das übertragene Originalmodell enthält 1353 Integerbedingungen. MOSEK-Versuch: das erzeugte native MOF mittels JuMP `read_from_file`/`write_to_file` in CBF schreiben; `mosek.exe -r -d MSK_IPAR_NUM_THREADS 1 -d MSK_DPAR_MIO_MAX_TIME 120 -jsolo OUTPUT.json native24.cbf`. Auf diesem Host erwarteter Lizenzfehler, kein PASS.
8. `finalize_replay.ps1` berechnet beide Pythonoracles, die neun Kosten-/Boundsummaries und alle 124 Metriken neu, exportiert am Fixcode die Metriken erneut und führt drei negative CLI-Aufrufe aus. `verify_and_package.py RUN AUDIT BASE prepare_cli_payload` kopiert die sieben frischen CLI-Ausgaben in einen neuen Byte-Snapshot. Dann aus BASE: `julia +1.10.11 --startup-file=no --project=. scripts/paper_a/ap3.jl export_paper_a_evidence RUN/cli_payload RUN/export`. Output liegt außerhalb des indizierten Inputs.
9. `verify_and_package.py RUN AUDIT BASE verify` prüft den vollständigen Fixexportvergleich und alle neuen Indexhashes. `build_closure_report.py RUN BASE` erzeugt die zehn P-/28 T-Zeilen und die Berichte aus tatsächlich vorhandenen Ergebnissen. `verify_and_package.py RUN AUDIT BASE package` erzeugt und prüft das neue ZIP vollständig mit SHA256 jeder enthaltenen Datei. Exakte Befehle und erwartete negative Prozesse zusätzlich in `additional_execution.json`.

Die Ausführungswerkzeuge bewahren absichtlich rohe nichtoptimale Status, Fehlversuche und Lizenzfehler. Globale neun-Fall-Optimalität, reale Quellen-/Kosten-/Jahresrepräsentativität und Owner-Ratifizierung werden durch diese Reproduktion nicht automatisch erteilt. Der exakte kleine 81-Zuweisungen-Fall ist von den neun Producerfällen getrennt.
