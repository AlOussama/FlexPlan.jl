# A3.7-B1 — Implementierungsbericht und Übergabe

Stand: 23.10.2026 (Messungen 22.10.2026 UTC / 22.–23.10.2026 MESZ). Rolle: A3.7-B1-IMPLEMENTER.

**Gesamturteil: `correction_ready_for_independent_reaudit`.** Die endliche registrierte Matrix erreicht 45/45 `OPTIMAL`; zusätzlich erreicht das unveränderte serialisierte Originalmodell `reference_24snap` `OPTIMAL/FEASIBLE_POINT`. Alle 46 Originalpunkte bestehen die separate numerische Prüfung. Das ist eine Implementiererqualifikation, keine unabhängige Abnahme und kein globaler Integeroptimalitätsbeweis.

## Auftrag, Specification Gate und Provenienz

`SPECIFICATION_READY`: Der explizite M2-v2-Auftrag legt G3, Integerdomänen, Originalkosten, neun Fälle, Matrix, Residuen, Zertifikate und Abnahmegrenzen fest. Die Fortsetzungsfreigabe erlaubt ausschließlich das unveränderte Liegenlassen der 28 fremden Dateien; die spätere Ergänzung erlaubt zielführende Solveroptionen/Toleranzen. Es wurden keine Feasibility-Anforderungen gelockert. Die Auswahl und Konditionierung betreffen die technische Solverschnittstelle, keine neue wissenschaftliche Methode. Der frühere Schutzstopp `blocked_environment_or_inputs` bleibt historisch richtig und vollständig erhalten.

Vorhandener Checkout: `D:/Projekte/Code/FlexPlan_UC_GSCR`; einziger neuer Branch: `fix/paper-a-a3-7-b1-native-solver-v1`, Parent `15ba10c193a562a48cb0e1dcc6fa12d922ac0613`. Kein neuer Worktree, Merge, PR, Rebase, Reset, Stash, Cherry-Pick oder Branchlöschen. Die sieben vorhandenen Worktrees bleiben registriert; die übrigen sechs sowie alle fremden Refs wurden unverändert verglichen.

Die Solverproduktion ist auf **`f302b7b63e917678fb14b7cbc3cfdbc0d8c624a1`** eingefroren. **`6b6bcd8b0f00caa3a7ee7d7e89fe1085596bd7fc`** repariert ausschließlich den separaten Nachweis für die vorhandene MOI-Intervall-SlackBridge; Solver-, Modell-, Test- und Dependencydateien bleiben gegenüber der Produktionsrevision identisch. Frühere eigene Implementierungsschritte bleiben in der Commitkette erhalten; `provenance.json` nennt sämtliche Parents. Die abschließende Remote-Verifikation erfolgt additiv im Publikationsbeleg.

Original-AP3 `485b637cc1998a327206c5929434bd26c6f0be16`, akzeptierter A3.6-HiGHS-Fix `910d44122a37d9ed2cca06940740b46706c73d40`, A3.6-Evidenz `1147873bf553667aec5cd7eb0e9c6f7e471b370c`, unabhängiger Reaudit `15ba10c193a562a48cb0e1dcc6fa12d922ac0613` bleiben unverändert. Die eingefrorenen wissenschaftlichen Commits/Blobs wurden read-only über den bestehenden Reauditpfad verifiziert; daraus folgt keine Ratifizierung des vorgeschlagenen Amendments.

## Gewählte Solverstrategie

Gewählt wurde **Gurobi 12.0.3**, Gurobi.jl 1.9.2, mit der vorhandenen exakten MOI-RSOC-QuadraticBridge, bewiesenen redundanten Nichtnegativitätsbounds, exakter Zweierpotenz-Konditionierung der gesamten emittierten affinen Zielfunktion und einem kontrollierten primalen Start.

Die temporäre Gurobi-Standardbridge erzeugt ausschließlich einen Startpunkt. Ihre gerundete Rotation wird ausdrücklich nicht als exakt modellgleich akzeptiert; ihre Bounds werden weder gelesen noch weitergereicht. Der Kandidat muss das Originalmodell numerisch bestehen. Anschließend löst ein eigenständiger finaler Optimierer das exakt abgebildete ursprüngliche RSOC-Modell; es werden keine Integerwerte fixiert und keine zusätzlichen fachlichen Restriktionen eingeführt.

