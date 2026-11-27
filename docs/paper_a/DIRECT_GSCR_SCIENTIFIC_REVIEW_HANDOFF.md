# Wissenschaftlicher Reviewauftrag für die direkte gSCR-Wochenstudie

**Status:** Zur unabhängigen wissenschaftlichen Prüfung vorgelegt. Gegenstand ist der Git-Commit, der diesen Handoff einführt. Bitte das Urteil mit geprüfter Commit-ID, Fall-SHA und den verwendeten Receipt-SHAs zurückgeben.

**Prüffrage:** Welchen annualisierten Mehrpreis erzwingt direkte gSCR gegenüber BASE bei jeweils identischer Netzformulierung, KW 8/2013, 168 gekoppelten Stunden, 70 % Mindestanteil Wind/PV und kontinuierlich relaxiertem Commitment? [Ergebnistabelle, Annahmen und Reproduktion](DIRECT_GSCR_WEEK168.md) · [BASE- und G2-Referenzen](AC_WEEK168_BASE_G2.md)

| Skripte unter `scripts/paper_a/` | Aufgabe im Nachweis |
|---|---|
| `run_week_strength_comparison.jl`, `week_ac_compare.jl` | Methodenwahl, Fallbindung, Aufbau der 168 G0-Matrizen bzw. der äquivalenten G3-Kantenkegel sowie Auswahl des Netzmodells |
| `week_ac_audit.jl`, `replay_direct_ac.py` | Export der ursprünglichen Affinterme, Prüfung des Primalvektors am unskalierten Modell und Eigenwertprüfung je Stunde |
| `rescale_socwr_angle_rows.py`, `solve_ac_native.py`, `solve_ac_mosek.py` | Exakte Winkelskalierung und native Solverpfade mit Protokollierung von Status und Ergebnis |
| `gold_inner_cost.py`, `gold_outer_cost.py` | Kostenkandidaten aus inneren Modellen und untere Schranken aus äußeren Modellen. Für die Zahlen sind jeweils der Originalreplay bzw. die korrigierte duale Rechnung maßgebend. |

Bitte folgende Aussagen getrennt beurteilen:

1. G0 und G3 repräsentieren auf der vorliegenden Matrixstruktur dieselbe direkte gSCR-Bedingung. Zu prüfen sind die Vorzeichenstruktur, die tatsächlich übertragenen Kegel, die exakte Winkelskalierung und bei QCRM die äquivalente Rotation der Strombedingungen.
2. Die drei GOLD-Intervalle verwenden je Netz dieselbe BASE-Zielfunktion und Fallidentität. Die untere Mehrpreisgrenze ist max(0, L_G0 − U_BASE), die obere U_G0 − L_BASE. Bei QCRM bleibt offen, ob der Mehrpreis strikt positiv ist.
3. Die LPAC-G3-Sensitivität bewertet einen einzelnen SUBOPTIMAL-Punkt gegen das LPAC-BASE-Intervall. Prüfen Sie die gesonderten Grenzwerte, den Q-Bilanzfehler und die Generator-P-Überschreitung. Das schmale Intervall beschreibt allein den Einfluss der BASE-Schranken auf diese Differenz.

Das [SHA-256-Register](DIRECT_GSCR_REVIEW_RECEIPTS.json) benennt die drei unteren Nachweise, die drei oberen Nachweise, den G3-Originalreplay und das archivierte Regressionsprotokoll. Die relativen Pfade beziehen sich auf `E:/ResearchResults/FlexPlan_UC_GSCR/KW08_RE70_G2_PQ_20261125_01`. Für eine eigenständige numerische Reproduktion wird Lesezugriff auf dieses Archiv einschließlich der MPS-Dateien, Primalvektoren und des Evaluators unter `BASE_PAIR_20261126` benötigt. Die Regression ist mit `julia --startup-file=no --project=. test/paper_a_ac_network.jl` ausführbar. Bitte im Urteil kenntlich machen, welche Belege anhand der Hashes identifiziert und welche Ergebnisse eigenständig nachgerechnet wurden.
