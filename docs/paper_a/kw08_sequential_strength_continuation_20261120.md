# KW 8 / 70 %: sequenzielle Fortsetzung mit zusätzlichem Budget

Der Owner hat nach dem begrenzten G3-Numeric-Handoff zusätzliche Versuche und
die sequenzielle Ausführung der restlichen qualifizierten Formulierungen für
die eine repräsentative Woche erlaubt. Der Jahresfall ist ausgeschlossen.

Der unveränderte Fall umfasst KW 8/2013, 168 Stunden, gemeinsame Ausbau- und
Betriebsoptimierung und 70 % tatsächliche Wind-/PV-Einspeisung relativ zur
Wochenlast. Physischer Schritt 1 h, OPEX einschließlich Start/Stop einmal mit
8760/168 gewichtet, annualisierte CAPEX einmal. Daten, Quellenproxy,
physikalische Grenzen und Originalprimal-Toleranz bleiben eingefroren.

## Ablauf und Formulierungsgrenzen

1. G3-SOCP mit der geprüften invertierbaren Konditionierung tatsächlich lösen.
2. G3-MISOCP nur nach zwei unabhängigen positiven Originalpunktprüfungen.
3. Den offenen G2-MILP gezielt erneut versuchen. Akzeptierte G1- und
   G2-LP-Ergebnisse übernehmen; keine Neuberechnung positiver Referenzen.

G0 ist im qualifizierten symmetrischen Z-Matrix-Bereich mathematisch durch
die vollständige G3-Kantendarstellung abgedeckt. Ein eigener SDP/MISDP-Lauf
ist mit der aktuellen Gurobi-Route nicht qualifiziert. M0 und LOCAL bleiben
vorhandene Diagnosegrößen. M1 benötigt ein tatsächlich durchgesetztes Bmin,
M2 ein qualifiziertes fallgebundenes W; externe SCR/eSCR-Familien benötigen
ihre konkreten Fehler-, Quellen-, Nenner- und Kompensationsbindungen.
Fehlende Eingänge werden nicht durch synthetische Registerwerte ersetzt.

## Technischer Stand

Ausgangscommit `b8b4c67dbda948606f744913f7eb796e342b5211` enthält den
unabhängig geprüften Routing-Fix aus `4719e08...`. Die 43 analytischen und
14 Runner-Assertions werden wiederverwendet. Die tatsächliche skalierte
native Matrix wird vor Optimierung geprüft; zwischen dieser Abnahme und
`optimize!` wird der Optimizer nicht neu angelegt.

G3-Case-SHA:
`1ceb274ab48bf2e4f90783fa881d394c79fb216d311c6bde197c6fe77dbbb15d`.
Input-Profil:
`7e043c288061a828e5ab69fddcc5055b7d2afd7b16545b63d78ba097c53880ff`.
Skalierte native Modellbytes:
`5dbbffef606cd987b383c20a080ca02ef462bebd67f1451058b0eed723a9f50b`.

Alle großen Ausgaben liegen unter
`E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE70_SEQUENTIAL_CONDITIONED_20261120_01`.
Die bestehenden Originalfälle werden an ihrem bisherigen Ort gelesen.
Eine Variante wird erst nach fertigem Export und unabhängiger Ergebnis-QA
als akzeptiert bezeichnet. Solverstatus allein ersetzt die Originalprüfung
nicht. Finale Lauf-, Kosten- und Gate-Receipts werden nach Ausführung ergänzt.

## Tatsächlicher erster konditionierter SOCP und gezielte Kosteneinheit

Der erste korrekt konditionierte SOCP endet nach 298,861 s mit Status 13
und unabhängigem Originalpunkt-NEGATIVE: 723 Verletzungen über 1e-7, davon
153 über 1e-6, Maximum 1,633704e-5. Alle Kegelpolynome bestehen. Die größten
Restfehler betreffen Reservoir-SOC, Knotenbilanzen und Speicherleistung.
Die vollständigen Original-/Nativewerte und Rückabbildungen sind gespeichert.
Dies ist kein Infeasibility-Nachweis und keine Kostenfreigabe.

