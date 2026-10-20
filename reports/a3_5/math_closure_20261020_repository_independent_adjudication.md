# A3.5-MATH — unabhängige mathematische Schlussadjudikation

Datum: 20.10.2026. Urteil: **accepted_with_scoped_amendment_proposal**, ausschließlich Theoriedomäne, keine Implementierungs-/Solver-/Empirieabnahme. Ausführliche mathematische Darstellung einschließlich aller 28 Theoreme, 30 rationaler Fälle und vollständiger Evidenzprotokolle ist separat als lokales vollständiges Auditpaket erarbeitet; diese Repository-Fassung dokumentiert die Entscheidungen, Beweise und Aufgaben für den Scientific Owner.

**Geprüfte Identität:** research-map/main e8118425adc335a99e85120d943763305f211315, Theorem-Freeze 2c2fce769b2ed6ffd4f1ced60c0798776acccc93, Paper-A-Scope 672a61c95525bf1d7a03cf745a754a15a23ce78b; Original-AP3 FlexPlan 485b637cc1998a327206c5929434bd26c6f0be16; Review-Eingangs-HEAD 0c58af3147881e951e34bcdb556cb47681b08e46. Review-Branch ist von AP3 12 Commits voraus, 0 zurück; Merge-Base ist exakt AP3. Verifizierte Primärquellen: Dissertationskapitel §§3–8,17–26,37–44,50–52, Anhänge B–I (1271 Zeilen, Blob 11ab4ba5a0005336756d252b4877967a3d90668b); Scientific Freeze (450 Zeilen, 5ae4d319ac6e204368a7f4b9cbd00ff621138f06); adjudicated proofs (518, 518e78a479b3336f55d0ecca253b256abfcf6225); Projekt-Prädikate (248, 4866f5f5dab7cd416c7fb203db0106d98c45897f); Paper-A-Plan (1005, c43ee68a7afc7c2c5f4110e304e90f189fe60a65); Ausführungsfreeze (69, f9f64539e69bf46386d0d597e0a6a85cbfb88a37). Sekundärer A3.5-Herleitungsreview **erst nach eigenem Beweisweg** gelesen; dessen 20/20-Oracle **nicht** wiederverwendet.

## I. Physik: AC-Netz, passive Reduktion, Quellen- und Expositionsdefinition

Aus KCL folgt \(I=Y^{(+)}V,\ Y^{(+)}=G+jB^{phys}\), und die intern deklarierte Realmatrix \(L=-\operatorname{Im}Y^{(+)}\). Sie ist nicht mit \(B^{phys}\), vollständigem AC-Leistungsfluss-Jacobi oder reduziertem Q–V-Jacobi gleichzusetzen. Für den Serienzweig \(y=(r+jx)^{-1}=g-j\beta\), \(x>0,\ \beta=x/(r^2+x^2)\), ist der Zweigstempel \(L^{ij}=\beta(e_i-e_j)(e_i-e_j)^\top\succeq0\). Kapazitive π-Ladeanteile und kapazitive Bus-Shunts vermindern dagegen L-Diagonale um \(b_c/2\) bzw. \(b_{sh}\); PSD folgt nicht automatisch. Transformator mit Tap \(a=\tau e^{j\phi}\): \(Y_{ff}+=(y+y_{sh,f})/|a|^2,\ Y_{ft}+=-y/\bar a,\ Y_{tf}+=-y/a,\ Y_{tt}+=y+y_{sh,t}\). Bei \(g\sin\phi\ne0\) kann L unsymmetrisch werden; \(\cos\phi<0\) kann Z-Offdiagonalen verletzen. Eine Slack-Angelfixierung ist kein physischer Erdungsstempel.

Für symmetrisches \(L=\begin{bmatrix}A&F\\F^\top&C\end{bmatrix}\) führt eliminierter Nullstrom und invertierbares C algebraisch zu \(B^0=A-FC^{-1}F^\top\). Quadratische Ergänzung ergibt \( [u;v]^\top L[u;v]=(v+C^{-1}F^\top u)^\top C(v+C^{-1}F^\top u)+u^\top B^0u \). Die isolierte PSD-Schur-Äquivalenz benötigt **C positiv definit**. Für \(C\succeq0\) singulär sind \( (I-CC^\dagger)F^\top=0 \) und \( A-FC^\dagger F^\top\succeq0 \) zusammen nötig. Fehlendes Range-Kriterium: \(L=\begin{bmatrix}1&1\\1&0\end{bmatrix}\) hat Pseudoinversen-Schur 1, ist aber indefinit. Bloße Invertierbarkeit genügt nicht für PSD: \(L=\begin{bmatrix}2&-1\\-1&-1\end{bmatrix}\) hat C=-1 und Schurwert 3, aber L ist indefinit. Endogene Nullblockänderung \(L(t)=\begin{bmatrix}2&-1\\-1&1+t\end{bmatrix}\) erzeugt \(B^0(t)=2-1/(1+t)\), nicht affine Werte 1,3/2,5/3.

