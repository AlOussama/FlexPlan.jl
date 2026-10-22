# Mathematischer Nachweis und Prüfumfang

## Ursprüngliches Modell

Unverändert sind M_t = B_t - alpha S_t, S_t = diag(p_t), B_t = B0 + diag(b_fix + b_src), alle ungerichteten Kanten genau einmal und die diagonalen Slackzeilen. Für jede Kante lautet die unveränderte Bedingung (u,v,w) in Qr mit u=q_ij, v=q_ji und w dem bereits emittierten Float64-Ausdruck sqrt(2)*M_ij. Eine neue sqrt(2)-Approximation wird nicht eingeführt. Der Nachweis gilt für die tatsächlich eingefrorenen binär-rationalen Koeffizienten, nicht als Gleichsetzung von Float64-sqrt(2) mit der reellen irrationalen Zahl. Die G0/G3-Theoremdomäne bleibt die eingefrorene symmetrische Z-Matrixdomäne.

## Exakte finale Backendabbildung

Für affine u(x),v(x),w(x) fügt die vorhandene MOI-Bridge neue reelle Variablen U,V,W und exakte lineare Verknüpfungen U=u(x), V=v(x), W=w(x) hinzu. Sie emittiert U>=0, V>=0 und W²-2UV<=0. Damit gilt in beiden Richtungen durch Einsetzen unmittelbar (u,v,w) in Qr genau dann, wenn eine solche Erweiterung existiert. Die Nichtnegativitätsbounds U>=0,V>=0 am nativen Backend sind redundant: Für jeden existiert bereits die identische affine Zeile 1*U>=0 bzw. 1*V>=0. Diese Identität wird vor dem Hinzufügen geprüft und pro Kegel protokolliert. Der Gurobi-Parameter NonConvex=0 verwirft unerkannte nichtkonvexe Formulierungen; er verändert die mathematische Menge nicht.

MOI speichert den diagonalen quadratischen Term als 1/2*q*W²: deshalb wird q=2 als W² und der Kreuzterm -2 als -2UV geprüft. Der separate Python-Prüfer verwendet diese Konvention ausdrücklich. Keine gerundete 1/sqrt(2)-Rotation wird im finalen Input benutzt.

Eine Intervallbedingung l<=f(x)<=u wird durch f(x)=z, z in [l,u] dargestellt; alternativ durch eine äquivalente verschobene Slackkoordinate. Das Existenzquantorargument liefert exakt dieselbe Projektion. Die tatsächlich verwendeten Intervallweiten müssen in Float64 exakt u-l darstellen. Der Nachweis zählt Intervalle und Links mit Multimengen, erhält Integerdomänen und lehnt zusätzliche nicht bewiesene Zeilen ab.

Die bereits vorhandenen Objective-Inkremente z=x-l mit z>=0 werden nur verwendet, wenn die ursprüngliche Grenze x>=l vorhanden ist. Jeder ursprüngliche zulässige Punkt hat die eindeutige Erweiterung z=x-l, jeder erweiterte Punkt projiziert auf denselben ursprünglichen Punkt. Originalvariablen bleiben unverändert, insbesondere wird keine Ganzzahligkeitsdomäne relaxiert oder fixiert. Die algebraische Zielfunktion c*x = c*z+c*l ist über exakter Arithmetik identisch; tatsächlich erfolgte Float64-Addition/Division wird zusätzlich getrennt geprüft.

## Objective und tatsächliches delta(x)

Sei C_emitted(x) die ursprüngliche affine Kostenfunktion, F_s(x,z) die tatsächlich emittierte rebased/dividierte Float64-Funktion bei gewünschtem Divisor s>0. Die neue Funktion lautet F_backend = r*F_s mit r=2^k>0. Sämtliche Koeffizienten und die Konstante werden mit r multipliziert; für jeden tatsächlichen Float64-Term wird Fraction(new)==r*Fraction(old) geprüft. Nullterme gehen nicht verloren. Endlichkeit und Obergrenze 2^40 werden geprüft; der kleinste nichtnull Objective-Term muss mindestens 2^-8 sein. Dadurch bleibt die Optimierungsordnung von F_s exakt erhalten.

Nach Elimination aller Graphvariablen wird für jeden Lauf die tatsächliche Identität

    (s/r)*F_backend(x,z(x)) = C_emitted(x) + delta(x)

