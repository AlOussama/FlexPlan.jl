# KW 8 / 70 %: vorhandene Netzstärkekriterien

QREF hat aus den zwölf unabhängig geprüften 50-/60-/70-%-Varianten den
70-%-Fall gewählt (MILP mit G1: Gap 0,367898 %, ohne G1: 0,052968 %).
Die vorhandenen G1-/G2-/G3-Gleichungen werden unverändert wiederverwendet.

## Gezielte Integration

Der bisherige Wochenhelfer fügte neue Wind-/PV-Verfügbarkeit direkt in die
G1-Zeilen ein. Für zusätzliche Kriterien wird der physische Builder mit
`objective=false, defer_paper_a_strength=true` verwendet. Nach den vorhandenen
RE-Kapazitäts-, Dispatch- und Bilanzvariablen bindet
`finalize_paper_a_strength!` die vollständige Netz-/Regionszuordnung einmal an:

`p_total[i,t] = p_native[i,t] + sum(availability[k,t] * added_MW[k] / base_MVA)`.

Dies ändert nur die diagonale Exposition in S und M; B erhält keinen neuen
RE-Quellenbeitrag. Abregelung verringert diesen Verfügbarkeitsansatz nicht.
Der gewöhnliche Builder und die eingefrorenen G1-Fälle bleiben erhalten.
Die unabhängige Rekonstruktion nutzt dieselben ursprünglichen Projektprofile
und prüft die vollständige geordnete, eindeutige Snapshot-ID-Liste.

`scripts/paper_a/run_week_strength_comparison.jl` verwendet den SHA-geprüften
bisherigen physischen Wochenhelfer, dessen UC-/Speicher-/Kostenlogik und
AP3-Extraktion. G2 nutzt ausschließlich den bereits gebundenen positiven
geordneten r-Vektor. G3 nutzt die vorhandenen vollständigen Kanten-RSOC und
unveränderten NativeG3Solver-Domänengrenzen. Die Zielfunktion bleibt CAPEX
einmal plus sämtliche OPEX einschließlich Start/Stop mit 8760/168 einmal.
Die Wind-/PV-Quote bleibt tatsächliche Einspeisung geteilt durch Last.

## Getrennte Nachweise

Vor Optimierung werden neue G2-/G3-AP2-Bytes mit Eltern-SHA,
Profil-SHA und neuem Variantdigest gespeichert. Danach werden tatsächliche
LP-/MILP-/SOCP-/MISOCP-Profile erzeugt und unabhängig geprüft. Ein fehlendes
Profil-PASS oder eine NativeG3-Domänenverletzung stoppt nur den betroffenen
Pfad vor `optimize!`. Der Runner speichert Originalvariablen, Koordinaten,
Projektprofile, physische Zustände, Kantenzeugen, Kosten und nachgerechnete
Kriterien; numerische Schranken werden nicht als rigorose Währungsbeweise
bezeichnet.

LOCAL und M0 werden mit vorhandenen Diagnosefunktionen ausgewertet.
Klassisches SCR und externe eSCR-Familien benötigen weiterhin ihre konkrete
Fehler-/Quellen-/Nenner-/Kompensationszuordnung. M1 benötigt ein tatsächlich
durchgesetztes Bmin, nichttriviales M2 ein qualifiziertes W. Diese fehlenden
Falldaten werden nicht frei ergänzt. E2/Ratio wird nicht zum sicheren
Zertifikat erklärt. G3 ist bei verifiziertem symmetrischem Z-M und vollständigen
Kanten die bestehende exakte G0-Darstellung; ein eigener MISDP-Lauf wird dadurch
nicht behauptet.

Der Quellenbeitrag bleibt der ownergewählte frozen-E-Planungsproxy. Keine
Full37-Volljahres-, Gate-J-, F3-, AC-, Fehlerstrom- oder Dynamikfreigabe.

## Ausführung

Gezielte Shared-GFL-, Snapshot-Negativ-, G1-Koeffizientenregressions- und
Native-G3-Tests sowie tatsächliche Case-/Profil-/Solverreceipts werden unter
`E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_20261118_01`
aufbewahrt. Ergebnisse und unabhängige Abnahme werden nach tatsächlicher
Ausführung ergänzt; dieser Implementierungsstand behauptet noch keinen Lauf.