Konfiguration: ein Thread, `Seed=20261020`, finale Zeitgrenze 120 s zuzüglich höchstens 30 s für die Kandidatenerzeugung und gesondert erfasster Vorbereitung, `NonConvex=0`, `MIPGap=1e-8`, `FeasibilityTol=1e-8` (engerer Matrixmodus `5e-9`), `IntFeasTol=1e-8`, `OptimalityTol=1e-9`. Die unabhängige Originalprüfung benutzt die zuvor festgelegte Schranke `1e-7`; die tatsächlichen Residuen werden ungerundet und als rationale Werte gespeichert. Das ändert keine Modellgleichung.

Die Julia-Anbindung von **MOSEK 11.0.29** wurde tatsächlich hergestellt: Mosek.jl 11.0.1 und MosekTools 0.15.10 sind die einzigen hinzugefügten Manifest-Einträge; alle 251 bestehenden Dependency-Einträge bleiben identisch. Es gab kein `Pkg.update`, keine Lizenzänderung oder Lizenzumgehung. Beide kommerziellen Solver bestehen dasselbe echte Integer-RSOC-Modell (Optimum 5), beide lösen das identische ursprüngliche G3-Modell. Lizenznutzbarkeit ist durch die ausgeführten Solves belegt, nicht durch Dateiexistenz. Die tatsächlich geladene Gurobi-Bibliothek ist 12.0.3; eine im Manifest vorhandene JLL-Version ersetzt diesen Laufzeitnachweis nicht.

MOSEK erhielt vorrangig zwei vollständige normalisierte 46-Läufe-Versuche: 44 `OPTIMAL`/2 `TIME_LIMIT`, danach 43 `OPTIMAL`/3 `TIME_LIMIT`. Betroffen ist `reference_24snap`, insbesondere Doppeldivisor und engere Feasibility, im zweiten Versuch auch Halbdivisor. Die jeweilige Grenze beträgt 120 s; diese Befunde behaupten keine fundamentale Unlösbarkeit durch MOSEK. Sie begründen, warum MOSEK in der hier geprüften Konfiguration nicht die gewählte Route ist. Alle erfolglosen Zwischenversuche bleiben erhalten.

Ein Gurobi-Zwischenstand mit Standardrotation löste 46/46, genügte aber der exakten binär-rationalen Backendidentität nicht. Die direkte exakte Quadratik ohne geeigneten Start scheiterte am 120-s-Limit. Erst die gemeinsame kontrollierte Strategie erfüllt sowohl die Identitäts- als auch die Abschlussprüfung. `REUSE_REJECTED`: MOI-Standardrotation als finaler Modellnachweis — gerundetes `1/sqrt(2)` verändert die binär-rationale Kegelabbildung. Wiederverwendet wurden die vorhandene MOI-QuadraticBridge und sämtliche fachlichen Modellbauer.

## Kausalbefund des bisherigen Pajarito-Stillstands

Der unabhängig akzeptierte HiGHS-Koeffizientenfix `small_matrix_value=1e-12` bleibt unverändert. Er beseitigt die konkrete lokale Filterursache, aber nicht den folgenden Abbruchkonflikt: Die innere HiGHS-MIP-Standardschranke `mip_abs_gap=1e-6` ist größer als Pajaritos äußere absolute Schranke `1e-8`. Ein verbleibender innerer Gap von ungefähr `6.84e-7` darf daher bereits den inneren Solver beenden, während die äußere OA noch weiterlaufen muss. Die beobachtete Wiederholung führt zum 100-Iterationen-Limit.

Die Ein-Faktor-Kontrolle am identischen Doppeldivisor-Input (SHA256 `2f16ef548a55bf63e83f8400b9627875cf58f55e64c317357255a0d37f3549db`) bestätigt den Mechanismus: Standardschranke `ITERATION_LIMIT/NO_SOLUTION` nach 61.18 s, ausschließlich `mip_abs_gap=1e-10` geändert: `OPTIMAL/FEASIBLE_POINT` nach 1.82 s. Im Original-Defaultmodell führen die engere absolute Schranke und zusätzlich `dual_feasibility_tolerance=1e-9` ebenfalls zu `OPTIMAL`.

