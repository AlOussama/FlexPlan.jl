# KW 8 · Gemeinsamer Ausbau und Betrieb bei 50/60/70 % Wind/PV

Alle zwölf Varianten für den 18.–24. Februar 2013 (168 Stunden) sind tatsächlich gerechnet, numerisch zulässig und unabhängig geprüft. LPs wurden separat gerechnet; alle sechs MILPs erreichten das eingestellte relative Gapziel von 0,5 %. Die Ganzzahlläufe übernahmen keine früheren LP-Pläne oder daraus abgeleiteten Variablenschranken. Der ursprüngliche Builder-Defaultstart der ersten Variante wurde verworfen und vom Solver bearbeitet; vor der zweiten Variante wurden alle Starts gelöscht.

In allen Fällen wird Ausbau und Betrieb gemeinsam optimiert. Wind/PV im Bestand und Zubau zählen mit ihrer positiven tatsächlichen Einspeisung; Nenner ist die Wochenlast von 71,058866 TWh. OPEX einschließlich Startup/Shutdown wird genau einmal mit 8760/168 = 52,142857 annualisiert, annualisierte CAPEX einmal. Speicherzustände und Netzstärkebedingungen verwenden keine Jahresgewichtung. Es handelt sich um annualisierte technische Wochenkosten.

Das Quellenmodell ist der ausdrücklich gewählte `colib_epri_frozen_E_blocks_v1`-Planungsproxy: SYN x″d=0,25, GFM R=0,0015 und X=0,15 auf der 25-MVA-Blockbasis. Die aktuelle aktive Bedingung ist G1 (Gershgorin). Bestehende Parameter, 2040/EUR2025-Kosten, 20-%-GFM-Aufschlag, 4-h-BESS, UC-/Speicher-/Netz- und Ausbaugrenzen bleiben gleich.

## Kosten und Optimalität

`OPTIMAL` bei einem MILP bedeutet hier das erreichte konfigurierte Gapziel, kein bewiesenes exaktes Nullgap-Optimum.

| Wind/PV | Modell | G1 | Kosten, Mrd. EUR2025/a | Untergrenze | Gap, % | CAPEX | OPEX |
|---|---|---|---:|---:|---:|---:|---:|
| 50 % | LP | an | 98.619706 | 98.619706 | 0.000000 | 62.062738 | 36.556968 |
| 50 % | LP | aus | 97.551529 | 97.551529 | 0.000000 | 60.351397 | 37.200132 |
| 50 % | MILP | an | 98.998127 | 98.619706 | 0.382251 | 62.455556 | 36.542571 |
| 50 % | MILP | aus | 97.566598 | 97.551529 | 0.015445 | 60.393267 | 37.173331 |
| 60 % | LP | an | 111.395759 | 111.395759 | 0.000000 | 86.782272 | 24.613487 |
| 60 % | LP | aus | 109.730971 | 109.730971 | 0.000000 | 84.708983 | 25.021988 |
| 60 % | MILP | an | 111.814151 | 111.395759 | 0.374185 | 87.244212 | 24.569938 |
| 60 % | MILP | aus | 109.743617 | 109.730971 | 0.011523 | 84.711423 | 25.032194 |
| 70 % | LP | an | 127.348376 | 127.348376 | 0.000000 | 111.232097 | 16.116280 |
| 70 % | LP | aus | 124.989733 | 124.989733 | 0.000000 | 108.292792 | 16.696941 |
| 70 % | MILP | an | 127.818619 | 127.348376 | 0.367898 | 111.598590 | 16.220028 |
| 70 % | MILP | aus | 125.055973 | 124.989733 | 0.052968 | 108.352826 | 16.703147 |

## Ausbau und Betrieb

Leistungsangaben sind neu installierte GW; Energiemengen beziehen sich auf die 168 tatsächlichen Stunden. Batterien enthalten GFL und GFM, ohne PHS oder Reservoir-Hydro.

| Wind/PV | Modell | G1 | CCGT / OCGT, GW | BESS GFL / GFM, GW | Onshore / PV, GW | Gas, TWh | BESS Laden / Entladen, TWh |
|---|---|---|---:|---:|---:|---:|---:|
| 50 % | LP | an | 1.799 / 0.000 | 7.271 / 30.683 | 343.420 / 438.061 | 4.192861 | 1.529788 / 1.468597 |
| 50 % | LP | aus | 1.875 / 0.000 | 16.970 / 0.000 | 343.301 / 436.277 | 4.560932 | 0.689396 / 0.661820 |
| 50 % | MILP | an | 1.841 / 4.200 | 7.300 / 33.525 | 341.283 / 442.800 | 4.164204 | 1.596535 / 1.532673 |
| 50 % | MILP | aus | 1.841 / 0.000 | 16.975 / 0.000 | 344.307 / 434.411 | 4.542495 | 0.686437 / 0.658979 |
| 60 % | LP | an | 1.724 / 0.000 | 37.270 / 56.094 | 457.062 / 620.167 | 1.503129 | 3.546705 / 3.404837 |
| 60 % | LP | aus | 1.811 / 0.000 | 76.298 / 0.000 | 459.515 / 603.455 | 1.718438 | 2.716798 / 2.608126 |
| 60 % | MILP | an | 2.659 / 0.000 | 38.175 / 62.800 | 452.696 / 628.293 | 1.493454 | 3.840939 / 3.687301 |
| 60 % | MILP | aus | 1.841 / 0.000 | 76.325 / 0.000 | 459.831 / 602.437 | 1.718263 | 2.729612 / 2.620427 |
| 70 % | LP | an | 1.715 / 0.000 | 57.677 / 101.289 | 588.959 / 719.818 | 0.496544 | 6.016090 / 5.775446 |
| 70 % | LP | aus | 1.785 / 0.000 | 141.758 / 0.000 | 583.442 / 719.221 | 0.599696 | 5.444260 / 5.226490 |
| 70 % | MILP | an | 1.636 / 0.000 | 58.875 / 104.575 | 587.424 / 726.053 | 0.603613 | 6.367852 / 6.113138 |
| 70 % | MILP | aus | 1.841 / 0.000 | 141.800 / 0.000 | 583.958 / 718.923 | 0.601380 | 5.607437 / 5.383139 |

