# AP3 → unabhängige A3.5-Prüfung

Worker-Ergebnis: **AP3_partial**. Alle beauftragten Formulierungsfamilien, die anwendbaren Metriken und acht CLI-Aktionen sind implementiert und ausgeführt. Die Einschränkung betrifft die zuverlässige native Integer-Konussolver-Qualifikation: Pajarito/HiGHS/Clarabel meldet für nachweislich zulässige G3-Modelle teilweise INFEASIBLE. Der aktuelle Runner behandelt diese Meldung als numerical_inconclusive und erhält die rohe Terminierung. G0/G3-Referenzen sind separat durch vollständige kleine Enumeration und neun numerisch geprüfte globale Kostenintervalle belegt.

Autoritative Ausgaben: reports/ap3_runs/20261020_macro/{accepted_suite,matrices_final,metrics_final,certificates_final,comparisons_final,planning_final,benchmarks_final,enumeration_final,plots_final,export_final}. Ältere Versuche bleiben erhalten. Große Metrikdateien aus ihren benachbarten ZIPs extrahieren; Hashgleichheit ist protokolliert. Gesamtbericht: reports/paper_a_ap3_validation.md; maschinenlesbare Gates: reports/paper_a_ap3_status.yaml. Dies ist Worker-Evidenz, keine unabhängige Abnahme.

Prüfbasis: Consumer e992edc88d39fa0eb2d72e2490e157441223f568, Produzent-Numerik 3b8fdb01d931225edc5f8fe1e2c200d0da288a09, Vollmathematik e8118425adc335a99e85120d943763305f211315 und Freeze 2c2fce769b2ed6ffd4f1ced60c0798776acccc93. Registro- und Szenariohashes stehen im Status. Finale Branch-Publikation und Dateimanifest werden separat von den unveränderlichen Laufdaten festgehalten.

Die unabhängige Prüfung soll:

1. T001–028 gegen paper_a_formulations.jl, paper_a_diagnostics.jl und AP2s gemeinsame affine B/S/M-Objekte prüfen. Insbesondere native MVA-Basis, feste Quellen genau einmal, a_conn gegenüber a_res, S_on und SOC-/Ereignisgewichte verfolgen.
2. G0/G3-Äquivalenz nur für vollständige symmetrische Z-Matrizen akzeptieren. Alle vorzeichenbehafteten Kanten, sqrt(2)-RSOC-Skalierung, Knotenreste sowie singuläre/reduzible/isolierte Nullzeilen überprüfen. Nicht-Z-PSD-Gegenbeispiel muss G0/G3-Unterschied behalten.
3. Positive Support-Elimination einschließlich PSD-Nullblock und Range-Projektor prüfen; all-zero exposure bleibt undefiniert. LOCAL-Matrixtest ist auch für singuläres B definiert, inverse Verhältnisse sind es nicht. Eigenspace-Multiplizität und skalierte Residuen prüfen.
4. M0: B PD, Inversenzeichen und alpha>0; Gegenbeispiel Zp=(7/9,19/18). M1: tatsächlich erzwungene Mindestmatrix, kanonische passive Stempel und inverse Ordnung. M2: W>=0, diag(W)=1, volle und Nachbargewichte getrennt. G1/G2-Gegenbeispiele in beiden Richtungen prüfen.
5. E2: Woodbury, endliche Reihe, tatsächlicher Fehler, exakter Rest und induzierte Normschranke prüfen. Die neun Studienszenarien liegen außerhalb der verwendeten Norm-Vertrauensregion; null remainder_bound ist korrekt. Positiver und negativer Bereich sind zusätzlich synthetisch getestet. Keine einseitige Planungssicherheit behaupten.
6. Die Originalwährungs-Gaps und die exakte Inkrement-Koordinatentransformation prüfen. Pajaritos rohe relative Gap darf wegen des Zielfunktionsoffsets nicht als Währungsgap gelten. BASE-LP-Bounds, G0/G3-projizierte globale Bounds und feste Integer-Feasibility-Checks auseinanderhalten. integer_bound_audit.json ist numerische Solver-Bound-Evidenz, keine Intervallarithmetik.
7. Blocker B1 mit einem unabhängig qualifizierten MISOCP-Pfad oder nachvollziehbarem reproduzierbarem numerischem Fix auflösen. Fehlende Gurobi-Lizenz ist dokumentiert; kein Lizenzkauf/keine Neuformulierung ist Teil dieses Workers.
8. Matrixreplay, alle 124 Registry-IDs, CSV/JSON-Rundlauf, Einheiten, einmalige Horizontkosten, explizite Nullzustände und alle acht CLI-Ausgaben neu prüfen. Vollregression und gespeicherte Evidenztests auf unveränderten Eingaben wiederholen; eigene Ergebnisse separat datieren.
9. P-C2A-001–010 anhand der Evidenzmatrix im Worker-Bericht fallbezogen adjudizieren. Ein bestandener Klassifikator beweist keine universelle PD oder empirische Quellenqualifikation.
10. Fachliche Eigentümerentscheidungen zur empirischen Parameter-, Quellen-, Fehlerstrom-, Spannungs-/Stromfähigkeits- und Jahresrepräsentativitätskonvention getrennt einholen. Externe SCR/ESCR/MSCR/gSCR und S_I bleiben ohne diese Daten nicht vergleichbar/berechenbar.

Die neun Strang-B-Szenarien bleiben **conditional_owner_review_pending**. AP1s ursprüngliche theorem_domain_valid=false und empirical_study_ready=false werden nicht geändert. AP3 verifiziert einen deklarierten numerischen Teilbereich; dies erteilt keine reale Studien- oder Publikationsfreigabe. Keine neuen AC-CPF-, Dynamik-, EMT- oder TNEP-Modelle wurden eingeführt.

**A3_closed=false; AP4_ready=false.** Erst unabhängige A3.5-Entscheidung und die getrennten fachlichen Daten-/Designfreigaben können diese Gates ändern.