Diese bloße Optionskorrektur wird trotzdem nicht als robuste Gesamtlösung übernommen: Ihre Default-Originalbounds liegen um `2.4434980469e-10` beziehungsweise `2.1623738952e-10` oberhalb eines exakt zulässigen Zeugen in genau derselben Originalkoordinate. `pajarito_diagnosis_verified.json` enthält die vollständigen rationalen Vergleiche und Originalresiduen. Der negative historische Befund wird weder entfernt noch umgedeutet.

## Gurobi-Boundwiderspruch und Objective-Koordinaten

Das unveränderte serialisierte Original hat SHA256 **`fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07`**, 3.680 Variablen, 1.353 Integer und 144 RSOCs. Constraint-Multimengen, Variablennamen, Objective-Koeffizienten und Konstante wurden separat exakt verglichen. Der historische Zeuge ist erneut rational exakt zulässig; sein Originalziel beträgt `0.01869304116753802` (exakter Bruch im maschinenlesbaren Ergebnis).

Ohne Konditionierung meldet Gurobi `OPTIMAL` mit Bound `0.018702546414934892`: Überschuss `9.505247396874162e-6`. Engere Dualtoleranz reduziert, beseitigt den Konflikt aber nicht (ungefähr `9.4731e-9`). MOSEK meldet auf demselben unskalierten Original ebenfalls einen zu hohen numerischen Bound (ungefähr `1.0810e-8`). Eine fehlende Modellgleichung oder ein vergessener Offset ist somit durch die vollständigen Koeffizientenprüfungen ausgeschlossen; die Befunde sind mit numerischer Objective-Empfindlichkeit vereinbar und keine bewiesene Aussage über interne Herstellercuts.

Die originale kleinste Objective-Koeffizientengröße ist `3.7524903900502144e-9`, die größte 1; die Konstante ist `2.178606398164727e-15`. Multiplikation **aller** affinen Terme einschließlich der Konstante mit `2^20` ist im Original exakt binär-rational und beseitigt die beobachteten Widersprüche. Jeder endgültige Lauf prüft seine tatsächliche Float64-Multiplikation nochmals exakt. Die bestehenden Rebase-/Divisionsrundungen werden davon getrennt als affines `delta(x)` rekonstruiert. Es existiert kein vorgetäuschter globaler Rundungsbound.

Der finale Original-Defaultlauf liefert Originalziel `0.01869304118645646`, nominalen numerischen Bound `0.018693041155797716`, Backendziel `19601.074355129764` und Backendbound `19601.074322981745`; finaler Solve `0.1204901` s, Startgenerierung `0.6201218` s. Beim `reference_24snap/G3/double_costscale` beträgt der finale Solve `0.1177927` s plus `0.498931` s Kandidatenerzeugung; Originalziel `14128094.100606883`. Das literal serialisierte Defaultmodell hat eine andere ursprüngliche Kostenkoordinate als der normalisierte registrierte Studienfall; ihre Zahlen werden nicht vermischt.

In allen 37 finalen G3-Läufen liegt der numerische Backendbound unter dem exakt ausgerechneten Backendziel eines exakt zulässigen historischen Zeugen. Das beseitigt diese Gegenbeispiele, zertifiziert aber keinen global gültigen Solverbound. `compare_formulations` lässt deshalb `effective_global_lower_bound` und die globale Währungsgap-Abnahme für diese nativen Bounds offen und führt `numerical_inconclusive`. Rohtermination `OPTIMAL` und akzeptierte globale Aussage sind getrennte Felder.

## Modell- und Feasible-Set-Erhaltung

`transformationsnachweis.md` führt den algebraischen Nachweis und die adversarialen Prüfungen aus. Die 27 frisch gebauten BASE/G0/G3-Modelle und 18 tatsächlich emittierten früheren Objective-Snapshots sind bytegleich zu den gepinnten A3.6-Inputs. Originale B-, p-, S-, M-Objekte, Kanten, Kosten, Integerdomänen, Investment-/Dispatch-/Event-/Storagemodell bleiben erhalten. `src/`, `data/`, A3.5/A3.6-Reports und historische AP3-Ergebnisse haben keinen Git-Diff zum Parent.

