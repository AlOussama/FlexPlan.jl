# Paper A · Technische Full37-Fallstudien und offene Ausführungsschritte

Dieses Dokument erfasst den KW‑3-Vergleich, die Q5-Speicherkorrektur und die am 15. November 2026 gestartete 840‑Stunden-Studie. Alle berechneten Fälle verwenden DC-Lastfluss mit verlustfreier HGÜ und die bestehenden 2040-Kostensätze in EUR2025.

## Aktueller Rücklauf · KW 8 mit positivem GFM-Planungsproxy

Alle zwölf LP-/MILP-Varianten für 50/60/70 % Wind/PV mit und ohne G1 sind abgeschlossen und unabhängig geprüft. Alle sechs MILPs erreichen das 0,5-%-Gapziel. Der [vollständige neue Ergebnisbericht](kw08_re50_60_70_joint_expansion_dispatch.md) dokumentiert Ausbau, Dispatch, annualisierte CAPEX/OPEX, Schranken und tatsächliche Gaps. Bei 70 % betragen die MILP-Kosten 127,818619 Mrd. EUR2025 mit G1 und 125,055973 Mrd. EUR2025 ohne G1. QREF hat 70 % als Referenz für den anschließend beauftragten Vergleich der bereits vorhandenen Netzstärkeformulierungen ausgewählt. Die bisherigen 840-h- und Jahresbefunde bleiben in ihren unten dokumentierten historischen Scopes erhalten.

Im [anschließenden Vergleich der vorhandenen G1/G2/G3-Formulierungen](kw08_strength_comparison.md) ist der G2-LP unabhängig akzeptiert (127,408222 Mrd. EUR2025/a). Der G2-MILP erreicht sein Zeitlimit ohne Ganzzahlkandidat. Zwei G3-Gurobi-Punkte wurden wegen tatsächlicher Originalmodellverletzungen verworfen. Der vorhandene native MOSEK-Pfad ist technisch geprüft; zwei Fullcase-Versuche wurden am 19. November durch den Windows-Commit-Reserveguard gestoppt, der erste vor der Optimierung, der zweite im Optimierungsfenster ohne Kandidat. Alle eigenen Prozesse sind beendet. Der weitere G3-Lauf bleibt ressourcenblockiert. Diese Stopps sind keine Infeasibility-Nachweise; es liegt noch kein akzeptierter G3-Vergleichspunkt vor.

Am 18. November wurden auf Owner-Anweisung zunächst 168 Stunden (18.–24. Februar 2013) gemeinsam für Ausbau und Betrieb optimiert. Beide LP-Relaxationen sind `OPTIMAL` und im aktiven Modell numerisch zulässig. Bei gleicher 50-%-Wind/PV-Quote, OPEX ×8760/168 und CAPEX ×1 ergeben sich mit G1/gSCR 98,619706 Mrd. EUR2025 und ohne G1/gSCR 97,551529 Mrd. EUR2025. Der Mehrbetrag beträgt 1,068177 Mrd. EUR2025 (+1,095 %).

| Ausbau beziehungsweise Wochenbetrieb | Mit G1/gSCR | Ohne G1/gSCR |
|---|---:|---:|
| Gaszubau, GW | 1,799 | 1,875 |
| BESS-Zubau GFL / GFM, GW | 7,271 / 30,683 | 16,970 / 0 |
| Onshore-/PV-Zubau, GW | 343,420 / 438,061 | 343,301 / 436,277 |
| Gasdispatch, TWh | 4,193 | 4,561 |
| Batterieentladung, TWh | 1,469 | 0,662 |

Die aktive G1-Variante verletzt keine der 6.216 Zeilen; 942 sind bei 1e-6 pu bindend. Der Vergleich ohne G1 verletzt bei nachträglicher Auswertung 3.026 dieser deaktivierten Zeilen. Die native maximale Constraintverletzung liegt in beiden aktiven Modellen unter 4e-10. Neue separate klassische SCR-/eSCR-Formeln wurden nicht aktiviert. Der positive GFM-Beitrag ist auf den ausdrücklich gewählten fixed-E-Planungsproxy begrenzt, SYN behält `x''d=0.25`.

Der [Qualifikations- und Ergebnisbericht](colib_epri_positive_gfm_source_qualification.md) und der [kompakte Ergebnisreceipt](receipts/kw08_re50_frozen_E_lp_20261118.json) binden Daten, Code, Kosten, stündliche Exporte und unabhängige Prüfung. Die Rohdateien liegen auf E:. Der 840-h-Lauf bleibt durch die Owner-Priorisierung zurückgestellt. Die anschließend beauftragten Integerläufe und die 60-/70-%-Paare sind inzwischen im neuen Gesamtbericht abgeschlossen; es wurden keine LP-basierten Variablenschranken eingeführt. Ein Jahres-, Gate-J-, F3- oder AC-/Dynamik-GO folgt daraus nicht.

## KW 3 · Referenz und Wind-/PV-Quoten

Die Wochenlast vom 14. bis 20. Januar 2013 beträgt 74,239 TWh. Für die Quote zählt die positive Einspeisung aus Wind und PV im Bestand und im Ausbau. Onshore-Wind und PV sind an je 37 Knoten mit vorhandenem Profil kontinuierlich ausbaubar. Die verfügbare Leistung neuer Anlagen geht über `p_max_pu` in den GFL-Term der G1-Ungleichung ein. Bei der Jahreshochrechnung kürzt sich der gleiche Gewichtungsfaktor für Einspeisung und Last. Die Quotenläufe verwenden annualisierte CAPEX einmal und Wochen-OPEX ×52.

| Quote | gSCR | Solverstatus | Gap | Jahreskosten, Mrd. EUR2025 | Gaszubau, GW | Batterie GFL / GFM, GW | Gasdispatch, TWh | Batterieentladung, TWh |
|---|---|---|---:|---:|---:|---:|---:|---:|
| Ohne | Aktiv | `OPTIMAL` | 0,0053 % | 100,577 | 18,295 | 2,075 / 0 | 26,955 | 0,044 |
| Ohne | Aus | `OPTIMAL` | 0,0014 % | 100,530 | 18,219 | 1,750 / 0 | 26,948 | 0,040 |
| 50 % | Aktiv | `TIME_LIMIT` | 1,6663 % | 109,428 | 7,145 | 0,875 / 3,100 | 5,121 | 0,165 |
| 50 % | Aus | `OPTIMAL` | 0,4165 % | 104,525 | 2,659 | 4,400 / 0 | 5,597 | 0,252 |
| 60 % | Aktiv | `TIME_LIMIT` | 4,1118 % | 131,511 | 16,418 | 3,750 / 6,850 | 2,643 | 0,385 |
| 60 % | Aus | `OPTIMAL` | 0,0033 % | 118,622 | 1,636 | 18,000 / 0 | 2,737 | 1,059 |

Das `TIME_LIMIT` bei 50 und 60 % belässt einen zulässigen Ganzzahlplan und offene Optimalität. Die Einspeisung aus Wind und PV beträgt bei 50 % 37,119 TWh und bei 60 % 44,543 TWh. Der 60‑%-Lauf übernahm den ursprünglichen KW‑3-Startdatensatz der 50‑%-Rechnungen. Die Wiederholung bei 70 % nutzte denselben ursprünglichen Startdatensatz.

Im Referenzplan mit gSCR war bei 1e-6 pu Toleranz keine der 6.216 Bedingungen bindend. Der kleinste Slack betrug 0,047706 pu an `HR1 0`. Die Nachrechnung des Plans ohne gSCR ergibt 835 negative Zeilen an neun Knoten, davon jeweils alle 168 Stunden an `AL1 0`, `HR1 0`, `LU1 0` und `MK1 0`. Die stündlichen Angaben stehen in `COMPARE_GSCR_01/baseline_gscr_slacks.csv` und `COMPARE_GSCR_01/no_gscr_g1_negative_slacks.csv`.

