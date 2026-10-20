# A3.5-MATH — kontrollierter Freeze-Amendment-Antrag (NICHT ANGENOMMEN)

2026-10-20. Eigentümer: Wissenschaftsleitung/Mathematikowner in research-map. Ausgangs-Freeze 2c2fce769b2ed6ffd4f1ced60c0798776acccc93. Originalziel AP3 485b637cc1998a327206c5929434bd26c6f0be16. Dieses Dokument ändert keinen wissenschaftlichen Normtext.

## A35-NEW-001: bedingte Ergänzung der Implikationskarte

Für B=Bᵀ≻0, Z=B⁻¹≥0 komponentenweise, p≥0, S=diag(p), α>0 und gemeinsame Basen gilt:
\[
Zp\le\alpha^{-1}{\bf1}\ \Longrightarrow\ B-\alpha S\succeq0.
\]
Beweis 1: Nichtnegative Matrix K=αZS, K1≤1 ⇒ ρ(K)≤1, K ist zu αB⁻¹ᐟ²SB⁻¹ᐟ² ähnlich; Kongruenz ergibt G0. Beweis 2: Auf positivem Support liefert 2y_i y_j≤y_i²+y_j² bei Z_ij≥0 die Operatorabschätzung S¹ᐟ²ZS¹ᐟ²≼diag(Zp)≼α⁻¹I. S darf singulär sein; bei S=0 ist die Quotientmetrik undefiniert, die LMI nicht. Ohne Z≥0 ist die Aussage falsch: B=[[1,4/5],[4/5,1]], p=(1,1) ⇒ Zp=(5/9,5/9), aber B−S indefinit.

Kette nur unter allen gemeinsamen Domain-Voraussetzungen: M2⇒G1⇒M0⇒G0; M1⇒M0⇒G0; G0⇔G3 nur für vollständige symmetrische Z-Matrizen. G0⇒M0 bleibt wegen B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3), Zp=(7/9,19/18) falsch. Kein Anspruch auf mathematische Originalentdeckung; Standardkonsequenz der nichtnegativen Matrix-/M-Matrix-Theorie.

## T006: Singular-S-Schutz

Mit S=diag(S_a,0_z), S_a≻0, ist das finite generalized-eigenvalue G0-Schwellenäquivalent nur bei B_zz≻0 oder bei B_zz≽0 plus (I−B_zz B_zz†)B_za=0 nach genauer (generalisierten) Schur-Elimination korrekt. Indefinite B_zz oder verletzte Range können Rayleigh-Quotienten −∞ zulassen, obwohl formale endliche Pencil-Eigenwerte existieren. Bei S=0 ist gamma undefiniert, während B−αS≽0 weiterhin eindeutig getestet werden kann.

## Quellenphysik: Randbedingung eines festen Phasors

Eine additive Diagonalstärkung b_src ist für den vereinbarten Zeithorizont exakt im Terminalmodell mit festgehaltenem internem Source-Voltage-Phasor hinter expliziter Reaktanz. Für [[b,−b],[-b,B_net+b]] ergibt diese Festspannung den Terminalwert B_net+b; ein freier, stromloser Innenknoten ergibt nach Schur B_net. Ein bloßes GFM-, SYN- oder SC-Label, ein x_src-Datenfeld und ein Bool source_equivalent_valid bestätigen keine extern qualifizierte, strombegrenzungsfreie, ideal feste Quelle. Zeitbereich, MVA-/Volt-Basis, Filter, Fault-/Reglerverhalten und Double Counting sind separat zu definieren. Ohne Qualifikation ausschließlich als Planungsproxy bezeichnen.

## Domain-/Implementierungsgrenze

Invertierbares eliminiertes C reicht algebraisch zur Kron-Elimination; PSD-Schur benötigt C≻0 oder bei singulärem C PSD+Range. Der AP2-Invertierbarkeitstest ist ohne reale L≽0-Evidenz keine umfassende PSD-Abnahme; einen Codefehler in registrierten Fällen beweist dies nicht. Alle P001–P010 und G3-Edge-/RSOC-Prädikate bleiben unabhängige spätere Implementierungsprüfungen.

**Governance:** Kein Commit in research-map, kein stilles Überschreiben des Freeze oder AP3. Autorisierte Wissenschaftsleitung soll A35-NEW-001, T006, Quellenrandbedingung und Domänenrestriktionen einzeln adjudizieren und nur gegebenenfalls einen neuen normativen SHA erzeugen. science_amendment_approved=false, A3_closed=false, AP4_ready=false.
