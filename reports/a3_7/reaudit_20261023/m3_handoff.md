# Handoff an M3 — globale Integerprüfung

Die unabhängige A3.7-B1-Abnahme akzeptiert die native Gurobi-Route ausschließlich für die neun registrierten binär-rationalen Inputs, vier G3-Modi und den literal Originaldefault. Kandidat `0ca85adad5b6bcdff5a3ce8df54f5b8ac8eb8568`, Produktion `f302b7b63e917678fb14b7cbc3cfdbc0d8c624a1`, A3.6-Basis `15ba10c193a562a48cb0e1dcc6fa12d922ac0613`. Der publizierte Reviewcommit steht im Receipt. `B1_repaired=true` ist in diesem Bereich eine technische/numerische Entscheidung.

Vor wissenschaftlicher Globalitätsaussage:

1. Für jeden Fall die genaue Objectivekoordinate festlegen. Die neun alten rationalen Intervalle gelten nur für ihre ursprüngliche normalisierte binär-rationale Domäne. Literal Default und Studienwährung nicht vermischen.
2. `reviewer_oracle.json` und die Original-/Solver-/Backendmodelle aus `reaudit_evidence.zip` verwenden. Alle affinen Rebase-/Divisionsreste `delta(x)` einschließlich Konstante erhalten. Die zusätzliche Zweierpotenzmultiplikation ist exakt, die frühere Division/Rebase nicht allgemein.
3. Neue native Punkte nur als numerische Kandidaten behandeln; nichtnull Originalresiduen sind dokumentiert. Exakt zulässige Zeugen erforderlichenfalls in der tatsächlich zu zertifizierenden Koordinate rekonstruieren und unabhängig prüfen.
4. Globale Lower Bounds und Integeroptimalität rigoros nachweisen. Native Gurobi-/MOSEK-/Pajarito-`OPTIMAL`-Flags sind kein exakter Beweis. Gegenbeispiele für raw Bounds stehen in `diagnostic_comparisons.json`; fehlende Gegenbeispiele der finalen Route zertifizieren keinen Herstellerbaum.
5. Die 18 LP-Zertifikate und 18 exakten Primale des separaten A3.6-Reviewerpfads sowie die 171er-Prüfung als begrenzte bestehende Evidenz verwenden. Neue Kostenintervalle nicht ohne Nachweis behaupten.
6. Wissenschaftliches Amendment, Ownerratifizierung, Daten-/Empiriequalifikation, A3.5-Gesamtakzeptanz und AP4-Release separat entscheiden. `A3_closed=false` und `AP4_ready=false` bleiben bestehen.

Offene Umgebungseinschränkung: vollständiger monolithischer Sympy-Treiber wegen fehlendem Modul nicht ausgeführt; der reale Fehlversuch ist archiviert. Exakte Fraction-Zertifikate und 124-Metrik-/CSV-Prüfung bestehen separat. Die vollständigen alternativen MOSEK-Stressmatrizen sind historische verifizierte Evidenz, keine frische unabhängige Qualifikation.

Keine Produktionskorrektur, kein Merge, Reset oder Branchlöschen ist durch diesen Handoff freigegeben. Die 28 fremden unversionierten `audit/`-Dateien weiterhin unverändert erhalten. Für neue Inputs oder Runtimewechsel die technische Qualifikation neu durchführen.