Die lokalen Receipts liegen unter `E:/ResearchResults/FlexPlan_UC_GSCR/ORCH_FULL37_SEQUENTIAL_117_20261113_01/TECH_FULL37_KW03_2013_168H_20261114_01`. `COMPARE_GSCR_01/comparison.json` hat SHA‑256 `3bc8fe13230ced2f0ff2dfa3077e33ca34c59a0f92c516082b9532d0272b226b`. `WIND_PV_50_ANNUAL_02/annual_50_comparison.json` hat SHA‑256 `e8958d3837e6f5218cb53af63e6ea4927539beb04667852ee37a3222cb384b2a`. Die Run-Summaries für 60 % unter `WIND_PV_60_70_ANNUAL_05/60` haben mit und ohne gSCR die SHA‑256-Werte `cfeeb28e67a1ad94ad796d03c884c483f6ca21cff5836824e1f28902f642e5fb` und `c828718128f5a13da25382bcebd0518f071fecb263649ac9c2b30ed12d112738`.

### KW 3 · Wiederholung bei 70 % Wind und PV

Der gemeinsame Ausbau-/Dispatchlauf mit gSCR fand nach 2.620 s einen zulässigen ganzzahligen Plan und endete mit `SOLUTION_LIMIT` bei 63,64 % Gap. Die unabhängige Nachrechnung bestätigte die 70‑%-Quote, die 111.401 ganzzahligen Variablen, 6.216 gSCR-Zeilen und die Ausbaugrenzen. Der vorhandene Lauf ohne gSCR erreichte seine Solvertoleranz mit 0,0122 % Gap.

| Ergebnis | Mit gSCR | Ohne gSCR |
|---|---:|---:|
| Kosten bei OPEX ×52, Mrd. EUR2025 | 424,478 | 140,724 |
| Dieselben Ausbau- und Fahrpläne bei OPEX ×365/7, Mrd. EUR2025 | 424,633 | 140,777 |
| Gaszubau GuD / OCGT, GW | 73,958 / 552,812 | 0 / 0 |
| Batteriezubau GFL / GFM, GW | 1.174,425 / 491,575 | 37,550 / 0 |
| Gasdispatch in 168 h, TWh | 9,406 | 0,783 |
| Batterieentladung in 168 h, TWh | 19,046 | 2,821 |

Die Differenz aus der besten ganzzahligen Untergrenze mit gSCR und dem zulässigen Kostenwert ohne gSCR beträgt 13,613 Mrd. EUR2025 im ursprünglichen ×52-Modell. Die mit 365/7 nachgerechneten Kosten bewerten die gleichen Entscheidungen. Für diese Zielfunktion existiert in dieser Studie keine neu ermittelte Solveruntergrenze. Die ganzzahligen Ausbauwerte mit gSCR sind wegen des offenen Gaps als Machbarkeitsbeleg zu lesen. Die getrennte kontinuierliche KW‑3-Relaxation kostete 154,336641 Mrd. EUR2025 bei ×52.

Originaler 168‑h-Case SHA‑256 `e0f701dfaec2daf5e18170663640fc8ec4893fa5b887fec3aa8ed01f8f646ea2`. Independent-Objective-Receipt SHA‑256 `545e86293f4fe5e9da7f734dfdd39ebbc53ea79709d4f1452eccd2a88c384316`.

## Makro 139 · Q5-Identität und Speicherprofil

| Komponente | Lokaler Codecommit | Tatsächliche Prüfung |
|---|---|---|
| Consumer | `4a78a9b6afb8e1a192c169073d43fffd8acc7330` | G2-Numeric-Digest aus den 37 Originalwerten korrigiert und separat an Datei und rationalen Vektor gebunden. G0–G3 und Negativfälle in 105 unabhängigen Assertions geprüft. |
| Producer | `becec6d63c0fbf2b8a160c41f87631f5270046b9` | Optionaler AP1-Exportmodus teilt exakt gleiche Gerätezeilen. In der 384-Snapshot-Probe sank der gehaltene Heap von 1,118 GB auf 0,361 GB. Der 168‑h-Export war byteidentisch. 18 unabhängige Vergleiche am Producer und 14 unabhängige Assertions beim AP2-Import bestanden. |

Beim bisherigen Volljahresversuch griff die damalige AP1-Grenze von 16 GiB Private Bytes vor der Ausgabe. Danach maß die AP2-Probe auf 168 Stunden 1,055 GB gehaltenen Heap nach Modellaufbau und 3,171 GB maximale Private Bytes. Die hochgerechneten 53,2 GB zusätzlicher Live-Heap für den aktuellen Jahrespfad sind eine Größenordnung aus der Probe. Für die 8.760 Stunden wurde kein tatsächlicher AP2-Peak gemessen. Das 20‑GiB-AP2-Profil qualifizierte sich auf diesem Host nicht. Der eingefrorene Fall wurde im neuen Pfad bis zur 168‑h-Byteparität geprüft. Ein neuer Jahres-Case-SHA, Q5-PASS, F1 sowie Gate J fehlen.

R2-Receipt SHA‑256 `377860d9027634866eb92a66132c795208361d0256591a2cedfb40091d3bc58b`. Das nächste Full37-Gate erfordert nachweislich ausreichende RAM-/Commit-/E:-Reserven oder einen unabhängig geprüften speicherbegrenzten AP2-Reader und Modellaufbau. Danach folgen ein vollständiger AP1-Export, AP2-Readback auf genau diesen Bytes, das unabhängig qualifizierte F1-Solverprofil und Gate J nach tatsächlichem F1-Ergebnis.

Während der 840‑h-Rechnung lag der Windows-Commitrahmen bei rund 56,9 GiB, einschließlich 8 GiB Auslagerungsdatei auf E:. Physisch stehen 31,2 GiB zur Verfügung. Der freie Platz auf E: betrug bei dieser Probe 12,5 GiB. Für die Jahresrechnung müssen Reader, Modellaufbau, Solver und die gleichzeitig benötigten Ausgabedateien vor demselben Lauf qualifiziert werden.

## 840 h · 50 % Wind und PV

Aus den vollständigen ISO-Wochen 2–52 im Originaljahr 2013 wurde die jeweils nächste Woche zum Mittelwert eines von fünf zeitlich zusammenhängenden Jahresabschnitten ausgewählt. Die Distanz nutzt die Streuung der Wochenmittelwerte von Systemlast, verfügbarer Wind- und PV-Leistung des Bestands und Speicherzufluss. Die Auswahl wurde vor den Optimierungsergebnissen festgeschrieben.

| KW | Stunden, inklusive | 1-basierte Originalindizes | AP1-Case-SHA‑256 |
|---:|---|---|---|
| 8 | 18.02. 00:00–24.02. 23:00 | 1153–1320 | `f4b66af21fe59240eaa236698cf371458ce1cc22cdd3c25d9af9aafa92c4939d` |
| 15 | 08.04. 00:00–14.04. 23:00 | 2329–2496 | `0b8ddf09637eef2fcb0ee7f08ad9dd243a309acf8a2e451a4a1461b121dc7d17` |
| 27 | 01.07. 00:00–07.07. 23:00 | 4345–4512 | `ab1995ed56f2f8922f98dd176adb8bb3facb3f3fba7417781f6e985e3092039e` |
| 39 | 23.09. 00:00–29.09. 23:00 | 6361–6528 | `0140cb335433dde584057c2e54408ec507cab9cfb398737b013c3ceccfe1ac80` |
| 45 | 04.11. 00:00–10.11. 23:00 | 7369–7536 | `99e59862c173c7f18ef604b9c9b725a28e20a9968b0e69ceb627d75a5b610d2d` |