Für \( \begin{bmatrix}b&-b\\-b&B_{net}+b\end{bmatrix}\) ergibt **festgehaltenes internes Quellenpotential** einen Terminal-Koeffizienten \(B_{net}+b\). Ein frei/stromlos Schur-eliminierter Quellknoten gibt \(B_{net}+b-b^2/b=B_{net}\). Das sind verschiedene Randwertaufgaben. Der physikalische Beitrag einer GFM-/SYN-/SC-Komponente wird nicht aus einem Technologie-Label, der bloßen Deklaration voltage_behind_reactance oder einem geprüften Datenfeld bewiesen. Zeitbereich, Spannungs-/MVA-Umrechnung, eigene Quellenreaktanz, Filter, Current-Limits, reale interne Spannungsfestigkeit und Doppelstempel sind getrennt zu qualifizieren.

Ausschließlich bei fester passiver Topologie, festem Reduktionsoperator, Quellen nur an retained Bussen, festem α und festen \(\mu\)-Gewichten ist die geplante Matrix affin:
\[
B_t=B^0+\operatorname{diag}(b^{fix}_i+\sum_{k\in src(i)}\mu_k^{str}b_k^{blk}n_{k,t}^{on}),\quad
p_{i,t}=\sum_{k\in GFL(i)}\mu_k^{fl}\frac{P_{k,blk}^{MW}}{S_{base}}n_{k,t}^{on},\quad
S_t=\operatorname{diag}(p_t).
\]
Dabei \(0\le n^{on}\le n^{avail}\le n^{inst}\), mit technisch getrennter Connection-Availability und Resource-Availability. \(S^{on}\) ist nicht \(S^{nom}\), \(S^{op}\) oder \(S^I\); die gleichen p/B/α-Definitionen sind für alle formalen Implikationen verbindlich.

## II. Entscheidung zu jedem Theorem T-C2A-001–028

