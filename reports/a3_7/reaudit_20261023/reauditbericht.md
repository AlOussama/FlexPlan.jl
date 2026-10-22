# A3.7-B1-REAUDIT — unabhängige Abnahme der nativen G3-MISOCP-Korrektur

Datum: 23.10.2026, Europe/Berlin. Rolle: eigenständiger Acceptance-Reviewer in einem neuen Chat; keine Beteiligung an der Implementierung. Alle hier als frisch bezeichneten Resultate wurden in diesem Auftrag neu erzeugt. Die UTC-Zeitstempel der Rohlogs liegen am 22.10.2026 nach 22 Uhr, entsprechend 23.10.2026 MESZ.

## Urteil und Reichweite

**`ACCEPTED_FOR_REGISTERED_FINITE_DOMAIN`**. Die M2-Korrektur wird unabhängig als funktionierende native G3-MISOCP-Solverroute für die neun registrierten Inputs, ihre vier G3-Modi und den zusätzlichen literal serialisierten Originaldefault akzeptiert. **`B1_repaired=true` gilt ausschließlich für diesen nachgewiesenen Bereich.** Die neun G0-Vergleichsläufe qualifizieren den vorhandenen Vergleichspfad, keine native MISDP-Fähigkeit von Gurobi.

Dieses Urteil umfasst exakte Erhaltung der eingefrorenen binär-rationalen G3-Constraints durch die finale Backendabbildung, numerische Originalzulässigkeit der ausgegebenen Punkte innerhalb der vorgegebenen Schranke `1e-7`, reproduzierten Solverabschluss und die konservative Behandlung nativer Bounds. Es umfasst keinen exakten Beweis optimaler Integerkosten und keine allgemeine Robustheitsgarantie für Float64-MISOCPs. Die ursprüngliche ideale reelle Modellierung und ihre wissenschaftlichen Freigaben werden nicht durch eine Gleichsetzung von Float64-`sqrt(2)` mit der irrationalen Zahl ergänzt.

**`A3_closed=false`, `AP4_ready=false`, `integer_optimality_proved=false`.** Die vollständigen Gates stehen in `release_gates.yaml`; M3 übernimmt die globale Integerfrage.

## Autorität, Specification Gate und Erhaltung

Repository: https://github.com/AlOussama/FlexPlan.jl.

| Rolle | exakt geprüfter SHA |
|---|---|
| Implementierungskandidat | `0ca85adad5b6bcdff5a3ce8df54f5b8ac8eb8568` |
| Solverproduktion | `f302b7b63e917678fb14b7cbc3cfdbc0d8c624a1` |
| A3.6-Ausgangsbasis | `15ba10c193a562a48cb0e1dcc6fa12d922ac0613` |
| Separater Backendnachweis | `6b6bcd8b0f00caa3a7ee7d7e89fe1085596bd7fc` |

Zuerst wurden der vollständige verbindliche Handoff und danach der Implementierungsbericht am Kandidaten gelesen, anschließend Transformationsnachweis, Reproduktionsanweisung, Operationsmanifest, Publikationsreceipt und Prüfcodes. `SPECIFICATION_READY`: Inputs, Matrix, numerische Schranke, Negativkontrollen und Freigabegrenzen sind vorgegeben; keine neue wissenschaftliche Methode wurde entwickelt.

HEAD und Remote-Kandidatenbranch wurden unabhängig auf den Kandidaten geprüft. Die Review-Branch `codex/a3-7-b1-independent-reaudit-20261023` wurde genau davon im vorhandenen Checkout erstellt. Keine neuen Worktrees, Produktionsänderungen, Merges, Resets oder Branchlöschungen. Die Ancestrykette wurde mit Git geprüft. Gegenüber der Produktionsrevision bleibt die Laufzeit unverändert; die spätere Änderung an `verify_native_g3.py` betrifft den separaten Intervall-Slacknachweis. `src/`, `data/`, A3.5/A3.6 und historische AP3-Ergebnisse sind zur Ausgangsbasis unverändert.

