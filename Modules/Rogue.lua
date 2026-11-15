-- =========================================================================
--  OneUI — Modules/Rogue.lua
--  Voleur : crocheter sans chercher le sort dans ses barres.
--
--  La page est visible pour toutes les classes, comme toute la catégorie
--  Classes : le profil est partagé, et un réglage de voleur se règle aussi
--  depuis un autre personnage. Rien n'agit tant que le personnage ne connaît
--  pas Crochetage.
--
--  ## Les coffres du monde
--
--  Le client refuse qu'un addon lance un sort sur un objet du monde à la place
--  du joueur : Crochetage se lance, puis se pose d'un clic sur le coffre. Ce
--  que le module retire, c'est d'aller chercher le sort. Au survol d'un coffre
--  verrouillé (une ligne « Verrouillé » dans son infobulle), le clic droit est
--  relié au sort ; le joueur clique ensuite sur le coffre. La liaison tombe
--  quand l'infobulle se cache ou que le sort part, et ne se pose pas en combat.
--
--  ## Les coffrets des sacs
--
--  Un objet des sacs se vise juste après le lancement du sort, dans la même
--  macro : une icône apparaît tant qu'un coffret verrouillé est dans les sacs,
--  et un clic le crochète.
--
--  Réversibilité (règle 6) : la liaison s'efface, le cadre se cache, les hooks
--  deviennent inertes avec le module.
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

--- Nom global du bouton de lancer : une liaison vise un bouton par son nom
--- (règle 3, exception des noms de frames).
local BUTTON_NAME = "OneUIPickLockCast"

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
--- langue : la ligne est celle que le jeu écrit lui-même sous un coffre ou un
--- coffret fermé.
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
--  Les coffres du monde
-- =========================================================================

---@type table|nil
local caster
local armed = false

local function disarm()
    if not (armed and caster) or InCombatLockdown() then return end
    SetOverrideBinding(caster, true, "BUTTON2", nil)
    armed = false
end

--- Une infobulle d'objet du monde vient de s'afficher : si c'est un coffre
--- verrouillé, le clic droit lance Crochetage.
---@param tooltip table
---@param data table
local function onObjectTooltip(tooltip, data)
    if tooltip ~= GameTooltip or armed then return end

    local mod = module()
    if not (mod and mod:IsEnabled() and mod:Get("pickLockClick")) then return end
    if not caster or InCombatLockdown() or UnitExists("mouseover") then return end

    local spell = pickLockName()
    if not (spell and saysLocked(data and data.lines)) then return end

    caster:SetAttribute("type", "spell")
    caster:SetAttribute("spell", spell)
    SetOverrideBindingClick(caster, true, "BUTTON2", BUTTON_NAME)
    armed = true
end

local hooked = false

local function enableWorld()
    caster = caster or W.SecureCaster(BUTTON_NAME)
    if not caster or hooked then return end
    hooked = true

    -- Le sort est parti : le clic droit redevient le sien.
    caster:HookScript("PostClick", disarm)

    local live = function()
        local current = module()
        return current ~= nil and current:IsEnabled()
    end

    -- Le curseur a quitté le coffre.
    U.GuardedScript(GameTooltip, "OnHide", disarm, live)

    -- Pas de retrait possible chez le client : l'appel se tait de lui-même
    -- quand le module est éteint (voir `onObjectTooltip`).
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
       and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, onObjectTooltip)
    end
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
                    shown  = function()
                        return mod:Get("lockboxPreview") == true or lockbox.bag ~= nil
                    end,
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
            isLocked   = function() return mod:Get("lockboxLocked") == true end,
            isCentered = function() return mod:Get("lockboxCentered") == true end,
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
    badge:ApplyLock()
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

--- Grise une ligne tant que l'interrupteur qui la commande est éteint.
---@param key string
---@return fun(): boolean
local function requires(key)
    return function()
        local mod = module()
        return not (mod and mod:Get(key))
    end
end

OUI:RegisterModule(MODULE, {
    title    = L["Rogue"],
    category = "Classes",
    order    = 10,
    -- La liaison du clic droit et l'icône cliquable ne s'écrivent pas en
    -- combat : le core diffère l'allumage et l'extinction.
    secure   = true,

    defaults = {
        pickLockClick   = false,

        showLockbox     = false,
        lockboxPreview  = false,
        lockboxLocked   = false,
        lockboxCentered = false,
        -- Position et échelle du cadre : réglages qui se changent en le
        -- faisant glisser, en tirant son coin, ou avec la glissière Taille.
        lockboxX        = 0,
        lockboxY        = 0,
        lockboxScale    = 1,
    },

    options = {
        { type = "header", text = L["Lockpicking"] },
        { type = "alert",  text = L["Rogue only"] },
        {
            type    = "toggle",
            key     = "pickLockClick",
            text    = L["Pick lock click"],
            tooltip = L["Pick lock click tip"],
        },
        {
            type    = "toggle",
            key     = "showLockbox",
            text    = L["Lockbox show"],
            tooltip = L["Lockbox show tip"],
        },
        {
            type     = "toggle",
            key      = "lockboxPreview",
            edit     = "preview",
            text     = L["Buff tracker preview"],
            tooltip  = L["Lockbox preview tip"],
            disabled = requires("showLockbox"),
        },
        {
            type     = "toggle",
            key      = "lockboxLocked",
            edit     = "lock",
            text     = L["Buff tracker lock"],
            tooltip  = L["Buff tracker lock tip"],
            disabled = requires("showLockbox"),
        },
        {
            type     = "toggle",
            key      = "lockboxCentered",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = requires("showLockbox"),
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
            disabled = requires("showLockbox"),
        },
    },

    OnEnable = function(self)
        enableWorld()
        findLockbox()
        applyLockbox(self)

        self:RegisterEvent("BAG_UPDATE_DELAYED", queueLockbox)
        self:RegisterEvent("SPELLS_CHANGED", queueLockbox)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", queueLockbox)
        -- Rattrape ce que le combat a gelé.
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            disarm()
            queueLockbox()
        end)
    end,

    OnDisable = function()
        disarm()
        if badge then badge:Stop() end
    end,

    OnSettingChanged = function(self)
        if not self:Get("pickLockClick") then disarm() end
        applyLockbox(self)
    end,
})
