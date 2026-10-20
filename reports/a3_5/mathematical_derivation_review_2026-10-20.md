# Paper A — A3.5: unabhängiger, schrittweiser mathematischer Herleitungsreview

**Datum:** 2026-10-20. **Art:** wissenschaftliche Beweisprüfung vor weiterer Software-/Solver-/Empirieabnahme.  
**Unveränderlicher Implementierungsreferenzpunkt:** FlexPlan.jl 485b637cc1998a327206c5929434bd26c6f0be16.  
**Wissenschaftliche Primärquelle:** research-map/main@e8118425adc335a99e85120d943763305f211315, scientific_report/2026-08-09__c2a-integrated-scientific-dissertation-chapter__restructured-v3.md, §§5–8, 17–26, 37–44, 50–52, Anhänge B–F.  
**Mathematischer Freeze:** 2c2fce769b2ed6ffd4f1ced60c0798776acccc93; eingefrorene Entscheidung in external_review/freeze/2026-08-02__c2a-scientific-formulation-freeze.md.  
**Akzeptierte frühere Beweismaterialien:** synthesis/2026-07-30__synthesis__c2a-track-a-adjudicated-proofs-and-counterexamples.md.  
**Neu hinzugefügte Resultate** sind hier ausdrücklich nicht automatisch Teil des eingefrorenen Theoremsets. **Keine Modifikationen an Mathematik-Freeze, Code, Inputdaten, Solverstatus oder bestehenden AP3-Berichten.**

## 0. Urteilslogik

Vier Gegenstände strikt trennen: (i) algebraische Aussage und genauer Geltungsbereich, (ii) physikalische Identifizierung von B und S, (iii) Abbildung auf Planungsentscheidungen, (iv) unabhängige numerische/Implementierungsprüfung. Dieser Bericht entscheidet (i) und identifiziert Voraussetzungen für (ii) und (iii); (iv) bleibt weitgehend außerhalb dieses Makroschritts. Ein bestandener algebraischer Test bedeutet weder, dass reale Daten die Domäne erfüllen, noch dass die Julia-Implementierung identisch ist.

Die Bezeichnungen G0, G1, G2, G3, M0, M1, M2, LOCAL und E2 gehören zur internen neutralen Forschungsformulierung; eine Zuordnung zu externen SCR/ESCR/MSCR/gSCR-Normen setzt separate physikalische Definitions- und Schwellenkalibrierung voraus.

Notation: B in R^{n×n} ist eine **reelle symmetrische Steifigkeitsmatrix**, Z=B^{-1} existiert nur unter Invertierbarkeitsannahme; p>=0 ist deklarierte GFL-Exposition auf kompatibler Basis, S=diag(p), alpha>0 ist eine fest vorgegebene Schwelle, M=B-alpha S. Schreibweisen <=, >= für Vektoren/Matrizen sind komponentweise, \succeq ist Loewner-Ordnung. Z-Matrix bedeutet m_ij<=0 für i!=j; eine reelle symmetrische positive definite Z-Matrix ist eine nonsingular M-Matrix mit B^{-1}>=0. S und Z bleiben mathematisch und physikalisch von der AC-QV-Jacobi-Matrix getrennt.

## 1. Von dem physikalischen Netzwerk zur Steifigkeitsmatrix (Herleitung)

### 1.1 Nodalgleichung und Stempel

Aus KCL und der linearen passiven Netzbeschreibung folgt I=Y^{(+)}V, Y^{(+)}=G+jB^{phys}. Für einen reziproken Zweig i-j ohne Tap ist sein Serien-Stempel
\[
Y^{(ij)}=y_{ij}(e_i-e_j)(e_i-e_j)^\top.
\]
Für y_{ij}=1/(r+jx)=(r-jx)/(r^2+x^2), x>0, folgt
\[
-\Im Y^{(ij)}=\frac{x}{r^2+x^2}(e_i-e_j)(e_i-e_j)^\top\succeq0,
\quad [-\Im Y^{(ij)}]_{ij}=-\frac{x}{r^2+x^2}<0.
\]
Im verlustlosen Fall r=0 ist das Gewicht 1/x. Addiert man ausschließlich solche Zweige, entsteht eine symmetrische positive semidefinite gewichtete Laplace-Matrix L mit L1=0. Sie ist bei einem schwebenden Netz **singulär**, nicht automatisch PD.

Shunt-/Ladebeiträge sind gesondert zu behandeln: ein kapazitiver Stempel +j b_sh fügt L_ii den Wert -b_sh hinzu. Das Vorzeichen kann PSD bzw. Z-Domänenaussagen beeinflussen. Komplexe Phasenschieber erzeugen im Allgemeinen unsymmetrische reale reduzierte Objekte. Daher ist
\[
L=-\Im Y^{(+)},\qquad L=L^\top,\ L_{ij}\le0
\]
nur unter der expliziten symmetrischen, reziproken Spezialisation ein gültiger Theoremeingang, nicht für beliebige AC-Netze. Ein als Winkelreferenz behandelter Bus darf nicht ohne deklarierte physische Bedeutung als zusätzliche Quelle künstlich geerdet werden.