Eine einzelne gezielte weitere numerische Korrektur verwendet die interne
Zielfunktionseinheit `2^20 EUR2025` statt `8192 EUR2025`. Die tatsächlichen
Preise, annualisierten Kosten und das Optimierungsproblem bleiben gleich.
Alle Koeffizienten und die Kostenkonstante werden exakt durch dieselbe
positive Zweierpotenz dividiert und Ergebnisse/Schranken in EUR zurückgerechnet.
Die native C-Spanne wird von 0,006365–4737 auf etwa 4,97e-5–37,01 verkleinert;
der Zielfunktionsmaßstab sinkt von ungefähr 15,5 Millionen auf 121.000.
Eine vorübergehend vermutete C-Obergrenze 606.000 bestätigte sich in den
tatsächlichen nativen Bytes nicht und ist keine Begründung dieses Schritts.

Der vorhandene Objective-Conditioner erhält dafür ein explizit qualifiziertes
Koeffizientenminimum 2^-20; sein Default 2^-8 bleibt erhalten. Andernfalls
würde er die zusätzliche Division automatisch zurückskalieren. Original-
Primalprüfung und sämtliche Feasibility-Toleranzen bleiben unverändert.
Die absolute native OptimalityTol hat in EUR eine andere numerische Bedeutung;
ein identisches oder rigoroses Euro-Dualzertifikat wird nicht behauptet.