Gezielte Validierung des Implementierungsdeltas: 259 Shared-GFL- und
Regressionsassertions erfolgreich (`shared_gfl_tests_04.log`); anschließend
17 Native-G3-Assertions und Runner-Parseprüfung erfolgreich
(`shared_gfl_tests_06_native.log`). Die ersten Testversuche bleiben erhalten.
Der Native-Test deckte zusätzlich auf, dass die bestehende Nicht-SDP-Grenze
nur PSD-Triangle zurückwies. Die gezielte Korrektur weist nun auch PSD-Square
zurück; Kegelformeln, Zahlenbereich und Primal-Toleranz bleiben unverändert.
Der neue Solver wird damit nicht für SDP/MISDP zugelassen.

## Tatsächlicher Ausführungsstand

Der implementierte Code ist als `c842bbd7db0eaf03c5804db6ba73c6f6ebb07f63`
committed und auf dem eigenen Entwicklungsbranch synchronisiert. Producer
bleibt `becec6d63c0fbf2b8a160c41f87631f5270046b9`; sein vorhandener Q4-Hunk
bleibt außerhalb dieser Commits.

Die unabhängige gemeinsame Laufadmission ist PASS, SHA-256
`f6ec875e967e23bc9a01201c3b3f0cc0e399fc5bf4461b69ce88669ec40c8ffe`.
Beide tatsächlichen AP2-Varianten unterscheiden sich vom G1-Elternfall nur
an Formulierungskennung und Variantdigest (je 169 Vorkommen). Die
vollständigen Profile wurden unabhängig reproduziert. G2 besitzt 311.395
Originalvariablen; G3 328.867 einschließlich 17.472 q-Zeugen für 52 Kanten
über 168 Stunden. Alle vier tatsächlichen Modellprofile sind freigegeben.

| Kriterium | AP2-Case-SHA256 | Profile-SHA256 |
|---|---|---|
| G2 | `c154322ea868313405ac7be70c541ad87839bbb070ac2fa556f18c1d2547e2d5` | `223f15ae0f78021846ef636e2db975a29607aa8524be18d9bf3ed9ca0e46d787` |
| G3 | `1ceb274ab48bf2e4f90783fa881d394c79fb216d311c6bde197c6fe77dbbb15d` | `7e043c288061a828e5ab69fddcc5055b7d2afd7b16545b63d78ba097c53880ff` |

### G2-LP: unabhängig akzeptierter erster Vergleich

Der kontinuierliche G2-Lauf ist tatsächlich abgeschlossen. Native Status 2,
numerisches Gap 0, 311.395 vollständige Originalwerte und Koordinaten;
keine Originalmodellverletzung oberhalb 1e-6. Solverzeit 249,167 s,
gesamter Prozess 671,094 s, Peak Private 4.556.279.808 Bytes, keine
Ressourcenguards. Der Kostenreplay weicht um 0,001831 EUR ab.

| Größe | G1-LP, eingefrorene Referenz | G2-LP |
|---|---:|---:|
| Gesamtkosten, Mrd. EUR2025/a | 127,348376 | 127,408222 |
| CAPEX, Mrd. EUR2025/a | 111,232097 | 111,294375 |
| OPEX, Mrd. EUR2025/a | 16,116280 | 16,113846 |
| CCGT-Zubau, GW | 1,714911 | 1,712787 |
| GFL-BESS-Zubau, GW | 57,676642 | 57,164691 |
| GFM-BESS-Zubau, GW | 101,288682 | 102,089707 |
| Onshore-Zubau, GW | 588,959461 | 589,728739 |
| PV-Zubau, GW | 719,818110 | 718,399008 |
| Gasdispatch, TWh/Woche | 0,496544 | 0,499556 |
| BESS-Entladung, TWh/Woche | 5,775446 | 5,834989 |

Die vorhandene Diagnose ergibt im G2-Punkt G2/G0/G3/LOCAL für alle 168
Stunden positiv; G1 ist in 81 und M0 in 18 Stunden nicht erfüllt. G3 ist
hier ein nachträglich konstruierter Zeuge, kein zusätzlich erzwungener
G3-Optimierungslauf. Die nicht aktiven Bedingungen sind keine Verletzungen
des aktiven G2-Modells. Externe SCR/eSCR-Namen werden daraus nicht abgeleitet.