### 1.2 Passive Festnetzreduktion (T001)

Partitioniere die physikalischen Busse in beibehaltene r und passive eliminierte e:
\[
L=\begin{bmatrix}L_{rr}&L_{re}\\L_{er}&L_{ee}\end{bmatrix}.
\]
Für den passiven e-Block gilt bei I_e=0 und L_ee invertierbar:
\[
0=L_{er}V_r+L_{ee}V_e
\Longrightarrow V_e=-L_{ee}^{-1}L_{er}V_r.
\]
Einsetzen in I_r liefert
\[
\boxed{B^0=L_{rr}-L_{re}L_{ee}^{-1}L_{er}}.
\]
Die Rechnung benötigt die Inverse; die Aussage über PSD benötigt zusätzlich L=L^\top, L_ee\succ0 und L\succeq0. Dies folgt aus quadratischer Ergänzung:
\[
\begin{bmatrix}u\\v\end{bmatrix}^{\!\top}
L\begin{bmatrix}u\\v\end{bmatrix}
=u^\top B^0u+
(v+L_{ee}^{-1}L_{er}u)^\top L_{ee}(v+L_{ee}^{-1}L_{er}u).
\]
Deshalb L\succeq0 genau dann, wenn B^0\succeq0 (bei L_ee\succ0). Ist L_ee eine nonsingular M-Matrix, dann L_ee^{-1}>=0, und der Schur-Stempel erhält die Z-Offdiagonalstruktur, sofern die relevanten Kopplungsblöcke diese Struktur haben. **Singuläres** L_ee erfordert die unten hergeleitete Range-Bedingung; bloßes Ersetzen durch Pseudoinverse ist unzulässig.

### 1.3 Diagonale Quellenstärke und ihre physikalische Grenze

Ein Quellreaktanzparameter x_k^{src} in p.u. auf der nativen Quellen-MVA-Basis S_k^{src} wird auf die gemeinsame S_base transformiert durch
\[
x_k^{sys}=x_k^{src}\frac{S_{base}}{S_k^{src}},\qquad
b_k^{src}=\frac1{x_k^{sys}}=\frac{S_k^{src}}{S_{base}x_k^{src}}.
\]
Das ist nur eine Umrechnung **unter gleicher Spannungsbasis und passender Transformator-/Anschlusskonvention**. Ein festes exogenes dimensionsloses regionales Aggregationsgewicht mu_k^{str} kann b_k^{src} multiplizieren.

Entscheidend ist die Quellenspannungsrandbedingung: für den eingefrorenen zweiknotigen Quellstempel
\[
L_{src}=\begin{bmatrix}b&-b\\-b&L_{net}+b\end{bmatrix}
\]
bleibt bei festgehaltenem internem Quellpotential E die terminale Steifigkeit L_net+b. Wird dagegen der **freie** innere Knoten mit I_internal=0 eliminiert, lautet dessen Schur-Beitrag
\[
(L_{net}+b)-(-b)b^{-1}(-b)=L_{net}.
\]
Ein bloßes „GFM vorhanden“ beweist daher kein zusätzliches b auf der Diagonalen. Die direkte Stärkeaddition ist physikalisch nur für die **deklarierte festgehaltene interne Quellspannungs-/Source-behind-reactance-Spezialisation** oder als ausdrücklich gekennzeichneter äquivalenter Planungsproxy zulässig. Dass B0 eine passive Schur-Matrix ist, beweist diese Source-Boundary-Annahme nicht automatisch.

Ist die Stärke **nur an erhaltenen** Buspositionen diagonal hinzugefügt, kommutiert sie mit der vorher fixierten passiven Elimination:
\[
\operatorname{Schur}_e(L+\operatorname{diag}(b_r,0_e))
=B^0+\operatorname{diag}(b_r).
\]
Ist dagegen eine Entscheidung im zu eliminierenden Block enthalten, tritt (L_ee+\Delta_e(x))^{-1} auf und die reduzierte Abbildung ist im Allgemeinen nicht affin. Beispiel: 2-1/(1+u) hat von null verschiedene zweite Ableitung.

### 1.4 Expositionsmatrix und affine Planungsspezialisation

Bei fixierter Regionstopologie und exogenen mu-Gewichten:
\[
p_{i,t}^{on}
=\sum_{k\in GFL_i}\mu_k^{fl}
\frac{P_k^{blk,MW}}{S_{base}}n_{k,t}^{on}\ge0,
\quad
b_{i,t}^{src}
=\sum_{k\in Sources_i}\mu_k^{str}
\frac{S_k^{src}}{S_{base}x_k^{src}}n_{k,t}^{on}\ge0.
\]
Die zweite Formel setzt die oben präzisierte Quellenäquivalenz voraus. Dann
\[
B_t=B^0+\operatorname{diag}(b_t^{src}),\quad
S_t=\operatorname{diag}(p_t^{on}),\quad
M_t=B_t-\alpha S_t.
\]
Diese Abhängigkeit ist **affin** in n_on für feste alpha, feste Koeffizienten und festes B0. Verfügbarkeits-/Online-Beschränkungen sind z.B. 0<=n_on<=n_avail<=n_inst, ggf. n_on<=a_conn n_inst bei exogenem a_conn. Installiert, online, abgegebenes P und Stromfähigkeit sind nicht austauschbar. S^nom, S^on, S^op und S^I sind unterschiedliche Datendefinitionen. Bei variabler Topologie oder Entscheidung im Kron-Block ist Affinität gesondert neu zu prüfen.

