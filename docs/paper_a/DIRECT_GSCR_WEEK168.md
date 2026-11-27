# Direkte gSCR im AC-Wochenmodell

Der Einstieg ist `scripts/paper_a/run_week_strength_comparison.jl OUTPUT_ROOT SCIENCE_CASE G0|G3 relaxed ac_compare`. Das Netzmodell wird über `PAPER_A_AC_FORMULATION` als `LPAC`, `SOC-WR` oder `QCRM` gewählt. Der Runner bereitet die ursprüngliche affine Netzstärkematrix einschließlich der verfügbaren Leistung zusätzlicher Wind-/PV-Projekte nach Anlage der Investitionsvariablen auf. Die vollständige Matrixbedingung ist in jeder Stunde aktiv.

* G0 setzt die symmetrische 37×37-Matrix jeder Stunde direkt in den PSD-Kegel. Für den nativen Pfad werden `PAPER_A_STRENGTH_BACKEND=mosek` und `PAPER_A_AC_SOLVER=mosek` gesetzt. Der Runner prüft die Dimensionen aller 168 PSD-Blöcke nach Übertragung zum Solver. Bei SOC-WR und QCRM werden die beiden Winkelzeilen pro Zweig exakt mit 2⁻²⁶ skaliert.
* G3 verwendet das äquivalente Kantenzertifikat für die geprüfte symmetrische Z-Matrix mit festen Nebendiagonalen. Auf dieser Woche sind das 8.736 rotierte Kegel und 6.216 regionale Residualzeilen. Die ursprünglichen Matrixeinträge stehen als Affinterme im Export. Im Gurobi-Pfad kann mit `PAPER_A_AC_EXPORT_NATIVE=1` nach dem Export Julia beendet und die native MPS mit `solve_ac_native.py` gelöst werden. Für SOC-WR und QCRM wird vorher `rescale_socwr_angle_rows.py` auf den Export angewendet.

## Reproduktion und Abnahme

Verwendet werden der bestehende Checkout, Julia 1.11.5, das Projektmanifest für Julia 1.11 und PowerModels 0.21.7. `PAPER_A_PROXY_CONSUMER_COMMIT` bezeichnet den lokalen Code-HEAD. `PAPER_A_WEEK_CONTRACT` verweist auf den geprüften Wochenvertrag, `PAPER_A_STRENGTH_EXISTING_CASE_DIR` auf den signierten G2-Elternfall und `PAPER_A_AC_CASE_DIR` auf den bestätigten AC-Fall. Nur die Methodenkennung und ihr Digest werden für G0/G3 im Arbeitsspeicher umgebunden. Der bestätigte AC-Quelldatensatz hat SHA-256 `66885c9b5d27b21ac1000cf16e8da5d886b7ab50085783957907cebef8a41d3b`. Das Profil dokumentiert die Methodenbindung separat.

Der Studienumfang umfasst KW 8/2013, 168 gekoppelte Stunden, 70 % Mindestanteil Wind/PV, kontinuierlich relaxierte Investitions- und Commitmentvariablen, die bestätigten zustandsabhängigen Q-Boxen und die Zweiggleichungen der gewählten PowerModels-Formulierung. Die Jahreskosten kombinieren jährliche Investitionskosten und 8760/168 mal die Betriebskosten dieser Woche.

Für native G3-Läufe prüft `replay_direct_ac.py STUDY ORIGINAL_EXPORT SOLVE_RESULT` die vollständige unskalierte MPS, die ursprüngliche Zielfunktion, Knotenbilanzen, Anlagen- und Leitungsgrenzen, Wochenenergie und alle 168 kleinsten Eigenwerte. Der Prüfer greift auf den archivierten Originalfall-Evaluator in `STUDY/BASE_PAIR_20261126` zurück. Eigenwerte oder ein Solverstatus allein qualifizieren keinen Wochenpunkt. Die separate unabhängige Rechnung bindet zulässige Obergrenzen und duale Untergrenzen an die Prüfarbeitsstände und Eingabedateien.

Die Regression `julia --startup-file=no --project=. test/paper_a_ac_network.jl` bestand mit 101 von 101 Prüfungen. Der erste technische Export unter Julia 1.10/PowerModels 0.21.4 wurde beim Vergleich mit der BASE-Referenz ausgesondert. Der Runner prüft für direkte Wochenstudien nun die PowerModels-Version. [Regression und Originalexporte](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/DIRECT_GSCR_PM0217_01)
## Nachgewiesene Kostenschranken für direkte gSCR

Stand 27.11.2026. Die Beträge sind annualisierte EUR 2025/a für KW 8/2013. Untere Kostenschranken stammen aus Relaxationen mit geprüfter dualer Korrektur, obere aus auf den Originalgleichungen geprüften Wochenpunkten. Die GOLD-Prüfung eines zulässigen Punkts allein zertifiziert keine Optimalität.

| Netz und Bewertung | BASE-Untergrenze | BASE-Obergrenze | gSCR-Kosten (Untergrenze oder Punkt) | gSCR-Kosten (Obergrenze oder Punkt) | Mehrpreis gegenüber BASE |
|---|---:|---:|---:|---:|---:|
| LPAC | 125908036326 | 125908201990 | 127407323716 | 128269955797 | 1499121726 bis 2361919471 |
| SOC-WR | 126073509961 | 126076996187 | 127395770699 | 128111711714 | 1318774512 bis 2038201753 |
| QCRM | 126073509961 | 137183220337 | 127395770699 | 137183220337 | 0 bis 11109710376 |
| LPAC-G3 Sensitivität | 125908036326 | 125908201990 | 127926227129,60 (Punkt) | derselbe Punkt | 2018025139 bis 2018190804 |

Für die LPAC-G3-Sensitivität gelten 2,5 × 10⁻⁵ für die native Modellverletzung und 0,0025 MW für die P-Knotenbilanz. Der archivierte Punkt erfüllt beide Grenzen mit 2,1320 × 10⁻⁵ und 0,0021320 MW. Der Originalreplay weist zusätzlich 0,0004251 MVAr Q-Bilanzfehler und 0,0011556 MW Überschreitung der Generator-P-Grenze aus. Der Solverstatus lautet SUBOPTIMAL. Das Sensitivitätsintervall entsteht durch Subtraktion der beiden LPAC-BASE-Schranken vom selben Punktwert, nach außen auf ganze EUR gerundet. Es bewertet diesen Betriebspunkt und bescheinigt keine Optimalitätslücke. [Originalreplay LPAC-G3](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/DIRECT_GSCR_PM0217_01/LPAC_G3_solve/original_gscr_replay.json)

Für QCRM dient der geprüfte G2-Punkt als zulässiger Punkt sowohl für G0 als auch für BASE. Die Null als untere Mehrpreisgrenze folgt aus der Inklusion der zulässigen Mengen. Die Kosten des geprüften SOC-WR-Primalpunkts und des QCRM-Primalpunkts sind an die unabhängigen Originalprüfungen mit SHA-256 `6e5f25b1ce03d53930686e20dcf3ee67be2ebaa5418d7f3890186914c68e0e43` bzw. `2ddbac0a4efae8430175bd17d8d4e9b26d0d60e4abfe544697c087157e84dccd` gebunden. [Unabhängige Schranken](E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01/G0_EIGEN_CUTS_20261127_01)
