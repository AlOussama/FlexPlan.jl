# Paper A — Vorschlag einer kontrollierten wissenschaftlichen Freeze-Ergänzung

**Datum:** 2026-10-20. **Status:** PROPOSED; NOT ADJUDICATED; SCIENTIFIC FREEZE UNMODIFIED.
**Erarbeitet in:** reports/a3_5/mathematical_derivation_review_2026-10-20.md auf review/paper-a-a3-5-independent-acceptance-v1.
**Ziel:** ausschließlich Ergänzung des wissenschaftlichen Forschungsberichts von AlOussama/research-map nach separater mathematischer Adjudikation; keine automatische Codekorrektur oder Aussage über Empirie.

## Ergänzungsvorschlag A: Neuer bedingter Folgesatz (A35-NEW-001)

**Voraussetzungen:** B=B^\top\succ0 ist eine reelle symmetrische Steifigkeitsmatrix, Z=B^{-1} ist elementweise nichtnegativ, p>=0, S=diag(p), alpha>0. Die gleiche p- und B-Normalisierung wird in M0 und G0 verwendet.

**Behauptung:**
\[
\bigl(Zp\le\alpha^{-1}\mathbf1\bigr)\ \Longrightarrow\
\bigl(B-\alpha S\succeq0\bigr).
\]

**Beweis:** K=alpha ZS ist nichtnegativ; aus M0 folgt K1<=1. Daher rho(K)<=||K||_infty<=1. K ist ähnlich zu alpha B^{-1/2}SB^{-1/2}, das symmetrisch PSD ist. Folglich ist sein größter Eigenwert höchstens eins. Also I-alpha B^{-1/2}SB^{-1/2}\succeq0. Kongruenz mit B^{1/2} liefert B-alpha S\succeq0. Die Herleitung bleibt für singuläres S gültig, solange B SPD und M0 definiert sind. Bei S=0 ist die skalare gamma-Zahl nicht definiert, die LMI-Aussage dagegen weiterhin gültig.

**Strikter Charakter:** Für B=[[1,-1/2],[-1/2,1]], p=(1/4,2/3), alpha=1 erfüllt G0 die PSD-LMI, aber M0 scheitert: Zp=(7/9,19/18). Somit ist die Rückrichtung falsch. Bei B=[[2,-1],[-1,2]], p=(11/10,1/20) erfüllt M0 Zp=(3/4,2/5)<=1, während G1 wegen erster negativer Zeilensumme -1/10 scheitert; M ist dennoch positiv definit mit Det=151/200. So sind G1=>M0 und M0=>G0 echte Mengeneinschlüsse auf der angegebenen Domäne.

**Notwendige Domain-Qualifikation:** Ohne Z>=0 ist der Satz falsch: B=[[1,4/5],[4/5,1]] ist SPD, aber nicht Z/inverse-positiv. Mit p=(1,1), alpha=1 ist Zp=(5/9,5/9)<=1, während B-S Eigenwerte +/-4/5 hat.

**Vorgeschlagener neuer Implikationsabschnitt:** Unter B=B^\top\succ0, Z>=0, p>=0 und fixiertem alpha>0:
\[
M2\Rightarrow G1\Rightarrow M0\Rightarrow G0,\qquad
M1\Rightarrow M0\Rightarrow G0.
\]
Die Formulierungen M1/M2 erfordern weiterhin sämtliche speziellen Bmin-/W-Voraussetzungen. Der Satz ist eine **neue Ergänzung des C2A-Projektledgers**, keine beanspruchte originäre Entdeckung der nichtnegativen Matrixtheorie. Die zentralen Bausteine sind inverse-positive M-Matrizen und die Standardungleichung rho(K)<=||K||_infty.

## Ergänzungsvorschlag B: Quellenspannungs-Randbedingung bei diagonalem Source-Stamp

Für den erweiterten Quellstempel
\[
\begin{bmatrix}b&-b\\-b&L_{net}+b\end{bmatrix}
\]
gilt die einfache Addition +b an der Netzdiagonalen bei festem internem Quellpotential (Dirichlet-Äquivalent) oder als offen deklarierte Quellenspezialisation. Das bloße Eliminieren eines freien internen Knotens mit Nullstromeinspeisung führt dagegen zum Schur-Wert L_net+b-b=L_net. Der Wissenschaftstext soll den physikalischen Randzustand ausdrücklich benennen, bevor aktive SG/GFM/SC-Komponenten als diagonale source-strength Terme in Planungsrestriktionen übernommen werden. Diese Randbedingung wird nicht allein durch ein GFM-Klassenlabel erfüllt. Bei konkreter quellenseitiger Nichtlinearität/Dynamik bleibt die diagonale Ersatzstärkung nur ein gekennzeichneter Screening-Proxy.

## Erforderliche getrennte Beurteilung

1. Ein vom vorliegenden Ableitungsautor verschiedener mathematischer Reviewer überprüft den vollständigen Beweis, insbesondere S singular, B SPD/inverspositive Klasse und Gegenbeispiele.
2. Der Eigentümer der wissenschaftlichen Formulierung entscheidet, ob die intern stärkere M0-Bedingung als zertifizierte Teilmenge der G0-Bedingung in der Publikation beschrieben werden soll; externe SCR-Nomenklatur wird nicht automatisch umgedeutet.
3. Die physikalische Quelle wird einer fest definierten Randbedingungs-/Äquivalenzschaltbild-Klasse zugeordnet; andernfalls bleibt die Aussage als Proxy gekennzeichnet.
4. Wenn angenommen, Änderung nur über den im Freeze vorgesehenen Änderungsweg in research-map mit neuem normativem SHA und abgegrenztem Theorem-/Implikations-Delta.
5. Bis dahin: keine Änderung an Forschungs-Freeze oder bereits gemeldeten AP3-Urteilen; A3_closed=false, AP4_ready=false.

## Externe mathematische Hintergrundliteratur (Bausteine, nicht Originalitätsbehauptung)

- R. J. Plemmons (1977), M-matrix characterizations I — nonsingular M-matrices, Linear Algebra and its Applications 18, 175–188. DOI: https://doi.org/10.1016/0024-3795(77)90073-8. Inverspositivität und M-Matrix-Klassen.
- Berman & Plemmons, Nonnegative Matrices in the Mathematical Sciences, SIAM, chapter on generalized inverse positivity: https://doi.org/10.1137/1.9781611971262.ch5.
- C. Gentile & J. Hungerford (2019), Decompositions of Semidefinite Matrices and the Perspective Reformulation of Nonseparable Quadratic Programs, Mathematics of Operations Research. https://doi.org/10.1287/moor.2018.0969. Zweimal-zwei-Zerlegung bei skalierter Diagonaldominanz.
- Standard-Collatz-Wielandt-/Perron-Frobenius-Abschätzung für K>=0: rho(K)<=max_i(K1)_i; im neuen Satz kann alternativ unmittelbar die induzierte Unendlichnorm verwendet werden.