## 2. Gewöhnlicher und generalisierter Schur (T001/T004)

Für die reell symmetrische Blockmatrix
\[
H=\begin{bmatrix}A&F\\F^\top&C\end{bmatrix}
\]
und C\succ0 folgt aus quadratischer Ergänzung
\[
H\succeq0\iff A-FC^{-1}F^\top\succeq0.
\]
Bei C\succeq0 **singulär** setze den orthogonalen Projektor P_C=CC^\dagger. Der gemischte bilineare Term zwischen einem Nullvektor v in ker(C) und u verschwindet in einem PSD-H genau dann, wenn
\[
(I-CC^\dagger)F^\top=0.
\]
Andernfalls kann ein beliebig großer Skalierungsfaktor entlang ker(C) die quadratische Form negativ machen. Mit der Range-Bedingung gilt durch quadratische Ergänzung mit C^\dagger:
\[
\boxed{H\succeq0\iff C\succeq0,\ (I-CC^\dagger)F^\top=0,\ A-FC^\dagger F^\top\succeq0}.
\]
Eine „Pseudoinverse ohne Range-Test“ ist kein gültiger allgemeiner Beweis.

**T002 Parallel Sum:** für N,D\succ0
\[
D-D(N+D)^{-1}D=D(N+D)^{-1}N.
\]
Invertieren des Produkts ergibt N^{-1}(N+D)D^{-1}=N^{-1}+D^{-1}, also
\[
\boxed{D-D(N+D)^{-1}D=(N^{-1}+D^{-1})^{-1}}.
\]
Keine Kommutativität wird vorausgesetzt. **T003** bleibt ausschließlich eine eingeschränkt interpretierte historische Vorzeichen-/Symbolzuordnung; ein exakter Herkunftsnachweis nicht zugänglicher Originalsymbole liegt nicht vor.

## 3. G0 als exaktes Matrixzertifikat (T005/T006)

Mit S\succ0 und symmetrischem B:
\[
\gamma^{GE}=\lambda_{\min}(S^{-1/2}BS^{-1/2}).
\]
Die Äquivalenz folgt direkt durch Kongruenz:
\[
\begin{aligned}
\gamma^{GE}\ge\alpha
&\iff S^{-1/2}BS^{-1/2}-\alpha I\succeq0\\
&\iff \boxed{B-\alpha S\succeq0}.
\end{aligned}
\]
Für S\succeq0 singulär bleibt **die Vollraum-LMI** B-alpha S\succeq0 sinnvoll, selbst bei S=0. Eine skalare gSCR-/gamma-Zahl ist dagegen bei S=0 nicht definiert. Für S!=0 kann sie primär über den Rayleigh-Infimumausdruck definiert werden:
\[
\gamma^{GE}=\inf_{x:\,x^\top Sx>0}
\frac{x^\top Bx}{x^\top Sx}.
\]
Schreibe positive Expositionsbusse a und Null-Expositionsbusse z. Ist B_zz\succ0, dann
\[
\gamma^{GE}=
\lambda_{\min}\!\left(
S_a^{-1/2}(B_{aa}-B_{az}B_{zz}^{-1}B_{za})S_a^{-1/2}
\right).
\]
Ist B_zz\succeq0 singulär, bedarf es (I-B_zz B_zz^\dagger)B_za=0 und der generalisierten Schur-Matrix. Bei B_zz mit negativer Richtung oder versagender Range-Bedingung kann das Infimum -unendlich werden; in diesem Fall darf eine gewöhnliche „kleinste endliche Eigenzahl“-Routinenantwort **nicht** als Sicherheitsgrenze ausgegeben werden.

**Exakte Null-Expositions-Gegenprobe:** B=[[2,-1],[-1,2]], S=diag(1,0). Exaktes Eliminieren des Null-Expositions-Busses liefert 2-1/2=3/2; naives Streichen liefert 2. Bei alpha=7/4 würde der naive lokale Test bestehen, G0 jedoch wegen des negativen Schur-Rests -1/4 scheitern. Bei B=[[1,1],[1,0]], S=diag(1,0) hat B_zz=0, B_za=1: Die Range-Bedingung scheitert; der Rayleigh-Quotient ist nach unten unbeschränkt.

## 4. LOCAL und exakte M0-Zeilenbelastung (T007–T010)