Die vorhandenen Increment-Variablen und die MOI-Slackvariablen sind eindeutig rückabbildbare Graphenerweiterungen. Für die finale Route wurden 37 tatsächliche Backendmodelle einschließlich linearer Zeilen, Integerdomänen, Objective, Intervallslacks und **1.368** RSOC-Quadratiken separat mit `Fraction` verifiziert. Der Nachweis erfolgt am per nativer MOI-API exportierten Solverinhalt, zusätzlich zu den LP-Texten. Ein bloßes erneutes Schreiben des JuMP-Caches wäre dafür unzureichend.

Alle 46 Originalpunkte bestehen die unabhängige Prüfung mit `1e-7`: maximale Gleichungsabweichung `1.0913033449133636e-8`, maximale Integerabweichung `5.266898028821743e-13`, größte positive polynomiale Original-RSOC-Verletzung **0**. Die Maxima aller Klassen und alle rationalen Einzelwerte stehen in `solver_comparison.json`. Die 37 tatsächlichen Backendpunkte und ihre Startpunkte bestehen ebenfalls. Die neuen Solverpunkte werden ausdrücklich nicht als rational exakt zulässig deklariert. Die historischen exakten Zeugen bleiben dagegen exakt zulässig.

## Tatsächlich ausgeführte Validierung

| Prüfung auf finaler Solverproduktion | Frisches Ergebnis |
|---|---:|
| Registrierte Matrix (36 G3 + 9 G0) | 45/45 OPTIMAL |
| Literal ursprüngliches G3-Defaultmodell zusätzlich | 1/1 OPTIMAL |
| Separate Originalpunktprüfung | 46/46 numerisch zulässig |
| Tatsächliche Gurobi-Backendidentitäten / -punkte | 37/37 |
| Neue gezielte Solver-/Guardtests | 34/34 |
| Volle Repositorytests | 6087/6087 |
| Gespeicherte AP3-Evidenztests | 4108/4108 |
| MOI-/JuMP-Schutzsuite | 42/42 |
| Raw-Domänenmutationen | 16/16 |
| Bestehende exakte Zertifikatssuite | 171/171 |
| Separater A3.6-Reviewerpfad | neun Fälle; 18 Primale, 18 LP-Zertifikate, 18 Objective-Koordinaten |
| HiGHS-Filterregressionen | 14/14 |
| Tatsächliche Backend-Manipulationen | 4/4 verworfen |
| Frische Modell-/Objective-Exporte | 27 + 18 bytegleich |
| Originalquellen/Runtime-Dateien, Git-Blobs | 131 / 56 verifiziert |
| CLI-Vertrag | acht echte Aktionen erfolgreich, drei negative Aktionen erwartungsgemäß Exit 1 |
| Metrikvertrag / CSV-Roundtrip | 124 IDs, 4396 Zeilen, null Wertfehler |

Die 34 Zusatztests wurden vor dem Freeze ausgeführt; ihre getesteten Solver-/Testdateien sind im finalen Commit byteidentisch. Die vollen Regressionen, Zertifikate, Matrix und CLI wurden auf der finalen Produktion erneut ausgeführt; `operations.json` und die Source-SHA-Manifeste trennen jeden Lauf von historischen oder verworfenen Zwischenständen. Keine alten PASS-Zahlen werden als neue Tests gezählt.

Der monolithische historische Sympy-Oracle konnte wegen fehlendem `sympy` nicht vollständig ausgeführt werden. Der Fehler bleibt archiviert. Für die 124 Metriken wurden exakt die unveränderten NumPy-Rohdatenfunktionen des gepinnten Oracles separat ausgeführt; der unabhängige Werte- und CSV-Prüfer prüfte anschließend alle 124 IDs. Diese gezielte Ausführung ist kein behaupteter PASS des vollständigen Sympy-Boundary-Treibers. Die erforderlichen exakten Grenz-/Zeugenzertifikate wurden über die 171er-Suite und den separaten Reviewerpfad frisch geprüft.

## Erhaltung, Rohdaten und Veröffentlichung