- **T001 bestätigt bedingt:** Kongruenz zerlegt die symmetrische Blockmatrix in C und ihren gewöhnlichen Schur; PSD-Äquivalenz ohne C-PD ist falsch.
- **T002 bestätigt:** Parallele Summe \(B_d-B_d(B_n+B_d)^{-1}B_d=(B_n^{-1}+B_d^{-1})^{-1}\); die Multiplikationsfolge \(B_d(B_n+B_d)^{-1}B_n\) benötigt keine Kommutativität.
- **T003 historische Identifikation offen:** Signabbildung mathematisch prüfbar, ursprüngliche Quellensymbole nicht belegt.
- **T004 bestätigt mit Range:** Zero-Exposure-Support darf nur mit PD-Schur bzw. PSD-Pseudoinverse **und** Range reduziert werden.
- **T005 bestätigt:** Für \(S\succ0\): \(\lambda_{\min}(S^{-1/2}BS^{-1/2})\ge\alpha\iff B-\alpha S\succeq0\).
- **T006 präzisierungsbedürftig:** Singular S setzt zulässige Nullsupport-Schur-Reduktion voraus. Bei \(B=\operatorname{diag}(2,-1),S=\operatorname{diag}(1,0)\) ist der formale endliche Eigenwert 2, aber der Rayleigh-Quotient für x=(1,t) ist \(2-t^2\to-\infty\). Bei S=0 ist die endliche gSCR-Zahl undefiniert; der PSD-Matrixtest bleibt definiert.
- **T007 bestätigt:** Rang-1-PSD-Test \(B-\alpha p_ie_ie_i^\top\succeq0\iff \alpha p_i Z_{ii}\le1\), wenn B SPD; inverse Skalarmetrik bei p_i=0 undefiniert.
- **T008 bestätigt, Konverse widerlegt:** G0 impliziert alle LOCAL; bei B=[[1,-1/2],[-1/2,1]], p=(3/4,3/4) bestehen LOCAL, M hat negativen Eigenwert -1/4.
- **T009 bestätigt bei Z≥0:** \((Zp)_i\ge Z_{ii}p_i\), damit M0 ⇒ LOCAL.
- **T010 falsche Konverse bestätigt:** B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3), α=1 hat \(\operatorname{eig}(M)=\{0,13/12\}\), aber \(Zp=(7/9,19/18)\); also **G0 nicht⇒ M0**.
- **T011 bestätigt bei symmetrischer Z-Struktur:** \(x^\top Mx=\sum_{i<j}|m_{ij}|(x_i-x_j)^2+\sum_i(M\mathbf1)_i x_i^2\), daher G1 ⇒ G0.
- **T012 bestätigt bei inverspositivem B:** \(B\mathbf1\ge\alpha p,\ Z\ge0\) ⇒ \(1\ge\alpha Zp\) komponentenweise.
- **T013 bestätigt:** Für festes r>0 und Mr≥0 ist \(DMD\), D=diag(r), diagonal dominant ⇒ G0.
- **T014 bestätigt:** G2(1)=G1 als identische Zeilenbedingungen.
- **T015 beiderseitige Nichtimplikation bestätigt:** r=(2,1), M=[[1,-3/5],[-3/5,1]] erfüllt G1 nicht G2; M=[[2/5,-3/5],[-3/5,6/5]] erfüllt G2 nicht G1.
- **T016 bestätigt:** Aus G2-Zeuge r>0 setze \(q_{ij}=|m_{ij}|r_j/r_i,\ q_{ji}=|m_{ij}|r_i/r_j\), dann Produkt gleich \(m_{ij}^2\), Knotenrest \((Mr)_i/r_i\ge0\).
- **T017 bestätigt:** Jede vorzeichenrichtige ungerichtete Kante ist ein PSD-2×2-Block mit \(q_{ij}q_{ji}\ge m_{ij}^2\), RSOC \((q_{ij},q_{ji},\sqrt2 m_{ij})\); Kantenblöcke plus nichtnegative Diagonalreste rekonstruieren M ⇒ PSD, auch ohne Z-Annahme.
- **T018 bestätigt inklusive singulär/reduzibel:** Für irreduzible PD-M-Matrixblöcke r=M^-1 1>0; für irreduzible singuläre Blöcke r>0 als Perron-Nullvektor; isolierte Nullreihen erhalten beliebiges r>0. Damit \(Mr\ge0\), DMD diagonal dominant. Symmetrische PSD-Z-Klasse = closed SDD.
- **T019 bestätigt nur strukturell:** Jede nonzero Kante genau einmal, Vorzeichen, beide Budgets, Diagonalrest; projektkonkrete Vollständigkeit **P008 nicht durch mathematischen Beweis getestet**.
- **T020 bestätigt bedingt:** G0⇔G3 nur für vollständiges Projekt-G3 auf symmetrischer Z-Klasse. Nicht-Z-Gegenbeispiel \(M=\mathbf1\mathbf1^\top\in\mathbb S_+^3\) hat Knotendiagonalsumme 3, aber alle drei Kanten erfordern mindestens 6 Budget → nicht SDD/G3.
- **T021 bestätigt komponentenweise:** Für geordnete inverse-positive M-Matrizen und **erzwungenes** \(B\ge B^{min}\): \(Z^{ub}-Z=(B^{min})^{-1}(B-B^{min})B^{-1}\ge0\) eintragsweise, nicht durch Loewner-Argument.
- **T022 bestätigt:** \(Z^{ub}p\le1/\alpha\) und \(p\ge0\) ⇒ M0.
- **T023 bestätigt:** Fixes \(W\ge0\) mit \(W_{ii}=1\) ⇒ \(Wp\ge p\), daher M2 ⇒ G1.
- **T024 bestätigt bedingt:** Mit Z≥0 zusätzlich M2 ⇒ G1 ⇒ M0.
- **T025 bestätigt:** Woodbury \((A+UCV)^{-1}=A^{-1}-A^{-1}U(C^{-1}+VA^{-1}U)^{-1}VA^{-1}\) gilt bei allen nötigen inversen Blöcken; keine MILP-Linearisierung.
- **T026 bestätigt durch false acceptance:** B=[[1,-1/2],[-1/2,1]], p=(3/5,3/5) liefert erste Neumann-Last 9/10, aber exakte inverse Last 6/5 >1.
- **T027 bestätigt:** Neumannreihe \(\sum_{k\ge0}(-E)^k\) konvergiert bei \(\rho(E)<1\). \(\|E\|<1\) ist hinreichend, nicht notwendig; nilpotentes E=[[0,2],[0,0]] hat ρ=0 und \(\|E\|_\infty=2\).
- **T028 bestätigt:** Rest \(R_{m+1}=(-E)^{m+1}(I+E)^{-1}A^{-1}\), Normschranke \(\|R\|\le\|E\|^{m+1}\|A^{-1}\|/(1-\|E\|)\) nur für \(\|E\|<1\). Beidseitiger Normfehler ist keine automatisch gültige einseitige Sicherheitsreserve.