Alle 28 fremden unversionierten Dateien unter `audit/` wurden vollständig vor und nach dem Audit mit SHA256 verglichen. Alle ursprünglichen Refs und die sechs anderen Worktree-Registrierungen blieben unverändert. Das eigene Audit ist ausschließlich additiv unter diesem Reportverzeichnis veröffentlicht. `provenance.json`, `foreign_before.json` und der Publikationsbeleg dokumentieren diese Kontrollen.

Die Archivprüfung ergab 406 A3.6-Witness-, 381 A3.5-EXEC-, 130 frühere Reaudit- und 1.738 Implementierer-Evidenzeinträge mit vollständigen Hashprüfungen. Zusätzlich wurden 55 frühere publizierte Dateien, 1.060 Indexeinträge, 520 ursprüngliche Inputs und acht wissenschaftliche Git-Blobs überprüft. Die wissenschaftlichen Blobs werden dadurch nicht ratifiziert. Die 251 vorhandenen Manifest-Dependency-Einträge sind unverändert; hinzu kamen ausschließlich die gepinnten Mosek-/MosekTools-Einträge.

## Unabhängige mathematische Prüfung

Die Originalkonstruktion bleibt `M=B-alpha*S`, `S=diag(p)`, `B=B0+diag(b_fix+b_src)`. Der unveränderte G3-Bauer verwendet jede strukturell nichtnull ungerichtete Kante genau einmal, verlangt feste symmetrische Offdiagonalen und erzeugt `q_ij,q_ji>=0`, diagonale Budgetslacks sowie `(q_ij,q_ji,w_ij)` im gedrehten Lorentzkegel. `w_ij` ist der bereits emittierte binär-rationale Float64-Ausdruck `sqrt(2.)*M_ij`. B-, p-, S-, M-, Kanten-, Slack-, Integer- und Kostenbytes wurden über frische Exporte mit den gepinnten Referenzen verglichen, nicht aus einem Implementierer-PASS übernommen.

Für affine Komponenten `u(x),v(x),w(x)` lautet die tatsächlich exportierte finale Erweiterung:

```
U=u(x), V=v(x), W=w(x), U>=0, V>=0, W²-2UV<=0.
```

Einsetzen beweist beide Richtungen der Projektion: Für jeden ursprünglichen Kegelpunkt existiert genau die durch die Links bestimmte Erweiterung; jede erweiterte Lösung erfüllt `u,v>=0` und `2uv>=w²`. Die finale Abbildung enthält keine `1/sqrt(2)`-Standardrotation. MOI speichert diagonale Quadratiken mit Halbkonvention: der exportierte Diagonalkoeffizient 2 bedeutet `W²`; der Kreuzkoeffizient -2 bedeutet `-2UV`.

Die ergänzten nativen Variablenbounds sind redundant, weil jeweils bereits eine exakt identische affine Zeile `1*U>=0` beziehungsweise `1*V>=0` existiert. Sie ermöglichen Gurobis Konvexitätserkennung mit `NonConvex=0`. Die affine Intervallbedingung `l<=f<=h` wird durch `f=z`, `z in [l,h]` dargestellt. Links, Endpunkte und die exakt darstellbare Intervallweite wurden geprüft. Die ursprünglichen Integerdomänen bleiben erhalten; es gibt keine Fixierung aus dem Startlauf.

Der geprüfte vollständige Constraint-Multimengenvergleich am tatsächlich nativen Export umfasst lineare Zeilen, Intervallslacks, Integerdomänen, Objective und Hilfsvariablen. Zusätzlich substituiert das neu geschriebene Reviewer-Oracle die nativen Quadratikvariablen unabhängig symbolisch zurück und vergleicht die resultierenden Polynommultimengen. **37/37 tatsächliche G3-Backends und 1.368/1.368 Quadratiken stimmen exakt überein.** Falsches Kreuzvorzeichen, fehlender Quadratterm, verschobene Link-RHS und veränderte Intervallgrenze werden alle verworfen. Jede der 46 Integerpunktmutationen wird ebenfalls verworfen.

