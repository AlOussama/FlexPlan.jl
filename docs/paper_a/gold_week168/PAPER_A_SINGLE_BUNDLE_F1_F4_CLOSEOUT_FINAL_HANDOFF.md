# Paper A · Konsolidierter Abschluss F1–F4

**Stand 24. November 2026 · PAPER_READY_AFTER_TARGETED_CORRECTIONS · Unabhängiges Urteil F4_GO_VARIANT_A.** Alle vier lokalen Gates sind für Variante A bestanden. Für die beibehaltenen Aussagen bestehen **0 offene P0-Befunde**. Die einzige ausstehende Entscheidung ist die abschließende Ratifikation dieses Stands durch S-GOV. Der Status für die Journaleinreichung bleibt `SUBMISSION_READY=false`. [Journalmanuskript (PDF)](https://github.com/AlOussama/research-map/blob/7d568b6ce3b821bba05812b61ca8ccc5240aacec/papers/paper-a-week168/04_PAPER_A.pdf) · [Unabhängiges F4-Urteil](05_F4_INDEPENDENT_PUBLICATION_VERDICT.md) · [Maschinenlesbarer Abschluss](FINAL_HANDOFF.json)

**Berichtigung vom 24. November 2026.** Der F4-Vermerk oben bezeichnet den historischen Paper-Commit. Die erneute Textprüfung korrigiert die fallweisen Solverversionen und die Rundung der hier angezeigten Kostenschranken. Der historische Commit bewahrt den ursprünglichen Bericht.

## Fragestellung und wissenschaftliches Ergebnis

Untersucht wurde KW 8/2013, vom 18. Februar 00 Uhr bis 24. Februar 23 Uhr. Alle 14 Fälle verwenden dieselben 168 Stunden. Die Wochenquote bezieht sich auf tatsächlich eingespeiste Wind-/PV-Energie relativ zur Last. Die stündliche Netzstärkeformulierung verwendet die Online-Beteiligung bestehender GFL-Blöcke und die mit der stündlichen Verfügbarkeit gewichtete neue Wind-/PV-Leistung. Die Investitionskosten werden einmal angesetzt, die Betriebskosten der Woche einmal mit 8.760/168 gewichtet. Alle Kostenangaben beziehen sich auf EUR zum Preisstand 2025. [Chronologie und Portfolios](02_CHRONOLOGY_AND_PORTFOLIO_CROSSCHECK.json) · [Vollständige Fallmatrix](02_FINAL_WEEK168_RESULT_MATRIX.csv)

Für das ganzzahlige Modell erhöht G1 die optimalen annualisierten Kosten gegenüber BASE. Aus den gegenüberliegenden numerischen Schranken folgen die konservativ gerundeten Intervalle **1,05–1,45 Mrd. EUR bei 50 %, 1,65–2,09 Mrd. EUR bei 60 % und 2,29–2,83 Mrd. EUR bei 70 %**. Bei 70 % ist die gefundene ganzzahlige G2-Lösung um rund 369 Mio. EUR günstiger als die gefundene G1-Lösung. Die G1- und G2-Optimalitätsintervalle überlappen. Der Vergleich ihrer Incumbents lässt die Rangfolge der Optima offen. [Schranken und ungerundete Werte](02_OBJECTIVE_AND_SOLVER_BOUNDS.csv)

## F2 · Kosten und Originalpunkte

LB ist die native numerische Solveruntergrenze, UB der am Originalvektor rekonstruierte Zielfunktionswert. CAPEX sowie LB und UB stehen in Mrd. EUR, die ungewichteten Wochenbetriebskosten in Mio. EUR. Der letzte Wert ist der maximale absolute Rest der gemeinsamen Originalzeilen im jeweiligen Modellmaß. Für die Abnahme gelten die dimensionsbezogenen Einzelprüfungen je Zeilenfamilie. Gurobi 12.0.3 lieferte 13 Kernpunkte. Der 70-%-G2-MILP-Punkt stammt aus Gurobi 13.0.3. Die sichtbaren LB-/UB-Endpunkte sind nach außen gerundet. [Originalresiduen und Einheiten](02_ORIGINAL_PRIMAL_REPLAY.json) · [QA-Abnahme](02_INDEPENDENT_ACCEPTANCE.json)

| Quote | Modell | Typ | CAPEX | OPEX der Woche | LB | UB | Gap [%] | Max. gemeinsamer Rest |
|---:|---|---|---:|---:|---:|---:|---:|---:|
| 50 % | BASE | LP | 60,351 | 713,427 | 97,551528 | 97,551529 | 0,000000 | 2.682e-07 |
| 50 % | BASE | MILP | 60,393 | 712,913 | 97,551528 | 97,566599 | 0,015445 | 9.686e-08 |
| 50 % | G1 | LP | 62,063 | 701,093 | 98,619706 | 98,619707 | 0,000000 | 2.310e-07 |
| 50 % | G1 | MILP | 62,456 | 700,816 | 98,619706 | 98,998128 | 0,382251 | 2.235e-07 |
| 60 % | BASE | LP | 84,709 | 479,874 | 109,730971 | 109,730972 | 0,000000 | 3.725e-08 |
| 60 % | BASE | MILP | 84,711 | 480,069 | 109,730971 | 109,743618 | 0,011523 | 3.326e-10 |
| 60 % | G1 | LP | 86,782 | 472,039 | 111,395759 | 111,395760 | 0,000000 | 1.416e-07 |
| 60 % | G1 | MILP | 87,244 | 471,204 | 111,395759 | 111,814151 | 0,374185 | 1.043e-07 |
| 70 % | BASE | LP | 108,293 | 320,215 | 124,989733 | 124,989734 | 0,000000 | 4.545e-07 |
| 70 % | BASE | MILP | 108,353 | 320,334 | 124,989733 | 125,055973 | 0,052968 | 3.512e-10 |
| 70 % | G1 | LP | 111,232 | 309,079 | 127,348376 | 127,348377 | 0,000000 | 3.278e-07 |
| 70 % | G1 | MILP | 111,599 | 311,069 | 127,348376 | 127,818619 | 0,367898 | 8.196e-08 |
| 70 % | G2 | LP | 111,294 | 309,033 | 127,408221 | 127,408222 | 0,000000 | 4.396e-07 |
| 70 % | G2 | MILP | 111,341 | 308,940 | 127,408221 | 127,449600 | 0,032466 | 8.941e-08 |

Für jeden Punkt wurden 723.833 gemeinsame Zeilen geprüft. Die zusätzliche Gegenprobe nutzt nach semantischer Umnummerierung und Einsetzen der jeweiligen Quote die archivierten identischen Nichtstärke-Koeffizienten. Für die älteren BASE-/G1-Läufe sind separate native Koeffizientendumps und Laufzeitprofildateien nicht archiviert. Ihre Identität ist über Eingangsprofil, Runner, Log, Vektor und fallspezifische physische Rekonstruktion gebunden. Die beiden frühen 50-%-LPs erforderten die Wiederzuordnung von je 12.432 Dispatch-Koordinaten. Ein frischer Wiederholungslauf reproduzierte 19 wissenschaftliche Dateien byteidentisch. [Herkunft der gemeinsamen Zeilen](02_COMMON_ROW_IDENTITY_SCOPE.json) · [Koordinatenbeleg](02_RE50_LP_COORDINATE_PROOF.json) · [Wiederholungslauf](02_PORTABLE_REPLAY_VERIFIED.json)

Das G2-MILP bei 70 % hat 311.395 Variablen, davon 111.401 diskret, sowie 6.216 aktive G2-Zeilen. Bei 49.741.206,272 MWh Wind/PV und 71.058.866,102 MWh Last beträgt die Quote 70 %. Unabhängig rekonstruiert ergeben sich **127.449.599.028,67 EUR**, eine numerische Untergrenze von **127.408.221.525,42 EUR** und ein Gap von **0,03246578 %**. Der maximale gemeinsame Originalrest beträgt 8,94·10⁻⁸. Das Portfolio enthält zusätzlich 57.225 MW GFL-Batterien, 102.450 MW GFM-Batterien, 589.728,739 MW Wind und 718.399,008 MW PV. Bedingt auf dieses Portfolio verletzt G2 die inaktive G1-Bedingung in 116 Stunden und M0 in 10 Stunden. Beim G2-LP sind es 81 bzw. 18 Stunden. [F4-Rekonstruktion](05_ORIGINAL_PUBLICATION_SAMPLES.json) · [Stundenzahlen und Portfolio aller Fälle](02_FINAL_WEEK168_RESULT_MATRIX.csv)

## F1 · Mathematische Korrekturen und Implementierung

MATH-R hat 23 Gleichungsfamilien auf Codezeilen abgebildet, 46 rationale Oracle-Prüfungen ausgeführt und 2.352 stündliche Matrixzustände unabhängig rekonstruiert. Das Netz hat 37 beibehaltene Busse, sieben Inseln und 52 aktive AC-Zweige. Es gibt in diesem Fall keine eliminierten Busse. Der größte Unterschied der rekonstruierten Netzmatrizen beträgt 5,69·10⁻¹⁴ p.u. Der Frozen-E-Quellenbeitrag stimmt bei einmaliger Anrechnung mit dem Original überein. Die physische Erdung bleibt unbestätigt. [Mathematischer Review](01_FORMULATION_AND_CODE_DIFFERENTIAL_REVIEW.md) · [Formel, Codezeile und Prüfnachweis](01_FORMULATION_COVERAGE.csv)

- Auf den angegebenen Vorzeichen-, Inverspositivitäts- und Symmetriedomänen gilt M2 ⇒ G1 ⇒ M0 ⇒ G0. Für symmetrische Z-Matrizen mit vollständiger Kantendarstellung ist G0 äquivalent zu G3. G2 ⇒ G0 setzt eine ex ante festgelegte positive Skalierung voraus. Zwischen G1 und G2 besteht allgemein keine Inklusion. Bei singulärer Exposition gelten PSD- und Bildraumbedingung des verallgemeinerten Schurkomplements. Von 1.008 BASE-Stunden liegt M0 in 996 außerhalb der Definitionsdomäne. Die übrigen zwölf fallen durch den definierten Test. [Korrekturen und Gegenbeispiele](01_OPEN_MATERIAL_FINDINGS.json)
- Unter 256.368 thermischen Start-/Stopp-Paaren waren vier gleichzeitig positiv, drei im BASE-MILP bei 50 %, eines bei 60 %. Das Subtrahieren des kleineren Ereigniszählers von beiden erhält die Übergangsbilanz und lockert die Mindestzeitbedingungen. Dadurch wären an den beiden Punkten 62.388,70 bzw. 21.391,15 EUR Wochenbetriebskosten vermeidbar. Die Tabelle verwendet die tatsächlichen Incumbents. Das mathematische Optimum und die Aussage über die strikten Prämien bleiben gültig. Die vereinfachte Block-UC garantiert keine harte Exklusivität. [Ereigniszensus](01_INDEPENDENT_EVENT_CENSUS.json)
- Die bestehenden Wochenbuilder und die geprüften SGOV145-Korrekturen wurden übernommen. Sie decken unter anderem die singuläre Schur-Auswertung, die Richtung der Ratio-Schranke, die Rücktransformation der G3-Koordinaten und die Bindung des M2-Warmstarts an das geprüfte LP-Portfolio ab. Im GOLD-Codecommit kam der parametrisierte SHA-Archivleser hinzu. Die gezielte Julia-Suite bestand 85 Prüfungen in vier Testsätzen. Für die 14 bereits vorhandenen Wochenpunkte war ein Originalreplay ausreichend. [Testkommandos und native Kontrollen](03_SYNTHETIC_NATIVE_TESTS.json)

## Methoden mit eingeschränkter Aussage

Der zuletzt gescheiterte historische Gurobi-Pfad endete nach 88 Barrier-Iterationen als suboptimal. Am zurückgegebenen Vektor überschritten 4.633 Zeilen die Originaltoleranz von 10⁻⁷. Die drei erneut geprüften historischen SOCP-Punkte zeigen maximale Originalreste von 7,8621·10⁻³, 1,6337·10⁻⁵ und 2,4696·10⁻³. Der aus G2 übertragene ganzzahlige G3-Zeuge erfüllt dagegen alle 756.257 Zeilen mit 17.472 Kantenvariablen und 8.736 Kegeln. Er belegt Zulässigkeit und eine numerische Kostenobergrenze. Eine direkte G3-Optimalitätsaussage bleibt offen. [Originalzeilen und Zeuge](02_COMPLETE_ALGEBRAIC_ROWS.json) · [Native Versuche und Ursachen](03_GATED_SOLVER_NEGATIVES.json)

Die beiden direkten G3-MOSEK-Versuche scheiterten an der Prüfung in Originalkoordinaten. Der direkte G0-SDP-Versuch lieferte keinen Primalpunkt. M1 ist generisch geprüft, für die reale Woche fehlt ein physisch durchgesetztes positiv definites Bmin. Für M2 liegt ein nichttriviales ex ante gebundenes W vor. Die akzeptierte kontinuierliche Relaxation ergibt eine numerische Untergrenze von 128.108.716.784,26 EUR, rund 659,12 Mio. EUR oberhalb des übertragenen G0/G3-Zeugen. Zwei M2-Ganzzahlläufe erreichten ihr Zeitlimit ohne zulässigen Incumbent. MISOCP blieb unausgeführt. Die Evidenz für EXP-Varianten ist je Methode als synthetisch oder explorativ gekennzeichnet. [19 Methodenfamilien](03_METHOD_STATUS_MATRIX.csv) · [Reale Methodenläufe mit Code-, Fall- und QA-Hashes](03_QUALIFIED_REAL_METHOD_RESULTS.csv)

## F3 und F4 · Publikationsstand

PAPER-W hat das achtseitige Manuskript, drei datengenerierte Abbildungen, zwei Tabellen und acht Literaturreferenzen gebaut. F4-R prüfte am veröffentlichten Commit 21 Dateien, 18 Claim-Belegketten und alle 14 Originalportfolios samt Solvergrenzen. Der G2-Zielwert wurde unabhängig bis auf 0,000367 EUR reproduziert. Alle drei Abbildungen sind byteidentisch reproduzierbar. Alle acht PDF-Seiten wurden gerendert und visuell geprüft. H3/H4 bleiben offene Hypothesen. Aussagen über AC- oder dynamische Stabilität, Fehlerströme und einen vollständigen Jahresbetrieb liegen außerhalb dieses Wochenmodells. Die Originalvektoren bleiben lokal zugangsbeschränkt. [Claimregister](https://github.com/AlOussama/research-map/blob/7d568b6ce3b821bba05812b61ca8ccc5240aacec/papers/paper-a-week168/04_PAPER_CLAIM_TO_EVIDENCE.csv) · [Supplement und Zugangsbedingungen](https://github.com/AlOussama/research-map/blob/7d568b6ce3b821bba05812b61ca8ccc5240aacec/papers/paper-a-week168/04_REPRODUCIBILITY_AND_LIMITATIONS.md) · [F4-Freeze mit Prüfkommandos und SHAs](05_SUBMISSION_FREEZE_MANIFEST.json)

## Abschluss der elf S-GOV-Gates

| ID | Disposition | Entscheidender Befund |
|---|---|---|
| K-P0-01 | `ORIGINAL_INDEPENDENT_PASS` | 14 Originalvektoren und 157 Archivobjekte identifiziert und unabhängig abgeglichen. [Beleg](00_INPUT_AND_RUNTIME_INTAKE.json) |
| K-P0-02 | `MATH_PASS` | Netz, Quellenstempel, Exposition und Domänen für 2.352 Fallstunden rekonstruiert. [Beleg](01_FORMULATION_AND_CODE_DIFFERENTIAL_REVIEW.md) |
| K-P0-03 | `ORIGINAL_INDEPENDENT_PASS` | Kosten, Quoten, Betriebsbedingungen und sechs strikte G1–BASE-Schrankenvergleiche geprüft. [Beleg](02_FINAL_WEEK168_RESULT_MATRIX.csv) |
| K-P0-04 | `PASS_VARIANT_A` | H1/H2 bedingt formuliert. H3/H4 bleiben Hypothesen. Manuskript und Claimregister unabhängig geprüft. [Beleg](04_PAPER_PUBLICATION.json) |
| K-P1-01 | `CLOSED_OPTIMAL_VALUE_NEUTRAL` | Vier gleichzeitige SU/SD-Paare. Kürzung erhält Zulässigkeit und senkt Kosten. Historische Obergrenzen bleiben gültig. [Beleg](01_OPEN_MATERIAL_FINDINGS.json) |
| K-P1-02 | `CLOSED_WITH_NUMERIC_REJECTIONS` | Drei historische SOCP-Punkte abgewiesen. Der aus G2 konstruierte Zeuge besteht sämtliche Originalzeilen. [Beleg](02_COMPLETE_ALGEBRAIC_ROWS.json) |
| K-P1-03 | `IMPLEMENTED_TESTED` | Parametrisierter Archivleser und separater Ein-Befehl-Replay. 19 Ergebnisdateien byteidentisch reproduziert. [Beleg](00_REPLAY_DRY_RUN.log) |
| K-P1-04 | `CLOSED_BY_METHOD_WITH_SCOPED_LIMITS` | 19 Methodenfamilien einzeln klassifiziert. Reale M1-, G0-, G3- und M2-Ganzzahlgrenzen sind dokumentiert. [Beleg](03_METHOD_STATUS_MATRIX.csv) |
| K-P1-05 | `LOCAL_F4_PASS_PENDING_S_GOV_RATIFICATION` | PDF, Abbildungen, Literatur und Originalstichproben am finalen Paper-Commit geprüft. Abschließende Ratifikation liegt bei S-GOV. [Beleg](04_PAPER_PUBLICATION.json) |
| K-P2-01 | `OUT_OF_SCOPE` | Jahresbetrieb und vollständige empirische Full37-Zulassung zurückgestellt. [Beleg](https://github.com/AlOussama/research-map/blob/7d568b6ce3b821bba05812b61ca8ccc5240aacec/papers/paper-a-week168/04_REPRODUCIBILITY_AND_LIMITATIONS.md) |
| K-P2-02 | `OUT_OF_SCOPE` | AC-, Kurzschluss- und Dynamikvalidierung sowie reale EXP-Studien zurückgestellt. [Beleg](https://github.com/AlOussama/research-map/blob/7d568b6ce3b821bba05812b61ca8ccc5240aacec/papers/paper-a-week168/04_REPRODUCIBILITY_AND_LIMITATIONS.md) |

## Rollen, Revisionsstand und Reproduktion

| Rolle | Geprüfter Stand |
|---|---|
| ORCH und einziger Consumer-Writer | FlexPlan-Modell `dbecc1f2d26db134ac7a817c6ce2b5d0ba05882a`, Archivleser `605f4784dc3e0337b7471162e74da6e2221db191`, eingefrorene Nachweise `027aee0ce2cff7b424ebea05858fc2fc310078b9` auf `codex/paper-a-q5-digest-139` |
| Producer | PyPSA2MatpowerX `becec6d63c0fbf2b8a160c41f87631f5270046b9`. Lokaler Q4-Dateihash `aceb4661c9fe3c92e41acf44a52250af2549a46c437a162e46f319453dfa1314`, Git-Diff-SHA-256 `56e116eb31589a19fe981dac46cc7f707bc603caedb57a1f5ff6183d740fefa8` vor und nach GOLD identisch |
| MATH-R | `/root/math_r`, F1-Bericht SHA-256 `6e18efd006ab5a22d9df49946cac1cb4ee0731f364ece01f95c37ed84998fa66` |
| QA-R | `/root/qa_r`, F2-Abnahme SHA-256 `c710c38d9c511ca6a4c2ef693b6dd729333018c5a85dba15685c3c61e215b8bc` |
| PAPER-W | `/root/governance`, einziger Science-Writer. Paper `7d568b6ce3b821bba05812b61ca8ccc5240aacec` auf `docs/s-gov-project-consolidation-20261024`, PDF SHA-256 `0be9f0253454a6d73a1f1e6ee904c2adc135dd55b0e9d561da4e3e4801126687` |
| F4-R | `/root/math_r`, unabhängig von Produktivcode und Manuskriptautor. Auditcode SHA-256 `44f3dc8ef1d192ec4cffd02537ad2cf650ff82bff84d4a27c599eb43ce7595e5`, Urteil SHA-256 `2eaee85f531f4916e409da05d2f61b0dd006ccab7f0a21b41988b19d02050a10` |

Je Repository wurde nur die vorhandene lokale Version verwendet. Der lokale Science-Checkout steht auf `main@2564c49bdc32c7508d2acfc9fe543d4887561484`. PAPER-W veröffentlichte über Git-Objekte auf dem bestehenden Dokumentationsbranch. Im Producer bestehen der vorgefundene Q4-Diff sowie die unversionierten Verzeichnisse `docs/data_ssot/` und `scripts/archive/` fort. Im Consumer blieben das vorgefundene Arbeitslog, `scripts/archive/` und der Python-Cache erhalten. Die per Fall tatsächlich verwendeten historischen Code-, Profil-, Primal- und Solverlog-SHAs stehen im JSON. Das technische Mandat ist `34f88b8b02e1bd5428e4c1fff7cd9bd956964e2d`, die Governancefreigabe `72bbcab3455fc04a8acad514607c97ebcb2a1030`.

Der Archivcheck läuft im vorhandenen Consumer-Checkout. Für die vollständige Reproduktion werden das zugängliche Originalarchiv, der Producer und ein leeres Ausgabeverzeichnis auf E: benötigt. Die Prüfung arbeitet ohne Optimierung. [Ein-Befehl-Replay](02_replay_bundle.py) · [Kommandobeleg des getrennten Wiederholungslaufs](F2_PORTABLE_REPLAY/02_REPLAY_COMMAND_RECEIPT.json)

```powershell
$archiv = 'E:/ResearchResults/FlexPlan_UC_GSCR'
$belege = 'docs/paper_a/gold_week168'
$producer = 'D:/Projekte/Code/pypsatomatpowerx'
$ausgabe = Join-Path $archiv ('F2_REPLAY_' + [guid]::NewGuid().ToString('N'))
python scripts/paper_a/replay_gold_manifest.py --input-root $archiv --manifest "$belege/00_INPUT_AND_RUNTIME_INTAKE.json"
python "$belege/02_replay_bundle.py" --input-root $archiv --producer-root $producer --output-root $ausgabe
```
