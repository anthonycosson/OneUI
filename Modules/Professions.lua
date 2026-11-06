-- =========================================================================
--  OneUI — Modules/Professions.lua
--  Métiers : les suivis de récolte éteints, la pêche, et les niveaux à l'écran.
--
--  Sur les deux clients. Les trois parties ne tiennent qu'à des API que retail
--  et *Forever* publient pareil : la liste des suivis de minicarte, la liste
--  des métiers (`GetProfessions`), un bouton sécurisé et le ciblage doux.
--
--  La pêche avait sa propre page jusqu'en 3.1 ; elle vit ici depuis 3.2, et ses
--  réglages ont suivi (palier 21 de `Core/DB.lua`).
--
--  ## Les suivis de récolte
--
--  Un herboriste a « Recherche de plantes » dans le menu de suivi de la
--  minicarte, un mineur « Recherche de minerais ». Les deux s'éteignent sans
--  rien dire — au relogin, en cochant autre chose, en changeant de personnage —
--  et rien à l'écran ne le signale. On s'en aperçoit une zone plus loin, à la
--  quantité de nœuds qu'on n'a pas vus.
--
--  **Une case, un cadre, et ce cadre n'écrit rien.** Il montre l'icône du
--  suivi qui manque — celle-là même que le menu de la minicarte affiche —, les
--  deux côte à côte quand les deux manquent, et il disparaît quand il n'y a
--  rien à dire. Une phrase aurait dit deux fois ce que l'image dit une : ce
--  qu'il y a à savoir de plus se lit au survol.
--
--  L'icône se clique et coche le suivi. C'est le geste du joueur, pas le
--  nôtre : l'addon ne coche **jamais** de lui-même — ce serait agir à sa place,
--  ce que la promesse interdit (règle 4), et un suivi éteint l'est parfois
--  exprès. On rapproche seulement la case de l'endroit qui dit qu'elle manque.
--
--  **Le joueur qui n'a pas le métier ne voit jamais son icône** : le sort
--  absent de la liste du client, il n'y a rien à lui dire.
--
--  **Le cadre ne se cache pas en combat**, et ce n'est pas un oubli. Il l'a
--  fait un temps : les deux bornes du combat le rangeaient et le rendaient. En
--  jeu, il restait affiché quand même, sans qu'aucune des deux questions
--  posées — `InCombatLockdown`, `UnitAffectingCombat` — n'explique pourquoi.
--  Retiré le 27 septembre 2026 plutôt que laissé à moitié : un code qui promet
--  quelque chose qu'il ne tient pas est pire que pas de code du tout, et ce
--  cadre est une icône dans un coin, pas une fenêtre au milieu de l'écran.
--
--  ## La pêche : une touche, deux gestes
--
--  La touche choisie **lance** la ligne : elle clique un bouton sécurisé qui
--  porte le sort de pêche — le seul chemin par lequel un addon lance un sort.
--  Pendant la canalisation, la même touche est reliée à **Interagir avec la
--  cible** (`INTERACTTARGET`) : le ciblage doux vise le bouchon, la touche le
--  ferre. La canalisation finie, elle redevient le lancer.
--
--  Les deux liaisons sont **prioritaires et posées par l'addon**
--  (`SetOverrideBinding…`), jamais enregistrées chez le client : elles
--  s'effacent en un appel quand le module s'éteint, et la touche retrouve ce
--  qu'elle faisait avant. Le client refuse de les changer en combat ; un
--  changement demandé à ce moment-là attend la sortie.
--
--  Au second appui rapproché du bouton droit dans le monde, le bouton droit est
--  relié au lancer **le temps d'un clic** : le relâchement lance la ligne, puis
--  la liaison disparaît. Pas sur une unité survolée — on y cliquerait pour lui
--  parler —, ni pendant la canalisation, où le clic droit sert à ferrer.
--
--  Le temps de pêcher, les effets sonores montent au maximum, la musique et
--  l'ambiance se taisent : on entend le bouchon plonger. Le tout est emprunté
--  au prêteur commun (`Core/CVars.lua`), qui le rend même après un `/reload` en
--  pleine prise. Il est rendu un peu après la dernière prise, pas à chacune.
--
--  ## Les niveaux
--
--  Un bloc de texte à même l'écran, une ligne par métier appris : son nom et
--  le niveau atteint sur le niveau maximal du rang, tels que la fiche de
--  métiers du client les donne. Il se relit à l'annonce d'un changement de
--  compétence, jamais avec le temps (règle 7).
--
--  Les cadres sont posés par `UI/Widgets/IconBadge.lua` et
--  `UI/Widgets/TextBlock.lua` : le module ne dessine rien.
--
--  Réversibilité (règle 6) : les cadres se cachent, les liaisons s'effacent,
--  les CVars sont rendues, le hook du monde devient inerte et les abonnements
--  tombent. Le suivi du client n'est que lu, jusqu'au clic.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets
local L    = ns.L