Bei höherer Quote steigt der Wind-/PV- und Speicherausbau; Gas erzeugt weniger Energie. G1 führt in allen gerechneten Paaren zu GFM-BESS-Zubau, während die Varianten ohne G1 ausschließlich GFL-BESS bauen. Die LP-Mehrkosten von G1 betragen bei 50/60/70 % rund 1,068/1,665/2,359 Mrd. EUR2025/a. Die beobachteten MILP-Planunterschiede müssen zusammen mit den verbleibenden Gaps gelesen werden; der jeweilige Kapazitätsmix ist damit nicht als eindeutig global optimal nachgewiesen.

Im 50-%-MILP entstehen mit G1 zusätzlich 4,2 GW OCGT an zehn Knoten (14 Modellblöcke). Diese erzeugen nur 1,920 GWh in der Woche: 0,457 äquivalente Volllaststunden. Jeder zusätzliche Gasmodellblock wird mindestens einmal im aktiven Blockmaximum benötigt. Der Befund zeigt die Bedeutung seltener Stunden; er beweist keine globale Notwendigkeit genau dieses Portfolios.

## Nachweise und Grenzen

Alle Varianten haben null nachgerechnete aktive Modellverletzungen oberhalb 1e-6; alle MILPs haben Integerresiduum null. Die deaktivierten G1-Zeilen werden in den Läufen ohne G1 ausschließlich nachträglich ausgewertet. Vollständige Träger-Dispatchaggregate, Kostenkomponenten, native Status/Schranken und unabhängige Reviewreceipts stehen im [maschinenlesbaren Ergebnisindex](receipts/kw08_re50_60_70_joint_results_20261118.json).

Alle 311.395 ursprünglichen JuMP-Variablen sind als Vollpräzisionswerte archiviert. Die neuen Exporte enthalten auch sämtliche RE-Dispatchkoordinaten; der frühere LP50-Export hat dafür einen ausdrücklich dokumentierten Metadatenrest. Die zusätzlichen nativen Gurobi-Bridge-Spalten sind kein Bestandteil des exportierten Originalvariablenvektors. Rohdaten und Solverlogs bleiben auf E:.

Physischer AP2-Eingang: `c03dfc3cd78d68e0aeb8fb6875a3875e71db5d2c2efd8d680ba1904f95a79cfe`; Profil: `13a242fc5f3e2f8f651d6d0dec2ec8d5cb8fb41e8c543b2daf03beb7879c26c2`. Producer: `becec6d63c0fbf2b8a160c41f87631f5270046b9`. Consumer: LP50 `89897ee8b0caa8a54533b0fb03fa61b6adb1bd88`, MILP50 `d11f3f3e8376768d97e08f339990c6bb489e6ce5`, 60/70 % `1edcc857036cec3703a581f2704a51dbcc886586`.

Der [Quellen- und Implementierungsbericht](colib_epri_positive_gfm_source_qualification.md) dokumentiert die fachliche Abgrenzung, Tests, Initialisierung und Retention. Neue große Ausgaben liegen ausschließlich unter `E:/ResearchResults/FlexPlan_UC_GSCR`; der vorhandene Q4-Hunk des Producers und historische Ergebnisse bleiben erhalten. Volljahres-, SCI02-, Gate-J-, F3-, AC- oder Dynamikfreigaben folgen aus diesen Wochenläufen nicht.

## Tatsächlicher nächster Schritt

QREF hat 70 % als höchste angeforderte beidseitig qualifizierte Quote gewählt. Der unabhängige Auswahlreceipt hat SHA-256 `971c4bac09ed5f859a7a4a07d378a4fa8a8d5314f12284a1ef57290be7f06b34`. Nun folgt der beauftragte Vergleich vorhandener Netzstärkekriterien auf derselben Woche und Quote. G0–G3 sind bereits mathematisch formuliert und implementiert; LOCAL/M0 und weitere SCR/eSCR-Definitionen sind ebenfalls vorhanden. Die gemeinsame neue RE-Exposition muss für die zusätzlichen Kriterien korrekt an p/S/M angebunden werden. Die vorhandenen Formulierungen werden wiederverwendet, mit gezielter technischer Delta-QA. Externe SCR/eSCR-Konventionen, M1-Bmin und M2-W bleiben an ihre jeweiligen tatsächlichen Fallnachweise gebunden.
