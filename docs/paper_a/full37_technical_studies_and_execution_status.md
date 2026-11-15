# Paper A · Technische Full37-Fallstudien und offene Ausführungsschritte

Stand 15. November 2026. Dieses Dokument erfasst den KW‑3-Vergleich, die Q5-Speicherkorrektur und die anschließende 840‑Stunden-Studie. Alle berechneten Fälle verwenden DC-Lastfluss mit verlustfreier HGÜ und die bestehenden 2040-Kostensätze in EUR2025.

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

### Rechenstand und Hindernisse

- Der AP1-Export aller fünf Wochen dauerte 235,562 s. Die gemessene Private-Bytes-Spitze betrug 1,312 GB. Das gemeinsame AP2-Modell umfasst 1.556.679 Variablen und davon 557.005 Ganzzahlvariablen. Der gehaltene Julia-Heap nach Modellaufbau lag bei rund 5,252 GB.
- Der G1-Ganzzahllauf erreichte nach 2.401,768 s `TIME_LIMIT`. Gurobi fand keinen ganzzahligen Plan. Die ausgewiesene untere Schranke von 73,835619339 Mrd. EUR2025 stammt aus dem Root-Knoten dieses 840‑h-Modells. Die erste Barriere-Relaxation meldete ein Optimum, der anschließende gSCR-Residuencheck wies den Kandidaten zurück. Der Prozess erreichte maximal 15,092 GB Private Bytes einschließlich des LP-Versuchs.
- Die zweite Barriere-Rechnung mit gSCR ohne Crossover meldete `LOCALLY_SOLVED` bei 73,835599577 Mrd. EUR2025. Der kleinste unskalierte gSCR-Slack betrug −0,001980756 pu. 609 gSCR-Zeilen unterschritten die Grenze um mehr als 1e-6 pu. Der Kandidat ist zu Diagnosezwecken gespeichert. Beim Wechsel zum Gegenlauf verbrachte der Adapter Zeit mit 31.080 einzelnen Löschungen im aktiven Gurobi-Backend. Der belegte Stopp erfolgte vor `solve_enter` des Gegenlaufs.
- Für den Crossover-Lauf wurde das Solver-Backend vor dem Variantenwechsel abgehängt. Die G1-Zeilen werden gesammelt am JuMP-Modell entfernt. Die LP-Rechnung verwendet Crossover und primale beziehungsweise duale Solvertoleranzen von 1e-8 bei gleicher Modellalgebra. Der ursprüngliche Ganzzahllauf mit gSCR bleibt erhalten. Der 40‑Minuten-Ganzzahllauf ohne gSCR ist im selben Ablauf nach dem LP-Crossover mit gSCR eingeplant.

### Weiterer Plan

Beide 840‑h-Varianten anhand der Solverstatus, der nachgerechneten Quote, der Stundenbilanzen und der primären Modellresiduen bewerten. Der Vergleich weist Ausbau in MW, Einspeisung und Speicherumsatz in MWh sowie annualisierte CAPEX und OPEX aus. Die Ganzzahlabweichungen einer Relaxation und die Gültigkeit der jeweiligen Schranke gehören zum Ergebnis. Bei einer Wiederaufnahme nach einem Solverabbruch zuerst prüfen, ob sich das bereits gebaute Modell oder eine daran gebundene Solverdatei wiederverwenden lässt. Das vermeidet Wiederholungen des AP2-Lese- und Aufbaupfads.

Die fünf Wochen bilden eine technische Stichprobe. Für eine größere Studienreihe wäre ihre Abdeckung von Stressstunden und saisonalen Speicherzuständen getrennt zu prüfen. PA‑SRC‑12 definiert für den formalen Fallback 168 oder 336 aufeinanderfolgende Stunden. Der 840‑h-Versuch ersetzt weder ein jährliches Q5-/F1-Modell noch Gate J.

M0/LOCAL bleibt an zulässige Postsolve-Domänen gebunden. Für M2 fehlt ein vorab fixiertes, quell- und busgebundenes nichttriviales W. Für M1 fehlt eine physisch erzwungene SPD-Mindestmatrix. Reale AC-Studien brauchen die fehlenden Q-Last-, Terminal-, Spannungs- und Reglerdaten. Die nächste technische Arbeit gilt dem vorhandenen DC-Ausführungspfad.

### Reproduktion und Artefakte

Die lokalen Studienartefakte liegen unter `E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_FIVE_WEEKS_RE50_20261115_01`. `select_weeks.py` erzeugt `week_selection.json`, `export_selected_weeks.jl` exportiert die fünf AP1-Fälle und `run_common.jl` liest jeden Fall mit der 168‑h-Variante des Consumers ein. `run_joint_weeks.jl` koppelt die fünf Investitionsportfolios und setzt Zielfunktion und Quote. `run_joint_weeks_recovery.jl` dokumentiert den enger eingestellten Barrierelauf. `run_joint_weeks_crossover.jl` verwendet Crossover und den korrigierten Variantenwechsel. `replay.py` rechnet Quote, stündliche Systembilanz, Ausbau und Zielfunktion aus den Dispatch- und Ausbau-CSV-Dateien nach. Die Produktionsvalidierung des Jahrespfads wurde für diesen Versuch nicht editiert.

Der Producer und der Consumer entsprechen den in der Q5-Tabelle genannten Commits. Das übernommene wissenschaftliche Manifest hat SHA‑256 `ec4986d4de0853f6a8188c0add991a139d014c247adee6cb960fae29416a4e9a`. Eingänge, Aufrufe und Laufgrenzen stehen in `AP1_EXPORT/launch.json` sowie `AP2_SOLVES/launch.json`, `AP2_RECOVERY/launch.json` und `AP2_CROSSOVER/launch.json`. Die SHA-gebundenen AP1-Sidecars, Solverlogs, die Prozessprofile und Kostenreceipts liegen bei den jeweiligen Läufen.

| Ausführungsdatei | SHA‑256 |
|---|---|
| `export_selected_weeks.jl` | `36cdc70eda7c3088d78cfd19906173446dd263aa8c9835c5a8f8f717cd6e7fa6` |
| `run_common.jl` | `40eb3f9d55289f031ba2f6ed965b9bb4beee5a5b7dda408cd4b8390cab435d9b` |
| `run_joint_weeks.jl` | `34707e3cc30bdc07821cff2e72d1676ad4280ba787d65a9f92e18a364558086e` |
| `run_joint_weeks_recovery.jl` | `2e51bfcacb04cbd051ee6ed66a7bd7653ec6f9dd73d3000c76f3cfd52b6c4279` |
| `run_joint_weeks_crossover.jl` | `37cbb440910d9f0b80ecab9cc5a7cc2b080298c3c05e898d85ca5c5ad7120cb3` |
