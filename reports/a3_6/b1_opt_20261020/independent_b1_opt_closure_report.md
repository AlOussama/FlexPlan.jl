# Paper A — A3.6-B1/OPT: unabhängiger technischer Abschlussbericht

20.10.2026. **Einziger Schlussstatus: `correction_ready_for_independent_reaudit`.** Der konkrete native False-Infeasibility-Fehlpfad ist bis zu einer veränderten OA-Ungleichung isoliert und lokal korrigiert. Die robuste native G3-Zuverlässigkeit und die enge globale Integeroptimalität aller neun Fälle sind weiterhin offen. `A3_closed=false`, `AP4_ready=false`.

## 1. Auftrag, Identität und Unabhängigkeit

Autorität ist der verbindliche Makroauftrag `e49b64216f82eefda77d6997ed68ed2d12c8ae78`. Prüfziele bleiben unverändert Original AP3 `485b637cc1998a327206c5929434bd26c6f0be16`, EXEC-Eingang `4d9f346c5fca80e00fd01d96c39a2bac91776ac0` und Exportmetadatenfix `e1e075626b38b478faf57efe62e557fc94753f00`. Zwischen EXEC und Auftragshead liegt nur die neue Auftragsdatei. Branch-/Parent-/Merge-Base-/Remoteprüfungen stehen in der neuen Autoritätsprovenienz. Die Original-AP3-Branch bleibt am gepinnten SHA. Neue einzige Produktionsbranch: `fix/paper-a-a3-6-b1-opt-v1`, Parent e49b642; Korrekturcommit **`910d44122a37d9ed2cca06940740b46706c73d40`**. Ausgangs- und Evidenzcommit werden im Publikationsnachweis getrennt geführt.

Der Audit wurde im neuen Chat unabhängig von AP3-Implementierer und A3.5-EXEC-Auditor ausgeführt. Bestehende Programme und akzeptierte Gleichung-zu-Code-Belege wurden als Werkzeuge/Quellen verwendet; frühere PASS-Flags ersetzen keine neu ausgeführten Prüfungen. Eigene Produktionskorrektur löst ausdrücklich eine weitere personell unabhängige Abnahme aus. Diese steht aus.

research-map bleibt read-only: Freeze 2c2fce769b2ed6ffd4f1ced60c0798776acccc93, Dissertation e8118425adc335a99e85120d943763305f211315, Paper-A-Scope 672a61c95525bf1d7a03cf745a754a15a23ce78b, SCIENCE/FINAL 2badb9a90a8d3c1d4a33accee640b295de1e33a1, vorgeschlagenes Amendment 5ceb19a6faf4e7c7e797a737ed5b449f9e2db609 / Blob fba4802ecabade61a752833a71106a5bda4ce78f, nicht ratifiziert. Producer bleibt read-only: b9e4efec8c2939bff1a65ae4ccb66cfbcf9cb62c, verwendete Datenhistorie 3b8fdb01d931225edc5f8fe1e2c200d0da288a09.

## 2. Specification Gate, Wiederverwendung und Diff

`SPECIFICATION_READY`: Fälle, Diagnosekette, Validierung, Grenzen und zulässige Terminalzustände sind vorgegeben. Wiederverwendet wurden AP3 prepare/build/solve!/extract, originale MOI-Exports, hashgesicherte Seedzeugen, BASE-LP-Kostenskalierung und die bestehenden tatsächlichen JuMP/MOI-/Domänentests. Neue Komponenten sind eng auf B1/OPT begrenzte Forensik, exakte Primal-Recovery, rationale LP-LB-Zertifikate und ein separater Verifikator.

Produktionsdiff: eine zusätzliche HiGHS-OA-Option `small_matrix_value=1e-12`, mit zwei erklärenden Kommentarzeilen. Keine neue Modellgleichung, Integer-Relaxation, Kostenannahme, Statusmanipulation oder Dependencyänderung. Alle Daten, historischen Archive, fremden Worktrees und untracked AP2-audit-Dateien bleiben erhalten. Keine PR, kein Merge, Rebase, Reset, Force-Push oder Branchlöschung.

## 3. Eingangsidentität und Reproduktion des Widerspruchs

Das EXEC-Archiv wurde vollständig erneut verifiziert: **24.237.795 Bytes**, SHA256 `0ec9969de7c8659bc50d82664556c09515080beb1bcd1e937bb9cc7b8d925993`, **381/381 Einträge** in Hash und Größe korrekt. Jeder verwendete Eingang ist im neuen Inputmanifest gebunden.

