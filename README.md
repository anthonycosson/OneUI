# OneUI

OneUI ne remplace pas votre interface — il répare, réglage par réglage, les
petites choses qui vous agacent dans celle de Blizzard, et ne touche à rien tant
que vous ne l'avez pas coché.

**[Télécharger sur CurseForge](https://www.curseforge.com/projects/1631877)** ·
World of Warcraft *retail* 12.0.7 et au-delà · anglais et français

## Pourquoi vous pourriez le garder

- **Rien n'est allumé par défaut.** L'installer ne change strictement rien.
  Chaque réglage est livré éteint, et la construction échoue si un seul ne l'est
  pas — c'est vérifié, pas promis.
- **Éteindre un module le rend indétectable.** Chaque cadre masqué revient,
  chaque texture remplacée est rendue, chaque variable de console écrite
  retrouve sa valeur.
- **Un seul dossier, aucune bibliothèque, aucune dépendance.** Rien à installer
  à côté, rien qui casse quand un autre addon se met à jour.
- **Il ressemble au jeu.** Couleurs, polices et bordures sont celles du client —
  la fenêtre d'options est faite pour passer pour une de Blizzard.

## Ce qu'il contient

**Interface**
Mode sombre pour les barres d'action, les cadres d'unité, les auras, la barre
d'incantation et l'infobulle · couleurs de classe, icônes de spécialisation et
agrandissement des cadres de groupe ou d'arène · plaques redimensionnables,
colorables par type de PNJ ou par menace, avec leurs propres rangées d'auras ·
une barre de ressource de classe à paliers de couleur et effet brillant · une
fiche de personnage qui affiche enfin niveau d'objet, piste d'amélioration, rang
d'enchantement et gemmes sur chaque emplacement.

**Qualité de vie**
Acceptation et rendu automatiques des quêtes, avec une touche pour suspendre ·
vente de la camelote et réparation à chaque marchand · niveau d'objet sur chaque
case de sac et de banque · historique du chat conservé, fenêtre de copie,
redimensionnement à la souris · un menu de téléportation réunissant vos pierres
de foyer et tous les portails de donjon que vous possédez · cinématiques
passées, têtes parlantes masquées · réponse automatique aux !keys · les fenêtres
du jeu déplaçables et redimensionnables.

**Mythique+ et raid**
Les paliers +2 et +3 dessinés sur le chrono du jeu, les temps de boss, les morts
· les charges de résurrection de combat et le temps de recharge de la Furie
sanguinaire en deux petits suivis · marqueurs de zone et minuteur de pull ·
journalisation qui démarre à la porte de l'instance et s'arrête en sortant.

## En jeu

- `/bui` ou `/oneui` — ouvre la fenêtre d'options
- `/bui version` — affiche la version chargée
- L'icône du compartiment d'addons, près de la minicarte, ouvre la même fenêtre

## Signaler un bug

Ouvrir une [issue](https://github.com/anthonycosson/OneUI/issues) avec :

- la version de l'addon — `/bui version` en jeu ;
- ce qui était en cours au moment du problème ;
- le texte complet de l'erreur Lua s'il y en a une — BugSack le copie en un clic.

## Développement

Le dépôt est le dossier d'addon lui-même : le jeu le lit directement, sans build.
Tout ce qui ne part pas chez le joueur vit sous `dev/`.

| Besoin | Fichier |
|---|---|
| Installer le dépôt sur un nouvel ordinateur | [dev/docs/SETUP.md](dev/docs/SETUP.md) |
| Comprendre l'architecture du code | [dev/docs/ARCHITECTURE.md](dev/docs/ARCHITECTURE.md) |
| Ajouter une option ou un widget | [dev/docs/DESIGN.md](dev/docs/DESIGN.md) |
| Comprendre pourquoi un passage étrange est écrit ainsi | [dev/docs/API_NOTES.md](dev/docs/API_NOTES.md) |
| Publier une version | [dev/docs/RELEASING.md](dev/docs/RELEASING.md) |
| Modifier la page CurseForge | [dev/docs/CURSEFORGE.md](dev/docs/CURSEFORGE.md) |
| Connaître les règles du dépôt | [CLAUDE.md](CLAUDE.md) |
| Contribuer | [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md) |

## Licence

Tous droits réservés — voir [license.txt](license.txt).

OneUI est un addon non officiel. Il n'est ni créé, ni affilié, ni soutenu
par Blizzard Entertainment, Inc.