Mathematisch-ökonomische Ergebnis-QA:
`76a0ef859ac44d7465369549d10fb9fe7517b937fa6dd99f1077335e53880af3`.
Physische Ergebnis-QA:
`e2115e19d4b592fee6546de45b013d5fa8262a4069228fb2c420a96af91bdfae`.
Sie prüft unter anderem 74 RE-Projekte, 18.312 UC-Übergänge und 20.328
Speicherzustände. In 124 abgeregelten Projektstunden bleibt die verfügbare
neue RE-Leistung korrekt in der Exposition enthalten. Maximale nodale
Bilanzabweichung 1,48e-7 MW, SOC-Abweichung 2,98e-8 MWh. MinUp/Down wird
durch die unverändert akzeptierte Formulierung und Originalprimalprüfung
abgedeckt; eine neue unabhängige Rampenprüfung wird nicht behauptet.

Der leere Violationssatz erzeugt im aktuellen CSV-Export keine Datei.
Die Reviewer protokollieren diese Exportkonvention ausdrücklich und prüfen
Summary und native Residuen; eine gelesene leere CSV wird nicht behauptet.
Alle historischen fehlgeschlagenen QA-Adapterversuche bleiben auf E: erhalten.

### G2-MILP: Zeitlimit ohne Ganzzahlkandidat

Native Status 9 (`TIME_LIMIT`), `SolCount=0`, `NO_SOLUTION`. Der Lauf liefert
keinen zulässigen Ganzzahlplan und keinen definierten Optimalitätsgap. Die
numerische Schranke beträgt 127.408.221.525,42133 EUR2025. Die nativen
`ObjVal`-/`MIPGap`-Werte 1e100 sind Infinity-Sentinels, keine Kosten oder Gaps.
Dies ist kein Infeasibility-Nachweis. Der separat geprüfte G2-LP bleibt als
kontinuierliche Referenz bestehen; G2 wird nicht erneut optimiert.

Die gemeldete Solverlaufzeit 8.144,059 s überschreitet den Parameter
`TimeLimit=7200`. Zusätzlich bestehen unbeobachtete Hostintervalle: eine
interne Messlücke von 7.181,875 s und eine weitere Lücke von 136.569,578 s
zwischen letzter Probe und Prozessreceipt. Daraus wird keine nachgewiesene
aktive CPU-Zeit abgeleitet. Das leere `guards`-Array belegt weder eine
lückenlose Überwachung noch einen vollständigen Ressourcen-/Hardbudget-PASS.
Genau ein gebündeltes Ledger, `STRENGTH-RUNTIME-BOUNDARY-01`, erhält diese
Abweichung: SHA-256
`1d00041df886e68f25b44e1c664270ebb226036f8ee58959f541e11c5a67e1b4`.
Unabhängiger No-Incumbent-Abschlussreceipt:
`f653dfe21f411b0c6dc6dacf57d1c2674d3b4c73c00c4fc9b2ca6b1e33f6e1fe`.

### Ownerbeauftragter frischer G3-Start am 19.11.2026

Der ältere noch laufende G3-Prozess wurde nach der expliziten Owneranweisung
identitätsgeprüft beendet, vor `solve_enter`. Die alte Queue ist beendet;
Prozess-/Teildateien bleiben erhalten. Es werden keine abgeschlossenen
Quoten- oder G2-Läufe wiederholt.

Frische G3-Ergebnisse liegen separat unter
`E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE70_STRENGTH_COMPARISON_RESTART_20261119_01`.
Die bestehenden Casebytes werden am alten Ort wiederverwendet; keine
Original-/Casekopien oder zweiten Worktrees. Der tatsächliche Runtime-SHA
ist `70b46e3064a43c04a2167bf3b145e8ca0d6777a728c3dd047a1ffc5bebaa4c9a`:
exakt der gepinnte Runner plus drei deklarierte I/O-Pfadänderungen. Die
Profile ändern nur Runtime-Identität und NodefileDir; numerische Felder
bleiben gleich und werden beim frischen Modellaufbau erneut vor `optimize!`
verglichen. Die unabhängige Restartadmission ist PASS:
`90ae3064d01aef358cc21757c417edf8a44a99405c84a2bd41898c16604872ad`.

