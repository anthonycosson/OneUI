-- =========================================================================
--  OneUI — Modules/Rogue.lua
--  Voleur : crocheter un coffret des sacs sans chercher le sort.
--
--  La page est visible pour toutes les classes, comme toute la catégorie
--  Classes : le profil est partagé, et un réglage de voleur se règle aussi
--  depuis un autre personnage. Rien n'agit tant que le personnage ne connaît
--  pas Crochetage.
--
--  Un objet des sacs se vise juste après le lancement du sort, dans la même
--  macro : une icône apparaît tant qu'un coffret verrouillé est dans les sacs,
--  et un clic le crochète. Les coffres du monde ont eu leur réglage ; il a été
--  retiré, le besoin n'y était pas.
--
--  Réversibilité (règle 6) : le cadre se cache, les abonnements tombent.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets
local L    = ns.L

local MODULE = "Rogue"

--- Crochetage. Un seul sort, le même sur les deux clients.
local PICK_LOCK = 1804

---@return table|nil
local function module()
    return OUI.Modules:Get(MODULE)
end

--- Le nom de Crochetage, si ce personnage le connaît.
---@return string|nil
local function pickLockName()
    local known = IsPlayerSpell or IsSpellKnown
    if not (known and known(PICK_LOCK)) then return nil end
    if not (C_Spell and C_Spell.GetSpellName) then return nil end
    return C_Spell.GetSpellName(PICK_LOCK)
end

--- Une infobulle dit-elle « Verrouillé » ? Le texte du client, dans sa
--- langue : la ligne est celle que le jeu écrit lui-même sous un coffret fermé.
---@param lines table|nil
---@return boolean
local function saysLocked(lines)
    if type(lines) ~= "table" or type(LOCKED) ~= "string" then return false end

    for i = 1, #lines do
        local text = lines[i].leftText
        if type(text) == "string" and not U.IsSecret(text) and text == LOCKED then
            return true
        end
    end
    return false
end

-- =========================================================================
--  Les coffrets des sacs
-- =========================================================================

--- Le coffret verrouillé trouvé à la dernière lecture : son sac, sa case, son
--- objet. Réemployé d'une lecture à l'autre (règle 7).
local lockbox = {}

--- Cherche un coffret verrouillé dans les sacs portés. Le même objet, une
--- fois crocheté, n'est plus verrouillé : on relit son infobulle, et non une
--- liste d'objets.
local function findLockbox()
    wipe(lockbox)
    if not pickLockName() then return end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then
        return
    end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return end

    -- Le sac 0 est le sac de dos, d'où la boucle qui commence à zéro.
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local item = C_Container.GetContainerItemID(bag, slot)
            if item then
                local data = C_TooltipInfo.GetBagItem(bag, slot)
                if data and saysLocked(data.lines) then
                    lockbox.bag, lockbox.slot, lockbox.item = bag, slot, item
                    return
                end
            end
        end
    end
end

--- Le clic sur l'icône : lance Crochetage, puis vise le coffret.
---@return table|nil
local function lockboxAction()
    local spell = pickLockName()
    if not (spell and lockbox.bag) then return nil end
    return { type = "macro", macrotext = ("/cast %s\n/use %d %d"):format(spell, lockbox.bag, lockbox.slot) }
end

local badge

---@param mod table
local function applyLockbox(mod)
    -- La case cliquable est protégée : tout attend la sortie de combat.
    if InCombatLockdown() then return end

    if not mod:Get("showLockbox") then
        if badge then badge:Stop() end
        return
    end

    if not badge then
        badge = W.IconBadge({
            slots = {
                {
                    shown  = function() return lockbox.bag ~= nil end,
                    icon   = function()
                        local item = lockbox.item
                        local icon = item and C_Item and C_Item.GetItemIconByID
                                     and C_Item.GetItemIconByID(item)
                        return icon or (C_Spell and C_Spell.GetSpellTexture
                                        and C_Spell.GetSpellTexture(PICK_LOCK))
                    end,
                    title  = L["Lockbox title"],
                    tip    = L["Lockbox tip"],
                    action = lockboxAction,
                },
            },
            getPos     = function() return mod:Get("lockboxX"), mod:Get("lockboxY") end,
            setPos     = function(x, y)
                mod:Set("lockboxX", x)
                mod:Set("lockboxY", y)
            end,
            getScale   = function() return mod:Get("lockboxScale") end,
            setScale   = function(scale) mod:Set("lockboxScale", scale) end,
        })
        if not badge then return end
    end

    badge:ApplyScale()
    badge:ApplyPosition()
    badge:Refresh()
end

--- Les sacs changent en rafale (règle 7).
local queueLockbox = U.Debounce(T.TIMING.TRACKING_SETTLE, function()
    local mod = module()
    if not (mod and mod:IsEnabled()) then return end
    findLockbox()
    applyLockbox(mod)
end)

-- =========================================================================
--  Déclaration du module
-- =========================================================================

OUI:RegisterModule(MODULE, {
    title    = L["Rogue"],
    category = "Classes",
    order    = 10,
    -- L'icône cliquable ne se montre ni ne se cache en combat : le core
    -- diffère l'allumage et l'extinction.
    secure   = true,

    defaults = {
        showLockbox  = false,
        -- Position et échelle de l'icône : elle se fait glisser, et sa taille
        -- se règle par son coin ou par la glissière.
        lockboxX     = 0,
        lockboxY     = 0,
        lockboxScale = 1,
    },

    options = {
        { type = "header", text = L["Lockpicking"] },
        { type = "alert",  text = L["Rogue only"] },
        {
            type    = "toggle",
            key     = "showLockbox",
            text    = L["Lockbox show"],
            tooltip = L["Lockbox show tip"],
        },
        {
            type     = "slider",
            key      = "lockboxScale",
            text     = L["Frame scale"],
            tooltip  = L["Frame scale tip"],
            min      = T.SIZE.BADGE_SCALE_MIN,
            max      = T.SIZE.BADGE_SCALE_MAX,
            step     = T.SIZE.FRAME_SCALE_STEP,
            decimals = 2,
            disabled = function()
                local mod = module()
                return not (mod and mod:Get("showLockbox"))
            end,
        },
    },

    OnEnable = function(self)
        findLockbox()
        applyLockbox(self)

        self:RegisterEvent("BAG_UPDATE_DELAYED", queueLockbox)
        self:RegisterEvent("SPELLS_CHANGED", queueLockbox)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", queueLockbox)
        -- Rattrape ce que le combat a gelé.
        self:RegisterEvent("PLAYER_REGEN_ENABLED", queueLockbox)
    end,

    OnDisable = function()
        if badge then badge:Stop() end
    end,

    OnSettingChanged = function(self)
        applyLockbox(self)
    end,
})
