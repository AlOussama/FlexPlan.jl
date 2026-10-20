# B1: belegtes Ursachenglied und verbleibende Grenze

Das native Originalmodell ist in sechs neuen Aufrufen bytegleich zum EXEC-Modell (`fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07`). Alle sechs Aufrufe liefern `INFEASIBLE`. Original und Metadatenfix sind hierbei identisch. Die Kegelrelaxation ist `OPTIMAL`. Der unabhängige rationale Primalpunkt erfüllt das serialisierte ursprüngliche G3-Modell und das separate G0-Modell exakt; das betrifft die normalisierten binären Koeffizienten, keine ungerundete physische Instanz.

Im erzeugten OA-Modell liegen zwei Zeilen vollständig unter HiGHS' Standard-Koeffizientenfilter `1e-9`. In der entscheidenden Zeile werden

`4.5830185178677806e-11*x3612 + 4.5830185178677806e-11*x3618 + 1.3046247794859574e-10*x3926 >= 3.025002202302713e-8`

alle Koeffizienten entfernt. Übrig bleibt `0 >= 3.025002202302713e-8`, gegenüber MIP-Feasibility `1e-8`. Der übertragene Originalzeuge erfüllt die unveränderte Zeile mit LHS `3.02627753631434e-8`. Das ist ein konkreter Verlust der zulässigen Menge durch Koeffizientenfilterung im OA/HiGHS-Übergang. Die Logs belegen die gelöschten Werte; reine Objective-Skalierung des bereits erzeugten OA-Modells behebt den Fehler nicht.

Der kleinste neue Gegenfall besitzt diese eine Zeile, drei nichtnegative kontinuierliche Variablen und einen Integer-Dummy in [0,1]. Er liefert mit Standardfilter `INFEASIBLE`, mit `small_matrix_value=1e-12` sowie mit exakt geprüfter Multiplikation der Zeile durch `2^33` jeweils `OPTIMAL`. Eine rationale zulässige Belegung ist x3=RHS/a3, x1=x2=z=0. Die Zweierpotenz-Skalierung ist ausschließlich Diagnose, kein Produktionspatch.

Produktionskorrektur `910d44122a37d9ed2cca06940740b46706c73d40`: eine HiGHS-OA-Option `small_matrix_value=1e-12` im vorhandenen Optimizer. Keine Lockerung der Feasibility-Toleranz. Die Korrektur behebt dieses belegte Ursachenglied. Der native Defaultpfad ohne explizite Kostenskalierung bleibt beim 24-Snapshot-Fall bei `ITERATION_LIMIT`. Die bereits vorhandene BASE-LP-Kostenskalierung ergibt für neun Fälle numerisch `OPTIMAL`; zusätzliche Stressfälle sind im CSV erfasst. Insbesondere bleibt `reference_24snap` bei doppeltem Kostendivisor `ITERATION_LIMIT`. Daher keine robuste native Gesamtqualifikation.

Root-conic-Feasibility, Bridging, eingefrorene OA-LP/MIP-Stufen, korrigierte indexbasierte Integerfixierung und sämtliche Originalconstraint-Residuengruppen sind getrennt archiviert. Die erste namensbasierte Integerfixierung war wegen anonymer OA-Variablen ungültig und ist als Fehlversuch erhalten. Die MathOptIIS-Konfliktkopie allein beweist ohne Integertrigger keine MIP-Infeasibilität.

Die globale exakte Gültigkeit aller floating-point-OA-Schnitte und eine vollständig validierte MIP-Baumuntergrenze sind nicht etabliert. Native OA-Bounds werden deshalb nicht als rigorose LBs eingesetzt. Die neuen rigorosen LBs stammen aus der separat inklusionsgeprüften BASE-LP-Relaxation. Gurobi Error 10009 und MOSEK 1001 wurden frisch reproduziert; alternative kommerzielle Zertifizierung ist durch die abgelaufenen Lizenzen blockiert.