local MODULE = "Professions"

--- Nom sous lequel la pêche emprunte ses CVars. Celui de son ancienne page, et
--- elle le garde : le prêteur range ses emprunts sur le disque par emprunteur,
--- et un emprunt laissé par une version d'avant — un `/reload` en pleine
--- prise — doit pouvoir être rendu par celle-ci.
local LENDER = "Fishing"

-- =========================================================================
--  Ce que le client publie
-- =========================================================================

--- Les sorts de suivi, par métier.
---
--- **Deux identifiants chacun, et c'est le client qui le dit** : sa table
--- `TRACKING_SPELL_OVERRIDE_ATLAS` (`Blizzard_Minimap/Mainline/Minimap.lua`)
--- nomme « Find Herbs 1 » et « Find Herbs 2 », « Find Minerals 1 » et
--- « Find Minerals 2 » — le second rang est celui d'un métier monté. Ne
--- chercher que le premier aurait fait disparaître l'icône au moment précis où
--- le joueur progresse, ce qui est la pire façon de se taire.
---
--- Un identifiant de sort n'est pas un test de version : il ne se périme pas
--- au patch suivant, et le module échoue proprement si le client en changeait —
--- le sort ne serait pas trouvé, donc aucune icône, jamais une fausse.
local TRACKING_SPELLS = {
    herb    = { [2383] = true, [8387] = true },
    mineral = { [2580] = true, [8388] = true },
}

--- L'état du suivi d'un métier, tel que le client le publie.
---
--- **L'indice est rendu et jamais retenu.** Oublier ou apprendre un sort
--- décale la liste : un indice gardé d'une passe sur l'autre finirait par
--- désigner le suivi d'à côté, et le clic cocherait autre chose.
---@param spells table<number, boolean>
---@return boolean known   le sort est dans la liste : le joueur a le métier
---@return boolean active
---@return number|nil index
---@return any texture     la vignette du client, telle que son menu la pose
local function trackingState(spells)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes
            and C_Minimap.GetTrackingInfo) then
        return false, false
    end

    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info  = C_Minimap.GetTrackingInfo(index)
        local spell = info and info.spellID

        -- Un secret ne sert pas de clé : l'indexer lèverait, et conclure à
        -- partir de ce que le client refuse de dire serait plus faux que de
        -- passer son chemin (voir `U.IsSecret`).
        if type(spell) == "number" and not U.IsSecret(spell) and spells[spell] then
            return true, U.IsTrue(info.active), index, info.texture
        end
    end

    return false, false
end

--- Le type d'instance que le client donne à un champ de bataille.
local BATTLEGROUND_INSTANCE = "pvp"