Setze B\succ0, Z=B^{-1}, p_i>0. Die lokale Diagonalkennzahl ist
\[
\rho_i^{diag}=\frac{1}{Z_{ii}p_i}.
\]
Der Rang-eins-PSD-Test folgt durch Kongruenz und die einzige nichtverschwindende Eigenzahl:
\[
\begin{aligned}
B-\alpha p_ie_ie_i^\top\succeq0
&\iff I-\alpha p_iB^{-1/2}e_ie_i^\top B^{-1/2}\succeq0\\
&\iff 1-\alpha p_i e_i^\top B^{-1}e_i\ge0\\
&\iff \boxed{\rho_i^{diag}\ge\alpha}.
\end{aligned}
\]
Aus G0 folgt wegen alpha S\succeq alpha p_i e_ie_i^\top jeder LOCAL-Test, aber die Umkehrung ist falsch.

Die exakte interne MSCR-/M0-Belastung verwendet **alle** Injektionen:
\[
\psi_i=(Zp)_i=\sum_jZ_{ij}p_j,\qquad
M0:\quad \boxed{Zp\le\alpha^{-1}\mathbf1}.
\]
Bei Z>=0 und p>=0 ist (Zp)_i>=Z_ii p_i, also M0=>LOCAL (bei p_i>0). Die Größe 1/(Zp)_i ist nur definiert für positiven Nenner; bei Nullbelastung nicht heimlich 0 verwenden.

**Frozen T010:** B=[[1,-1/2],[-1/2,1]], p=[1/4,2/3], alpha=1:
\[
M=\begin{bmatrix}3/4&-1/2\\-1/2&1/3\end{bmatrix},
\quad \sigma(M)=\{0,13/12\},
\quad Zp=(7/9,19/18)^\top.
\]
G0 besteht, M0 scheitert am zweiten Bus. Bei p=(3/4,3/4) bestehen beide lokalen Diagonalbedingungen, während M einen Eigenwert -1/4 besitzt; LOCAL allein reicht nicht für G0.

## 5. G1: symmetrische Z-Matrix und Gershgorin (T011/T012)

Sei M=M^\top und m_ij<=0 für i!=j. Schreibe a_ij=-m_ij>=0 und den Zeilenrest
\[
d_i=m_{ii}-\sum_{j\ne i}a_{ij}=(M\mathbf1)_i.
\]
Dann ist für beliebiges x
\[
\boxed{x^\top Mx=\sum_{i<j}a_{ij}(x_i-x_j)^2+\sum_i d_ix_i^2}.
\]
G1 ist d_i>=0 für alle i, also hinreichend für G0. In B/p/alpha ist dies
\[
\boxed{B\mathbf1\ge\alpha p}
\quad\Leftrightarrow\quad
B_{ii}-\sum_{j\ne i}|B_{ij}|\ge\alpha p_i
\]
für die Z-Klasse. Die Z-Voraussetzung ist unverzichtbar für das Ersetzen von Betragssummen durch normale Zeilensummen: [[1,2],[2,1]] hat positive Zeilensummen, aber Eigenwert -1. G1 ist hinreichend und allgemein nicht notwendig für G0.

Wenn zusätzlich B invertierbar und Z=B^{-1}>=0 ist, darf die **komponentenweise** Ungleichung links mit Z multipliziert werden:
\[
B\mathbf1\ge\alpha p\Longrightarrow
\mathbf1\ge\alpha Zp,
\]
also G1=>M0 (T012). Das ist kein Loewner-Inversionsargument. Ist B singulär oder Z nicht nichtnegativ, folgt M0 nicht auf diesem Weg.

## 6. G2: positiv vorab festgelegte Zeilenskalierung (T013–T016)

Für festes r>0 setze D=diag(r). Die Bedingung G2 lautet
\[
\boxed{Mr\ge0}.
\]
Denn für jede Zeile gilt
\[
(DMD)_{ii}-\sum_{j\ne i}|(DMD)_{ij}|
=r_i(Mr)_i\ge0.
\]
DMD ist symmetrisch diagonaldominant und daher PSD, woraus per Kongruenz M\succeq0 folgt. G2(1)=G1. Ein bereits positiver Vektor r ist ein G2-Beweiszeuge und induziert G3-Budgets:
\[
q_{ij}=|m_{ij}|\frac{r_j}{r_i},\quad
q_{ji}=|m_{ij}|\frac{r_i}{r_j},\quad
q_{ij}q_{ji}=m_{ij}^2.
\]

Die Wahl von r muss vor der linearen Optimierung feststehen; gemeinsames Entscheiden über r und n_on erzeugt generell Produkte m_ij(n_on)r_j. G1 und ein **beliebiges vorab gewähltes** G2 sind nicht geordnet:
- M=[[1,-3/5],[-3/5,1]], r=(2,1): M1=(2/5,2/5)>=0, Mr=(7/5,-1/5) nicht>=0;
- M=[[2/5,-3/5],[-3/5,6/5]], r=(2,1): Mr=(1/5,0)>=0, M1=(-1/5,3/5) nicht>=0.

Die Existenz *irgendeines* r>0 ist auf der PSD-Z-Klasse dagegen äquivalent zur PSD-Eigenschaft (siehe G3), aber das ist **keine** Gleichheit mit einem fix gewählten G2(r).

## 7. G3: vollständige signierte Kantenzerlegung (T016–T020)

