# KW 8 / 70 %: G3 mit aktuellem Gurobi

Der produktive Solver ist Gurobi 13.0.3. Die Fortsetzung verwendet dieselben 168 Stunden, den bisherigen G3-Fall
`1ceb274ab48bf2e4f90783fa881d394c79fb216d311c6bde197c6fe77dbbb15d`,
den bisherigen frozen-E-Quellenproxy und den bestehenden Wochenrunner.
Formulierungen, Quoten, Daten, UC, Speicher, kalter Start und Investitions-
beziehungsweise Betriebskosten bleiben unverändert: CAPEX einmal, alle OPEX
einschließlich Start/Stop mit 8760/168 einmal. Die native Zielfunktion wird
weiter exakt durch 8192 geteilt; Ergebnisreplay erfolgt in EUR2025.

## Tatsächlich geladene Umgebung

| Komponente | Geladene Version |
|---|---|
| Julia | 1.11.5 |
| Mosek.jl / MosekTools.jl | 11.2.1 / 0.15.11 |
| Native MOSEK-Bibliothek | 11.2.6 |
| Gurobi.jl / native Gurobi-Bibliothek | 1.9.3 / 13.0.3 |
| JuMP / MathOptInterface | 1.32.1 / 1.54.0 |
| PowerModels | 0.21.7 |

Beide tatsächlichen Lizenzproben lösen ein kleines kontinuierliches Problem
optimal mit x=0,5. Die neu übernommene `Manifest-v1.11.toml` ist das aktive
versionsspezifische Lockfile für diesen Lauf. `Manifest-v1.10.toml` bleibt
unverändert und wird für diesen Neustart nicht verwendet. Es wurden keine
allgemeinen Paketupdates oder wissenschaftlichen Parameteränderungen ausgeführt.
Der Wechsel umfasst auch die im Lockfile enthaltenen JuMP-/MOI-/PowerModels-
Versionen; er wird nicht als ausschließlicher MOSEK-Wrapperwechsel dargestellt.

Die gezielte unabhängige Quellenprüfung bestätigt unveränderte MOSEK-
Status-/Schranken- und native RSOC-Semantik. Die neue direkte `ZeroOne`-
Unterstützung wird mit vorhandenen G3-Kegeln und expliziten Variablengrenzen
geprüft, einschließlich eines analytisch unzulässigen Binärfalls. Ein
Ergebniszähler wird nicht mit der Anzahl zulässiger Ganzzahlpläne verwechselt.

## Ressourcen