## III. A35-NEW-001: M0 ⇒ G0 unabhängig bewiesen

**Voraussetzungen** B=Bᵀ≻0, Z=B^-1≥0 komponentenweise, p≥0, S=diag(p), α>0, gleiche Normierung. Dann
\[
Zp\le\alpha^{-1}\mathbf1\quad\Longrightarrow\quad B-\alpha S\succeq0.
\]

**Beweis 1, spektral:** K=αZS≥0, K1=αZp≤1 ⇒ ρ(K)≤||K||∞≤1. K ist ähnlich zur symmetrischen PSD-Matrix αB^-1/2 S B^-1/2. Somit \(I-\alpha B^{-1/2}SB^{-1/2}\succeq0\), also via Kongruenz G0.

**Beweis 2, Perron/Collatz:** \(K^m1\le1\) folgt induktiv aus K≥0 und K1≤1, also Perron-Radius ≤1. Auch reduzible B und Null-p sind zulässig.

**Beweis 3, direkte quadratische Abschätzung:** \(C=S^{1/2}ZS^{1/2}\). Für x_i=√p_i y_i (auf dem positiven Support) gilt wegen \(Z_{ij}\ge0\) und \(2y_iy_j\le y_i^2+y_j^2\):
\[
x^\top Cx=\sum_{ij}Z_{ij}p_ip_jy_iy_j
\le\sum_i (Zp)_i x_i^2\le\alpha^{-1}\|x\|^2.
\]
Damit C≼α^-1 I, und über das gemeinsame Nichtnullspektrum von C und \(B^{-1/2}SB^{-1/2}\) folgt G0. Bei S=0 ist nur die LMI, nicht ein endlicher Quotient definiert.

**Notwendige Inverspositivität:** B=[[1,4/5],[4/5,1]], p=(1,1), α=1: B SPD, Z hat negative Offdiagonalen, Zp=(5/9,5/9)≤1; B−S hat Eigenwerte ±4/5, also falsche Verallgemeinerung **widerlegt**.

**Echte Mengenstrenge:** B=[[2,-1],[-1,2]], p=(11/10,1/20): M0 gilt mit Zp=(3/4,2/5), G1 scheitert wegen erster Zeilensumme −1/10, G0 ist PSD. G0 ohne M0 siehe T010.

**Wissenschaftliche Einordnung:** neu ausdrücklich für das C2A-Projektledger, aber **kein** belegter originärer Matrixtheorie-Satz. Es ist ein Spezialfall der Perron-Frobenius-/M-Matrix-Theorie; vollständige nummerierte Satzlokatoren in Plemmons 1977/Berman-Plemmons und DSOS/SDSOS-Artikel waren nicht volltextverifiziert.

## IV. Hierarchie, Optimum, Grenzen

Unter vollständigen gemeinsamen Voraussetzungen:
\[
M2\Rightarrow G1\Rightarrow M0\Rightarrow G0\iff G3,\quad
M1\Rightarrow M0\Rightarrow G0,\quad G2(r)\Rightarrow G3\Rightarrow G0.
\]
Daneben M0⇒alle LOCAL und G0⇒alle LOCAL. Nicht gültig: G0⇒M0; alle LOCAL⇒G0; beliebig festes G2(r)⇔G1; G0⇒G3 außerhalb Z. **M1 und G1 inkomparabel**, ebenso G1 und beliebiges fixes G2. Eine kleinere Nachbar-W-Matrix macht M2 leichter, nicht zu einem externen Fault-MS​CR-Nachweis.

Für dieselbe Optimierungs- und Expositionsdomäne, identische Kosten und existierende optimale Werte:
\[
C^*_{G0}=C^*_{G3}\le C^*_{M0}\le C^*_{G1}\le C^*_{M2},\quad C^*_{M0}\le C^*_{M1}.
\]
Keine pauschale Ordnung M1 gegen G1/M2. Neun Worker-M1-INFEASIBLE-Fälle bedeuten **nicht** M0-INFEASIBLE. Kein Gleichsetzen interner B/S/gamma/Zeilenlast mit externer Fault-gSCR/MSCR, instationärer Converter-Stabilität oder voller Q–V-/CPF-Sicherheit.

