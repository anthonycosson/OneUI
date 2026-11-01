## 2.0.13 — 2026-11-02

### Ajouté
- **Pêche**, nouvelle page (Qualité de vie), sur les deux clients : une
  touche qui lance la ligne puis ferre le bouchon, le double clic droit pour
  lancer, et un son qui laisse entendre le bouchon plonger.
- **Scintillements**, nouvelle page (Qualité de vie, *Forever*) : l'étincelle
  des objets de quête gardée malgré les préréglages graphiques, et l'icône du
  jeu sur l'herbe, le filon ou le coffre le plus proche.

### Interne
- Un prêteur de CVars commun (`Core/CVars.lua`) : deux modules peuvent
  emprunter le même réglage du client, et ce qui est emprunté est rendu même
  après un `/reload`.
- Un contrôle « touche » pour les pages d'options (`UI/Widgets/KeyBind.lua`).
- Ménage : code mort retiré (`W.BoundRow`, `DB:LoadedEmpty`, `U.Count`,
  trois entrées du thème, un texte), et l'analyse locale ne signale plus rien.

### Retiré
- **Suivi des buffs** et **Liste BIS** (*Forever*) : deux pages restées en
  chantier, retirées plutôt que laissées grisées. La commande `/bui bis`
  part avec elles.