--- Sommes-nous dans un champ de bataille ? Aucun nœud n'y compte : un suivi
--- éteint là-dedans n'est pas un oubli à signaler.
---
--- Le type arrive du client : il se teste après `U.IsSecret`, jamais avant.
---@return boolean
local function inBattleground()
    local _, instanceType = IsInInstance()
    if U.IsSecret(instanceType) then return false end
    return instanceType == BATTLEGROUND_INSTANCE
end

-- =========================================================================
--  Le cadre
-- =========================================================================

--- Un métier : la clé de sa liste de sorts, et les clés de locale de son
--- infobulle. Les deux entrées sont identiques à leurs noms près — c'est ce
--- qui garantit que les deux icônes se lisent et se cliquent pareil.
local JOBS = {
    { key = "herb",    title = "Herb tracking off" },
    { key = "mineral", title = "Mineral tracking off" },
}

local badge

---@param mod table
---@param job table
---@return boolean
local function jobShown(mod, job)
    -- L'aperçu passe devant : il sert à placer le cadre, où que l'on soit.
    if mod:Get("preview") then return true end
    if mod:Get("hideInBattleground") and inBattleground() then return false end

    local known, active = trackingState(TRACKING_SPELLS[job.key])
    return known and not active
end

--- La vignette du suivi, prise **au client** : c'est celle que son menu
--- affiche pour cette ligne-là, donc exactement celle que le joueur cherchera
--- des yeux en allant cocher. Rien n'est embarqué de notre côté, et rien ne se
--- périme.
---
--- Sans métier, pas de vignette — et pas de case : le widget saute celle qui
--- n'a pas d'image. C'est ce qui fait que l'aperçu d'un personnage sans métier
--- ne montre rien plutôt qu'un carré vide.
---@param job table
---@return any
local function jobIcon(job)
    local _, _, _, texture = trackingState(TRACKING_SPELLS[job.key])
    return texture
end

--- Coche le suivi. **Le seul geste de la page qui touche au jeu**, et il part
--- d'un clic sur l'icône.
---
--- Rien à faire quand le suivi est déjà allumé : l'icône n'est alors pas à
--- l'écran, sauf en aperçu — d'où la relecture plutôt qu'un état retenu.
---@param job table
local function enableTracking(job)
    local known, active, index = trackingState(TRACKING_SPELLS[job.key])
    if not known or active or not index then return end
    if type(C_Minimap.SetTracking) ~= "function" then return end

    C_Minimap.SetTracking(index, true)
end

---@param mod table
local function apply(mod)
    if not mod:Get("showBadge") then
        if badge then badge:Stop() end
        return
    end

    if not badge then
        local slots = {}

        for i = 1, #JOBS do
            local job = JOBS[i]
            slots[i] = {
                shown   = function() return jobShown(mod, job) end,
                icon    = function() return jobIcon(job) end,
                title   = L[job.title],
                tip     = L["Turn tracking on tip"],
                onClick = function() enableTracking(job) end,
            }
        end

        badge = W.IconBadge({
            slots    = slots,
            isLocked = function() return mod:Get("lockBadge") == true end,
            isCentered = function() return mod:Get("centerBadge") == true end,
            getPos   = function() return mod:Get("badgeX"), mod:Get("badgeY") end,
            setPos   = function(x, y)
                mod:Set("badgeX", x)
                mod:Set("badgeY", y)
            end,
            getScale = function() return mod:Get("badgeScale") end,
            setScale = function(scale) mod:Set("badgeScale", scale) end,
        })
        if not badge then return end
    end

    badge:ApplyScale()
    badge:ApplyLock()
    badge:ApplyPosition()
    badge:Refresh()
end

--- La même passe, groupée. `SPELLS_CHANGED` arrive en rafale à la connexion :
--- relire la liste des suivis à chaque fois en ferait dix pour un seul état
--- (règle 7).
local queueRefresh = U.Debounce(T.TIMING.TRACKING_SETTLE, function()
    local mod = OUI.Modules:Get(MODULE)
    if mod and mod:IsEnabled() then apply(mod) end
end)