Gegeben sei M=M^\top. Für jedes nichtverschwindende Paar (i,j), i<j, genau **eine** ungerichtete Kante. Setze zwei Endpunktbudgets q_ij,q_ji>=0 und
\[
E^{ij}=
\begin{bmatrix}q_{ij}&m_{ij}\\m_{ij}&q_{ji}\end{bmatrix}\succeq0.
\]
Das ist bei q>=0 äquivalent zu q_ij q_ji>=m_ij², also bei der Standardkonvention Q_r^3={ (u,v,w):2uv>=w², u>=0,v>=0 } zu
\[
\boxed{(q_{ij},q_{ji},\sqrt2\,m_{ij})\in Q_r^3}.
\]
Die diagonal verbleibenden Budgets sind
\[
d_i^{res}=m_{ii}-\sum_{j:\,\{i,j\}\in E}q_{ij}\ge0.
\]
Durch Einbettung jedes E^{ij} in die Gesamtmatrix und Addieren von diag(d^{res}) erhält man M **genau**, ohne doppelt gezählte Kanten. Alle Summanden PSD, also G3=>G0 für **jede symmetrische** Matrix, auch außerhalb der Z-Klasse.

Die **umgekehrte Richtung** benötigt die symmetrische Z-Klasse. Für M\succeq0, m_ij<=0:
1. Zerlege M nach zusammenhängenden nichtverschwindenden Offdiagonalkomponenten.
2. Jeder nonsinguläre irreduzible Block ist eine SPD-M-Matrix; r_k=M_k^{-1}1>0.
3. Jeder singuläre irreduzible PSD-Z-Block besitzt aus der Perron-Frobenius/M-Matrix-Struktur einen strikt positiven Nullvektor r_k>0.
4. Isolierte Nullzeilen erhalten beliebige positive r_i; isolierte positive Diagonalen ebenfalls.
5. Insgesamt gibt es r>0 mit Mr>=0. Die Budgets aus §6 erfüllen alle Konen und Knotenreste.
Damit gilt für die **vollständig abgebildete** symmetrische Z-Klasse:
\[
\boxed{G3\iff G0}.
\]
Die Singulargrenze einschließlich Laplacians ist enthalten; weder PD noch Irreduzibilität des gesamten M ist notwendig. **P-C2A-008** (vollständige Kantenpaare und signierte Rekonstruktion) ist jedoch ein separates Modellprädikat.

Die Z-Klasse kann nicht entfallen: Die symmetrische Matrix mit Diagonalwerten 1 und drei positiven Kopplungen 7/10 hat Eigenwerte 12/5, 3/10, 3/10, ist also PSD; eine positive DD-Skalierung würde aber für alle i r_i>=0.7(r_j+r_k) verlangen. Summation ergäbe sum(r)>=1.4sum(r), unmöglich für r>0. Somit ist G0 erfüllt, G3 nicht; die allgemeine rückwärtige Implikation ist falsch.

## 8. M0 ==> G0: im Freeze nicht explizit ausgewiesener zusätzlicher Satz

**Neuer, eigenständig hergeleiteter Satz A35-NEW-001 (keine stillschweigende Freeze-Modifikation):**

Sei B=B^\top\succ0, Z=B^{-1}>=0 komponentweise, p>=0, S=diag(p), alpha>0. Dann
\[
\boxed{Zp\le\alpha^{-1}\mathbf1\quad\Longrightarrow\quad B-\alpha S\succeq0}.
\]

**Beweis Schritt für Schritt.**
1. Definiere K=alpha ZS. Aus Z,S>=0 folgt K>=0 komponentweise.
2. K1=alpha Zp<=1. Deshalb \|K\|_\infty=max_i sum_j K_ij<=1 und \rho(K)<=1.
3. K ist über B^{1/2} ähnlich zu H=alpha B^{-1/2} S B^{-1/2}: B^{1/2} K B^{-1/2}=H.
4. H=H^\top\succeq0, hat dieselben Eigenwerte wie K, also 0<=lambda_max(H)<=1.
5. I-H\succeq0, und B^{1/2}(I-H)B^{1/2}=B-alpha S\succeq0.

Damit ist unter der gemeinsamen inverspositiven SPD-Domäne G1=>M0=>G0. Weil G0 nicht M0 impliziert (T010), ist die zweite Inklusion echt. Auch G1=>M0 ist im Allgemeinen echt: B=[[2,-1],[-1,2]], p=(11/10,1/20), alpha=1 ergeben Zp=(3/4,2/5)<=1, aber (B-diag(p))1=(-1/10,19/20), sodass G1 scheitert; G0 gilt (Determinante 151/200>0 bei positiven Diagonalen).

**Unverzichtbare Inverspositivität:** B=[[1,4/5],[4/5,1]] ist symmetrisch PD, aber Z besitzt negative Offdiagonalen. Bei p=(1,1), alpha=1 ergibt Zp=(5/9,5/9)<=1, während B-S die Eigenwerte +/-4/5 besitzt. Ohne Z>=0 ist M0=>G0 also falsch.

Diese neue Implikation ergänzt die bisherige Quelle; sie korrigiert **nicht** den gültigen T010-Gegenbeweis. Sie sollte als vorgeschlagener Folgesatz gesondert mit Freeze-Change-Control adjudiziert werden. Semantisch ist sie eine Relation der hier **intern definierten** M0-/G0-Objekte, keine Übertragung auf extern anders normierte MSCR-/gSCR-Indizes.

