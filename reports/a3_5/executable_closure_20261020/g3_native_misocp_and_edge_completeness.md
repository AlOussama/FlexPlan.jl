# G3: Gleichung und native Runtime getrennt

Original: `485b637cc1998a327206c5929434bd26c6f0be16`. Im exakten nativen Repro wird die originale `AP3Pipeline.solve!` ohne mathematischen Patch verwendet; ein Optimize-Hook schaltet ausschließlich die Protokollierung ein.

Pajarito-Termination: **INFEASIBLE**, Primalstatus `NO_SOLUTION`. Der frische vollständige Witness erfüllt dagegen dasselbe serialisierte Integer-Modell einschließlich ursprünglicher Bounds, Integerrestriktionen und sämtlicher Objective-Rebase-Gleichungen mit maximaler Verletzung **7.5153490016e-12**. Zusätzlich wurde der Punkt durch die tatsächliche MOI-Optimizer-Indexabbildung in Pajaritos Daten nach Bridging übertragen: lineare Gleichungen **4.26325641456e-14**, maximaler Kegelabstand **8.83513342703e-11**. Native Infeasibilität ist damit für genau diesen Fall widerlegt.

Die tatsächlichen MOI-RSOC-Vektoren wurden ausgelesen: `(qij,qji,sqrt(2)*mij)`, beide q nichtnegativ, jede ungerichtete Nichtnullkante einmal, sämtliche Knotenbudgets. Die neue analytische MOI-Suite besteht 42/42; auch singuläre/reduzible Nullzeilen und Nicht-Z-PSD sind enthalten. Fehlende/duplizierte Kante, falscher Faktor, Verlust des Offdiagonalzeichens und fehlender Residualterm sind separate Mutationen.

Die Grenze liegt im numerischen OA-/MIP-/Conic-Solverpfad. Eine allgemeine Fehlerzuweisung an eine einzelne Bibliothek oder einen bestimmten Cut ist nicht abschließend bewiesen. `b1_generated_OA_model.mof.json`, `b1_bridged_conic_relaxation.mof.json` und vollständige Logs sind erhalten. Eine Variante mit geänderter positiver Objective-Skalierung liefert OPTIMAL mit vollständigem Primalcheck; andere geringfügig abweichende OA-Toleranzen liefern ITERATION_LIMIT. Das ist Sensitivitätsnachweis, keine allgemeine Reparatur oder Solverqualifikation.

Gurobi-Test: Error 10009, Lizenzablauf 2026-10-12. MOSEK 11.0.29 liest den echten CBF-Integer-Kegel-Export (1353 Integer), endet aber mit 1001/MSK_RES_ERR_LICENSE_EXPIRED. Beide Versuche sind tatsächlich ausgeführt und protokolliert. Native Zuverlässigkeit bleibt `numerical_inconclusive`.