Die E:-Auslagerungsdatei wurde von 8 auf 16 GiB vergrößert und mit
`Win32_PageFileUsage.AllocatedBaseSize=16384` tatsächlich aktiv bestätigt.
Der native Erweiterungsaufruf lieferte Status 0; es war kein Neustart nötig.
C: blieb bei 18.076 MiB. Es wurden weder fremde Prozesse beendet noch Dateien
gelöscht. Die persistente Einstellung und die aktive Belegung sind getrennt
protokolliert; die Unterscheidung folgt der
[Microsoft-WMI-Dokumentation](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-pagefilesetting).
Der gezielte Aufruf zur aktiven Erweiterung verwendet die in den
[System-Informer-Headern](https://raw.githubusercontent.com/winsiderss/phnt/master/ntmmapi.h)
beschriebene Schnittstelle für eine bestehende Paging-Datei.

Der vorhandene Ressourcen-/Zeitguard bleibt erhalten: mindestens 7 GiB freie
Commit-Reserve zum Eintritt, mindestens 2 GiB während des Laufs, maximal
12 GiB Private Bytes und höchstens 7.200 Sekunden im Optimierungsfenster.
Die tatsächlichen Reserven und Monitoringintervalle werden protokolliert;
die bloße Eintrittsmessung ist keine Fit- oder Erfolgsgarantie.

## Ausführungs- und Reviewfolge

Die gezielten Tests sind unter Julia 1.11 abgeschlossen: 34 bestehende
Native-G3-Guards und 37 vorhandene exakte Skalierungs-/Kegel-/Witness-
Assertions mit Gurobi bestanden. Zusätzlich bestehen 22 vorhandene native
MOSEK-Klassen-/Kostenassertions sowie 18 Binärgrenzenassertions. Der erste
zusätzliche Binärtest erwartete für einen unzulässigen MIP zu eng
`NO_SOLUTION`; der Adapter meldet dort `UNKNOWN_RESULT_STATUS`. Korrigiert
wurde ausschließlich diese Testannahme: Bei nativ `INFEASIBLE` darf kein
zulässiger Primalplan behauptet werden. Die historischen 17/18- und die
korrigierten 18/18-Testlogs bleiben erhalten; keine Modellgrenze oder
Primal-Toleranz wurde gelockert.

Der Gurobi-Wochenlauf verwendet die bestehenden vier Threads, 7.200 s,
`NumericFocus=3`, `BarQCPConvTol=1e-10`, Feasibility-/Optimality-Toleranz
1e-9 und `NonConvex=0`; im Ganzzahllauf Gapziel 0,005. Die vorhandene
exakte RSOC-Brücke und die separate Originalprimalprüfung werden beibehalten.
Ein positives `PrimalStatus` allein ist kein Zulässigkeitsnachweis.

Der erste neue Start unter `e86745fa5dc8a9e0ec4394069e9e4d1cd27a43fc`
endete nach 45,828 s vor der Optimierung: JSON 1.13.4 liefert standardmäßig
`JSON.Object`, die bestehende Consumer-Schnittstelle benötigt `Dict{String,Any}`.
Der Wochenrunner fordert diesen Typ nun an seinen zwei Falllesestellen
explizit an, genau wie der vorhandene AP1-Importer in `src/io/parse.jl`.
PowerModels 0.21.7 benötigt JSON 1; alle Paketversionen und das Lockfile
bleiben unverändert. Die acht gezielten Assertions am tatsächlichen G3-Fall
bestätigen rekursive Dict-Container, 168 Snapshots, erfolgreiche Vorbereitung,
unveränderte Originalbytes und unveränderten Profildigest
`7e043c288061a828e5ab69fddcc5055b7d2afd7b16545b63d78ba097c53880ff`.
Der Test verwendet denselben vorhandenen SHA-geprüften technischen
Wochenkontext wie der Runner; die Kernregeln für die Jahreschronologie
wurden nicht geändert. Es wurde kein Modell oder Solver im Importtest gestartet.

Der frische Lauf erhält eigene Ausgaben unter
`E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE70_G3_GUROBI_DICT_20261120_02`.
Der vorherige technische Start und die Importtestbelege bleiben unter
`E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE70_G3_GUROBI_CURRENT_20261120_01`.
Versions-, System- und zusätzliche MOSEK-Kleintestbelege liegen unter
`E:/ResearchResults/FlexPlan_UC_GSCR/TECH_FULL37_KW08_RE70_G3_MOSEK_CURRENT_20261120_01`.
Alte Kandidaten, Fallbytes und fehlgeschlagene Versuche bleiben erhalten.

Vor `optimize!` muss der neue Wochenaufbau das qualifizierte tatsächliche
Modellprofil reproduzieren. Nach der Relaxation sind ein vollständiger
Originalpunkt sowie unabhängige mathematisch-ökonomische und physische
PASS-Receipts erforderlich. Erst deren gemeinsames SHA-gebundenes Gate
startet den Ganzzahllauf. Ein Lizenz- oder Kleintest-PASS ersetzt dieses
Ergebnisgate nicht. Für den Wochenfall wird ausschließlich Gurobi verwendet;
frühere Lösungen werden nicht als Startwerte übernommen.

Tatsächliche Code-/Lauf-SHAs, Ergebnisse und Ergebnis-QA werden nach dem Lauf
ergänzt. Die bestehenden Full37-Jahres-, SCI02-, Gate-J-, F3-, AC- und
Dynamikgrenzen bleiben erhalten.