Die temporäre Standardrotation dient ausschließlich zur Startpunkterzeugung. Der Quellcode liest daraus keinen Bound und fügt keine Integerfixierung oder andere Constraint hinzu. Die 37 Startpunkte wurden zusätzlich durch das eigene rationale Originalpunkt-Oracle geprüft. Der finale Optimierer löst das exakt abgebildete Modell erneut.

## Vollständige Objective-Koordinate

Das vorhandene Rebase erzeugt für ausgewählte Variablen mit unterer Grenze `l>0` die Graphvariable `z=x-l`, `z>=0`. Diese Graphenerweiterung ist exakt projektionsäquivalent, weil die ursprüngliche untere Grenze fortbesteht. Algebraisch gilt `c*x=c*z+c*l`. Die tatsächlichen Float64-Additionen und Divisionen erzeugen jedoch einen gesonderten affinen Rundungsrest.

Seien `C(x)` die ursprünglichen emittierten Kosten, `F_s(x,z)` die tatsächlich rebased und durch `s>0` dividierte Float64-Funktion und `r=2^k`. Die finale Funktion ist `F_backend=r*F_s`. Das eigene Oracle prüft die tatsächlichen Koeffizienten nach Division und Multiplikation und die exakte Rückdarstellbarkeit aller mit `r` skalierten Terme einschließlich Konstante. **Die zusätzliche Zweierpotenzmultiplikation ist exakt; sie erhält die Ordnung von `F_s`.**

Nach Eliminierung der Graphvariablen wurde für jeden Lauf unabhängig rekonstruiert:

```
(s/r)*F_backend(x,z(x)) = C(x) + delta(x).
```

Alle nichtnull Koeffizienten und die Konstante von `delta` stehen in `reviewer_oracle.json`. Bei 45 normalisierten Läufen ist `delta` nicht identisch null; beim literal Originaldefault ist es null. Die vollständigen rationalen Residuen und Deltas stimmen mit dem separat neu ausgeführten eingereichten Prüfer überein. **Eine exakte Gleichheit der normalisierten Float64-Objectives mit den ursprünglichen Kosten wird deshalb ausdrücklich nicht attestiert.** Es wird auch keine globale Schranke für `delta(x)` erfunden.

Das Originalziel jedes ausgegebenen Punktes wird direkt mit `C` ausgewertet. Native Bounds werden gegen exakt zulässige Zeugen in derselben tatsächlichen Backendkoordinate verglichen. Ihre nominale Rückkonversion ist kein rigoroser Währungsbound. Der frische CLI-Vergleich lässt `effective_global_lower_bound` und die globale Währungsgap-Abnahme für native G3-Ergebnisse offen und klassifiziert sie entsprechend als `numerical_inconclusive`.

## Frische numerische Reproduktion

Laufzeit: Julia 1.10.11, JuMP 1.31.1, MOI 1.51.2, Gurobi.jl 1.9.2 / tatsächlich Gurobi 12.0.3, Mosek.jl 11.0.1, MosekTools 0.15.10 / tatsächlich MOSEK 11.0.29, HiGHS.jl 1.24.1 / HiGHS 1.15.1, Clarabel 0.11.1 und Pajarito 0.8.3. Native Versionsmeldungen, geladene DLLs und echte Solves sind archiviert. Die Gurobi-JLL-Metadaten dienen nicht als Laufzeitnachweis.

Beide kommerziellen Solver lösten das echte Integer-RSOC-Problem `min x`, `0<=x<=10`, `x` ganzzahlig, `y=1`, `(x,y,3) in Qr` mit Optimum 5. Der zusätzliche öffentliche Capabilitypfad führt echte LP-/MILP-/SDP-/SOCP-/MISOCP-/MISDP-Proben für HiGHS, Clarabel und Pajarito aus und dokumentiert auch nicht unterstützte Kombinationen. G3-Erfolg wird nicht in native G0-MISDP-Fähigkeit umgedeutet.