Auswahl-Receipt SHA‑256 `88d30f72eb2e8edb176fb7eb75b413a99d6b14228005b3792753365eb990d9d3`. Alle fünf 168‑h-Teilnetze sind Teil **eines** JuMP-Modells. 1.412 Gleichungen koppeln dieselben installierten Gas-/Speicherblöcke über alle Perioden. Die 74 kontinuierlichen Onshore-Wind- und PV-Ausbauvariablen werden direkt geteilt. UC, Speicher und eine physische Stundendauer von 1 h gelten je Periode. Die Modelle übernehmen die nativen Speicher-Randbedingungen und schließen zyklische Speicher innerhalb jeder Woche. Ein gemeinsamer Quotenwert über alle 840 Stunden verlangt positive Einspeisung aus Onshore-/Offshore-Wind und PV von mindestens 50 % der Lastsumme. Die Lastsumme beträgt 310,822 TWh.

Der Zielfunktionsfaktor für alle 840‑h-Betriebskosten einschließlich Starts und Stopps beträgt genau 73/7. Die annualisierten Investitionskosten des gemeinsamen Portfolios gehen einmal ein. Die Vergleichsvariante entfernt genau 31.080 G1-Zeilen. Die G1-Variante ist eine hinreichende Bedingung auf der verwendeten DCP-Systemstärke-Domäne. Sie macht keine Aussage über reale AC-/PQVI- oder dynamische Zulässigkeit.

Der Modellmarker lautet `reservoir_no_gscr_oil_coal_minimum_v1`. Das Szenario verwendet `MIXED` mit GFL- und GFM-Batterien, jeweils 25 MW und 25 MVA je Block sowie 4 h Speicherdauer. Der GFM-Aufschlag beträgt 20 %. Die G1-Schwelle ist `alpha=1`. Der Wind-/PV-Ausbau verwendet native Profilgrenzen und die Kostendatei `paper_a_2040_cost_bridge_candidate.csv` mit SHA‑256 `ec344ecd4c191595b054f5d66474b82f8079069ee6fa2ef0c7e1223de436d8e5`. Die vorhandenen thermischen UC-Koeffizienten und Ausbaugrenzen der eingefrorenen Ausgangsdaten gelten periodengleich.

### Rechenstand und Hindernisse