Die neue begrenzte Aufsicht kontrolliert die tatsächlich gestarteten
G3-Julia-Kinder des jeweiligen Profilers ab nativer Logerstellung mit
7.200 s Wandzeitgrenze. Ein finaler Messabstand und ein während einer
Hostlücke beendeter Child werden ausdrücklich mit erfasst. Fehlende
Hostabdeckung bleibt unqualifiziert; ein harter Stopp kann einen noch nicht
exportierten Kandidaten unverfügbar machen. Dies verändert keine
Modellgleichung oder Solverparametrierung. Tatsächliche Lauf-/Kandidaten-
und Ressourcenqualifikation folgt aus den neuen Receipts, nicht aus dem
Vorhandensein des Supervisors. Die frischen G3-SOCP-/MISOCP-Läufe sind noch
offen; Ergebnisse werden erst nach Lauf und unabhängiger Prüfung ergänzt.

### G3-SOCP-Neustart: numerisch zurückgewiesener Punkt und gebündelte Korrektur

Der frische SOCP-Lauf meldete nach 197,911 Solversekunden `OPTIMAL`, sein
vollständig gespeicherter Originalpunkt ist jedoch unzulässig: 4.623
Originalmodellverletzungen über 1e-6, maximale Constraintabweichung
0,0078621049943 pu und maximale Boundabweichung 0,0053256466081 pu. Der
Original-RSOC-Polynomfehler beträgt 0,0054178225382 bei unveränderter
Prüftoleranz 1e-7. Der Punkt wird **nicht** als Vergleichslösung akzeptiert.
Der berichtete Kostenwert 127,001478 Mrd. EUR2025/a ist kein freigegebenes
Studienergebnis. `ObjBound=-1e100` ist ein nicht verfügbarer Bound, der
daraus ursprünglich berechnete Gap ist ungültig.

Die unabhängige Diagnose reproduziert alle 328.867 Originalwerte und
Koordinaten sowie sämtliche 8.736 Kegel. Verletzungen betreffen Speicher,
Knotenbilanz, Dispatch, Untergrenzen und Kegel; die vollständigen 52 Kanten
und alle q-Zeugen sind vorhanden. Es handelt sich um einen breit numerisch
schlechten Primalpunkt, keinen Nachweis mathematischer G3-Infeasibility.
Diagnose-SHA:
`eb4b26e79826a279fda5a1dea651b0f8e89f2644eb98913ec6300d4510db32ec`.
Der folgende MISOCP-Aufbau wurde deshalb vor `optimize!` beendet; alle
Teil-/Fehlerdateien bleiben erhalten. Die Zeitaufsicht des SOCP-Laufs war
beobachtet (maximale Monitoringlücke 0,297 s), der Prozess endete in
503,281 s ohne Hardstop.

Die gezielte technische Korrektur verwendet die bereits vorhandene
AP3-Zielfunktionsdivision und NativeG3-Konditionierung: globaler positiver
Divisor 8192 (=2^13), mit Rationalgleichheitsprüfung sämtlicher Float64-
Koeffizienten und der Konstante. Keine neuen Variablen, keine heuristischen
Seed-Solves und keine Preis-/Modelländerung. Sämtliche Kosten werden aus
der ursprünglichen Zielfunktion rekonstruiert; gültige Solverbounds werden
mit dem effektiven Divisor nach EUR2025 zurückgerechnet. Infinity-Sentinels
werden als nicht verfügbare Bounds/Gaps ausgewiesen.

G3 erhält `BarQCPConvTol=1e-10`, `FeasibilityTol=1e-9` und
`OptimalityTol=1e-9`. Die QCP-spezifische Toleranz ist erforderlich, weil
`BarConvTol` diese Modelle nicht steuert; engeres Abbruchverhalten garantiert
für sich allein noch keine zulässige Lösung.
[Gurobi-Parameterreferenz](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html).
Die Originalconstraints, Rangeguards, `NonConvex=0`, Eingangsprofile,
Quellenparameter und Originalprimal-Toleranz 1e-7 bleiben erhalten.

Die Korrektur besteht 37 gezielte Skalierungs-/Kegel-/Reportingassertions
und 34 bestehende Native-G3-Default-Regressionsassertions. Die unabhängige
Deltaabnahme und die erneute tatsächliche Originalprimalprüfung sind die
nächsten Schritte; ein positiver synthetischer Test ist kein Fullcase-PASS.
