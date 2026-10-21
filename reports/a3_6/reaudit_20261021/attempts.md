# Erhaltene Prüfwerkzeug-Fehlversuche

1. Die erste Ausführung von `integrity.py` verwendete die Reihenfolge der
   Referenzliste als vermutete Ancestry-Kette. `merge-base --is-ancestor
   4d9f346c5fca80e00fd01d96c39a2bac91776ac0
   e1e075626b38b478faf57efe62e557fc94753f00` endete mit Exit 1.
   Tatsächlich ist e1e0756 der Parent von 4d9f346. Es wurde kein Input geändert.
   Die korrigierte Prüfung verwendet die aus Git verifizierte Reihenfolge
   Original → Metadatenfix → EXEC → Makroauftrag → Produktionsfix → Evidenz.
   Der leere erste Scratchordner `../reaudit_run` bleibt erhalten;
   alle erfolgreichen Läufe liegen separat unter `../reaudit_run02`.
2. `python --version` erreichte zunächst nur den Windows-Store-Alias und endete
   mit Exit 1. Verwendet wurde anschließend das von der App ausgewiesene
   Python-Binary unter `.cache/codex-runtimes/codex-primary-runtime/dependencies/python`.
3. Ein explorativer `rg`-Aufruf mit dem Windows-Pfadglob `src/objective*`
   meldete einen ungültigen Dateipfad. Die relevanten Treffer wurden danach
   direkt in `src/core/objective.jl` gelesen. Frühe `Get-Content`-Aufrufe auf
   noch nicht erzeugte Ergebnisdateien bzw. einen nicht vorhandenen
   extrahierten Toolpfad waren reine Status-/Suchversuche; sie sind keine
   fehlgeschlagenen fachlichen Tests und wurden nicht als PASS gezählt.

Die historischen Fehlversuche, Lizenzfehler und nichtoptimalen Status bleiben
zusätzlich vollständig im unveränderten, hashgeprüften Eingangsarchiv erhalten.

4. Der erste finale Export-/SHA-Abgleich endete bei der Receiptprüfung mit
   Exit 1. Das Prüfprogramm hatte dessen Git-Blobnachweise gegen den aktuellen
   Evidenznachfolger `1147873...` statt gegen den ausdrücklich im Receipt
   bezeichneten Commit `8d982224c407145a42bd800ec95f1a4840187eae` geprüft.
   Nur `directory_inventory.json` und `published_file_sha256.csv` unterscheiden
   sich dort: Im Nachfolger wurde der neue Receipt in diese Inventare aufgenommen.
   Die Prüfung wurde auf den deklarierten Receipt-Zielcommit korrigiert;
   zusätzlich werden sämtliche Dateien von `1147873...` separat gegen ihre
   Git-Inhalte geprüft. Die erste Logdatei und der ursprüngliche Exit-1-Eintrag
   bleiben erhalten; nur die kurze Vergleichsstufe wird als eigener Retry
   erneut ausgeführt. Keine Solverläufe und keine Originaldateien werden ersetzt.

5. Die erste gestagte Whitespaceprüfung meldete CRLF-Zeilenenden der neu unter
   Windows geschriebenen JSON-/CSV-/Berichtsdateien als trailing whitespace.
   Der Paketgenerator schreibt diese neuen Publikationsdateien nun explizit
   mit LF und erzeugt ihre Hashes erneut. Archivierte Rohlogs und Eingänge
   werden bytegleich erhalten. Die anschließende Prüfung muss ohne Ausnahme
   bestehen; dies ist keine wissenschaftliche Teständerung.
