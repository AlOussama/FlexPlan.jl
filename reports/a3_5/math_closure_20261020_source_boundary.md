# A3.5-MATH — Physikalische Source-/Netz-Grenzen

Die Definition L=-Im(Y+) ist von AC-PF-/QV-Jacobi, Fault-SCR und Converter-Dynamik getrennt. Eine symmetrische Z-/PSD-Matrix folgt bei Laplace-artigem positivem Serien-L nur unter einzeln bestätigten Tap-/Shunt-/Grounding-Bedingungen. Kapazitive Ladung wird mit Vorzeichen minus auf L-Diagonalen gestempelt.

Positive semidefinite Schur-Zertifizierung: Für L=[[A,F],[Fᵀ,C]], C≻0 ist L≽0 äquivalent zu A-FC^-1Fᵀ≽0. Ist C≽0 singulär, sind Range (I−CC†)Fᵀ=0 und A-FC†Fᵀ≽0 zusätzlich nötig. Beispiel C=-1, A=2,F=-1: Schur=3, obwohl L indefinit. Nicht als AP3-Implementierungsfehler ohne Domain-Test ausgeben.

Quelle hinter Reaktanz: Bei im gewählten Zeitbereich gehaltenem E ist der terminale b-Stamp sachgerecht. Bei frei/stromlos intern eliminiertem Knoten verschwindet b nach Schur, da b−b²/b=0. Diese zweite Aufgabe beschreibt ausdrücklich keine ideale Spannungsquelle. Das korrekte Netz-/Source-Äquivalent hängt von synchronspezifischer transient-/subtransient-Reaktanz, GFM-Regler, Ausgangsfilter, Strombegrenzung, Fault-Verhalten und zeitlicher Annahme ab. Deklarierte source_equivalent_valid/voltage_behind_reactance/Parameterfelder sind nur eine Modellannahme, keine unabhängige externe Kalibrierung.

Native Base: x_src,sys=x_src,native (S_base/S_native)(V_native/V_system)^2; b_src,sys=1/x_src,sys bei physikalisch korrekter Spannungstransformation. MVA und Volt einer Quelle nicht über verschiedene Anschlussseiten ohne Umrechnung vergleichen. Passive in Y bereits gestempelte feste Quellen/Shunts nicht nochmals zu diag(b) addieren. GFL p aus S_on ist nameplate, nicht S_nom/S_op/S_I.

Reviewer-Haltung: mathematisches Source-Modell bedingt korrekt; physikalische reale Quellen-/Current-Limit-Freigabe offen. Keine tatsächliche Code-Defektbehauptung und keine reale gSCR/MSCR-Äquivalenz.
