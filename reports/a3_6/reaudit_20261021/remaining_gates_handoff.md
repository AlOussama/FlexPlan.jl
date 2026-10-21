# Verbleibende Gates nach A3.6-REAUDIT

Unabhängig abgenommen: Produktionsoption `small_matrix_value=1e-12` am
Fix `910d44122a37d9ed2cca06940740b46706c73d40` für die konkret nachgewiesene lokale
Filterursache. Neun exakte Kostenintervalle der Evidenz
`1147873bf553667aec5cd7eb0e9c6f7e471b370c` sind auf der erklärten normalisierten
binären rationalen Domain und in der deklarierten Raw-Kostenkoordinate gültig.
Der Reaudit hat keinen Produktionscode geändert.

Noch offen:

1. **B1:** `reference_24snap` endet mit korrigierter nativer Defaultfactory und
   mit doppeltem BASE-LP-Divisor weiterhin bei `ITERATION_LIMIT`. Unterhalb der
   endlichen 1e-12-Filterschwelle ist ein weiterer exakt zulässiger technischer
   Gegenfall nachgewiesen. Globale Cut-Gültigkeit und vollständige Node-/Dual-
   Zertifikate fehlen. Eine neue fachlich spezifizierte und separat geprüfte
   Cut-Normalisierung/Skalierung oder tatsächlich verfügbare native
   MISOCP-Alternative ist erforderlich. Kein Aufweichen der Feasibility-
   Toleranz, keine Statusumschreibung.
2. **OPT:** Insbesondere connectivity_3snap, event_price_3snap und
   reference_24snap benötigen wesentlich stärkere nachweisbar globale
   Integer-LBs. Vollständig prüfbare B&B-Bäume/Nodebounds, äquivalente exakte
   Zertifikate oder vollständige fallbezogene Enumeration sind mögliche
   zu spezifizierende Folgeaufträge. Kein Transfer der alten 81-Zuweisungen-
   Enumeration, keine globale LB aus Fixed-Integer-SOCP-Optima. Der Owner muss
   das erforderliche Präzisionskriterium vorgeben; auch schmale Intervalle sind
   keine exakte Optimalitätsgleichheit.
3. **Wissenschaftsowner:** ausschließlich Amendment-Blob
   `fba4802ecabade61a752833a71106a5bda4ce78f` ratifizieren oder zurückweisen.
   Dieser technische Reaudit erteilt keine Ratifizierung.
4. **Datenowner:** Quellen-/Passivinventare, Source-Accounting, Erdungsbezug,
   Preis-/Kostenjahr, Storage-P/E-Kostenbasis und zeitliche Repräsentativität
   realer Daten qualifizieren.

Verbindlicher fortbestehender Zustand:
`native_G3_MISOCP=numerical_inconclusive`, `B1_repaired=false`,
`integer_bounds_proved=true` nur im genannten Intervallgeltungsbereich,
`integer_globality=case_specific_partial`, `integer_optimality_proved=false`,
`independent_A3_5_accepted=false`, `A3_closed=false`, `AP4_ready=false`,
`empirical_study_ready=false`.

Für eine Fortsetzung zuerst den unabhängigen Bericht, die neuen Gates,
die exakten Intervalle und die Rohstatus lesen. Änderungen an Solverintegration
oder Modell erst nach bestandenem Specification Gate auf eigener kontrollierter
Branch ausführen und unabhängig nachprüfen lassen. Originale und beide
Evidenzveröffentlichungen erhalten; keine PR oder Merge ohne neuen Auftrag.