-- =========================================================================
--  La pêche
-- =========================================================================

--- Nom global du bouton de lancer : une liaison vise un bouton par son nom
--- (règle 3, exception des noms de frames).
local BUTTON_NAME = "OneUIFishingCast"

--- Ligne de compétence de la pêche. La même depuis le premier jour, sur tous
--- les clients : c'est elle qui reconnaît le métier, et non son rang dans la
--- liste — retail le range quatrième, *Forever* parmi ses secondaires.
local FISHING_SKILL_LINE = 356

--- Ce que le son emprunte le temps de pêcher.
local SOUND_CVARS = {
    { "Sound_EnableSFX",      "1" },
    { "Sound_SFXVolume",      "1" },
    { "Sound_MusicVolume",    "0" },
    { "Sound_AmbienceVolume", "0" },
}

--- Ce que la touche emprunte au ciblage doux le temps de pêcher : viser les
--- objets en permanence, tout autour du personnage, assez loin pour un bouchon.
local TARGET_CVARS = {
    { "SoftTargetInteract",      "3" },
    { "SoftTargetInteractArc",   "2" },
    { "SoftTargetInteractRange", "30" },
}

---@type table|nil
local caster
---@type string|nil  nom du sort de pêche, tel que ce personnage l'a appris
local spellName
local channeling = false
local armed      = false
local lastRight  = 0
local pending    = false
local hooked     = false
---@type table|nil
local linger

---@return table|nil
local function module()
    return OUI.Modules:Get(MODULE)
end

-- =========================================================================
--  Le métier
-- =========================================================================

--- Le nom du sort de pêche de ce personnage, ou `nil` s'il ne pêche pas.
---
--- Le nom et non un identifiant : retail n'a qu'un sort, *Forever* un rang par
--- palier de compétence, et lancer par le nom prend le plus haut des rangs
--- appris — ce que le joueur ferait lui-même.
---@return string|nil
local function findFishing()
    if not (GetProfessions and GetProfessionInfo) then return nil end

    local indices = { GetProfessions() }
    for i = 1, select("#", GetProfessions()) do
        local index = indices[i]
        if index then
            local name, _, _, _, _, _, skillLine = GetProfessionInfo(index)
            if skillLine == FISHING_SKILL_LINE and type(name) == "string"
               and not U.IsSecret(name) then
                return name
            end
        end
    end
    return nil
end

---@param spellID any
---@return boolean
local function isFishing(spellID)
    if not spellName or type(spellID) ~= "number" or U.IsSecret(spellID) then
        return false
    end

    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    return name ~= nil and not U.IsSecret(name) and name == spellName
end

-- =========================================================================
--  Les liaisons
-- =========================================================================

local function disarm()
    if not (armed and caster) or InCombatLockdown() then return end
    SetOverrideBinding(caster, true, "BUTTON2", nil)
    armed = false
end

--- Relie la touche choisie à ce qu'elle doit faire maintenant. Tout est effacé
--- puis reposé : il n'y a jamais qu'une ou deux liaisons, et les reposer est
--- plus sûr que de suivre ce qui a changé.
---@param mod table
local function bind(mod)
    if not caster then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false

    ClearOverrideBindings(caster)
    armed = false

    if not mod:IsEnabled() then return end

    caster:SetAttribute("type", spellName and "spell" or nil)
    caster:SetAttribute("spell", spellName)

    local key = mod:Get("fishKey")
    if not (spellName and type(key) == "string" and key ~= "") then return end

    if channeling then
        SetOverrideBinding(caster, true, key, "INTERACTTARGET")
    else
        SetOverrideBindingClick(caster, true, key, BUTTON_NAME)
    end
end

-- =========================================================================
--  Le double clic droit
-- =========================================================================

