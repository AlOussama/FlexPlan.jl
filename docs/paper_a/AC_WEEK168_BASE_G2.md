# Gurobi-Zulässigkeitsprüfung und BASE-Kostenvergleich
KW 8/2013 (18.–24. Februar), 168 gekoppelte Stunden, mindestens 70 % Wind/PV, kontinuierliche UC- und Investitionsrelaxation. Kosten in annualisierten EUR 2025.

## Zulässigkeit

Gurobi 13.0.3 liefert für beide BASE-Netzformulierungen einen Punkt, der bei unabhängiger Nachrechnung in der vollständigen Original-MPS die native Toleranz von 10⁻⁶ einhält. Die archivierten Fehlversuche endeten mit Status 12 (NUMERIC). Für einen materiellen Konflikt zwischen Wochenquote, Anlagen- oder Zweiggrenzen liegt kein Gurobi-IIS vor. Die Gurobi-Diagnose setzt das Optimierungsziel auf null und DualReductions auf 0. Ein Nullziel liefert ausschließlich einen numerischen Zulässigkeitszeugen. [Gurobi-Statuscodes](https://docs.gurobi.com/projects/optimizer/en/current/reference/numericcodes/statuscodes.html)

| BASE-Modell | Suche | Wind/PV | max. native Zeilenverletzung | max. P-KCL (MW) | max. Q-KCL (MVAr) |
|---|---|---:|---:|---:|---:|
| SOC-WR | Vollständiges Modell, frei optimierte Spannungsvariablen | 70,0108005981 % | 2,5302 × 10⁻⁸ | 1,263 × 10⁻⁹ | 3,16 × 10⁻¹¹ |
| LPAC | Fixierter Spannungszustand, Nachprüfung im vollständigen Modell | 74,1686490955 % | 4,6093 × 10⁻⁷ | 7,37 × 10⁻¹⁰ | 3,44 × 10⁻¹⁰ |

Beide Punkte erfüllen die geprüften thermischen AC-Grenzen und die P-/Q-Grenzen der Anlagen und HGÜ-Enden. Für den LPAC-Zeugen wurden 20.664 Spannungsvariablen auf die Kombination aus 99,99 % G2-Referenz und 0,01 % Flachstart fixiert. Alle übrigen Variablen durften sich innerhalb ihrer ursprünglichen Grenzen bewegen. Die Fixierungen dienten ausschließlich der Punktsuche. Der unabhängige Reviewer prüfte die Ergebnisse in den ursprünglichen Modellen ohne Fixierungen. Die nachträglich angewandte G2-Bedingung wird am SOC-WR-Zeugen in 44 und am LPAC-Zeugen in 120 Stunden unterschritten. Diese beiden Punkte wurden ohne G2 optimiert. [SOC-WR-Replay](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_feasibility/independent_base_point_review.json) · [LPAC-Replay](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/LPAC_voltage_witness/independent_base_point_review.json)

## Ursachen der Abbrüche

**LPAC, Gurobi.** Im kontrollierten 2×2-Test auf derselben MPS wurden ausschließlich Aggregate und ScaleFlag variiert. Alle vier Läufe verwendeten NumericFocus 2, vier Threads, Seed 1 und fünf Barriereschritte. Die Zahlen sind die im Gurobi-Log ausgegebenen primalen Barriereresiduen und haben keine unmittelbare Einheit MW.

| Aggregate | ScaleFlag | Iteration 0 | Iteration 5 |
|---:|---:|---:|---:|
| 1 | −1 | 9,22 × 10⁶ | 9,22 × 10⁷ |
| 0 | −1 | 2,46 × 10⁷ | 3,52 × 10⁵ |
| 1 | 2 | 2,90 × 10⁷ | 7,14 × 10⁷ |
| 0 | 2 | 1,82 × 10⁸ | 5,34 × 10⁶ |

Bei beiden Skalierungen kippt die Entwicklung des frühen Residuums mit der Zeilenaggregation. Die beiden ursprünglichen LPAC-Kostenversuche blieben ab Iteration 2 stehen. Der vollständige Lauf ohne Aggregation endete nach 197 Iterationen mit SUBOPTIMAL. Die fünf frühen Gurobi-Kostenabbrüche bei LPAC und SOC-WR hatten 736–832 MiB Prozess-Spitzen-RAM und reguläre NUMERIC-Endprotokolle. [Kontrollversuche](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/barrier_diagnostics) · [LPAC-Solverlog](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/LPAC_noaggregate/native_solver.log)

**SOC-WR, Winkelzeilen.** Die Originaldaten verwenden ±π/2 in allen 8.736 Zweigstunden. PowerModels erzeugt daraus 17.472 Tangentenzeilen mit Koeffizienten ±1,633123935319537 × 10¹⁶ und eine kleine positive Untergrenze für den Realteil des Spannungsprodukts. Die Spanne der linearen Koeffizienten reicht von rund 8 × 10⁻⁸ bis 2 × 10¹⁶. Dieselben Winkelzeilen kommen auch im G2-Modell vor. Die lokale Redundanz der gespeicherten endlichen Tangentenbedingungen folgt weder aus dem Produktkegel noch aus den thermischen Grenzen. Für den Kontrollversuch wurden ausschließlich diese 17.472 vollständigen Null-RHS-Zeilen mit dem positiven Faktor 2⁻²⁶ multipliziert. Alle 34.944 geänderten Koeffizienten lassen sich bitgenau zurückrechnen. Die unabhängige Prüfung bestätigt die Äquivalenz. [Original-Solverlog](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR/native_solver.log) · [Skalierungsregister](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_angle_scaled/scaled_angle_rows.csv)

**SOC-WR, MOSEK.** Beim direkten QC-MPS-Import scheitert MOSEK an qc0 mit Fehler 1294. Die gespeicherte Form t²−Σx² ≥ 0 mit t ≥ 0 ist ein Lorentzkegel. Als explizite Kegelaufgabe importiert MOSEK alle 26.208 Kegel und meldet anschließend prim_infeas_cer. Der Gurobi-Nullzielpunkt wurde direkt auf der identischen serialisierten Kegelaufgabe geprüft. Seine kleinste Kegelmarge ist +0,109177, alle Variablengrenzen sind erfüllt, die größte affine Zeilenverletzung beträgt 2,5302 × 10⁻⁸. Der numerische Zertifikatsstatus lässt sich daher nicht als Nachweis eines physikalischen Konflikts verwenden. [Importfehler](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_mosek/outcome.json) · [MOSEK-Status](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_mosek_conic/outcome.json) · [Direkte Nachrechnung](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_mosek_conic/independent_contradictory_certificate_review.json)

## Modellidentität

Fall-SHA-256 `66885c9b5d27b21ac1000cf16e8da5d886b7ab50085783957907cebef8a41d3b`. BASE entstand durch Entfernung der 37 × 168 unabhängig aus Koeffizienten und rechten Seiten identifizierten G2-Zeilen. Variablengrenzen, Zielfunktion, Kosten, Zeitkopplung und alle verbleibenden MPS-Datensätze wurden abgeglichen. SOC-WR-BASE-MPS `01848864794dee9911ce5cf4a40bc4941c002fffe183e84fd565615ddfc15849`. LPAC-BASE-MPS `4aa116e6185a779b86d354ec5e8bf0b053344d3041f4fd46b15f5a4b09a98d9b`. [SOC-WR-Modellvergleich](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR/independent_base_model_review.json) · [LPAC-Modellvergleich](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/LPAC/independent_base_model_review.json)


## Gurobi-Kontrolllauf und Kosten

Im gepaarten SOC-WR-Test wurden identische Parameter verwendet (3 Threads, Aggregate 0, ScaleFlag −1, NumericFocus 2, Seed 1, homogene Barriere, BarQCPConvTol 10⁻⁷). Auf der Original-MPS lag das primale Residuum nach fünf Schritten bei 9,22 × 10⁷. Nach ausschließlicher Skalierung der Winkelzeilen betrug es 3,06 × 10⁵ und sank weiter. Gurobi exportierte nach 66 Schritten einen Kostenpunkt. Der unskalierte Kontrollversuch war auf fünf Schritte begrenzt. Ein früherer unskalierter Lauf ohne dieses Limit endete nach fünf Schritten mit NUMERIC. Das isoliert den Einfluss der numerischen Darstellung auf diesen Barrierestart. [Unskalierte Kontrolle](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/soc_angle_control/aggregate0_scale-1.json) · [Skalierter Lauf](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_angle_scaled/native_solver.log)

| Netz | Freier BASE-Kostenlauf, Mrd. EUR 2025/a | G2-Vergleichspunkt, Mrd. EUR 2025/a | G2 minus BASE, Mrd. EUR 2025/a | Befund am BASE-Kostenpunkt |
|---|---:|---:|---:|---|
| DC | 124,989733 | 127,408222 | 2,418488 | Akzeptierter GOLD-Vergleich aus den Originalreceipts |
| LPAC | 125,908117 | 128,350670 | 2,442552 | SUBOPTIMAL, Quote um 11,545 kWh unterschritten, max. P-KCL 0,020027 MW |
| SOC-WR | 126,073860 | 128,548666 | 2,474806 | SUBOPTIMAL, Quote um 29,527 kWh übertroffen, max. P-KCL 0,074183 MW |

Die AC-Zahlen sind Differenzen bewerteter Kandidaten. Der marginale G2-Kosteneffekt zwischen zwei qualifizierten AC-Optima bleibt offen. Die historische Schwelle für P-KCL beträgt 0,0001 MW. Der LPAC-Kostenpunkt verletzt eine Generator-P-Grenze um höchstens 0,013861 MW, der SOC-WR-Kostenpunkt um 0,074464 MW. Die Zweig-MVA-Grenzen sind an beiden Kostenpunkten eingehalten. Nachträglich unterschreiten 3.809 von 6.216 G2-Zeilen bei LPAC und 3.826 bei SOC-WR die Marge −10⁻⁶ pu, jeweils in allen 168 Stunden. [LPAC-Kostenreplay](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/LPAC_noaggregate/independent_base_point_review.json) · [SOC-WR-Kostenreplay](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_angle_scaled/independent_base_point_review.json) · [G2-Vergleichspunkte](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/CONFIRMED_QBOX/independent_final_week_review.json)

Bei fixierten LPAC-Spannungen lieferte Gurobi zusätzlich 125,909311 Mrd. EUR/a und 4,857 kWh Quotenreserve. Die P-KCL-Abweichung von 0,021300 MW sowie Überschreitungen bei Generator-P und Speicher-P schließen die Verwendung als nach GOLD qualifizierte obere Kostenschranke aus. Der zusätzliche MOSEK-LPAC-Lauf wurde zugunsten der Gurobi-Diagnose bei 3,35 GiB freiem RAM mit erhaltenem Log beendet. [Fixierter Kostenversuch](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/LPAC_cost_voltage_repair/independent_base_point_review.json) · [Stopprotokoll](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/LPAC_mosek/stop_receipt.json)

## MOSEK-Zertifikatsvektor

Eine eigenständige Wiederholung mit der identischen gespeicherten Task reproduzierte prim_infeas_cer. MOSEK meldet für den gespeicherten Vektor bei dualem Ziel 0,999605 die dualen Verletzungen dviolcon = 1.529,59 und dviolvar = 10.627,99. Der Status liefert hier keinen gültigen Unzulässigkeitsnachweis am Originalmodell. Ray-SHA-256 `a355c4dc32dd160db3abde9dfb862b8a26a8a83baf0baa9bbcc8d0bcc1431ac3`. [Zertifikatsqualität und Hashes](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_conic_certificate_replay/outcome.json)

Lokaler Code-Commit `e60ce3898afd758f99d9e51e9fa7871b3e7ab780`. Die für die gepaarten Kontrollen und die Zertifikatswiederholung verwendeten Skripte liegen neben diesem Bericht. Die Originaldaten und G2-Ergebnisse stammen aus dem bestehenden lokalen Checkout und dem archivierten 168-h-Fall. Modellvergleich und Lösungsprüfung erfolgten durch den getrennten Reviewer `/root/qa_week`. Die Herkunft der Winkelkoeffizienten und die Redundanzfrage prüfte `/root/math_r`.

Der unabhängige Test widerlegt den archivierten MOSEK-Strahl als Farkas-Zertifikat. An 5.544 ausschließlich nach unten beschränkten Zeilen ist der zugehörige Multiplikator negativ. Für R255706 ist er −1.529,59153. An V297534, einer Variablen mit unterschiedlichen endlichen Grenzen, ist der obere Multiplikator −10.627,98793. Damit sind die Vorzeichenbedingungen verletzt. Der vollständige Vektor liegt in der SHA-geprüften NPZ-Datei. Der separat exportierte native Postsolve-Dump enthält beim Wiedereinlesen keinen als solchen markierten Lösungsstatus. [Test des Strahls](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_conic_certificate_replay/independent_farkas_ray_review.json) · [Einseitige Vorzeichen-Gegenbeispiele](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/SOC-WR_conic_certificate_replay/independent_ray_sign_witness.json)

Das unabhängige Schlussprotokoll umfasst 16 BASE-Versuche und fünf an der vollständigen Originalmatrix nachgerechnete Primallösungen. SHA-256 `f6a671334ef259d95c8314e4ddcd6457461fabdbf9ddf646d07201baf8f93ba1`. [Unabhängiger Abschluss](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/independent_base_pair_final.json)
## Codepfad

Der Wochenrunner scripts/paper_a/week_ac_compare.jl erzeugt das native G2-Modell. export_ac_base.py identifiziert die G2-Zeilen anhand ihrer Koeffizienten und rechten Seiten. solve_ac_native.py löst die exportierte MPS mit der Gurobi-C-API und speichert den vollständigen Primalvektor. Das archivierte Skript [rescale_socwr_angle_rows.py](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/BASE_PAIR_20261126/rescale_socwr_angle_rows.py) dokumentiert die binäre Winkelskalierung. Alle Solverdateien liegen im selben Skriptverzeichnis wie der Wochenrunner.
