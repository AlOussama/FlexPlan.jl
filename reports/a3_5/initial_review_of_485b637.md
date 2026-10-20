# A3.5 — unveränderlicher AP3-Ausgangsbefund (unabhängig, nicht abgeschlossen)

Datum: 2026-10-20. Gegenstand: 485b637cc1998a327206c5929434bd26c6f0be16. Review-Arbeitsbranch: review/paper-a-a3-5-independent-acceptance-v1; anfänglicher Branch-HEAD 5e98feab298295dd0a5bda9ca334f75d63c66be1 (reiner Dokumentationscommit, direkter Parent der AP3-Baseline).

## Evidenzautorität und Grenzen
Autoritativ: research-map e8118425adc335a99e85120d943763305f211315; Theorem-Freeze 2c2fce769b2ed6ffd4f1ced60c0798776acccc93. AP3-Selbstberichte sind nicht unabhängige Testnachweise. GitHub-Connector-Lesen von Quelltext, Manifest und Status war möglich; lokaler git-ls-remote scheiterte an DNS, und Julia ist in der ausführenden Umgebung nicht installiert. Weder 6087/6087 noch 4108/4108 wurden erneut ausgeführt. ZIPs, 1,5-GB-Index, neun vollständige Integer-Witnesses und 124 Metriken wurden nicht unabhängig byteweise verifiziert.

## Unabhängige exakt-rationale Negativprobe (eigener SymPy-Prozess)
B=[[1,-1/2],[-1/2,1]], p=[1/4,2/3], alpha=1.
M=B-diag(p)=[[3/4,-1/2],[-1/2,1/3]].
Eigenwerte(M)={0,13/12}; G0=PASS.
M*1=[1/4,-1/6]; G1=FAIL.
B^-1*p=[7/9,19/18]; M0=FAIL (zweiter Wert >1).
G3-Zeuge q12=3/4, q21=1/3: q12*q21=1/4=m12²; beide Knotenreste exakt null; G3=PASS.
Das demonstriert eine echte G0/G3-Boundary bei G1- und M0-Verletzung. Es beweist weder die allgemeine G0/G3-Äquivalenz noch die Korrektheit der AP3-Implementierung.

## Statischer Gleichung-zu-Code-Teilaudit
src/core/paper_a_formulations.jl@485b637cc1998a327206c5929434bd26c6f0be16: G0 verwendet Symmetric(M) in PSDCone; G2 verwendet die feste r-Zeilensumme; G3 indexiert i<j und führt zwei orientierte q>=0 pro nichtverschwindender fixer symmetrischer Kopplung mit [qij,qji,sqrt(2)*mij] in RotatedSecondOrderCone sowie Knotenrest ein. Mit MOI-Konvention 2*qij*qji>= (sqrt(2)*mij)^2 ist die Skalierung algebraisch korrekt. M1 erzwingt Bii>=Bmin_ii und Zub*p<=1/alpha mit identischen kanonisierten Offdiagonalen. M2 erzwingt Zeilensummen-B>=alpha*W*p und W>=0, diag(W)=1. Das sind Quelltextbefunde ohne ausgeführte Julia-Instanz und kein vollständiger Theorem-Trace.

## Wissenschaftliche Bewertung
Kein bestätigter mathematischer Widerspruch in den statisch inspizierten Formulierungen. Der native G3-MISOCP-Widerspruch B1 bleibt ungeklärt: ein INFEASIBLE-Rückgabewert und ein separater G0-Zulässigkeitsbericht genügen ohne vollständigen identischen Integer-Witness und MOI-Bridge-Protokoll nicht zur Diagnose eines Solverfehlers. Die neun numerischen Boundintervalle aus dem AP3-Artefakt sind nicht als rigide globale Zertifikate unabhängig anerkannt. Unvollständige A3.5-Nachweise sind ein Abnahmeblocker, kein nachgewiesener Programmierfehler.

Urteil für unveränderte Baseline: corrections_required im Sinne ausstehender qualifizierender Nachweise; keine Codekorrektur auf Verdacht. A3_closed=false, AP4_ready=false.