---@param mod table
local function onWorldMouseDown(mod, mouseButton)
    if mouseButton ~= "RightButton" or not mod:Get("fishDoubleClick") then return end

    local now = GetTime()
    local double = now - lastRight < T.TIMING.FISH_DOUBLE_CLICK
    lastRight = double and 0 or now
    if not double then return end

    if not (caster and spellName) or channeling or armed then return end
    if InCombatLockdown() or UnitExists("mouseover") then return end

    SetOverrideBindingClick(caster, true, "BUTTON2", BUTTON_NAME)
    armed = true
    C_Timer.After(T.TIMING.FISH_ARM, disarm)
end

-- =========================================================================
--  La canalisation
-- =========================================================================

---@param mod table
local function lend(mod)
    if mod:Get("fishSound") then
        for i = 1, #SOUND_CVARS do
            OUI.CVars:Lend(LENDER, SOUND_CVARS[i][1], SOUND_CVARS[i][2])
        end
    end

    local key = mod:Get("fishKey")
    if type(key) == "string" and key ~= "" then
        for i = 1, #TARGET_CVARS do
            OUI.CVars:Lend(LENDER, TARGET_CVARS[i][1], TARGET_CVARS[i][2])
        end
    end
end

local function giveBack()
    if linger then
        linger:Cancel()
        linger = nil
    end
    OUI.CVars:ReturnAll(LENDER)
end

---@param mod table
local function onChannelStart(mod)
    channeling = true
    if linger then
        linger:Cancel()
        linger = nil
    end
    lend(mod)
    bind(mod)
end

---@param mod table
local function onChannelStop(mod)
    channeling = false
    bind(mod)

    if linger then linger:Cancel() end
    linger = C_Timer.NewTimer(T.TIMING.FISH_LINGER, function()
        linger = nil
        if not channeling then OUI.CVars:ReturnAll(LENDER) end
    end)
end


-- =========================================================================
--  Allumage et extinction de la pêche
-- =========================================================================

---@param mod table
local function enableFishing(mod)
    -- Ce qu'une session précédente tenait encore — un `/reload` en pleine
    -- prise — est rendu d'abord : on n'emprunte que pendant la pêche.
    giveBack()
    channeling = false

    caster = caster or W.SecureCaster(BUTTON_NAME)
    if caster and not hooked then
        hooked = true
        -- Le clic armé a servi : le bouton droit redevient le sien.
        caster:HookScript("PostClick", disarm)
    end

    spellName = findFishing()
    bind(mod)

    U.GuardedScript(WorldFrame, "OnMouseDown", function(_, mouseButton)
        local current = module()
        if current then onWorldMouseDown(current, mouseButton) end
    end, function()
        local current = module()
        return current ~= nil and current:IsEnabled()
    end)

    local function relearn()
        local found = findFishing()
        if found ~= spellName then
            spellName = found
            bind(mod)
        end
    end
    mod:RegisterEvent("SKILL_LINES_CHANGED", relearn)
    mod:RegisterEvent("SPELLS_CHANGED", relearn)

    mod:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, spellID)
        if unit == "player" and isFishing(spellID) then onChannelStart(mod) end
    end)
    mod:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit, _, spellID)
        if unit == "player" and channeling and isFishing(spellID) then
            onChannelStop(mod)
        end
    end)

    mod:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pending then bind(mod) end
        disarm()
    end)
end

local function disableFishing()
    giveBack()
    channeling = false
    armed = false
    if caster and not InCombatLockdown() then ClearOverrideBindings(caster) end
end

--- Une option retirée en pleine prise rend ce qu'elle tenait ; celles qui
--- restent reprennent aussitôt.
---@param mod table
local function fishingSettingChanged(mod)
    if channeling then
        OUI.CVars:ReturnAll(LENDER)
        lend(mod)
    end
    bind(mod)
end

-- =========================================================================
--  Les niveaux
-- =========================================================================

local levelsBlock

--- Les lignes du bloc, et les morceaux de chacune : refaites à chaque
--- relecture dans les mêmes tables, qui ne grandissent qu'avec le nombre de
--- métiers (règle 7).
local levelLines  = {}
local levelPieces = {}