Die 28 fremden unversionierten `audit/`-Dateien wurden vor Branchwechsel vollständig SHA256-inventarisiert, auf Nichtkollision mit sämtlichen vorgesehenen Schreib-/Gitpfaden geprüft und nach den Läufen erneut verglichen. Keine wurde verschoben, verändert, gelöscht oder gestagt. `foreign_files_before_sha256.json`, Vorher-/Nachherbeleg und Publikationsbeleg machen das prüfbar. Alle 99 früheren Preflight-Dateien bleiben bytegleich; deren Manifest-SHA lautet `6855a46e43a6d170d858f55a858ea1a0846d6a4ac6112916503f3e31707c51c3`.

A3.6-Witness-ZIP: SHA256 `ca15ee8a3cd73eefe9c75b00896ec4f4cdb71f12e23d6fc55a0916e35417482c`, 406/406 Einträge geprüft. A3.5-EXEC-ZIP: `0ec9969de7c8659bc50d82664556c09515080beb1bcd1e937bb9cc7b8d925993`, 381/381 Einträge. Reaudit-ZIP: `9a22d037f61c1dbc6f60a2e91a27bb04aa273d110b7567241c4527cc27efa41f`, 130/130 Einträge. Zusätzlich wurden 520 Originalinputdateien, acht Wissenschaftsblobs, 55 publizierte Dateihashes, 14 historische ZIP-CRCs und 1060 Indexeinträge geprüft. Die neuen Resultate ersetzen diese Archive nicht.

`native_solver_evidence.zip` enthält die frischen Original-/Solver-/Backendmodelle, Punkte, Optionen, Runtime- und Hashnachweise, Rohlogs, Operationsbelege, Diagnoseskripte und gescheiterte Versuche. `reproduction_manifest.json` beschreibt jeden publizierten Eintrag; das Archiv wurde vollständig zurückgelesen und mit SHA256 geprüft. Nur numerische Lizenzkennungen in publizierten Textkopien wurden maskiert; Originalhash, publizierter Hash und Grund stehen pro Eintrag im Manifest. Die externen Rohoriginale bleiben unverändert. Unveränderte historische Inputkopien und Paketbinärdateien werden nicht erneut verbreitet.

## Grenzen und getrennte Gates

Geltungsbereich sind ausschließlich die neun registrierten binär-rationalen Modellinputs und die dokumentierten Skalierungs-/Toleranzmodi auf dieser Laufzeit. Die Eingabeschutzschranke verwirft nichtnull Constraint-Koeffizienten unter `1e-9`, Größen über `2^40`, nicht exakt abbildbare Intervallweiten und nicht sicher konditionierbare Objectives. Solche Eingaben liefern `OPTIMIZE_NOT_CALLED/NO_SOLUTION` und eine Diagnose, kein mathematisches `INFEASIBLE`. Der `<1e-12`-Adversarialfall demonstriert eine Restgrenze des alten HiGHS-Filters; die neue Route verwirft ihn sicher vor Solve. Die geprüften registrierten Originalkoeffizienten liegen klar innerhalb der Schranken. Dies ist keine universelle numerische Robustheitsgarantie und keine Zertifizierung sämtlicher interner Herstellercuts, Presolveoperationen oder Branch-and-Bound-Knoten.

G3-MISOCP-Erfolg belegt keine native G0-MISDP-Fähigkeit. G0 behält den vorhandenen Pajarito-Vergleich; M3 bleibt separat. Die neun alten rationalen Kostenintervalle sind ausschließlich in ihrer ursprünglichen normalisierten binär-rationalen Domäne erhalten, keine neu bewiesenen optimalen Integerkosten. Lizenzabhängigkeit, endliche Ressourcen, unabhängige Abnahme, wissenschaftliche Ratifizierung und Datenqualifikation bleiben offen.

`B1_repaired=false`, `native_G3_MISOCP=numerical_inconclusive`, `integer_optimality_proved=false`, `integer_globality=case_specific_partial`, `science_amendment_approved=false`, `independent_A3_5_accepted=false`, `A3_closed=false`, `AP4_ready=false`, `empirical_study_ready=false`. Nur ein neuer unabhängiger A3.7-B1-Reviewer darf die materielle Korrektur im expliziten Geltungsbereich akzeptieren. Alle weiteren Bedingungen und Pflichtprüfungen stehen im eigenständigen `reaudit_handoff.md`.