## V. Implementierungsabhängigkeiten, nicht automatisch freigegeben

P001 Symmetrie bei allen Netzelementen; P002 Z-Vorzeichen nach Reduktion; P003 PSD/PD/Nullität/Inseln/Grounding; P004 Inverspositivität; P005 genaue G1-Reihe und identisches p/α; P006 Quellenstempel nur bei gültigem Quellenäquivalent; P007 p≥0 und MVA-/Spannungs-/S-on-Semantik; P008 vollständige G3-Kanten, signierte Stempel, √2-RSOC, Nicht-Doppelzählung und Rest; P009 Singular-S-Schur und Range; P010 unabhängige exakte M/Zp/Cost-Postverifikation. Jedes Prädikat bleibt auf realen registrierten Daten zu prüfen.

Original AP2 PaperARegional.reduced_strength prüft invertierbares L_ee über svdvals, nicht direkt PD. Das reicht für algebraische Kron-Elimination, nicht alleine für PSD-Schur; **kein nachgewiesener Datenfallfehler**, da gültige Eingangsdomäne L≽0 möglicherweise PD des eliminierten Blocks bereits sichert. Eine kontrollierte spätere Testmatrix muss C negativ, singulär, PSD-gültig und real physikalisch qualifiziert unterscheiden.

**Separate Folgeaufträge nach Wissenschaftsentscheidung:** A3.5-Gleichung-zu-JuMP, P001–P010 fallbezogen, native G3-MISOCP-B1, unabhängige Integer-Gap-/Optimalitätsbeweise, 124 Metric-IDs/acht CLI-Läufe, AP1/AP2-Parameter/Source- und Jahresrepräsentativitätsprüfung.

## VI. Findings, Entscheidung und Gates

**Major/confirmed:** A35-NEW-001 M0⇒G0 **konditional korrekt** und kontrolliert in Implikationsgraph einzubringen. **Major/confirmed scoped:** Source-behind-reactance erfordert physikalisch deklarierte Randbedingung, sonst Proxy. **Major/confirmed correction required:** T006 finite-GEV-Singularinterpretation nur mit gültiger Support-Schur-Domäne. **Major/unresolved implementation:** P001–010, native Solver/Integer/Empirie. **Major/conditional warning:** Invertierbarkeit ≠ PD bei eliminiertem Netz. **Minor/confirmed:** interne und externe SCR-Normalisierung nicht identisch. **Info/unresolved:** T003 historische Symbolidentität und volle externe Literatur-Gleichungsprüfung.

Literaturkontext (nicht originäre Entdeckung): Plemmons, LAA 18 (1977), DOI 10.1016/0024-3795(77)90073-8; Berman/Plemmons SIAM, DOI 10.1137/1.9781611971262; Ahmadi/Majumdar 2019 SIAM, DOI 10.1137/18M118935X. Bei eingeschränktem Volltext keine erfundenen nummerierten externen Sätze.

**Freeze-Amendment ausdrücklich nur PROPOSED**: (i) A35-NEW-001; (ii) Singularfall T006; (iii) Dirichlet-/Zeithorizont-Bedingung für b_src; (iv) strikte Theorie-/Projektprädikate. Entscheidung/Übernahme nur durch autorisierten Wissenschaftsowner mit neuem research-map-SHA, niemals aus diesem GitHub-Review allein.

**Mathematisches Reviewer-Urteil:** accepted_with_scoped_amendment_proposal. **Projektgates alle falsch:** science_amendment_approved=false, independent_A3_5_accepted=false, A3_closed=false, AP4_ready=false, empirical_study_ready=false. Ein erhaltener AP3-Worker-PASS ersetzt keine zusätzliche Abnahme.

Reproduzierbare lokale Evidenz: unabhängig entwickeltes Python-Fraction/SymPy-Oracle, 30/30 rationale Cases mit separater exakter Eigenspektralprüfung. SHA256 Skript 2301c90617bf7d6e931af7b0da55be7ca20664d3c46003a3ed80064c6dc279ba, Ergebnis-JSON f26874523782347e8e4ee4a42282e10bcc081e9d6b7840d02a1b167c25a466bb. Diese Theorie-Evidenz ist keine Implementierungs- oder Solverqualifikation.