--- Une ligne par métier appris, dans l'ordre de la fiche du client : les
--- principaux d'abord, les secondaires ensuite. Le nom en doré et le niveau,
--- puis la barre, puis le maximum du rang — trois morceaux, pour que le
--- widget règle au pixel le blanc autour de la barre (voir `W.TextBlock`).
---
--- Les retours de `GetProfessions()` ont des trous — un métier principal non
--- appris laisse sa place vide —, d'où le parcours par `select("#", …)` (voir
--- `dev/docs/API_NOTES.md`, la pêche).
---@return string[][]
local function collectLevels()
    wipe(levelLines)
    if not (GetProfessions and GetProfessionInfo) then return levelLines end

    local count   = select("#", GetProfessions())
    local indices = { GetProfessions() }

    for i = 1, count do
        local index = indices[i]
        if index then
            local name, _, rank, maxRank = GetProfessionInfo(index)
            if type(name) == "string" and not U.IsSecret(name)
               and type(rank) == "number" and not U.IsSecret(rank)
               and type(maxRank) == "number" and not U.IsSecret(maxRank) then
                local line   = #levelLines + 1
                local pieces = levelPieces[line] or {}
                levelPieces[line] = pieces

                pieces[1] = L["Profession level"]:format(
                    T.COLOR.NORMAL:WrapTextInColorCode(name), rank)
                pieces[2] = "/"
                pieces[3] = tostring(maxRank)
                levelLines[line] = pieces
            end
        end
    end

    return levelLines
end

---@param mod table
local function applyLevels(mod)
    if not mod:Get("showLevels") then
        if levelsBlock then levelsBlock:Stop() end
        return
    end

    if not levelsBlock then
        levelsBlock = W.TextBlock({
            lines      = collectLevels,
            isLocked   = function() return mod:Get("lockLevels") == true end,
            isCentered = function() return mod:Get("centerLevels") == true end,
            getPos     = function() return mod:Get("levelsX"), mod:Get("levelsY") end,
            setPos     = function(x, y)
                mod:Set("levelsX", x)
                mod:Set("levelsY", y)
            end,
            getScale   = function() return mod:Get("levelsScale") end,
            setScale   = function(scale) mod:Set("levelsScale", scale) end,
        })
        if not levelsBlock then return end
    end

    levelsBlock:ApplyScale()
    levelsBlock:ApplyLock()
    levelsBlock:ApplyPosition()
    levelsBlock:Refresh()
end

--- Une montée de compétence s'annonce en plusieurs événements à la fois : un
--- seul passage pour la rafale (règle 7).
local queueLevels = U.Debounce(T.TIMING.TRACKING_SETTLE, function()
    local mod = OUI.Modules:Get(MODULE)
    if mod and mod:IsEnabled() then applyLevels(mod) end
end)

-- =========================================================================
--  Déclaration du module
-- =========================================================================

--- Grise une ligne tant que l'interrupteur qui la commande est éteint.
---@param key string
---@return fun(): boolean
local function requires(key)
    return function()
        local mod = OUI.Modules:Get(MODULE)
        return not (mod and mod:Get(key))
    end
end