Die vorgeschriebene Folge Native → vollständiger Witness-Transfer → Native wurde zweimal am Original und einmal am unveränderten Metadatenfix ausgeführt. **6/6 native Solves: INFEASIBLE/NO_SOLUTION.** Alle sechs Modellbytehashes stimmen mit `fcd52695238591d6c6019385d64e4407e1ea480849ca4125e1191b992581ab07` überein. Das Modell enthält 1353 Integerrestriktionen. Höchste ursprüngliche Witnessverletzung `7.515349001601957e-12`; nach tatsächlichem Bridging Kegelabstand `8.835133427034015e-11`, Gleichungsresidual rund `4.263256414560601e-14`.

Über die Float64-Zeugen hinaus liegt jetzt ein rational rekonstruierter Punkt vor, der alle serialisierten Original-G3-Constraints exakt erfüllt. Dasselbe gilt separat für G0. Damit ist exakte Feasibility der ausdrücklich normalisierten binären Modellkoeffizienten belegt; eine solche Aussage wird nicht auf ungerundete physikalische Quelldaten übertragen.

## 4. Kausale B1-Kette und Korrekturgrenze

Source/JuMP/Bridging führen für den übertragenen Punkt zu konsistenten Modellen. Die kontinuierliche Root-Kegelrelaxation ist OPTIMAL. Der erzeugte OA-MIP wird durch HiGHS' Koeffizientenfilter verändert: In einer gültig erfüllten Zeile mit drei Koeffizienten zwischen 4.58e-11 und 1.30e-10 bleiben nach Filterung keine Variablenterme, aber RHS **3.025002202302713e-8** übrig. Bei MIP-Feasibility 1e-8 wird daraus Infeasibilität. Der neu erzeugte Ein-Zeilen-/Integer-Dummy-Gegenfall reproduziert genau diesen Mechanismus. Er löst mit erhaltenen Koeffizienten oder exakt geprüfter positiver Zweierpotenzskalierung.

Die neue Solveroption erhält diese kleinen Koeffizienten. Der eingefrorene Original-OA-MIP wird damit numerisch OPTIMAL. Dies ist ein belegter lokaler Konfigurationsfix. Er ist kein allgemeiner Beweis für jede erzeugte OA-Normale oder jeden MIP-Baum. Die Mindestschwelle 1e-12 ist weiterhin endlich; kleinere Koeffizienten können andere Fälle betreffen.

Neu ausgeführte, betroffene Ausgangsmatrix: **54 Läufe**, Statusverteilung `{'ITERATION_LIMIT': 10, 'OPTIMAL': 43, 'INFEASIBLE': 1}`. Neue Fix-/Stressmatrix: **45 Läufe**, Statusverteilung `{'OPTIMAL': 44, 'ITERATION_LIMIT': 1}`. Die kostskalierten G3-Primärläufe und G0-Vergleichsläufe lösen numerisch; **reference_24snap bei doppeltem Divisor bleibt ITERATION_LIMIT**. Der Defaultpfad ohne explizite Kostenskalierung ist ebenfalls nicht durch den einzelnen Optionsfix geschlossen. `native_G3_MISOCP=numerical_inconclusive`, `B1_repaired=false`. Der Patch ist getrennt zur unabhängigen Nachprüfung bereit.

Gurobi wurde neu tatsächlich angesprochen: Error 10009, abgelaufene Lizenz 12.10.2026. MOSEK 11.0 liest das echte Integer-CBF und endet erneut mit 1001/LICENSE_EXPIRED; Exit -1. Keine Lizenz wurde verändert und keine alternative native Solverabnahme behauptet.

## 5. Neun globale Kostenintervalle und Beweisniveau

Alle neun Raw-Case-SHAs sind einzeln im Ledger enthalten. Die BASE-LP-Constraints sind als echte Relaxation der tatsächlichen G0-/G3-Modelle geprüft; die emittierten Objectives stimmen zwischen diesen Modellen exakt überein. Der neue Verifikator prüft alle vollständigen rationalen Integerzeugen, bei G3 die Kegelprodukte, bei G0 alle Hauptminoren. Er prüft unabhängig jede LP-Bound-Inferenz, Dualrichtung, Stationaritätsrestkorrektur und Boundsumme. **171/171 Prüfungen**, einschließlich negativer Zertifikats-/Integer-Mutationen. Es wurde keine wissenschaftliche Fehlertoleranz erfunden.

Die Tabelle verwendet die separat rekonstruierte ursprüngliche Rohwährungsfunktion auf der normalisierten Modelldomain. Anzeigeendpunkte sind Float64 nach außen gerundet; rationale Brüche im JSON sind maßgeblich. Gültige globale Intervalle bedeuten hier noch keine enge Integeroptimalitätszertifizierung.

