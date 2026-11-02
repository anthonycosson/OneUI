-- =========================================================================
--  OneUI — Modules/Fishing.lua
--  Pêche : une touche pour lancer et ferrer, le double clic droit, et un son
--  qu'on entend.
--
--  Sur les deux clients. Le mécanisme ne tient qu'à des API que retail et
--  *Forever* publient pareil : le métier se reconnaît à sa ligne de compétence,
--  le lancer passe par un bouton sécurisé, le ferrage par le ciblage doux du
--  client.
--
--  ## Une touche, deux gestes
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
--  ## Le double clic droit
--
--  Au second appui rapproché du bouton droit dans le monde, le bouton droit est
--  relié au lancer **le temps d'un clic** : le relâchement lance la ligne, puis
--  la liaison disparaît. Pas sur une unité survolée — on y cliquerait pour lui
--  parler —, ni pendant la canalisation, où le clic droit sert à ferrer.
--
--  ## Le son
--
--  Le temps de pêcher, les effets sonores montent au maximum, la musique et
--  l'ambiance se taisent : on entend le bouchon plonger. Le tout est emprunté
--  au prêteur commun (`Core/CVars.lua`), qui le rend même après un `/reload` en
--  pleine prise. Il est rendu un peu après la dernière prise, pas à chacune.
--
--  Réversibilité (règle 6) : liaisons effacées, CVars rendues, hook du monde
--  inerte.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets
local L    = ns.L

local MODULE = "Fishing"

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

    local key = mod:Get("castKey")
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
    if mouseButton ~= "RightButton" or not mod:Get("doubleClick") then return end

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
    if mod:Get("sound") then
        for i = 1, #SOUND_CVARS do
            OUI.CVars:Lend(MODULE, SOUND_CVARS[i][1], SOUND_CVARS[i][2])
        end
    end

    local key = mod:Get("castKey")
    if type(key) == "string" and key ~= "" then
        for i = 1, #TARGET_CVARS do
            OUI.CVars:Lend(MODULE, TARGET_CVARS[i][1], TARGET_CVARS[i][2])
        end
    end
end

local function giveBack()
    if linger then
        linger:Cancel()
        linger = nil
    end
    OUI.CVars:ReturnAll(MODULE)
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
        if not channeling then OUI.CVars:ReturnAll(MODULE) end
    end)
end

-- =========================================================================
--  Déclaration du module
-- =========================================================================

OUI:RegisterModule(MODULE, {
    title    = L["Fishing"],
    category = "QoL",
    order    = 47,
    -- Les liaisons prioritaires et les attributs du bouton de lancer ne
    -- s'écrivent pas en combat : le core diffère l'allumage et l'extinction.
    secure   = true,

    defaults = {
        castKey     = "",
        doubleClick = false,
        sound       = false,
    },

    options = {
        { type = "header", text = L["Casting"] },
        {
            type    = "keybind",
            key     = "castKey",
            text    = L["Fishing key"],
            tooltip = L["Fishing key tip"],
        },
        {
            type    = "toggle",
            key     = "doubleClick",
            text    = L["Double right-click to fish"],
            tooltip = L["Double right-click to fish tip"],
        },

        { type = "header", text = L["Sound"] },
        {
            type    = "toggle",
            key     = "sound",
            text    = L["Fishing sound"],
            tooltip = L["Fishing sound tip"],
        },
    },

    OnEnable = function(self)
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
        bind(self)

        U.GuardedScript(WorldFrame, "OnMouseDown", function(_, mouseButton)
            local mod = module()
            if mod then onWorldMouseDown(mod, mouseButton) end
        end, function()
            local mod = module()
            return mod ~= nil and mod:IsEnabled()
        end)

        local function relearn()
            local found = findFishing()
            if found ~= spellName then
                spellName = found
                bind(self)
            end
        end
        self:RegisterEvent("SKILL_LINES_CHANGED", relearn)
        self:RegisterEvent("SPELLS_CHANGED", relearn)

        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, spellID)
            if unit == "player" and isFishing(spellID) then onChannelStart(self) end
        end)
        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit, _, spellID)
            if unit == "player" and channeling and isFishing(spellID) then
                onChannelStop(self)
            end
        end)

        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            if pending then bind(self) end
            disarm()
        end)
    end,

    OnDisable = function()
        giveBack()
        channeling = false
        armed = false
        if caster and not InCombatLockdown() then ClearOverrideBindings(caster) end
    end,

    OnSettingChanged = function(self)
        -- Une option retirée en pleine prise rend ce qu'elle tenait ; celles
        -- qui restent reprennent aussitôt.
        if channeling then
            OUI.CVars:ReturnAll(MODULE)
            lend(self)
        end
        bind(self)
    end,
})