## 9. M1: festes inverses Oberzertifikat (T021/T022)

Sei Bmin eine vorab fixierte **nonsinguläre M-Matrix** mit Zub=Bmin^{-1}>=0. Für jeden zulässigen Onlinezustand sei B ebenfalls eine nonsinguläre M-Matrix und **modellseitig** B>=Bmin komponentweise gewährleistet. Dann
\[
Zub-Z=Bmin^{-1}-B^{-1}
=Bmin^{-1}(B-Bmin)B^{-1}\ge0
\]
komponentenweise, da alle drei Faktoren nichtnegativ sind. Mit p>=0:
\[
Zp\le Zub p.
\]
Damit ergibt sich die lineare hinreichende M1-Bedingung
\[
\boxed{B\ge Bmin,\qquad Zub p\le\alpha^{-1}\mathbf1}
\Longrightarrow M0.
\]
Innerhalb der in §8 genannten SPD-inverspositiven Domäne folgt zusätzlich M1=>G0. Die Mindestmatrix kann selbst durch die Quelle nachgeführte **physikalische echte Mindeststärke** oder ein explizites Screening-Policy-Parameterobjekt sein; sie darf nicht ohne Kennzeichnung als gemessene Netzerdung ausgegeben werden. Ein als Untergrenze behaupteter b_min-Wert ohne tatsächliche Optimierungsrestriktion reicht nicht aus.

Die Behauptung „Gershgorin-Zeilenrest <=1/Zub_ii“ ist **nicht** allgemein aus SPD-M-Matrix-Eigenschaften ableitbar. Nicht als Beweisschritt einsetzen.

## 10. M2: normierte Interaktionsgewichte (T023/T024)

Voraussetzungen: p>=0, W>=0, W_ii=1, W vor der Optimierung festgehalten. Dann
\[
(Wp)_i=p_i+\sum_{j\ne i}W_{ij}p_j\ge p_i.
\]
Die M2-Bedingung im eingefrorenen Projekt ist
\[
\boxed{B\mathbf1\ge\alpha Wp}.
\]
Somit B1>=alpha p und daher M2=>G1. Wenn außerdem B^{-1}>=0, B nonsingulär, folgt über §5 M2=>M0; und über §8 folgt M0=>G0. Das ist eine **hinreichende** Absicherung von M0 unter Zusatzannahmen, nicht die exakt nachgebildete M0-Ungleichung.

Ein W aus einer fixen Referenzimpedanz mit W_ij=Zref_ij/Zref_ii ist eine zusätzliche Daten-/Interpretationswahl. Wird ein gültiges nichtnegatives Voll-W zur sparsamen Nachbargewichtung verkleinert, kann die Bedingung leichter erfüllbar werden. Daraus folgt weder eine numerische Genauigkeitsgarantie für MIIF noch ein exaktes Zertifikat für externe dynamische Multi-Infeed-Wechselwirkung. Domäne und Diagonale 1 müssen erhalten bleiben.

## 11. Woodbury, Neumann, E2 und einseitige Sicherheitsbehauptungen (T025–T028)

Bei A invertierbar, C invertierbar und wohldefinierten weiteren Inversen ist Woodbury:
\[
(A+UCV)^{-1}=A^{-1}-A^{-1}U(C^{-1}+VA^{-1}U)^{-1}VA^{-1}.
\]
Bei einer Entscheidungsmatrix \Delta gilt alternativ, auch für singuläre \Delta, wenn I+A^{-1}\Delta invertierbar:
\[
(A+\Delta)^{-1}=(I+E)^{-1}A^{-1},\quad E=A^{-1}\Delta.
\]
Die exakte inverse Aktualisierung linearisiert nicht automatisch die Planungsaufgabe.

Für \rho(E)<1 konvergiert die Neumann-Reihe
\[
(I+E)^{-1}=\sum_{k=0}^\infty(-E)^k.
\]
Nach Ordnung m mit T_m=sum_{k=0}^{m}(-E)^k A^{-1} ist das **exakte** Restglied
\[
R_{m+1}=(A+\Delta)^{-1}-T_m
=(-E)^{m+1}(I+E)^{-1}A^{-1}.
\]
Für eine induzierte Norm mit q=\|E\|<1:
\[
\|R_{m+1}\|\le\frac{q^{m+1}}{1-q}\|A^{-1}\|.
\]
Bei q>=1 darf diese Normformel nicht als Zertifikatsgrenze verwendet werden, selbst wenn die Reihe aufgrund rho(E)<1 eventuell konvergiert. Eine Normschranke ist zunächst zweiseitig; für eine **einseitig sichere** MSCR-Bedingung muss z.B. zusätzlich ein gültiger komponentweiser Fehlermajorant \varepsilon_i>=\psi_i-\widehat\psi_i nachgewiesen und \widehat\psi_i+\varepsilon_i<=1/alpha erzwungen werden.