OUI:RegisterModule(MODULE, {
    title    = L["Professions"],
    category = "QoL",
    -- Juste sous le chat, qui est à 40.
    order    = 45,
    -- Les liaisons prioritaires et les attributs du bouton de lancer de la
    -- pêche ne s'écrivent pas en combat : le core diffère l'allumage et
    -- l'extinction.
    secure   = true,

    defaults = {
        showBadge = false,
        preview   = false,
        lockBadge = false,
        centerBadge = false,
        hideInBattleground = false,
        -- Position du cadre, en décalage de centre à centre, et son échelle.
        -- Réglages sans contrôle dans la page : ils se changent en faisant
        -- glisser le cadre, ou en tirant son coin.
        badgeX     = 0,
        badgeY     = 0,
        badgeScale = 1,

        fishKey         = "",
        fishDoubleClick = false,
        fishSound       = false,

        showLevels   = false,
        lockLevels   = false,
        centerLevels = false,
        -- Mêmes réglages sans contrôle que ceux du cadre de récolte.
        levelsX      = 0,
        levelsY      = 0,
        levelsScale  = 1,
    },

    options = {
        { type = "header", text = L["Gathering"] },
        {
            type    = "toggle",
            key     = "showBadge",
            text    = L["Missing tracking"],
            tooltip = L["Missing tracking tip"],
        },
        {
            type     = "toggle",
            key      = "preview",
            edit     = "preview",
            text     = L["Missing tracking preview"],
            tooltip  = L["Missing tracking preview tip"],
            disabled = requires("showBadge"),
        },
        {
            type     = "toggle",
            key      = "lockBadge",
            edit     = "lock",
            text     = L["Lock missing tracking"],
            tooltip  = L["Lock missing tracking tip"],
            disabled = requires("showBadge"),
        },
        {
            type     = "toggle",
            key      = "centerBadge",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = requires("showBadge"),
        },
        {
            type     = "toggle",
            key      = "hideInBattleground",
            text     = L["Hide missing tracking in battlegrounds"],
            tooltip  = L["Hide missing tracking in battlegrounds tip"],
            disabled = requires("showBadge"),
        },

        { type = "header", text = L["Profession levels"] },
        {
            type    = "toggle",
            key     = "showLevels",
            text    = L["Show profession levels"],
            tooltip = L["Show profession levels tip"],
        },
        {
            type     = "toggle",
            key      = "lockLevels",
            edit     = "lock",
            text     = L["Lock profession levels"],
            tooltip  = L["Lock profession levels tip"],
            disabled = requires("showLevels"),
        },
        {
            type     = "toggle",
            key      = "centerLevels",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = requires("showLevels"),
        },

        { type = "header", text = L["Fishing"] },
        {
            type    = "keybind",
            key     = "fishKey",
            text    = L["Fishing key"],
            tooltip = L["Fishing key tip"],
        },
        {
            type    = "toggle",
            key     = "fishDoubleClick",
            text    = L["Double right-click to fish"],
            tooltip = L["Double right-click to fish tip"],
        },
        {
            type    = "toggle",
            key     = "fishSound",
            text    = L["Fishing sound"],
            tooltip = L["Fishing sound tip"],
        },
    },

    OnEnable = function(self)
        apply(self)
        applyLevels(self)
        enableFishing(self)

        -- Le client annonce chaque changement de suivi : c'est l'événement qui
        -- allume et éteint les icônes.
        self:RegisterEvent("MINIMAP_UPDATE_TRACKING", queueRefresh)

        -- Le métier appris, oublié, ou simplement rendu par le serveur à la
        -- connexion : la liste des suivis change avec lui.
        self:RegisterEvent("SPELLS_CHANGED", queueRefresh)

        -- La liste n'est pas remplie avant l'entrée en jeu, et un rechargement
        -- à chaud passe par là lui aussi. C'est aussi l'entrée et la sortie
        -- d'un champ de bataille.
        self:RegisterEvent("PLAYER_ENTERING_WORLD", queueRefresh)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", queueLevels)

        -- Un point de compétence gagné, un métier appris ou oublié.
        self:RegisterEvent("SKILL_LINES_CHANGED", queueLevels)
        self:RegisterEvent("CHAT_MSG_SKILL", queueLevels)
    end,

    OnDisable = function()
        if badge then badge:Stop() end
        if levelsBlock then levelsBlock:Stop() end
        disableFishing()
    end,

    OnSettingChanged = function(self)
        apply(self)
        applyLevels(self)
        fishingSettingChanged(self)
    end,
})