| Fall | rigoroser LB | rigoroser UB | exakte Breite, dezimal angezeigt | historisches numerisches UB−LB |
|---|---:|---:|---:|---:|
| bess_premium_3snap | 2524596.121899694 | 2524596.121902168 | 2.47362584e-06 | -2.05705874e-05 |
| connectivity_3snap | 2585242.788803075 | 2594530.970268474 | 9288.18147 | -5.54658473e-05 |
| event_price_3snap | 5607031.884446461 | 5608912.202479163 | 1880.31803 | -0.000255036168 |
| exposure_multiplier_3snap | 2524596.121899694 | 2524596.121902244 | 2.54958031e-06 | -2.13366002e-05 |
| reference_24snap | 14127976.852376012 | 14128094.086304095 | 117.233928 | -9.89548862e-05 |
| reference_3snap | 2524596.121899694 | 2524596.121902168 | 2.47359807e-06 | -2.05705874e-05 |
| reference_6snap | 4085284.715586666 | 4085284.719908584 | 0.00432191615 | 0.00428838842 |
| source_reactance_3snap | 2524596.121899694 | 2524596.121908070 | 8.37500374e-06 | -8.29361379e-05 |
| threshold_3snap | 2524596.121899694 | 2524596.121902177 | 2.48224571e-06 | -2.07694247e-05 |

Die früheren acht negativen numerischen Intervalle bleiben unverändert dokumentiert. Ihre Interpretation als rigorose globale Intervalle wird zurückgezogen. Daraus wird weder die exakte Ungültigkeit jeder historischen LB-Zahl noch eine pauschale Rundungserklärung abgeleitet. Neue rationale Punkte und direkte Kosten-/Dualauswertung stellen gültige Intervalle her. Kostenresiduen, Integernähe und tatsächlich gespeicherte Rebase-/Skalierungsabweichungen werden separat geführt.

`integer_bounds_proved=true` gilt ausschließlich für diese gültigen Intervalle auf der deklarierten normalisierten Domain. `integer_optimality_proved=false`: insbesondere Relaxationslücken von rund 9288,18 / 1880,32 / 117,23 verhindern die enge globale Abnahme von connectivity/event_price/reference_24snap. reference_6snap bleibt etwa 0,004322 breit. Auch kleinere Breiten beweisen keine exakte Optimumsgleichheit. Kein vollständiger MIP-Baum oder vollständige Enumeration aller neun Fälle wurde zertifiziert. G0/G3-Optimumsgleichheit wird nicht aus ähnlich günstigen Punkten abgeleitet. `integer_globality=case_specific_partial`.

## 6. Objective-Koordinate

Der reale Rebase behält nominal C und dividiert durch s>0. Der tatsächliche Float64-Export kann zusätzlich eine exakt aus den Bits rekonstruierte affine delta(x) enthalten. Diese Abweichung ist für alle neun Fälle und zwei Divisoren gesondert gespeichert. Ein Punktwert von delta wird nicht als globaler Fehlerbound benutzt. Deshalb werden native numerische OA-Bounds nicht durch bloße Multiplikation in rigorose Geldbounds verwandelt. Die Zertifikate prüfen die emittierte Kostenfunktion sowie die aus Rawdaten exakt rekonstruierte Rohwährungsfunktion jeweils direkt. Details, Vorzeichen und Rücktransformationen stehen in `objective_rebase_derivation.md`.

CAPEX-/Dispatch-/Storage-/Event-Komponenten und feste Offsets sind getrennt. 24×3 h=72 h. Physisches baseMVA, Ereigniswiederholungen und Dispatchstunden werden nicht vertauscht. Quellkostenjahre, Storage-P/E-Quellen und tatsächliche Studienrepräsentativität werden durch die arithmetische Prüfung nicht qualifiziert.

## 7. Tatsächlich ausgeführte Regression und Umgebung

Julia **1.10.11**, JuMP 1.31.1, MOI 1.51.2, Pajarito 0.8.3, HiGHS.jl 1.24.1 / native Bibliothek 1.15.1, Clarabel 0.11.1. Julia-Threads 1; BLAS-Threads 6. Die Runtime-, Manifest-, Source-, Solveroptions- und Dateihashes sind erfasst. Paketstände wurden nicht aktualisiert.