Unkontrollierte Approximation ist nicht sicher: B=[[1,-1/2],[-1/2,1]], p=(3/5,3/5). Die Ersatzinverse I liefert Belastung (3/5,3/5), die exakte Inverse dagegen (6/5,6/5) und verletzt M0. Das gilt unabhängig davon, dass \rho(E)<1 und eine vollständige Neumann-Reihe existiert: eine endliche ungesicherte Trunkierung kann falsch akzeptieren.

## 12. Korrigierte/erweiterte mathematische Implikationskarte

Nur bei festem alpha und derselben p-/B-Normalisierung, auf den jeweils ausdrücklich genannten Domänen:

- Allgemein symmetrische M: G3 => G0.
- Symmetrische Z-M: G1=>G0, G2(r>0 fest)=>G0, G3=>G0; G0=>LOCAL bei B\succ0.
- Vollständig modellierte symmetrische PSD Z-M: G3 <=> G0 (inklusive Nullrandfälle).
- B=B^T\succ0, Z>=0, p>=0: **M2=>G1=>M0=>G0**, M1=>M0=>G0, M0=>LOCAL. Die Pfeile von M0=>G0 und M1=>G0 sind die neue mathematische Ergänzung aus diesem Review; eingefrorene Originalpfeile bleiben unverändert.
- Nicht gültig allgemein: G0=>M0; LOCAL (alle)=>G0; festes beliebiges G1=>G2 oder G2=>G1; G0=>G3 ohne Z; M0=>G0 ohne inverse Positivität.

Das exakte M0 ist in dieser Matrixklasse ein **Zeilennorm-Zertifikat** der spektralen G0-Bedingung: \rho(alpha ZS)<=\|alpha ZS\|_\infty=\alpha\|Zp\|_\infty. Diese Ungleichung ist der eigentliche Grund der neuen Relation.

## 13. Präzise Theoremprüfung T-C2A-001–028

| Theorem-ID | Inhalt / Beweiskette | Mathematischer Befund |
|---|---|---|
| 001 | Algebraisches Eliminieren; PSD-Schur verlangt eliminierten PD-Block | korrekt, domänengebunden |
| 002 | Parallel Sum ohne Vertauschbarkeitsannahme | korrekt, hergeleitet |
| 003 | Historisches Vorzeichen und Originalsymbol | keine neue Quellenidentität beweisbar; bestehende Ungewissheit erhalten |
| 004 | Zero-support-Schur; Pseudoinverse plus Range | korrekt; negative/null Bereiche ausdrücklich behandeln |
| 005 | positiver Support, G0 spektral iff PSD | korrekt |
| 006 | S singulär, reduzierte endliche Werte | korrekt bei Schur-Domäne; indefiniter/range-falscher Nullblock darf nicht als regulärer endlicher Gammawert klassifiziert werden |
| 007 | lokaler Rang-eins-Test | korrekt für B PD und p_i>0 |
| 008 | G0 impliziert alle lokalen Diagonaltests | korrekt für B PD, p>=0 |
| 009 | M0 impliziert lokale Diagonaltests | korrekt für Z>=0, p>=0 |
| 010 | G0 nicht impliziert M0 | exakter rationaler Gegenfall bestätigt |
| 011 | G1-Zeilensummen und quadratische Zerlegung | korrekt auf symmetrischer Z-Klasse |
| 012 | G1=>M0 durch inverspositive Multiplikation | korrekt; Invertierbarkeit nötig |
| 013 | festes positives G2=>G0 | korrekt |
| 014 | G2(1)=G1 | korrekt |
| 015 | G1/festes G2 nicht vergleichbar | beide rationalen Fälle bestätigt |
| 016 | positives r ergibt G3-Budgetzeuge | korrekt |
| 017 | vollständige Edge-PSD-Zerlegung => PSD | korrekt, sogar ohne Z |
| 018 | PSD-Z-Matrix => geschlossene SDD inklusive singulär/reduzibel | korrekt auf angegebener Klasse |
| 019 | vollständige signierte i<j-Kantenmodellierung | notwendig für exakte Projektion; projektseitig noch zu verifizieren |
| 020 | G3<=>G0 auf symmetrischer Z-Klasse bei P008 | mathematisch korrekt, implementierungskonditional |
| 021 | geordnete nonsinguläre M-Matrizen: inverse Ordnung | korrekt |
| 022 | erzwungenes Bmin und Zub p => M0 | korrekt; Bmin muss tatsächlich gelten |
| 023 | Wp>=p und M2=>G1 | korrekt |
| 024 | M2=>G1=>M0 unter inverspositivem B | korrekt |
| 025 | exakte Woodbury-Identität | korrekt unter Inversenannahmen |
| 026 | unkontrollierte erste Ordnung nicht global sicher | korrekt, Gegenfall |
| 027 | Neumann unter rho(E)<1 | korrekt |
| 028 | exakter Rest; induzierte Normschranke für \|E\|<1 | korrekt, keine automatische einseitige Sicherheit |

