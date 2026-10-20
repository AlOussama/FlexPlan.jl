# Unveränderter Pre-fix-Befund A3.6-B1/OPT

Vor jeder Produktionsänderung geschrieben. Original AP3: `485b637cc1998a327206c5929434bd26c6f0be16`; EXEC-Eingang: `4d9f346c5fca80e00fd01d96c39a2bac91776ac0`; additive Auftragsbasis: `e49b64216f82eefda77d6997ed68ed2d12c8ae78`.

`SPECIFICATION_READY`. Historische Archive und Originalbranches bleiben unverändert. Die neue Diagnose verwendet eigene Scratchdateien. Alle 381 archivierten EXEC-Einträge wurden bytegenau geprüft.

Der originale `solve!`-Pfad wurde unverändert ausgeführt. Erste Wiederholungen liefern `INFEASIBLE`/`NO_SOLUTION`; vor und nach Witness-Transfer unverändert. Der Originalwitness erfüllt das Originalmodell numerisch mit maximal `7.515349001601957e-12` Verletzung. Eine zusätzliche neue rationale Rekonstruktion erfüllt sämtliche originalen serialisierten G3-Constraints exakt; die gleichen Basisvariablen bestehen die exakte PSD-Prüfung des G0-Modells. Dieser Beweis gilt für die exakt als binäre rationale Zahlen interpretierten serialisierten Koeffizienten, nicht für ungerundete physische Daten.

Ursachenlokalisierung: Zwei erzeugte OA-Zeilen haben ausschließlich Koeffizienten kleiner als `1e-9`. HiGHS entfernt diese beim Einlesen. Eine Zeile wird dadurch von einer erfüllbaren Ungleichung zu `0 >= 3.025002202302713e-8`. Der aktuelle MIP-Feasibilitywert ist `1e-8`. Der gleiche eingefrorene OA-MIP liefert mit `small_matrix_value=1e-12` numerisch `OPTIMAL`; die lineare Relaxation mit Standardfilter bleibt numerisch lösbar. Reine Objective-Multiplikation des bereits eingefrorenen OA-Modells behebt die Infeasibilität nicht. Die Nachprüfung verwechselt die fehlgeschlagene erste namensbasierte Integerfixierung nicht mit dem korrigierten indexbasierten Test.

Die Koeffizientenfilterkorrektur allein erreicht am frisch aufgebauten nativen 24-Snapshot-Pfad `ITERATION_LIMIT`. Zusammen mit der bereits vorhandenen, expliziten positiven BASE-LP-Kostenskalierung liefern alle neun registrierten G3-Modelle numerisch `OPTIMAL`. Dies ist eine experimentell belegte Konfiguration, keine allgemeine Solverzuverlässigkeitsfreigabe. Zusätzliche Nachfix- und Skalierungsregressionen stehen noch aus.

OPT: Die acht historisch negativen numerischen Abstände bleiben gespeichert. Es existieren jetzt exakte zulässige Primalpunkte und exakt nachgerechnete LP-Untergrenzen. LP-Untergrenzen sind in mehreren Fällen weit vom Integerzeugnis entfernt; globale Integeroptimalität aller neun Fälle wird nicht behauptet. Der alternative Rohkostenkoordinatenvergleich und dessen Validierung sind noch laufend.

Geplanter Produktionsdiff: ausschließlich `small_matrix_value=1e-12` im vorhandenen HiGHS-OA-Optimizer. Keine Gleichung, Integerdomain, Zieldefinition, Statusmanipulation oder neue mathematische Formulierung. Weil dies die Solverintegration materiell beeinflusst, ist eine weitere unabhängig beauftragte Abnahme verpflichtend. Eigene Nachtests ersetzen diese nicht.

Pre-fix-Urteil: `native_G3_MISOCP=numerical_inconclusive`; `integer_globality=case_specific_partial`; `B1_repaired=false`; `integer_bounds_proved=false` im Sinn der geforderten engen globalen Integerzertifizierung. `A3_closed=false`, `AP4_ready=false`.