- Der AP1-Export aller fünf Wochen dauerte 235,562 s. Die gemessene Private-Bytes-Spitze betrug 1,312 GB. Das gemeinsame AP2-Modell umfasst 1.556.679 Variablen und davon 557.005 Ganzzahlvariablen. Der gehaltene Julia-Heap nach Modellaufbau lag bei rund 5,252 GB.
- Der G1-Ganzzahllauf erreichte nach 2.401,768 s `TIME_LIMIT`. Gurobi fand keinen ganzzahligen Plan. Die ausgewiesene untere Schranke von 73,835619339 Mrd. EUR2025 stammt aus dem Root-Knoten dieses 840‑h-Modells. Die erste Barriere-Relaxation meldete ein Optimum, der anschließende gSCR-Residuencheck wies den Kandidaten zurück. Der Prozess erreichte maximal 15,092 GB Private Bytes einschließlich des LP-Versuchs.
- Die zweite Barriere-Rechnung mit gSCR ohne Crossover meldete `LOCALLY_SOLVED` bei 73,835599577 Mrd. EUR2025. Der kleinste unskalierte gSCR-Slack betrug −0,001980756 pu. 609 gSCR-Zeilen unterschritten die Grenze um mehr als 1e-6 pu. Der Kandidat ist zu Diagnosezwecken gespeichert. Beim Wechsel zum Gegenlauf verbrachte der Adapter Zeit mit 31.080 einzelnen Löschungen im aktiven Gurobi-Backend. Der belegte Stopp erfolgte vor `solve_enter` des Gegenlaufs.
- Für den Crossover-Lauf wurde das Solver-Backend vor dem Variantenwechsel abgehängt. Die G1-Zeilen wurden gesammelt am JuMP-Modell entfernt und der Ganzzahllauf ohne gSCR gestartet. Die LP-Rechnung mit gSCR erreichte nach 3.300,267 s `TIME_LIMIT` ohne ausgegebene Lösung. Das Log dokumentiert einen Neustart des Crossover nach dem Verlust einer Basisvariablen.
- Der Ganzzahllauf ohne gSCR endete nach 2.400,687 s mit einem zulässigen Plan und 95,6805 % Gap. Die Untergrenze beträgt 70,111040156 Mrd. EUR2025. Der Plan erreicht 72,083 % Quote und kostet 1.623,120 Mrd. EUR2025 bei 1.594,126 Mrd. CAPEX. Ausbau und Kosten dieses weit von der Schranke entfernten Plans belegen die Machbarkeit. Der anschließende Variantenvergleich wertet die kontinuierlichen Läufe getrennt aus.
- Die kontinuierliche Rechnung ohne gSCR meldete nach 349,034 s `OPTIMAL`. Die maximale Systembilanzabweichung aus dem Stundenreplay beträgt 8,09e-7 MW. Die nachträgliche Auswertung der deaktivierten G1-Zeilen findet 17.643 Unterschreitungen bei 1e-6 pu Toleranz.
- Der Wiederanlauf mit gSCR verwendete `Crossover=2`, `CrossoverBasis=1`, `NumericFocus=2`, `AggFill=0` und eine primale Solvertoleranz von 1e-9. Die Simplex-Nachbereinigung endete nach 5.400,155 s mit `TIME_LIMIT / NO_SOLUTION`. Die Private-Bytes-Spitze betrug 11,055 GB ohne Ressourceneingriff. [Gurobi-Parameterreferenz](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#crossoverbasis)
- Ein weiterer Barrierelauf ohne Crossover verwendete die durch 128 dividierte, mathematisch äquivalente Quotenzeile und die interne Zielfunktionsskalierung `ObjScale=1024`. Der Lauf mit `Aggregate=0`, `BarHomogeneous=1`, `ScaleFlag=2` und `NumericFocus=3` endete beim Unterschreiten der konfigurierten physischen Hostreserve von 2 GiB. Die Prozessspitze lag bei 10,388 GB Private Bytes. Der Lauf hat keinen Plan ausgegeben. [Gurobi-Parameterreferenz](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#objscale)

Beide Ganzzahlläufe bearbeiteten nur den Root-Knoten. Ohne gSCR fand der Solver erst am Zeitlimit zwei zulässige Pläne. Der zweite verbesserte die Zielfunktion von rund 1.630,237 auf 1.623,120 Mrd. EUR2025, während die untere Schranke bei 70,111 Mrd. blieb. Der MIP-Gap sank von rund 95,70 % auf 95,68 %. Mit gSCR fehlte ein zulässiger Ganzzahlplan zur Berechnung des Gaps.

Der relative Abstand der primalen und dualen Barriere-Zielwerte ohne gSCR fiel von 30,5 % bei Iteration 30 auf 0,51 % bei Iteration 50, 0,021 % bei Iteration 70 und 0,00068 % bei Iteration 108. Diese Zwischenwerte haben noch primale oder duale Residuen. Der Solver meldete den optimalen LP-Wert erst nach Crossover und Simplex-Nachprüfung.

### Vergleich von Ausbau, Dispatch und Kosten

| Kennzahl | Mit gSCR, numerischer LP-Kandidat | Ohne gSCR, geprüftes LP-Optimum | Ohne gSCR, geprüfter Ganzzahlplan |
|---|---:|---:|---:|
| GuD / OCGT, Ausbau in GW | 0 / 4,803 | 0 / 3,699 | 0 / 3,900 |
| Batterie GFL / GFM, Ausbau in GW | 19,880 / 3,336 | 43,388 / 0 | 43,500 / 0 |
| Onshore-Wind / PV, Ausbau in GW | 194,045 / 477,825 | 156,616 / 516,560 | 156,563 / 516,436 |
| Gasdispatch in 840 h, TWh | 17,788 | 13,284 | 13,285 |
| Batterie Laden / Entladen in 840 h, TWh | 4,055 / 3,893 | 8,351 / 8,017 | 8,587 / 8,243 |
| Wind-/PV-Einspeisung in 840 h, TWh | 155,411 | 155,411 | 155,411 |
| Annualisierte CAPEX, Mrd. EUR2025 | 44,469928 | 42,628893 | 42,636088 |
| Annualisierte OPEX, Mrd. EUR2025 | 29,365672 | 27,482147 | 27,482406 |
| Annualisierte Gesamtkosten, Mrd. EUR2025 | 73,835600 | 70,111040 | 70,118494 |

Die gSCR-Spalte stammt aus `with_gscr/relaxed_retry` und dokumentiert einen Solver-Kandidaten mit 609 gSCR-Verletzungen. Sein Ausbau und Dispatch haben Diagnosewert. Die Wind-/PV-Summe von 155,411 TWh entspricht in allen drei Rechnungen 50 % der Lastsumme. Die CAPEX/OPEX-Summen wurden mit der Gewichtung 1 und 73/7 nachgerechnet.

Für den ursprünglichen 840‑h-Fall beträgt der Abstand zwischen der nativen Solveruntergrenze mit gSCR und den geprüften Ganzzahlkosten ohne gSCR 3,717125670 Mrd. EUR2025. Sofern das ursprüngliche gSCR-MIP zulässig ist, liefert dieser Abstand aus Solveruntergrenze und zulässiger Obergrenze eine einseitige Untergrenze des Kostenunterschieds der beiden ganzzahligen Optima. Der genaue Kostenunterschied und die Portfolioänderung mit gSCR bleiben bis zu einem geprüften gSCR-Plan offen.

### MIP-Starts und Reparaturläufe

Der angeforderte MIP-Start verwendet je Variante ihr eigenes LP-Portfolio. Der Adapter prüft die 148 ausbaubaren Anlagen gegen ihre nativen Blockgrenzen und 74 gemeinsame Gas-/BESS-Knotendeckel. Er verwendet aufgerundete `n_inst`-Werte als Teilstart und fällt bei einem verletzten Deckel auf abgerundete Werte zurück. Die identischen Startwerte gelten in allen fünf Wochen. Gurobi vervollständigt bei Annahme UC-Ereignisse, Dispatch und Speicherzustände. Ein vollständig geprüfter zulässiger Plan liefert eine obere Schranke. [Gurobi-Dokumentation zu MIP-Starts](https://support.gurobi.com/hc/en-us/articles/360043834831-How-do-I-use-MIP-starts)

Fehlt ein geprüfter LP-Plan oder scheitert die Vervollständigung, verwendet ein separater MIP-Reparaturlauf die Untergrenze `floor(n_inst_LP)` und die Obergrenze `ceil(n_inst_LP)+1` innerhalb der ursprünglichen Assetgrenzen. Alle übrigen Bedingungen einschließlich aktiver G1-Zeilen bleiben Teil der Reparatur. Die Box begrenzt ausschließlich die Suche nach einem Startplan. Nach Wiederherstellung der ursprünglichen Grenzen kann der Hauptlauf den reparierten Plan als Start verwenden. Der Versionsstand wurde mit einem Test für gemeinsame Ausbaugrenzen, Startwerte, engere Intervalle und Rückkehr zu den ursprünglichen Grenzen geprüft.

Für die gSCR-Reparatur wird der gespeicherte Barrierekandidat mit der geringsten belegten Modellverletzung verwendet. Der direkte Teilstart ohne gSCR verwendet die geprüfte LP-Lösung. Die beiden gespeicherten Portfolios bestanden die Prüfung für 148 ausbaubare Anlagen und 74 Knotengrenzen auf den tatsächlichen AP1-Eingängen. Die MIP-Wiederholung verwendet zwei Solverthreads, 2.400 s je Hauptlauf und höchstens 1.800 s je Reparatur.

Die gSCR-Reparatur hob bei den fünf periodischen Kopien insgesamt 85 Untergrenzen an und senkte 740 Obergrenzen ab. Sie endete nach 1.800,173 s im Crossover der Wurzelrelaxation mit `TIME_LIMIT / NO_SOLUTION`. Für den geplanten Wiederanlauf mit gSCR fehlte damit ein reparierter Startplan. Die ursprüngliche gSCR-Schranke von 73,835619339 Mrd. EUR2025 gehört weiter zum unveränderten 840‑h-MIP.

Der direkte Start ohne gSCR übermittelte das aufgerundete Portfolio als 740 Teilstartwerte. Gurobi meldete `User MIP start did not produce a new incumbent solution` und einen Rest von 0,040824829 an der internen Solverzeile `R18573`. Der Lauf endete nach 2.400,172 s mit `TIME_LIMIT / NO_SOLUTION` bei unveränderter unterer Schranke von 70,111040156 Mrd. EUR2025. Anschließend startete die Reparatur mit engen Blockintervallen.

Der Modellbauer hatte zusätzlich Startwerte für `n_active` und weitere Variablen gesetzt. Die 740 aus dem LP abgeleiteten Werte waren daher Teil eines gemischten Startvektors. Der korrigierte Teilstartadapter löschte am tatsächlichen Modell 1.171.045 vorhandene Startattribute und prüfte anschließend genau 740 gesetzte Ausbauwerte. Ein Julia-Test bestätigte die Entfernung vorhandener Betriebsstartwerte bei erhaltener Ganzzahligkeit. Die Modellgleichungen einschließlich des UC-Anfangszustands sind unabhängig von diesen Solverattributen.

Die Reparatur ohne gSCR hob 40 Untergrenzen an und senkte 740 Obergrenzen ab. Sie endete nach 1.800,100 s mit `TIME_LIMIT / NO_SOLUTION`. Der Prozess mit beiden Start- und Reparaturvarianten hatte 13,438 GB Private Bytes und 10,869 GB Working Set in der Spitze.

Der bereinigte Teilstart ohne gSCR wurde nach 1.746,32 s Vervollständigung geladen. Der Hauptlauf endete nach 2.330,890 s mit `OPTIMAL` zur Solvertoleranz. Aus dem Zielfunktionswert 70,118493669 Mrd. EUR2025 und der Schranke 70,111040156 Mrd. EUR2025 ergibt sich 0,0106299 % Gap. Der zuvor gespeicherte Ganzzahlplan hatte 95,6805 % Gap. Der neue ganzzahlige Plan liegt 7,454 Mio. EUR2025 über dem LP-Optimum. Die Prüfung umfasste 353 Blockanlagen, 74 Knotendeckel und 840 Stundenbilanzen. Die größte Abweichung der nachgerechneten stündlichen Systembilanz betrug 1,31e-5 MW. Die Ganzzahlabweichung war null. Der Prozess erreichte 12,047 GB Private Bytes und 9,801 GB Working Set.

Die angeforderte Wiederholung mit gSCR übernimmt dieselben Eingänge, dieselben Reparaturintervalle und das Zweithread-Profil. Beide Reparaturläufe haben den Gurobi-Modellfingerprint `0x393bd2fe`. Das konfigurierte Solverbudget beträgt insgesamt 7.195 s mit fünf Sekunden Puffer zur Obergrenze von 7.200 s. Wenn die Reparatur einen geprüften Plan findet, steht nur die verbleibende Zeit für dessen Einsatz im unveränderten Haupt-MIP zur Verfügung. Modellaufbau und Replay werden separat gemessen.

Die Wiederholung löste die Wurzelrelaxation nach rund 1.723 Solver-Sekunden mit null gemeldeter primaler und dualer Simplex-Verletzung. Nach 7.195,186 s und 445.764 Simplex-Iterationen am einzigen bearbeiteten Knoten endete sie mit `TIME_LIMIT / NO_SOLUTION`. Die Solveruntergrenze von 73,861375250 Mrd. EUR2025 gehört zu den eingeschränkten Blockintervallen. Die Schranke des ursprünglichen gSCR-MIP bleibt 73,835619339 Mrd. EUR2025. Ein zulässiger gSCR-Plan und damit ein MIP-Gap blieben offen. Der Lauf erreichte 13,433 GB Private Bytes und 10,937 GB Working Set ohne Ressourceneingriff.

### Prüfung der Stärkebedingung vor einer Wiederholung

Am 17. November 2026 wurden auf Owner-Anfrage die gespeicherten 840‑h-Eingänge, Solverreceipts und Rundungsadapter gezielt nachgeprüft. Das Specification Gate betrifft die vorhandene G1-Ungleichung, ihre Vorzeichen, Quellenkoeffizienten und die Folgen einer Aufrundung aktiver Quellen. Der Audit führte keine Optimierung aus.

Die ausgeführte G1-Zeile hat die Form

\[
m_{i,t}=\sigma_i^0+b_i^{fix}
+\sum_{k\in\mathrm{SYN}\cup\mathrm{GFM}}\mu_k^{str}b_k z_{k,t}
-\alpha\left(
\sum_{k\in\mathrm{GFL}}\mu_k^{fl}\frac{P_k^{block}}{S_{base}}n_{k,t}^{active}
+\sum_{r\in\mathrm{neue\ Wind/PV}}\frac{a_{r,t}^{res}\Delta P_r}{S_{base}}
\right)\ge0.
\]

`_paper_a_g1!` in `src/core/paper_a_integration.jl` erzeugt die Zeile. `_paper_a_online_expressions!` verwendet für thermisches UC den aktiven Blockzähler. Bei `SELECTIVE_SYN` und `PHS_SYN` liefert `_paper_a_strength_count` in `src/core/paper_a_full37.jl` den eigenen gutgeschriebenen Quellenzähler `paper_a_strength_blocks`. Die 20‑%-PHS-Erzeugungsschwelle und die Erzeugungsschwellen selektiver SYN-Quellen sind an diesen Zähler gekoppelt.

Bei festgehaltener GFL-Seite und nichtnegativen Quellenkoeffizienten gilt

\[
\Delta m_{i,t}
=\sum_k\mu_k^{str}b_k\left(\lceil z_{k,t}\rceil-z_{k,t}\right)\ge0.
\]

Die Aufrundung positiv angerechneter Quellen erhält damit eine bereits erfüllte G1-Zeile. Bei einem negativen Ausgangsrest muss die tatsächliche Verbesserung am betroffenen Knoten mindestens dessen Betrag erreichen. Das Aufrunden von `n_inst` allein ändert die Zeile nicht. Bei selektiven Quellen reicht auch eine Änderung von `n_active` ohne den gutgeschriebenen Quellenzähler nicht.

| Feststellung | Tatsächlicher Beleg | Bedeutung für die Rundung |
|---|---|---|
| GFM besitzt im eingefrorenen Fall keine statische Stärkegutschrift. | Alle 37 GFM-Kandidaten an allen 840 Stunden haben `b_block=mu_str=mu_fl=0` und `GFM_ZERO_STRENGTH`. | Eine GFM-Aufrundung verändert den G1-Slack um exakt null. Der Quellenkoeffizient entspricht der übernommenen Fallentscheidung. |
| Die bisherigen Adapter rundeten installierte Kapazitäten. | `apply_capacity_start!` und `tighten_capacity_bounds!` in `run_joint_weeks_mip_start.jl` verarbeiten `n_block`. | Eine Aufrundung der tatsächlichen stündlichen Quellenzähler wurde damit noch nicht ausgeführt. |
| Der gespeicherte LP-Kandidat verfehlt die unskalierte Prüfung. | 609 G1-Zeilen unter −1e-6 pu, kleinster Slack −0,001980756 pu, Status `LOCALLY_SOLVED`. | Der Ausgangskandidat erfüllt die Voraussetzung einer zulässigen LP-Lösung für eine automatische Erhaltung nicht. |
| Der eigene Zähler für gutgeschriebene Quellen ist erforderlich. | Selektive SYN- und PHS-Zeilen koppeln Stärke an Mindestproduktion und PHS-Erzeugungsmodus. | Allein höhere angeschlossene oder installierte Blockzahlen liefern keine zusätzliche Gutschrift. |
| Vollständige LP-Blockzähler wurden nicht exportiert. | `summarize` und `fill_dispatch` speichern Ausbau und Leistung, aber keine vollständigen `na_block`-, Quellen-, Pump-, Start-/Stopp- und SOC-Vektoren. | Der ursprüngliche Plan lässt sich nachträglich nicht exakt aufrunden oder zeilenweise aus diesen Dateien rekonstruieren. |

Die Leistungsgrenzen verlangen nach einer Aufrundung einen neuen Dispatch. Ein konkretes Beispiel aus dem gespeicherten LP ist `EE6 0 OCGT` am 18. Februar 2013 um 00 Uhr. Bei 36,261057 MW Erzeugung, 300 MW Blocknennleistung und `p_min_pu=0.2` erfordert mindestens ein aktiver Ganzzahlblock 60 MW Erzeugung. Die Aufrundung verlangt hier mindestens 23,738943 MW zusätzliche Erzeugung. Der Fahrplan muss diese Leistung bilanziell aufnehmen. Thermische Mindestzeiten, Start-/Stopplogik und Speicherzustände gehören ebenfalls zur Reparatur.

Eine zusätzliche notwendige Bedingung wurde für alle 31.080 Knotenstunden aus dem gespeicherten LP-Dispatch nachgerechnet. Verwendet wurden eine möglichst hohe Stärkegutschrift bei diesem Dispatch und eine möglichst geringe erforderliche GFL-Exposition. Selbst bei aufgerundeter installierter Kapazität unterschreitet die Obergrenze des erreichbaren G1-Slacks für ganzzahlige Quellenzähler an 12.963 Knotenstunden −0,01 pu. Damit erfordert die ganzzahlige Reparatur eine Anpassung des Dispatch. Diese Schrankenrechnung rekonstruiert keine fehlenden LP-Zähler und trifft keine Aussage über die Zulässigkeit einer neuen gemeinsamen Optimierung.

Die tatsächlichen Produktionsfunktionen wurden an den 37 G1-Zeilen und 353 quellmarkierten Anlagen mit 15.764 Assertions ohne Solver geprüft. Geprüft wurden Quellen-/GFL-Vorzeichen, MW-/100‑MVA-Normierung, die Wahl separater Quellenzähler, die monotone Wirkung positiver Quellenaufrundung, die Nullwirkung der 37 GFM-Kandidaten und ein Mindestleistungsgegenbeispiel. Der passive Matrixstempel wurde separat aus den physischen Pi-Leitungsdaten rekonstruiert. Seine größte Abweichung vom Fallwert betrug 5,68e-14 pu. Im geprüften algebraischen Codepfad wurde kein Vorzeichen- oder Quellenbasisfehler gefunden.

Ein negativer G1-Slack bedeutet eine verletzte hinreichende Gershgorin-Bedingung. Er beweist für sich allein keine Verletzung des exakten spektralen gSCR-Kriteriums. Für diese Prüfung werden die tatsächlichen B-/S-Zustände und die zugehörige Matrixdomäne benötigt. Die ausgewerteten `TIME_LIMIT / NO_SOLUTION`-Läufe liefern ebenfalls keinen Unzulässigkeitsbeweis. Die 17.479 negativen Zeilen des geprüften Ganzzahlplans ohne gSCR sind eine nachträgliche Auswertung der in diesem Modell deaktivierten G1-Zeilen.

Die gezielten Receipts liegen im Studienverzeichnis unter `ROUNDING_DIAGNOSIS_20261117_01`. `input_and_dispatch_audit.json` bindet die fünf Eingangs-SHAs und hat SHA‑256 `573d3abd64a0ebcf2705d3ca01a8143521c399ecc6577d20c4be768187ff217d`. `production_row_receipt.json` dokumentiert die Produktionsfunktionsprüfung mit SHA‑256 `4af3c3e9a7b70375904ddaa13cf44368e8ea3aa7e30898b30df64468a6f9ece6`. `fixed_dispatch_examples.json` enthält die Leistungsbeispiele mit SHA‑256 `158c8a1df62259cd5b1caadb85afde1a157541f1cc30356e00e5a33df59adb81`. Die beiden CSV-Dateien dokumentieren die notwendigen Stärkeschranken je Knotenstunde und die stündlichen Grenzen einer Reparatur bei festem Dispatch.

Die erweiterte Owner-Anfrage vom 17. November präzisiert einen positiven GFM-Stärkebeitrag als Ziel. Der bestehende Nullansatz hat eine konkrete Vorgeschichte. Im eingefrorenen Register 35 ist `COLIB-EPRI-GFM-XF=0.15` als Filterreaktanz belegt. Die Einträge `GFM_XF_AS_UNIVERSAL_STATIC_XSRC` und `GFM_XV_AS_UNIVERSAL_STATIC_XSRC` schließen dessen automatische Verwendung als universelles statisches Quellenäquivalent aus. Darauf beruhte der zwischenzeitlich gewählte Fall ohne GFM-Stärkegutschrift; Governance-Dokumente 119 und 127 behalten diesen Fallumfang ausdrücklich bei. Der Producer setzt in `src/paper_a_full37.jl` die Partizipationskoeffizienten entsprechend auf null und der Consumer erzwingt den Fallmarker `GFM_ZERO_STRENGTH`. Das Ergebnis beschreibt damit die derzeit angerechnete Modellwirkung. Die weitere Quellenprüfung zeigt: Positive Zahlen und historische Quellenannahmen sind vorhanden. Offen ist ihre qualifizierte Übernahme als effektives Quellenmodell mit festgelegter Betriebs-/Reglerdomäne.

Die gezielte historische Prüfung fand in allen fünf ursprünglichen Full37-Carrier-Tabellen `BESS-GFM: b_gfm=5 pu_device, S_block=100 MVA`, entsprechend `b_block=5 pu_system` auf 100 MVA. Das Producer-Register `data/paper_a_study/parameter_registry.csv` am Commit `b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c` enthält zusätzlich 135 GFM-Zeilen für `x_src`, `b_block` und `mu_str` über neun historische parametrische Szenarien: Referenz `x_src=0.2`, Sensitivität `0.3`, jeweils `mu_str=1`. Diese Szenarien waren `qualified_parametric`; ihre Zeilen tragen ausdrücklich keine empirische Freigabe. Damit wäre die pauschale Aussage, GFM-Parameter fehlten, unzutreffend.

Der Vergleich verwendet zur Trennung von Blockgrößen und Geräteparametern hypothetisch für jede Zeile denselben 25-MVA-Klassenblock, 100 MVA Systembasis und konsistente Spannungsbasen. Für ein bereits zulässiges rein induktives Quellenäquivalent gilt `b_block=S_block/(S_base*x_device)`. Die Skalierung des 900-MVA-Kundur-Benchmarks auf gleich parametrierte Klassenblöcke ist eine Modellannahme; sie ist keine Basenumrechnung derselben physischen Maschine.

| Parameterfall | Gerätewert | Koeffizient eines 25-MVA-Blocks auf 100 MVA | Einordnung |
|---|---:|---:|---|
| CoLib-SYN, im aktuellen Fall verwendeter Klassenproxy | `x''d=0.25` | 1.000000 pu | Subtransienter Quellenansatz. |
| Historischer GFM-Referenzfall | `x_src=0.20` | 1.250000 pu | Parametrische Quellenannahme; 25 % über dem gleich großen SYN-Block. |
| Historische GFM-Sensitivität | `x_src=0.30` | 0.833333 pu | Parametrische Quellenannahme. |
| CoLib/EPRI-GFM-Filter | `Xf=0.15` | 1.666667 pu, nur formale Filterinversion | 66,7 % über SYN; noch kein qualifizierter statischer Quellenkoeffizient. |

Die CoLib-Prüfung ist an Commit `16d6171513fd1adf900d51a0ec664888d66b274a` gebunden. Das [EPRI-GFM-Modell](https://github.com/CRESYM/Colib_Quarto.github.io/blob/16d6171513fd1adf900d51a0ec664888d66b274a/models/4-HVDC/VSC/GridFormingConverter/EPRI-GFM-Converter/index.qmd) bestätigt `Xf=0.15`, `Rf=0.0015` und `Te=0.01 s` sowie Droop-, VSM- und dVOC-Reglermodi. Der Filterwert wird in der Tabelle nicht nach diesen Modi unterschieden. Das Modell ist eine besser belegte Grundlage für eine gezielte GFM-Modellqualifikation als der alte pauschale Stärkewert. Seine Parameter allein belegen jedoch keine universelle statische Ausgangsimpedanz. Die ebenfalls am selben CoLib-Commit vorhandenen [UPC-RMS](https://github.com/CRESYM/Colib_Quarto.github.io/blob/16d6171513fd1adf900d51a0ec664888d66b274a/models/4-HVDC/VSC/GridFormingConverter/UPC-RMS-GFM-VSC/index.qmd)- und UPC-EMT-GFM-Modelle liefern eine LCL-Struktur mit Reglern. Ihre Tabellen nennen 2,45 kV, `R=0.0326 Ohm, L=0.001038 H` für den netzseitigen Zweig, `R=0.0048913 Ohm, L=0.00031139 H` für den konverterseitigen Zweig und `C=1.63e-4 F`. Die geprüften Seiten nennen dafür keine ausdrückliche MVA-Nennbasis. Sie liefern daher keinen unmittelbar einsetzbaren alternativen Geräte-p.u.-Quellenwert für den 25-MVA-Block. Das He-`x_v=0.20` bleibt eine getrennte controllergebundene Referenz; Werte aus unterschiedlichen Modellfamilien werden nicht zu einer neuen Serienimpedanz kombiniert.

Für die zusätzliche Kurzschlussfrage wurde die lokal installierte PowerMCP-Version 0.5.1 mit Pandapower 3.5.6 geprüft. Der installierte Pandapower-MCP-Adapter bietet keinen Kurzschlussaufruf. Deshalb erfolgte der kleine Vergleich direkt mit `pandapower.shortcircuit.calc_sc` im selben Python-Environment; ein MCP-Toolaufruf wird nicht behauptet. Der tatsächlich installierte Quellpfad `shortcircuit/ppc_conversion.py::_add_gen_sc_z_kg_ks` liest `gen.xdss_pu` und bildet daraus `X_gen_ohm=xdss_pu*V_gen_kV^2/S_gen_MVA`. Dies entspricht der dokumentierten subtransienten Reaktanz für die anfängliche symmetrische Kurzschlussstromberechnung nach IEC 60909. [Pandapower-Generatorparameter](https://pandapower.readthedocs.io/en/latest/elements/gen.html) [Kurzschlussberechnung](https://pandapower.readthedocs.io/en/latest/shortcircuit/run.html)

Der synthetische 100-MVA-/20-kV-Einbus-Test mit `cos_phi=1`, `rdss=0`, ohne Leitung oder Transformator ergibt bei `x''d=0.25` exakt `S''k=400 MVA`. Eine Änderung zusätzlich hinterlegter transienter Reaktanzspalten von 0,30 auf 0,60 lässt dieses Ergebnis unverändert. Als gezielte falsche Eingaben in das Feld `xdss_pu` ergeben 0,30 nur 333,333 MVA und die Summe 0,25+0,30 nur 181,818 MVA. Dies veranschaulicht den Fehler der Regimeverwechslung; es sind keine zulässigen alternativen Anfangskurzschlussmodelle. Für den auf anfänglicher Kurzschlussleistung beruhenden klassischen SCR ist `x''d` der passende Maschinenparameter. `x'd` gehört zur transienten Zeitdomäne und wird nicht zu `x''d` addiert oder parallel als zweite Quelle angerechnet. Für ein zeitabhängiges Maschinenmodell können beide Parameter mit ihren Zeitkonstanten benötigt werden. Das ersetzt keine Domänenprüfung eines eigenständigen gSCR-Stabilitätskriteriums und macht einen GFM-Filter nicht zu einem unbegrenzt kurzschlussfähigen Synchrongenerator.

Die neuen kompakten Belege liegen unter `ROUNDING_DIAGNOSIS_20261117_01/GFM_COLIB_SHORT_CIRCUIT_20261117_01` im Studienverzeichnis. `parameter_history_and_colib_receipt.json` hat SHA-256 `9bd0dba4c3124c0d174d0fa63becc1ed45ba38950d8ab84ce2c8594727ef95f2`; `short_circuit_receipt.json` hat SHA-256 `e6acde6184fdb112b711e9bf3a4345aef6060b5dea57d99a93ecd49568a07c1e` und dokumentiert neun bestandene numerische und Quellpfadprüfungen. Die Skripte und Primärquellen-Lokatoren sind mit abgelegt. Die Prüfung änderte keine Produktivimplementierung, keine Eingangsdateien und keinen Full37-Case; sie führte keine neue Optimierung aus.

Die regionalen Carrier-Aggregate werden bereits in äquivalente Modellblöcke aufgeteilt. Beim vorhandenen Generatorbestand erhält `n0*P_block` exakt die ursprüngliche aggregierte Leistung. Damit ist die blockweise Abbildung von RoR, Biomasse und PHS für diesen aggregierten Modellfall implementiert. Die Aggregation liefert selbst keine beobachtete Zahl physischer Einzelmaschinen. Die Modellblockgrößen stammen aus der bestehenden Parametrierung.

| Technologie | Aggregate mit positivem Bestand | Vorhandene Modellblöcke | Angerechnete Quellenblöcke |
|---|---:|---:|---|
| CCGT | 28 | 578 | Aktive UC-Blöcke mit positivem SYN-Koeffizienten, Erzeugungsminimum 45 %. |
| OCGT | 1 | 2 | Aktive UC-Blöcke mit positivem SYN-Koeffizienten, Erzeugungsminimum 20 %. Weitere regionale Gaskandidaten besitzen positive Koeffizienten für ihren möglichen Ausbau. |
| Kohle | 10 | 100 | Aktive UC-Blöcke mit positivem SYN-Koeffizienten, Erzeugungsminimum 38 %. |
| Braunkohle | 12 | 96 | Aktive UC-Blöcke mit positivem SYN-Koeffizienten, Erzeugungsminimum 50 %. |
| Kernenergie | 13 | 73 | Aktive UC-Blöcke mit positivem SYN-Koeffizienten, Erzeugungsminimum 50 %. |
| Öl | 10 | 123 | Separat gutgeschriebene SYN-Blöcke. Erzeugungsminimum 38 %, Gutschriftsschwelle 20 %. Der bisherige Ölpfad verwendet Partizipation ohne thermische Start-/Stopplogik. |
| RoR | 28 | 1.024 | Separat gutgeschriebene SYN-Blöcke ab 30 % ihrer jeweiligen Blockleistung. |
| Biomasse | 12 | 341 | Separat gutgeschriebene SYN-Blöcke ab 50 % ihrer jeweiligen Blockleistung. |
| PHS | 20 | 351 | Synchrone Turbinenblöcke im Erzeugungsmodus ab 20 %, mit eigener Pump-/Turbinenbelegung. |

Die angegebenen Quellenwirkungen beruhen auf der vorhandenen SYN-Zuordnung und den eingefrorenen Quellenproxies. Die 27 Reservoir-Hydro-StorageUnits behalten die separat beschlossene native Energiebilanz ohne Quellenblöcke. Die fünf zuvor ausgeschlossenen PHS ohne qualifizierte Energiekapazität sind in den 20 PHS-Aggregaten nicht enthalten.

Die widersprüchliche LP-Zulässigkeitsmeldung wurde bis in die tatsächlich verwendete Schnittstelle verfolgt. Das native Solverlog des gespeicherten gSCR-Kandidaten endet mit `Sub-optimal termination`. Gurobi.jl 1.9.2 bildet `GRB_SUBOPTIMAL=13` auf `MOI.LOCALLY_SOLVED` ab. In `MOI.get(::Optimizer, ::MOI.PrimalStatus)` liefert der Zweig für `LOCALLY_SOLVED` bei vorhandenem Kandidaten unmittelbar `FEASIBLE_POINT`. Die darunter vorhandene Funktion `_is_primal_feasible_to_tolerance`, die `ConstrVio`, `BoundVio` und gegebenenfalls `IntVio` prüft, wird in diesem Zweig nicht aufgerufen.

Der Status ist deshalb in diesem Lauf eine Adapterzuordnung. Die eigenständige Prüfung des ausgegebenen Vektors weist 609 verletzte G1-Zeilen und insgesamt 3.074 Modellverletzungen oberhalb 1e-6 in den jeweiligen Modellkoordinaten aus. Das Barrierelog endet mit einem primalen Rest von 3,52e-3. Die Matrixkoeffizienten liegen zwischen 8e-8 und 3e3 und die rechten Seiten zwischen 1e-3 und 2e8. Dieser große Zahlenbereich und die dokumentierte Barrierenstagnation begründen die numerische Problemdiagnose. Ein präziser Nachvollzug jedes Rundungs- oder Unskalierungsschritts ist mit dem gespeicherten unvollständigen Primalvektor offen. Gurobi unterscheidet den Status `SUBOPTIMAL` von seinem Optimalitätsstatus und beschreibt die Zulässigkeitstoleranzen als absolute Toleranzen. [Gurobi-Statuscodes](https://docs.gurobi.com/projects/optimizer/en/current/reference/numericcodes/statuscodes.html) [Gurobi-Toleranzen und Skalierung](https://docs.gurobi.com/projects/optimizer/en/current/concepts/numericguide/tolerances_scaling.html)

Der ergänzende Receipt `technology_and_solver_status_20261117.json` hat SHA‑256 `0ec143feb971ccce9d277955204aa2da778d51eed2e566d068c912c981763423`. Er enthält die Technologieübersicht, die vier maßgeblichen Registereinträge und die SHA-Bindung des lokalen Gurobi.jl-Adapters sowie des ursprünglichen Solverlogs. Die ergänzende Untersuchung führte keine Optimierung aus.

### Weiterer Plan

Owner-Nachtrag 17.11.2026: „bilde beide modelle gleich ähnlich aus“. Die vergleichbare positive GFM-Quellenvariante wird als expliziter frozen-E-Planungsproxy mit gleicher aktiver Blockzählung wie SYN umgesetzt; SYN `x''d=0.25` bleibt erhalten. Der neue [Qualifikations- und Ausführungsvertrag](colib_epri_positive_gfm_source_qualification.md) dokumentiert Primärquelle, unabhängige Prüfungen, exakte R/X-Normierung und die gesonderte 840-h-LP-Variante. Die Originalfälle und ihr Null-GFM-Scope bleiben als historische Referenz erhalten.

Vor einer Wiederholung den effektiven positiven GFM-Quellenparameter und seine Gültigkeitsdomäne festlegen. Die übrigen oben genannten Technologien besitzen bereits Quellenblöcke. Anschließend das aufgebaute Modell und einen vollständigen LP-Vektor an die Eingangs-SHAs binden. Der benötigte Vektor umfasst installierte, aktive, gutgeschriebene und Pump-Blöcke, UC-Ereignisse, Dispatch, Speicherzustände sowie G1-LHS, GFL-RHS und Slack je Knotenstunde. Zusätzlich nativen Solverstatus, RawStatus, `ConstrVio` und `BoundVio` erfassen und die Akzeptanz ausdrücklich an die nachgerechneten Bedingungen in Originaleinheiten binden. Die Reparatur rundet die positiv angerechneten Quellenzähler auf und erhöht erforderlichenfalls die zugehörigen aktiven Blockzahlen. Die gemeinsame installierte Blockzahl muss das Maximum der aktiven Blöcke über alle fünf Wochen decken. Für PHS gilt zusätzlich die gemeinsame Turbinen-/Pumpgrenze. Anschließend sind Knotendeckel, Mindestproduktion, UC, Speicher, Quote und Lastfluss gemeinsam zu prüfen und bei Bedarf der Dispatch neu zu bestimmen. Die Solver-Startattribute werden vor der Übergabe vollständig bereinigt.

Die fünf Wochen bilden eine technische Stichprobe. Für eine größere Studienreihe wäre ihre Abdeckung von Stressstunden und saisonalen Speicherzuständen getrennt zu prüfen. PA‑SRC‑12 definiert für den formalen Fallback 168 oder 336 aufeinanderfolgende Stunden. Der 840‑h-Versuch ersetzt weder ein jährliches Q5-/F1-Modell noch Gate J.

Die direkte Nachrechnung in `week_selection_coverage.json` reproduziert die Auswahl aus den Originalprofilen. Gegenüber allen 8.760 Stunden liegen die Stichprobenmittel bei der Last um +0,84 %, bei verfügbarer Windleistung des Bestands um −4,37 %, bei verfügbarer PV-Leistung um +1,19 % und beim Speicherzufluss um −5,48 % auseinander. Die Stichprobe enthält eine Lastspitze von 501,6 GW gegenüber 525,1 GW im Originaljahr. Die geringste verfügbare Bestandswindleistung beträgt 12,7 GW gegenüber 5,7 GW im Originaljahr.

M0/LOCAL bleibt an zulässige Postsolve-Domänen gebunden. Für M2 fehlt ein vorab fixiertes, quell- und busgebundenes nichttriviales W. Für M1 fehlt eine physisch erzwungene SPD-Mindestmatrix. Reale AC-Studien brauchen die fehlenden Q-Last-, Terminal-, Spannungs- und Reglerdaten. Die nächste technische Arbeit gilt dem vorhandenen DC-Ausführungspfad.

### Reproduktion und Artefakte

Die lokalen Studienartefakte liegen unter `E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01`. `select_weeks.py` erzeugt `week_selection.json`, `export_selected_weeks.jl` exportiert die fünf AP1-Fälle und `run_common.jl` liest jeden Fall mit der 168‑h-Variante des Consumers ein. `run_joint_weeks.jl` koppelt die fünf Investitionsportfolios und setzt Zielfunktion und Quote. `run_joint_weeks_recovery.jl` dokumentiert den enger eingestellten Barrierelauf. `run_joint_weeks_crossover.jl` verwendet Crossover und den korrigierten Variantenwechsel. `replay.py` rechnet Quote, stündliche Systembilanz, Ausbau und Zielfunktion aus den Dispatch- und Ausbau-CSV-Dateien nach. Die Produktionsvalidierung des Jahrespfads wurde für diesen Versuch nicht editiert.

Der Producer und der Consumer entsprechen den in der Q5-Tabelle genannten Commits. Das übernommene wissenschaftliche Manifest hat SHA‑256 `ec4986d4de0853f6a8188c0add991a139d014c247adee6cb960fae29416a4e9a`. Eingänge, Aufrufe und Laufgrenzen stehen in `AP1_EXPORT/launch.json` sowie `AP2_SOLVES/launch.json`, `AP2_RECOVERY/launch.json`, `AP2_CROSSOVER/launch.json`, `AP2_STABLE_BASIS/launch.json`, `AP2_SCALED_BARRIER/launch.json`, `AP2_MIP_START/launch.json`, `AP2_GSCR_MIP_2H/launch.json` und `AP2_PARTIAL_CLEAN_START/launch.json`. Die SHA-gebundenen AP1-Sidecars, Solverlogs, die Prozessprofile und Kostenreceipts liegen bei den jeweiligen Läufen. `replay_final.py` verifiziert zusätzlich die Eingangsbytes und die Bindung der Run-Summaries. Der kombinierte Crossover-Prozess erreichte 14,596 GB Private Bytes und 11,966 GB Working Set ohne Eingriff der Ressourcengrenzen.

Der abschließende `comparison_final.json`-Receipt hat SHA‑256 `c79f14b13ebf149208bf9447006de505859b422763a81d39da33ad0ff70de740`. Die Run-Summary des geprüften Ganzzahlplans ohne gSCR hat SHA‑256 `2302b5e2e94fabb3755d0109507c5f8072b8497d93db76231ef3540671e03bd1`.

| Ausführungsdatei | SHA‑256 |
|---|---|
| `export_selected_weeks.jl` | `36cdc70eda7c3088d78cfd19906173446dd263aa8c9835c5a8f8f717cd6e7fa6` |
| `run_common.jl` | `40eb3f9d55289f031ba2f6ed965b9bb4beee5a5b7dda408cd4b8390cab435d9b` |
| `run_joint_weeks.jl` | `34707e3cc30bdc07821cff2e72d1676ad4280ba787d65a9f92e18a364558086e` |
| `run_joint_weeks_recovery.jl` | `2e51bfcacb04cbd051ee6ed66a7bd7653ec6f9dd73d3000c76f3cfd52b6c4279` |
| `run_joint_weeks_crossover.jl` | `37cbb440910d9f0b80ecab9cc5a7cc2b080298c3c05e898d85ca5c5ad7120cb3` |
| `run_joint_weeks_stable_basis.jl` | `5d6fa109ed1518aed0960836328c9b0502e12ff58b78c4baf35cc5ced6c23a5f` |
| `run_joint_weeks_scaled_barrier.jl` | `8732159fd22dbbef5acf03cde59ce548284439457d229485ef7af9ee813bbbec` |
| `run_joint_weeks_mip_start.jl` | `821e5fc1224eca4e1bdf7af688c43b67677c58adac4d49a3d87b18cc87ad7c2f` |
| `run_joint_weeks_gscr_2h.jl` | `4affbc8281690efe27f6c36ceac79402ab7f6204cc0a265072dcb850313de1b8` |
| `run_joint_weeks_partial_clean_start.jl` | `c78bef8e2610a9532920be9978619a70b8fd2d3bac3a35e85ca2d85177001abd` |
