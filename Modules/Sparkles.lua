-- =========================================================================
--  OneUI — Modules/Sparkles.lua
--  Scintillements : ce qui se ramasse se voit.
--
--  *Forever* seulement (sa ligne du `.toc` l'écarte de retail, voir
--  `CLAUDE.md` §1). Le module ne dessine rien : il règle le client, qui sait
--  déjà tout faire et qu'un préréglage graphique empêche de le montrer.
--
--  ## Les objets de quête
--
--  Un objet de quête au sol scintille — sauf quand le mode contour du client
--  est actif, ce que la plupart des préréglages graphiques allument. Le client
--  sait garder l'étincelle avec les contours éteints
--  (`outlineModeShowLootEffectWhenDisabled`) : on éteint les contours, on
--  garde l'étincelle. Ces CVars sont empruntées **en tenant la main** : un
--  préréglage graphique choisi plus tard les réécrit toutes, et le prêteur
--  repasse derrière (voir `Core/CVars.lua`).
--
--  **Le retour demande un redémarrage du jeu**, et l'infobulle le dit : le
--  client ne relit le mode contour qu'au lancement. Rendre les CVars est
--  immédiat ; ce qu'on voit ne change qu'au prochain démarrage.
--
--  ## L'objet le plus proche
--
--  Le ciblage doux du client sait viser l'objet avec lequel on peut interagir
--  le plus près — une herbe, un filon, un coffre, un objet de quête — et poser
--  au-dessus l'icône de l'action. On le lui demande en permanence, tout autour
--  du personnage. La portée qu'on écrit est un plafond : le client s'arrête de
--  lui-même vers quinze mètres, et aucun addon ne voit plus loin.
--
--  Ce que ce module ne fait pas, et ne peut pas faire : poser un effet sur un
--  cadavre ou un objet du monde. Aucune API ne le permet ; on ne règle que ce
--  que le client montre déjà.
--
--  Réversibilité (règle 6) : chaque CVar est rendue au prêteur, qui remet la
--  valeur d'avant — ou celle que le joueur a choisie depuis.
-- =========================================================================

local _, ns = ...
local BUI = ns.BUI
local L    = ns.L

local MODULE = "Sparkles"

--- L'étincelle des objets de quête : contours éteints, étincelle gardée.
local QUEST_CVARS = {
    { "outlineModeShowLootEffectWhenDisabled", "1" },
    { "graphicsOutlineMode",                   "0" },
    { "OutlineEngineMode",                     "0" },
    { "raidGraphicsOutlineMode",               "0" },
    { "RAIDOutlineEngineMode",                 "0" },
}

--- L'icône sur l'objet le plus proche.
local NEAREST_CVARS = {
    { "SoftTargetInteract",            "3" },
    { "SoftTargetInteractArc",         "2" },
    { "SoftTargetInteractRange",       "60" },
    { "SoftTargetInteractOnlyInRange", "0" },
    { "SoftTargetIconInteract",        "1" },
    { "SoftTargetIconGameObject",      "1" },
    { "SoftTargetLowPriorityIcons",    "1" },
}

--- Emprunte une liste, ou la rend. Liste par liste, et non tout d'un coup :
--- rendre puis réemprunter les contours à chaque clic sur l'autre case
--- réécrirait des réglages graphiques pour rien.
---@param list table
---@param wanted boolean
---@param hold? boolean
local function sync(list, wanted, hold)
    for i = 1, #list do
        if wanted then
            BUI.CVars:Lend(MODULE, list[i][1], list[i][2], hold)
        else
            BUI.CVars:Return(MODULE, list[i][1])
        end
    end
end

---@param mod table
local function apply(mod)
    sync(QUEST_CVARS, mod:Get("questItems") and true or false, true)
    sync(NEAREST_CVARS, mod:Get("nearest") and true or false)
end

BUI:RegisterModule(MODULE, {
    title    = L["Sparkles"],
    category = "QoL",
    order    = 48,

    defaults = {
        questItems = false,
        nearest    = false,
    },

    options = {
        { type = "header", text = L["Loot"] },
        {
            type    = "toggle",
            key     = "questItems",
            text    = L["Quest item sparkles"],
            tooltip = L["Quest item sparkles tip"],
        },
        {
            type    = "toggle",
            key     = "nearest",
            text    = L["Nearest object icon"],
            tooltip = L["Nearest object icon tip"],
        },
    },

    OnEnable = function(self)
        apply(self)
    end,

    OnDisable = function()
        BUI.CVars:ReturnAll(MODULE)
    end,

    OnSettingChanged = function(self)
        apply(self)
    end,
})