Die frische Matrix umfasst die neun Fälle `bess_premium_3snap`, `connectivity_3snap`, `event_price_3snap`, `exposure_multiplier_3snap`, `reference_24snap`, `reference_3snap`, `reference_6snap`, `source_reactance_3snap`, `threshold_3snap`: jeweils G3 mit Produktions-, Halb-, Doppeldivisor und engerer Feasibility sowie einmal G0. Hinzu kommt der literal Originaldefault mit SHA256 `fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07`, 3.680 Variablen, 1.353 Integer und 144 RSOCs.

**46/46 `OPTIMAL/FEASIBLE_POINT`, 46/46 unabhängig numerisch zulässige Originalpunkte, 37/37 zulässige Backend- und Startpunkte.** Die Polynomial-, Linear- und Integerresiduen wurden aus den ausgegebenen Zahlen als rationale Werte neu berechnet. G0-Punkt-PSD-Eigenwerte sind numerisch; die historischen PSD-Zeugen wurden im separaten Reviewerpfad über exakte Hauptminoren geprüft.

| Originalresiduum, Maximum über 46 Läufe | Wert |
|---|---:|
| Gleichungen | `1.0913033449133636e-8` |
| Untere Ungleichungen | `4.9649173661237e-13` |
| Obere Ungleichungen | `7.638334409421077e-13` |
| Intervalle | `0` |
| Integerabweichung | `5.266898028821743e-13` |
| Positive polynomiale RSOC-Verletzung | `0` |

Alle liegen innerhalb `1e-7`. Die neuen Punkte sind wegen nichtnull Residuen **keine rational exakt zulässigen Zeugen**. Die historischen Zeugen sind separat exakt zulässig.

| Fall | Originalziel | nomineller Originalbound | Start / Vorbereitung / final, Sekunden |
|---|---:|---:|---:|
| Literal Originaldefault | `0.01869304118645646` | `0.018693041155797716` | `0.857261 / 0.045223 / 0.132195` |
| reference_24snap, Doppeldivisor | `14128094.100606883` | `14128094.077432465` | `0.486714 / 0.038475 / 0.120735` |

Die vollständige Matrix benötigte 339,55 s einschließlich Modellaufbau, Kompilierung und Exporten. Maximaler finaler G3-Solve: 0,4321 s; maximale Startphase: 2,8557 s; maximale native Vorbereitung: 2,2215 s. Die konfigurierten Grenzen sind 30 s für den Start und 120 s für den finalen Solve. Die separat ausgewiesenen Phasensummen sind keine vollständige Ende-zu-Ende-Zeit pro Fall. Parallel laufende Prüfprozesse beeinflussen die Wandzeiten. Der literal Default wurde gemäß integriertem Reproduktionstreiber zuletzt ausgeführt; die beiden Default-/Doppeldivisorbefunde sind separat ausgewiesen.

## Reproduzierte Widersprüche und Kausaldiagnose

Der historische Zeuge ist im literal Originalmodell exakt zulässig mit Ziel ungefähr `0.01869304116753802`. Der unabhängige rationale Vergleich liefert folgende Überschüsse eines numerischen Bounds über diesen zulässigen Punkt:

| Solver / unveränderte Originalkoordinate | Boundüberschuss |
|---|---:|
| Raw Gurobi | `9.505247396874162e-6` |
| Gurobi, engere Dualtoleranz | `9.473084719847354e-9` |
| Raw MOSEK | `1.0810351163260386e-8` |
| Pajarito, engerer absoluter innerer Gap | `2.443498046908314e-10` |
| Pajarito, zusätzlich engere Dualtoleranz | `2.1623738951730018e-10` |