Die Wahl einer passenden Währungseinheit und ein Zielfunktionsmaßstab zwischen
1 und 1e6 entsprechen den gezielt herangezogenen
[Gurobi-13-Numerikhinweisen](https://docs.gurobi.com/projects/optimizer/en/13.0/concepts/numericguide/tolerances_scaling.html).
Das ist eine technische Begründung, kein Erfolgsnachweis. Vor dem neuen Lauf
müssen analytische LP-/MIP-Tests und der Vergleich der tatsächlichen nativen
Bytes zeigen: A/Q/RHS/Grenzen identisch, ausschließlich C und Konstante /128.

Der frühere unskalierte Fehlstart bleibt unverändert dokumentiert. Das neue
Ownerbudget ist davon getrennt; der frühere Negativreceipt wird nicht in einen
PASS umgedeutet. Aus Wochenläufen folgt keine Jahres-, Gate-J-, F3-, AC-,
Dynamik- oder Publikationsfreigabe.

## Ergebnis der beiden tatsächlichen Gurobi-SOCPs

Beide Versuche verwenden denselben G3-Case. Der zweite ändert gegenüber dem
ersten ausschließlich die Zielfunktionskoordinate: alle nativen C-Werte und
die Konstante exakt /128; A, Q, RHS und Grenzen bleiben bitidentisch.

| Tatsächlicher Versuch | Native Laufzeit | Native Rückgabe | Originalmaximum | Zeilen >1e-7 / >1e-6 | Unabhängiges Gate |
|---|---:|---|---:|---:|---|
| `01_G3_SOCP`, Kosten /8192 | 298,861 s | `SUBOPTIMAL` / `LOCALLY_SOLVED` | 1,633704e-5 | 723 / 153 | NEGATIVE |
| `02_G3_SOCP_BINARY_MILLION`, Kosten /2^20 | 254,530 s | `SUBOPTIMAL` / `LOCALLY_SOLVED` | 2,469585e-3 | 4.633 / 1.921 | NEGATIVE |

Sämtliche 8.736 Kegelpolynome bestehen in beiden Punkten. Die übrigen
Originalgleichungen bestehen nicht. Im zweiten Punkt beträgt beispielsweise
der größte Reservoir-SOC-Rest 0,246959 MWh, der größte Knotenbilanzrest
0,000466113 MW. Die vollständig gespeicherten Native-/Originalvektoren
bestätigen die exakte Rückabbildung. Die positive Änderung der Währungseinheit
schließt die numerische Zulässigkeitslücke somit nicht.

Die gemeinsamen Negativreceipts haben SHA-256
`4cf808d0b091e4ef6a7bc19f942c15a75f8722a16fc422b73b692d0dd5915f75`
und `2415b64fb60179fa1b6607f9a688b8c064a4d8d98287d873ad8b7bda126de25c`.
Die unveränderte Originaltoleranz ist 1e-7. G3-MISOCP bleibt gesperrt;
G3-Ergebniskosten, Kostenschranken und Gaps sind nicht freigegeben.
Die zwei Fehlschläge beweisen keine mathematische Unzulässigkeit des Falls.

## Separater offener G2-MILP

Der G2-MILP verwendet den unveränderten Case
`c154322ea868313405ac7be70c541ad87839bbb070ac2fa556f18c1d2547e2d5`
und Consumer-Commit `a6eadd1bf3d534765cbd26c6599d975489d955ed`.
Der Auditpfad erhält lediglich die Behandlung einer leeren Q-Matrix; die
Modellformulierung bleibt unverändert. Neun Tests ohne Optimierung prüfen
diesen unmittelbar betroffenen Null-Q-Pfad. Die zusätzliche Kosteneinheit
der G3-Versuche ist für G2 ausgeschaltet.

Der eigene bereits akzeptierte G2-LP liefert ausschließlich partielle
Kapazitätshinweise: 148 freie installierte Blockzahlen, innerhalb der
bestehenden Einzel- und gemeinsamen Knotengrenzen aufgerundet, und 74
unveränderte Wind-/PV-Kapazitäten. 205 fixe Anlagen werden übersprungen.
234.209 zuvor automatisch gesetzte Starts sind entfernt. Alle übrigen
319.909 nativen Startattribute bleiben exakt `GRB_UNDEFINED`. Operations-,
UC- und Hilfsvariablen erhalten keine übernommenen Werte. Der Solver darf
die 222 Hinweise reparieren oder verwerfen; daraus folgen keine neuen
Variablenuntergrenzen und keine garantierte Zulässigkeit.

Die tatsächlichen 320.131 nativen Variablen, 417.555 linearen Zeilen,
111.401 Integer-/Binärdomänen, Grenzen und die Kostenkonstante bleiben vor
und nach der Startübergabe unverändert. Die native Modellidentität lautet
`c5b2ac5bc83639fda2a8201cef78def73a94a6278f960847f3c80171869f9589`.
Das tatsächlich abgefragte Solverlimit beträgt 6.900 s, das Gapziel 0,005;
der externe Guard begrenzt das native Fenster auf 7.200 s und lässt regulär
300 s Exportreserve. Große Logs, Nodefiles und Ergebnisvektoren liegen auf E:.

Die gemeinsame unabhängige Eintrittsfreigabe
`651bf43446cf307969a1b04b7ab87971e499335de54bcefe322cd652be046a46`
bindet Profil `ede315108e08dfa2e7e8d42f9441ceb749809b01e272fce16f39f7d09d8e8e1d`,
Quellcommit, tatsächliche Starts, Modellbytes und die bereits angehängte
Solverinstanz. Das davon getrennte Ergebnisgate folgt nach vollständigem
Export und unabhängiger Prüfung.

## G2-MILP: tatsächlicher akzeptierter Ganzzahlplan

Der neue Lauf endet nach 513,126 s mit nativem Status 2 (`OPTIMAL` im
eingestellten Gapziel). Es liegen zehn solverinterne Lösungen vor. Der
abschließend exportierte vollständige Plan besteht die getrennten
Original-, Integer-, mathematisch-ökonomischen und physikalischen Prüfungen.
Der frühere G2-Zeitlimitlauf ohne Kandidat bleibt als historische Evidenz
erhalten; dieser neue Versuch schließt dessen offenen Ganzzahlbefund.

| Größe | G1-MILP, übernommen | G2-LP, übernommen | Neuer G2-MILP |
|---|---:|---:|---:|
| Annualisierte Studienkosten, Mrd. EUR2025 | 127,818619 | 127,408222 | 127,449599 |
| CAPEX, Mrd. EUR2025/a | 111,598590 | 111,294375 | 111,340589 |
| OPEX, Mrd. EUR2025/a | 16,220028 | 16,113846 | 16,109010 |
| Numerischer Gap, % | 0,367898 | 0 | 0,032466 |
| CCGT-Zubau, GW | 1,636000 | 1,712787 | 1,840500 |
| OCGT-Zubau, GW | 0 | 0 | 0 |
| GFL-BESS-Zubau, GW | 58,875000 | 57,164691 | 57,225000 |
| GFM-BESS-Zubau, GW | 104,575000 | 102,089707 | 102,450000 |
| Onshore-Zubau, GW | 587,424043 | 589,728739 | 589,728739 |
| PV-Zubau, GW | 726,052712 | 718,399008 | 718,399008 |
| Gasdispatch, TWh/Woche | 0,603613 | 0,499556 | 0,501633 |
| BESS-Entladung, TWh/Woche | 6,113138 | 5,834989 | 6,068611 |

Die Mehrkosten gegenüber dem eigenen LP betragen 41.377.503,25 EUR/a.
Gegenüber dem gespeicherten G1-MILP-Plan ist der neue Plan um
369.019.516,70 EUR/a günstiger. Die jeweiligen Optimalitätsintervalle
überlappen; unterschiedliche Gaps und festgehaltene unterschiedliche
G1-/G2-Zeilen erlauben daraus kein Ranking ihrer exakten Optima.
Der unabhängige Vergleich hat SHA-256
`1749bca245676495ff3858163cb0ee0e35c451ee5341c27cd7327bdd232b4a0c`.
Dies ist ein Wochenmodell mit Jahresgewichtung, keine 8.760-h-Simulation.
Die unabhängig aus vollständigen CSVs nachgerechneten Kosten betragen
127.449.599.028,67047 EUR; der Workerwert weicht um rund 0,00258 EUR ab.
Alle 36.624 Start-/Stoppvariablen werden mit ihren ursprünglichen
Koeffizienten in der Betriebskostensumme einmal annualisiert.

Die native numerische Untergrenze beträgt 127.408.221.525,4212 EUR.
Das tatsächliche relative Gap ist 0,03246578 %, damit kleiner als das Ziel
0,5 %. `OPTIMAL` bedeutet hier erreichtes Gapziel, keinen Nullgap-Beweis.
Die Schranke ist eine numerische Solverschätzung in Originalwährung und
kein rigoroses exaktes Geldzertifikat. Im nativen Log werden während der
Startvervollständigung bessere Kandidaten nach 90,81 s, 118,66 s und etwa
237 s gemeldet. Erst nach der Wurzelrechnung steht ein belastbares
gemeldetes MIP-Gap zur Verfügung; Barrierereste sind keine MIP-Gaps.

Die unabhängige vollständige Prüfung findet bei allen 111.401 diskreten
Originalvariablen exakt Ganzzahligkeit. Der größte erneut summierte native
Zeilenrest beträgt 8,940697e-8; die größte Boundabweichung 1,01258e-9.
Der maximale physische Knotenrest beträgt 5,12537e-7 MW, der SOC-Rest
5,02223e-7 MWh und die stündliche Systembilanzabweichung 7,40984e-7 MW.
Die vorhandene G2-Originaltoleranz von 1e-6 bleibt unverändert.

G2 ist in allen 168 Stunden erfüllt, kleinster Zeilenslack 7,635878e-5.
Die zusätzlichen vorhandenen G0- und LOCAL-Matrixdiagnosen bestehen in
allen Stunden. G1 ist in 116 und M0 in zehn Stunden negativ. Diese beiden
Bedingungen sind im G2-Lauf nicht aktiv; ihre Diagnosen sind keine
Verletzung des optimierten G2-Modells. M0 ist in allen Stunden definiert.
Ein externes physisches SCR/eSCR-Zertifikat folgt daraus nicht.

Das gemeinsame unabhängige G2-Ergebnisgate hat SHA-256
`dd1af5ee5f3cc1951587314b2919389b6955833d37893d979f7dc82064bc1dac`.
Es bindet die vollständige native Originalpunktprüfung
`3ba78d8f2adc7e8d8fdd87e231e59c8054c08c332ea2301511a2762d36b11e6c`,
die Mathematik-/Kostenprüfung
`a2cf5e106d9a5e66e91c688a09cc64066ed9f65ef3954bd34a8a95d78315f501`
und die Physikprüfung
`d03b35797e7448c9ea48bb1df12c38074b7f0c1fa009ac4dc5e5ec059d02d826`.
Der gesonderte Wochenenergie-/Annualisierungsvergleich hat SHA-256
`c15559b38eefd0348fd440669ecd88d3bbb2ad964e5558665ced4575ab742b12`.

Der Ressourcenmonitor bestätigt vollständigen Export, 6.042.988.544 Bytes
Peak Private und keinen Guardeingriff. Das längste Messintervall beträgt
0,281 s. Der Solver nutzte vier Threads. Der erhöhte Zeitrahmen wurde
zugelassen, aber wegen des erreichten Gapziels nicht ausgeschöpft.

Der abschließende Startwertvergleich bestätigt: Alle 148 vorgeschlagenen
installierten Blockzahlen sind im Endplan bitidentisch erhalten. Von 74
RE-Kapazitäten sind 67 bitidentisch und 73 innerhalb 1e-6 MW gleich; die
größte Änderung beträgt 1,545025e-5 MW. Die Betriebs-/UC-Zustände musste der
Solver selbst ergänzen. Die erfolgreiche Kapazitätsrundung beweist daher
keine automatische Zulässigkeit eines unveränderten LP-Dispatch.
Der Beleg hat SHA-256
`342b5ffbdc731cd7b8532c6570131eebf0430c920bd7bbd99b28dc85730e4d69`.

Der neue vollständige G2-Ganzzahlpunkt liefert außerdem einen besseren
G3-Referenzvektor. Mit dem vorhandenen Zeugenverfahren werden 17.472
Kegelvariablen ergänzt und alle 756.257 gespeicherten G3-Originalzeilen
unabhängig nachgerechnet. Der größte fsum-Rest beträgt 8,940697e-8, das
größte Kegelpolynom 1,455192e-11; alle bleiben unter 1e-7. Der alte kleine
Quotenrest des G2-LP blockiert diese neue Referenz somit nicht mehr.
Dies ist ein konstruierter Referenzreplay, kein tatsächlicher G3-Solverpunkt.
Der NativeG3-JuMP-Guard wurde dabei nicht aufgerufen; die zwei negativen
SOCP-Ergebnisse und das MISOCP-Gate bleiben unverändert. Der Referenzbeleg
hat SHA-256
`6d940f4b33d47d4acca29833953a1b53af7940b1e1e355091356a9dcc7456b7b`.

## Abschließender Formulierungsumfang und Restbefunde

| Vorhandene Familie | Status für genau diese Woche | Konkrete Grenze |
|---|---|---|
| Ohne Stärke / G1 | Akzeptierte LP-/MILP-Ergebnisse übernommen | Keine Wiederholung abgeschlossener positiver Läufe. |
| G2 mit eingefrorenem r | LP übernommen; neuer MILP unabhängig PASS | Gapziel erreicht, numerische Restlücke 0,03246578 %. |
| G3 | Zwei tatsächlich konditionierte SOCPs unabhängig NEGATIVE | Lineare Originalreste trotz erfüllter Kegel; MISOCP nicht freigegeben. |
| G0 | Vorhandene Eigenwertdiagnose im neuen G2-Plan 168/168 PASS | G3 bildet G0 im qualifizierten Z-/Vollkantenbereich ab; kein separater SDP-/MISDP-Lauf. |
| LOCAL | Vorhandene Matrixdiagnose 168/168 PASS | Keine eigenständige neue Wochenoptimierung oder globale SCR-Freigabe. |
| M0 | Vorhandene domänengeprüfte Diagnose; zehn negative Stunden | Im Fall nicht aktiv; kein qualifizierter endogener Full37-Wochenadapter. |
| M1 | Fallgebunden blockiert | Tatsächlich erzwungene minimale Quellenzustände und daraus belegtes SPD-Bmin fehlen. |
| Nichttriviales M2 | Fallgebunden blockiert | Ex ante fixierte W-Matrix mit Busfolge, Referenzzustand, Normierung, Quellen-/Rechtebindung fehlt. |
| Physisches SCR/eSCR/MSCR | Fallgebunden blockiert | Fehler-/Quellenkonvention, Nenner-/Terminalbindung und eSCR-Kompensation fehlen. |
| Woodbury/Neumann/E2 | Vorhandene Diagnosefunktionen | Kein qualifiziertes einseitig sicheres Fallzertifikat. |

Die unabhängigen Bestandsaufnahmen sind SHA-gebunden im ersten Laufordner.
Für M1 wird kein künstlicher Quellenfloor, für M2 weder W=I noch das
G2-r und für eSCR keine stillschweigende Nullkompensation eingesetzt.
Der feste r-Vektor macht G1 und G2 nicht generell geschachtelt. Ein
günstigerer gespeicherter MIP-Plan wäre deshalb zusammen mit den jeweiligen
Schranken und Gaps zu bewerten, nicht als allgemeiner Konservativitätsbeweis.

Der unmittelbar offene numerische Restbefund bleibt `G3-NUMERIC-01`.
Die beiden Gurobi-Punkte werden erhalten und nicht durch höhere Toleranzen
akzeptiert. Der bereits vorhandene alternative MOSEK-Pfad ist keine
Ergebnisfreigabe; ein erneuter Solverwechsel wartet auf die Antwort zur
ausdrücklich vorher getroffenen Gurobi-Auswahl. Ohne akzeptierten tatsächlichen
G3-SOCP-Originalpunkt startet kein G3-MISOCP.

Der neue Umfang umfasst drei tatsächliche Optimierungen: zwei G3-SOCPs und
einen G2-MILP. Kein Jahr, kein neuer G1-/G2-LP und keine unqualifizierte
zusätzliche Modellfamilie wurden gerechnet. Alle großen Originalpunkte,
Logs, gescheiterten Versuche, Monitorspuren und Reviewer bleiben auf E:.
Keine historischen Eingänge oder Ergebnisse wurden gelöscht. Der vorhandene
ungecommittete Producer-Q4-Hunk bleibt mit Datei-SHA
`aceb4661c9fe3c92e41acf44a52250af2549a46c437a162e46f319453dfa1314`
erhalten; der Producer wurde nicht editiert.

Der [kompakte maschinenlesbare Handoff](receipts/kw08_sequential_strength_handoff_20261120.json)
bindet die tatsächlichen Code-/Case-/Profil-/Native-/Ergebnisbytes,
separate Eintritts- und Ergebnisreceipts sowie die deduplizierten Restbefunde.
Die zusätzlich geprüften Tests umfassen 116 Konditionierungs-/Kosten-,
30 tatsächliche Runner-, 34 vorhandene Native-Default- und neun
Null-Q-Auditassertions. Die historischen 43/14 Tests wurden übernommen.
