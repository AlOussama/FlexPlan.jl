# AP3 — geprüfte Publikation

Am 2026-10-20 wurde der Evidenzcommit [897aa6f407f69a68b58d5f0bbdf922438eb8db46](https://github.com/AlOussama/FlexPlan.jl/commit/897aa6f407f69a68b58d5f0bbdf922438eb8db46) normal auf implementation/paper-a-ap3-all-formulations-v1 gepusht und anschließend gezielt gefetcht. Lokaler HEAD, origin-Trackingref und git ls-remote ergaben exakt denselben SHA, ahead/behind=0/0. Merge-Base zum qualifizierten Consumer ist e992edc88d39fa0eb2d72e2490e157441223f568. Dieser anschließende Publikationsnachweis und die vervollständigte Hashmanifestzeile sind reine Metadaten; ihre Commit-ID steht im abschließenden Workerbericht beziehungsweise Git-Log.

**AP3_partial.** Alle Familien und acht CLI-Aktionen sind ausgeführt. Finale Vollregression **6087/6087**, gespeicherte Evidenzprüfung **4108/4108**, jeweils Exit 0. Neun numerisch geprüfte Integer-Referenzintervalle; native G3-MISOCP-Zuverlässigkeit bleibt eingeschränkt. Datenqualifikation conditional_owner_review_pending; empirische Freigabe=false; A3_closed=false; AP4_ready=false. Keine unabhängige A3.5-Abnahme und kein PR/Merge.

1087 geänderte Pfade gegenüber e992edc stehen exakt in paper_a_ap3_changed_files.txt. paper_a_ap3_file_manifest.csv enthält SHA256 der lokalen Dateibytes und Git-Blob-SHA1 des Index; Git kann Quelltext-Zeilenenden normalisieren, die Laufdateien besitzen -text. Nur das Manifest selbst ist zur Vermeidung eines Selbsthashzyklus ausgenommen. Alle anderen finalen Pfade einschließlich dieser Publikationsnotiz sind gehasht. Große Metrik-Rohdateien sind lokal erhalten und remote in 14 verlustfreien, SHA256-identischen ZIPs enthalten.

Der Laufindex erfasst **1060 Dateien** mit **1541266168 Rohbytes**, einschließlich der nach Extraktion wiederherstellbaren Metrikdateien. Index-SHA256: 813ab23e7cdb49642b070155ae4414a9941d0c16ee074f2901e46512254c188a. Alle Größen und SHA256 wurden nach dem Export neu geprüft. Neu erzeugte Exportdateien sind ohne Selbstreferenz separat gehasht; Nachweis paper_a_ap3_index_verification.json. Nach dem Export wurden keine indizierten Dateien geändert.

AP2-Worktree bleibt auf 725de2e6c1cea21f63902474f72ec614b2358356 mit unverändertem vorhandenem untracked audit/. Strang-B bleibt sauber auf e992edc88d39fa0eb2d72e2490e157441223f568. Producer- und Science-Worktrees sind sauber und wurden nur gelesen. Vor dieser Metadatenänderung war auch der AP3-Worktree sauber. Historische vom Test neu erzeugte Berichte wurden kopiert und ihre drei Basisversionen gezielt wiederhergestellt. Es erfolgten kein Reset, Force-Push, Master-Merge, fremder Branchwechsel oder Löschen alter Versuche.

Direkte Links auf den geprüften Evidenzcommit:

- [Deutscher Gesamtbericht](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/reports/paper_a_ap3_validation.md)
- [Maschinenlesbarer Status](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/reports/paper_a_ap3_status.yaml)
- [Formulierungskandidaten](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/docs/paper_a/ap3_formulation_candidate_registry.md)
- [Vollständiges Metrikregister](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/docs/paper_a/ap3_evaluation_metric_registry.md)
- [Implementierungsarchitektur](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/docs/paper_a/ap3_implementation_architecture.md)
- [Reproduktions- und CLI-Anleitung](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/docs/paper_a/ap3_postprocessing_user_guide.md)
- [Unabhängige A3.5-Übergabe](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/docs/paper_a/ap3_to_a3_5_handoff.md)
- [Laufdaten und fehlgeschlagene Versuche](https://github.com/AlOussama/FlexPlan.jl/tree/897aa6f407f69a68b58d5f0bbdf922438eb8db46/reports/ap3_runs/20261020_macro)
- [Menschenlesbarer Evidenzexport](https://github.com/AlOussama/FlexPlan.jl/blob/897aa6f407f69a68b58d5f0bbdf922438eb8db46/reports/ap3_runs/20261020_macro/export_final/evidence_report.md)