Alle sind echte Gegenbeispiele zur rigorosen Interpretation dieser numerischen Bounds. Die vollständigen Original-Constraintmultimengen und Objectivekoordinaten wurden geprüft; ein vergessener Offset erklärt sie nicht. Gurobi mit kompletter `2^20`-Objectiveverstärkung und MOSEK mit derselben Verstärkung zeigten diese Gegenbeispiele frisch nicht. Auch in allen 37 finalen G3-Läufen liegt der Backendbound unter dem exakt ausgewerteten zulässigen Backendzeugenziel. Fehlende Gegenbeispiele sind **kein Beweis globaler Boundgültigkeit** und kein Zertifikat interner Herstellercuts oder des Nodebaums.

Die Ein-Faktor-Kausalprobe verwendet in beiden Läufen exakt Inputhash `2f16ef548a55bf63e83f8400b9627875cf58f55e64c317357255a0d37f3549db`. Mit innerem HiGHS-Default `mip_abs_gap=1e-6` gegenüber Pajarito `tol_abs_gap=1e-8` wurde `ITERATION_LIMIT/NO_SOLUTION` nach 92,90 s reproduziert. Ausschließlich `mip_abs_gap=1e-10` geändert: `OPTIMAL/FEASIBLE_POINT` nach 3,39 s. Die Optionsdictionaries und Inputhashes wurden unabhängig verglichen. Die Abweichung zu den Implementiererzeiten 61,18/1,82 s betrifft Laufzeiten, nicht Status oder Ursache. Die verbleibenden Pajarito-Boundgegenbeispiele verhindern, diesen Optionenlauf als robuste Gesamtclosure zu werten.

Die 14 Filterregressionen reproduzieren Default-Falsch-Infeasibilität, den akzeptierten `1e-12`-Fix, exakte vollständige `2^33`-Zeilenskalierung und die adversariale Restgrenze unter `1e-12`. Der native Guard verwirft die winzigen Constraintkoeffizienten vor Solve mit `OPTIMIZE_NOT_CALLED/NO_SOLUTION`, ohne mathematisches Infeasibilityurteil. Die duale RSOC-Schnittaussage folgt aus Selbstdualität: `y in Qr` impliziert `<y,z>>=0` für alle `z in Qr`; falsches Vorzeichen, fehlender Term, dual unzulässiger Vektor oder positive RHS am Ursprung werden verworfen. Dies zertifiziert den geprüften Schnitt, nicht alle internen Solvercuts.

Die früheren MOSEK-46er-Versuche mit 120-s-Stresslimits sind im verifizierten Implementiererarchiv erhalten. Im Reaudit wurden Capability und raw/skalierte Originalläufe frisch ausgeführt; die beiden vollständigen alternativen MOSEK-Matrizen wurden nicht nochmals ausgeführt. Die unabhängige native Qualifikation gilt für die gewählte Gurobi-Route.

## Tests, CLI, Metrikvertrag und Grenzen

| Frische Prüfung | Ergebnis |
|---|---:|
| Vollständige Repositoryregression | `6087/6087` |
| Gespeicherte AP3-Evidenzsuite | `4108/4108` |
| MOI-/JuMP-Schutzsuite | `42/42` |
| Raw-Domänenmutationen | `16/16` |
| Exakte Zertifikatssuite | `171/171` |
| Separater A3.6-Reviewer | 9 Fälle; 18 Primale, 18 LP-Zertifikate, 18 Objectivekoordinaten |
| Neue native Solver-/Guardtests | `34/34` |
| Filterregressionen | `14/14` |
| Tatsächliche Backendmanipulationen | `4/4` verworfen |
| Frische Exporte | 27 Modelle + 18 Objectives identisch; 131 Dateien / 56 Git-Blobs geprüft |
| Öffentliche CLI | 8 Aktionen Exit 0; 3 absichtlich ungültige Aktionen Exit 1 |
| Metrik-/CSV-Vertrag | 124 IDs, 4.396 Zeilen, keine Wertefehler |