**Grenzen der Eigenprüfung:** Die algebraischen Ableitungen wurden unabhängig rekonstruiert. 20 rational-exakte SymPy-Assertions wurden tatsächlich ausgeführt. Das ist kein maschinelles Beweiszertifikat für beliebige Dimensionen und keine Prüfung von Julia-Modellkodierung, Präzisionsgrenzen aller Instanzen oder externen Normen.

## 14. Wissenschaftliche Findings (ohne Codekorrektur)

**A35-MATH-001 — major / neue zu adjudizierende Folgerung.** M0=>G0 fehlt im expliziten eingefrorenen Implikationsdiagramm. Selbstständiger Beweis und genaue Annahmen in §8; eigenständiger rationaler Test zeigt strikte G1/M0-Inklusion und Nicht-Z-Gegenbeispiel. Keine ursprüngliche Behauptung wird durch den neuen Satz widerlegt. Änderungsbedarf ist eine **kontrollierte Ergänzung** zum Theorie-Freeze, nicht ein ungeprüfter Implementierungsfix.

**A35-MATH-002 — major / physikalische Begrenzung.** Die Additivität einer Quellenreaktanz zur Steifigkeitsdiagonale folgt nicht allein aus der passiven Netz-Kron-Reduktion. Festes internes Quellpotential bzw. offengelegte Proxy-Semantik muss als Modellannahme genannt werden. Physikalische Generator-/Converter-Spezifikation und GFM-Label sind für sich kein Beweis dieser Ersatzstempelung. Die Basisrechnung des Kapitels ist bedingt korrekt; der freie innere Quellknoten liefert ein konstruktives Gegenmodell gegen unqualifizierte Allgemeinaussagen.

**A35-MATH-003 — major / Singular- und Z-Geltungsbereich.** Gamma-, M0- und G3-Berichte dürfen nur unter jeweils gültiger Domain interpretiert werden. Nullsupport fordert Range, M0 fordert B invertierbar plus inverse Ordnung, G0/G3-Exactness benötigt Symmetrie, Z-Struktur und vollständige signierte Kanten. Die eingefrorene Quelle beschreibt dies korrekt, verlangt aber lückenlose Prädikatanwendung bei späterer Abnahme.

**A35-MATH-004 — minor / Aussageklassifikation.** M1 (strenge Zeilenlastbegrenzung mittels Zub), M2 (gewichtet verstärkte G1-Reihe), G1, G2, G3 verwenden verschiedene innere Sicherheitsannahmen. Allein ein gemeinsamer Schwellenwert alpha garantiert keine externe fault-/converter-spezifische physikalische Metrikgleichheit. S^on muss als Produktionsvergleich festgehalten werden.

**A35-MATH-005 — informational / offene historische Quelle.** T003 und externe Symboläquivalenzen bleiben in der Primärquelle ausdrücklich ungeklärt. Keine nachträgliche erfundene Gleichungsidentität oder Quellenlokalisierung.

## 15. Freigabeentscheidung vor den nächsten Studien

**Mathematische Originalformeln:** Die geprüften Kernaussagen T001–T028 sind innerhalb ihrer ausdrücklich genannten Annahmen schlüssig. Es wurde **kein Widerspruch** zu einem bestehenden eingefrorenen Satz nachgewiesen.  
**Vollständigkeit der theoretischen Implikationskarte:** Ergänzungsbedarf A35-MATH-001.  
**Physikalische Interpretation der Quellenstärkung:** nur bedingt validiert; A35-MATH-002 muss für den konkret gewählten Ersatzschaltkreis ausdrücklich fixiert werden.  
**Projektweite Gültigkeit der mathematischen Voraussetzungen:** vor künftigen numerischen/Implementierungsstudien nachzuweisen, nicht durch diesen Beweisreview ersetzt.  
**Bisherige Gates:** independent_A3_5_accepted=false, A3_closed=false, AP4_ready=false.

**Nächste wissenschaftliche Entscheidung vor weiterer Solver-/Datenarbeit:** Einen *mathematischen Freeze-Amendment*-Entwurf für den neuen konditionalen Satz M0=>G0 und eine explizite Quellenspannungs-Randbedingung erstellen; unabhängig adjudizieren; erst danach Gleichung-zu-Code/Integer/124-Metrik/CLI/empirische Abnahme fortsetzen. Der Freeze bleibt bis zu dieser Entscheidung inhaltlich unverändert.

## 16. Reproduzierbare unabhängige rationale Prüfungen

20/20 exakte SymPy-Assertions wurden ohne FlexPlan/AP3-Import unter SymPy 1.14 ausgeführt. Testfamilien: gewöhnlicher/allgemeiner Schur, Nullsupport/Range, lokale rank-one, G0 vs M0, G1/G2 in beiden Richtungen, G3 signed RSOC, singuläre reduzible SDD, nicht-Z PSD vs SDD, M-Matrix-Inversenordnung, M2, exakter Neumannrest, unsichere Trunkierung, neuer M0=>G0-Fall, notwendige Inverspositivität und Quellen-/Kron-Randbedingung. Reproduktionskommando: python oracles.py in der zugehörigen eigenständigen Testdatei (benötigt SymPy 1.14). Die Tests sind Nachweise für konkrete Identitäten/Gegenbeispiele, nicht universelle Beweise.
