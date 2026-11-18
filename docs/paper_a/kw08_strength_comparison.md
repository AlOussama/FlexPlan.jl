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