Der vollständige historische Sympy-Treiber wurde tatsächlich gestartet und scheitert mit `ModuleNotFoundError: No module named 'sympy'`, Exit 1. Das ist ein dokumentierter Umgebungsausfall, kein bestandener Negativtest und kein vollständiger Oracle-PASS. Als begrenzte Alternative wurden die unveränderten NumPy-Rohdatenfunktionen des historischen Oracles sowie der unabhängige 124-Metrik-/CSV-Prüfer frisch ausgeführt. Exakte Grenz-/Zeugenzertifikate sind über die 171er-Suite und den separaten rationalen Reviewerpfad gedeckt. Eine vollständige Ausführung des monolithischen Sympy-Treibers bleibt offen.

Bewusst nicht umgesetzt: Produktionskorrekturen, alternative wissenschaftliche Modelle, neue Benchmarks, universelle Guardqualifikation, globale Integerenumeration, Lizenzänderungen oder Dependency-Upgrades. Die Wiederverwendung betrifft die gepinnten Modellbauer, Reproduktions- und Zertifikatstreiber; neu sind ausschließlich Reviewer-Oracles, Aufzeichnung, Bericht und Evidenzpaket. `REUSE_REJECTED`: eingereichte PASS-Flags als Abnahmebeweis — eigenständige Neuberechnung erforderlich.

## Freigabegates und M3-Handoff

Freigegeben ist die **begrenzte technische und numerische B1-Reparatur** in der tatsächlich geprüften Domäne. Die exakte Erhaltung der Constraints gilt zwischen den exportierten eingefrorenen Float64-Modellen und ihren finalen Graphenerweiterungen. Der Wissenschafts-/Theorem-Geltungsbereich wird dadurch nicht erweitert.

M3 erhält Kandidat, Produktionsrevision, ursprüngliche neun rationalen Kostenintervalle, die frischen exakt geprüften historischen Zeugen, native Lösungen als numerische Kandidaten, tatsächliche Backendmodelle und sämtliche affinen Deltas. M3 muss Lower Bounds und Integeroptimalität in einer explizit festgelegten Originalkoordinate rigoros nachweisen. Ein nativer `OPTIMAL`-Status oder nominaler Währungsbound genügt nicht. Die neun übernommenen Intervalle gelten ausschließlich für ihre ursprünglichen normalisierten binär-rationalen Modelle; neue optimale Integerkosten sind nicht bewiesen.

Für erweiterte Inputs, andere Koeffizientendomänen oder eine neue Runtime ist eine neue Qualifikation erforderlich. Nichtnull Constraintkoeffizienten unter `1e-9`, Größen über `2^40`, inexacte Intervallweiten und unsicher konditionierbare Objectives gehören nicht zum freigegebenen Bereich. Keine universelle G0/G3-Äquivalenz oder Herstellerbaumzertifizierung wird attestiert. Wissenschaftliches Amendment, Ownerratifizierung, unabhängige A3.5-Gesamtabnahme sowie Daten-/Empiriequalifikation bleiben separate offene Entscheidungen.

`m3_handoff.md` enthält den konkreten Folgeauftrag. Historische Gate-Dateien bleiben unverändert; allein die neue additive Reviewentscheidung setzt `B1_repaired` in diesem begrenzten Bereich.

## Evidenz und Reproduktion

`reproduction_manifest.json` nennt jeden publizierten ZIP-Eintrag mit SHA256, Umfang, externem Originalhash und gegebenenfalls Maskierung. Das Archiv wurde vollständig zurückgelesen. Enthalten sind frische Modelle, Punkte, Rohlogs, Diagnoseinputs/-outputs, alle Befehle mit Exitcodes/UTC-Zeiten und die eigenständigen Oracleergebnisse. Nur numerische Lizenzkennungen in Textkopien wurden maskiert; externe Originale sind erhalten.

Externe Originale: `D:/Downloads/A37_B1_REAUDIT_20261023`. Bereits vorhandene Inputkopien und Binärpakete werden nicht erneut publiziert. `package_sha256.json` schützt das additive Reportpaket. Die Reproduktion ist in `reproduce.md` beschrieben. Das Publikationsreceipt nennt den geprüften Remote-Reviewcommit; ein automatischer Merge ist nicht erfolgt.