* Auf Korrekturcommit 910d44122a37d9ed2cca06940740b46706c73d40: vollständige Regression **6087/6087**, gespeicherte Evidenz **4108/4108**, jeweils Exit 0.
* Tatsächliche JuMP/MOI-/RSOC-/Kanten-/Singulär-/Range-Schutzsuite: vor Fix **42/42**, nach Fix **42/42**; rohe Domänenmutationen jeweils **16/16**.
* Neue Koeffizientenfilter-/Skalierungs-/Vorzeichen-/Objective-Prüfungen **18/18**, Exit 0. Dazu minimaler tatsächlicher HiGHS-MIP-Gegenfall und frischer Gurobi-Lizenzversuch.
* Neuer separater rationaler Zertifikatsverifikator **171/171**, alle neun Fälle mit beiden G0-/G3-Primalprüfungen und beiden Kostenkoordinaten.
* Neue vollständige Fixed-integer-Witnesspaare **18**, dazu neun BASE-LP-Läufe; echte 3/6/24-Snapshot- und alle neun registrierten Fallgruppen sind in den beiden Solvermatrizen enthalten.
* Die 124-Metrik-/8-CLI-Abnahme wird unverändert aus dem gepinnten A3.5-EXEC-Archiv referenziert. Kein Metrik-, Export-, CLI- oder Bound-Ausgabecode wurde geändert. Diese früheren Tests werden ausdrücklich nicht als neue Läufe ausgegeben.

Alle eigenen fehlgeschlagenen Versuche, Lizenzfehler und nichtoptimalen Solverstatus sind erhalten. Der erste Exact-Recovery-Versuch scheiterte an doppelten exportierten q-Namen; die tatsächliche MOI-Indexzuordnung behebt die Prüfwerkzeugfrage. Eine erste Konfliktkopie wurde falsch als Objekt statt Tupel gelesen. Die namensbasierte Integerfixierung war ungültig; der korrigierte Indextest ist gesondert. Kein dieser Fehlversuche wird als PASS gezählt.

## 8. Reproduktion, Veröffentlichung und offene Gates

Rootvariablen: BASE=`D:/Projekte/Code/FlexPlan_A35_EXEC_BASELINE`, FIX=`D:/Projekte/Code/FlexPlan_A36_B1_OPT_FIX`, RUN=`D:/Projekte/Code/FlexPlan_A36_B1_OPT_RUN`. Die tatsächlichen Argumentarrays/Exitcodes stehen in den Ausführungsmanifesten. `reproduce.md` enthält die Reihenfolge und die Abgrenzung von Snapshotdiagnostik und echten Solves. Alle neuen Rohmodelle, Witness-/Dual-/Bounddateien, Programme und vollständigen Test-/Solverlogs liegen verlustfrei in `verified_primal_dual_witnesses.zip`. Reproduktionsmanifest und Entryhashes sichern jede Datei. Der finale Git-/Remote-/Blobnachweis wird nach Push zusätzlich festgehalten; selbstreferenzierende Commit-SHAs werden nicht in den eigenen Commit hinein behauptet.

Der bestehende bedingte Satz- und Gleichung-zu-Code-Status bleibt `accepted_for_registered_cases`; dieser Auftrag wiederholt keine vollständige Gleichung-zu-Code-Abnahme. Der Solverfix benötigt weitere unabhängige Abnahme, B1 benötigt belastbare Statusstabilität einschließlich des noch fehlschlagenden Skalierungsfalls, OPT stärkere global validierte Integeruntergrenzen. Wissenschaftsowner-Ratifizierung und reale Datenqualifikation bleiben getrennt. Siehe den eigenständig kopierbaren Folgeauftrag in `remaining_gates_handoff.md`.

**Getrennte Schlussentscheidung:** konkretes B1-Ursachenglied reproduziert und partiell korrigiert; robuste native Gesamtzuverlässigkeit offen. Neun gültige exakte normalisierte Kostenintervalle hergestellt; enge globale Integeroptimalität nicht für alle neun bewiesen. `science_amendment_approved=false`, `independent_A3_5_accepted=false`, `A3_closed=false`, `AP4_ready=false`, `empirical_study_ready=false`.

Zusätzlicher exakter Originalmodellnachweis: native_exact_extension_verification.json prüft alle 3680 Originalvariablen einschließlich 23 exakt ergänzter Objective-Increments und 1353 Integerrestriktionen ohne Feasibility-Toleranz. Außerdem wurden 520 ursprüngliche Inputdateien, acht Wissenschaftssnapshots, 14 historische Archive und alle 1060 Originalindexeinträge frisch hashverifiziert; diese Integritätsprüfungen sind keine neue wissenschaftliche Freigabe.
