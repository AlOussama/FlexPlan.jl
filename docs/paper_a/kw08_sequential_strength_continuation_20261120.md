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
