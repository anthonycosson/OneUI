# OneUI sur *World of Warcraft: Forever*

*World of Warcraft: Forever* — le « Classic+ » annoncé le 12 septembre 2026,
en bêta du 17 septembre à sa sortie fin octobre — est un **client séparé**
(`_forever_`, produit `wowf`), plafonné au niveau 60.

Cette note dit comment l'addon sert les deux clients, et où chercher une
réponse sur celui-ci.

---

## Ce qu'est le client, vu du code

La première version de cette note le supposait bâti sur une base vanilla, avec
une API à dix ans de la nôtre. C'est faux, et la lecture du client l'a montré
(bêta 1.60.1.69913, 19 septembre 2026) :

- **C'est l'interface de retail.** Mode Édition, `CooldownViewer`,
  `PersonalResourceDisplay`, compartiment d'addons, valeurs secrètes : tout y
  est. Quelques cadres seulement reçoivent un habillage propre — joueur, cible,
  points de combo — rangé dans des dossiers `Camelot/`.
- **L'API C documentée est la même** à treize fonctions près, dont aucune n'est
  appelée par l'addon.
- **`## Interface: 16001`.**
- **Le nom de jeu, dans les directives de `.toc`, est `camelot`.** Blizzard
  s'en sert partout : `standard` désigne retail seul, `camelot` Forever, et
  `mainline` les deux — d'où ses lignes
  `[AllowLoadGameType mainline] [ExcludeLoadGameType camelot]`.

Ce qui manque est le **contenu** vanilla, pas l'API : pas de Mythique+
(`Blizzard_ChallengesUI` est `standard, mists`), pas de ressources de classe
modernes (charges arcaniques, puissance sacrée, chi…).

## Un seul addon, un seul `.toc`

Pas de second dépôt, pas de second projet CurseForge, et finalement pas de
second `.toc` non plus.

```
## Interface: 120007, 120100, 16001
...
Modules\Keystones.lua [AllowLoadGameType standard]
```

Un module qui n'a pas de sens sur Forever porte `[AllowLoadGameType standard]`
sur sa ligne : le client de Forever ne le charge pas, il n'apparaît pas dans le
menu, ses réglages dorment dans `OneUIDB` sans rien gêner. C'est le
mécanisme de Blizzard lui-même, et celui d'Auctionator.

Écartés aujourd'hui : `ClassResource`, `RaidCooldowns`, `NameplatesPage`,
`Nameplates`, `AuctionHouse`, `Keystones`, `GroupFinder`, `Teleports`,
`MythicTimer`, `Emotes`. Les autres modules chargent sur les deux clients, **tels
quels** ; leurs options ont été triées une à une, et ce que Forever n'a pas
est retiré par `Core/Forever.lua` (ci-dessous).

L'inverse existe aussi : `Professions` et `Sparkles` ne chargent que sur
Forever, `[AllowLoadGameType camelot] [ExcludeLoadGameType standard]`. **Les
deux directives sont nécessaires** : le client retail ne connaît pas `camelot`
et charge une ligne qui n'a que la première — constaté en jeu le
19 septembre 2026, où un module de Forever apparaissait sur retail et
`Core/Forever.lua` y retirait des options. `standard`, lui, retail le connaît.

La règle qui va avec est dans `CLAUDE.md` §1.

### Une option, pas un module

Même principe, un cran plus fin : `Core/Forever.lua` est chargé par Forever
seul (`[AllowLoadGameType camelot] [ExcludeLoadGameType standard]`) et publie `ns.WITHDRAWN`, la liste des
options que ce client n'a pas. `RegisterModule` les sort de la page et de la
recherche ; `self:Get` rend leur défaut quoi que la base contienne. Le module
ne sait rien, et la valeur en base reste intacte pour retail.

Le même fichier publie `ns.PREVIEW` : un module qui existe sur Forever mais
n'y est pas encore vérifié s'affiche grisé, comme un module `preview`.

## Où chercher une réponse