mit exakten binär-rationalen Koeffizienten rekonstruiert. `actual_objective_coordinate_delta` enthält jeden nichtnull Term, die Konstante und die Auswertung am exakt zulässigen Zeugen. Die alte Rebase-/Divisionsrundung wird nicht als Null gesetzt. Die neue Multiplikation erzeugt nach Prüfung keinen weiteren Rundungsfehler. Eine globale Schranke für delta(x) wird nicht behauptet; deshalb ist (s/r)*bound_backend lediglich eine nominale numerische Originalkoordinate, kein rigoroser Währungsbound.

Die erneute Auswertung der Originalkosten für jede ausgegebene Lösung benutzt C_emitted selbst. Beim Vergleich gegen exakte Zeugen werden Bounds und Zeugenziele unmittelbar in derselben Backendkoordinate verglichen, ohne gerundete Rückkonversion. Ein positiver exakter Überschuss verwirft die Bound-Aussage unabhängig von einer Gap-Toleranz. In den 37 finalen G3-Läufen tritt keiner auf.

## Startpunkt und Status

Die temporäre Standardrotation ist eine numerische Heuristik ohne Modellgleichheitsbehauptung. Es wird ausschließlich ein endlicher, am Originalmodell numerisch geprüfter primaler Start an den finalen Optimierer übergeben. Ein Start ist keine Constraint und schränkt daher die zulässige Menge nicht ein. Der finale Solver darf den Start verbessern oder verwerfen; der tatsächliche finale Modellinhalt wird vollständig exportiert. Keine Bound- oder Dualaussage aus dem heuristischen Lauf wird verwendet.

Der Abschluss `OPTIMAL` bleibt ein Rohstatus des endlichen numerischen Solves. Originalmodell, Linear-/Integer-/Kegelresiduen und Backend werden separat geprüft. Ungeprüfte oder verletzte Punkte sowie Guardablehnungen erhalten keine mathematische Infeasibility-/Globalitätsfreigabe. Der Herstellerbaum bleibt unzertifiziert.

## Kegelschnitte, endliche Filter und negative Kontrollen

Qr ist in der verwendeten Konvention selbstdual. Für einen exakt geprüften Dualvektor y mit y1,y2>=0 und 2*y1*y2>=sum(y_tail²) ist <y,z>>=0 für jedes z in Qr global gültig. Jede positive exakte Zeilenskalierung erhält Richtung und Menge; RHS und Konstante müssen vollständig mitskaliert werden. Der separate Test benutzt y=(1,1,-1), prüft Dualmitgliedschaft exakt und weist falsches Vorzeichen, fehlenden Term, einen dual unzulässigen Vektor und inkonsistente positive RHS am Kegelursprung zurück; eine vollständige Zweierpotenzskalierung wird exakt geprüft. Dies zertifiziert diesen Testschnitt, nicht beliebige interne Solvercuts.

14 echte HiGHS-Regressionen erhalten Default-Falsch-Infeasibilität, akzeptierten 1e-12-Fix, exakte 2^33-Skalierung und die adversariale Restgrenze unter 1e-12. Tatsächlich exportierte HiGHS-Zeilen sind archiviert. Der neue Gurobi-Pfad verwendet keine Pajarito-OA-Cuts; winzige ursprüngliche Constraint-Terme unter seiner deklarierten 1e-9-Schutzschranke werden vor der Optimierung abgelehnt. Die aktuelle Matrix durchläuft keine solche Ablehnung. Das ist eine endliche geprüfte Eingabedomäne, kein Beweis über sämtliche internen Presolve-/Cutoperationen.

Vier gezielte Manipulationen am tatsächlichen nativen Backend — falsches Vorzeichen des Kreuzterms, fehlender Quadratterm, verschobene Verknüpfungs-RHS und veränderte Intervallgrenze — werden sämtlich vom separaten Identitätsprüfer verworfen. Außerdem wird jeder der 46 Originalpunkte um 0.5 in einer Integerkoordinate verfälscht und verworfen. Diese Kontrollen verhindern einen bloßen Immer-PASS-Prüfpfad.

## Numerischer und exakter Befund

Die neuen Solverpunkte besitzen geringe nichtnull Gleichungsresiduen und gelten innerhalb 1e-7 als numerisch zulässig. Kein solcher Punkt wird zu einem exakten Zeugen erklärt. Historische Original-/normalisierte Zeugen werden dagegen mit Fraction und für G0 mit exakten Hauptminoren geprüft. Die erhaltenen neun A3.6-Intervalle sind separate exakte Aussagen über ihre ursprünglichen Modelle; native numerische Bounds stärken diese Aussagen nicht.