Dans cet ordre :

1. **Le code du client.** Le miroir `Gethe/wow-ui-source` a une branche
   `forever`, au build près. Ce sont les fichiers que Blizzard livre
   dans le client, extraits sans retouche, y compris
   `Blizzard_APIDocumentationGenerated` — la documentation que `/api` affiche
   en jeu. Les `.toc` de Blizzard y disent quel fichier charge sur `camelot`.
2. **Le jeu.** La sonde ci-dessous, ou `/api` et `/fstack` en jeu.
3. warcraft.wiki.gg, en dernier : communautaire, et souvent en retard sur
   Forever.

Un nom de cadre ne se trouve pas toujours par recherche de texte : Blizzard
écrit `$parentToT`, pas `TargetFrameToT`. Pour un cadre, la sonde a raison
contre le grep.

## Publication

Une seule release sert les deux clients : le packager envoie le zip à
CurseForge avec les versions de jeu des deux, `1.60.1` comprise. Comment on y
est arrivé : `dev/docs/API_NOTES.md`, « CurseForge ne connaissait pas la
version de jeu de Forever ».

---

## La sonde : ce qui remplace les suppositions

`dev/probe/OneUI_Probe/` est un addon autonome qui pose au client toutes
les demandes du dépôt — fonctions, globales, cadres nommés, événements, CVars,
templates, atlas — et rend un score **par fichier** : `Modules/Quest.lua — 100 %`
veut dire que ce module est portable tel quel.

La liste n'est pas écrite à la main : `dev/scripts/make-probe.sh` l'extrait du
dépôt. La relancer après chaque modification du code.

### Le parcours, dans cet ordre

```bash
# 1. Engendrer la liste depuis le dépôt
bash dev/scripts/make-probe.sh
```

```powershell
# 2. Poser sur RETAIL — le client de référence, celui qui tient tout
powershell -File dev/scripts/install-probe.ps1 -Client "C:\Program Files (x86)\World of Warcraft\_retail_"
# se connecter, /reload
powershell -File dev/scripts/install-probe.ps1 -Client "C:\Program Files (x86)\World of Warcraft\_retail_" -Collecter
```

```bash
# 3. Étalonner : ce qui manque sur retail ne renseigne pas sur Forever
bash dev/scripts/make-probe.sh --calibrer "<chemin rendu à l'étape 2>"
```

```powershell
# 4. Poser sur Forever, et lire le verdict
powershell -File dev/scripts/install-probe.ps1 -Client "C:\Program Files (x86)\World of Warcraft\_forever_" -Interface 16001
```

En jeu : le résumé s'affiche à la connexion, `/ouiprobe` le redonne,
`/ouiprobe tout` déplie tout, `/ouiprobe quest` liste ce qui manque à un
fichier. Le fichier de WTF reste la sortie de référence.

### Pourquoi l'étalonnage n'est pas facultatif

Les demandes les plus fragiles de l'addon sont des **cadres nommés par une
chaîne** — `local VIEWER = "BuffIconCooldownViewer"`, puis `_G[VIEWER]`.
`luacheck` ne les voit pas : ce ne sont pas des identifiants. Le générateur les
repère à la forme de leur nom, ce qui ramène forcément des noms de méthodes et
de scripts (`SetPoint`, `OnUpdate`) qui ne sont pas des globales.

Confronter la liste à retail les élimine tous d'un coup, sans liste écrite à la
main : ce que retail ne tient pas est soit un faux positif, soit du code déjà
mort. Les noms écartés sont consignés dans `dev/probe/absent-du-retail.txt`,
pour que l'exclusion reste relisible.

Non étalonnée, la sonde le dit en toutes lettres et ses scores sont trop bas.

## Environnement de développement

Une seconde jonction, sur le modèle de celle de retail :

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\OneUI
  -> %USERPROFILE%\Documents\Claude\OneUI
```

Le même dépôt se teste donc sur les deux clients, par `/reload`.
