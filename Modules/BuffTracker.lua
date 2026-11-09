-- =========================================================================
--  OneUI — Modules/BuffTracker.lua
--  Suivi des buffs : ce qui manque, dit par une icône par catégorie.
--
--  *Forever* seulement (sa ligne du `.toc` l'écarte de retail) : les
--  consommables et les buffs de camp listés ici sont ceux de ce client.
--
--  Même présentation que le suivi de récolte des métiers : un cadre sans texte
--  (`W.IconBadge`), une icône par catégorie suivie et non couverte, et plus de
--  cadre du tout quand rien ne manque. Une catégorie est couverte dès qu'**un**
--  de ses buffs est actif : on ne choisit pas lesquels. Deux catégories
--  regardent le personnage : le buff de sa classe, et un buff de camp permis par ses
--  métiers, ou le buff de classe équivalent reçu d'un autre joueur.
--
--  ## D'où viennent les listes
--
--  Consommables : par **objet**. Le client dit lui-même quel sort pose chaque
--  objet (`C_Item.GetItemSpell`), ce qui évite de deviner des identifiants
--  d'aura, et le nom rendu couvre les auras qui ne portent pas l'identifiant
--  du sort. Détail et sources : `dev/docs/API_NOTES.md`.
--
--  Réversibilité (règle 6) : le cadre se cache, les abonnements tombent. Rien
--  n'est modifié dans le jeu, les auras ne sont que lues.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets
local L    = ns.L

local MODULE = "BuffTracker"

-- =========================================================================
--  Ce qui compte, par catégorie
-- =========================================================================

--- Fait un ensemble d'une liste d'identifiants.
---@param ids number[]
---@return table<number, boolean>
local function set(ids)
    local out = {}
    for i = 1, #ids do out[ids[i]] = true end
    return out
end

--- Réunit plusieurs listes d'identifiants en une seule.
---@return number[]
local function merge(...)
    local out = {}
    for i = 1, select("#", ...) do
        local list = select(i, ...)
        for j = 1, #list do out[#out + 1] = list[j] end
    end
    return out
end

local INTELLECT = { 10157, 10156, 1461, 1460, 1459, 23028 }
local FORTITUDE = { 10938, 10937, 2791, 1245, 1244, 1243, 21564, 21562 }
local SPIRIT    = { 27841, 14819, 14818, 14752, 27681 }
local WILD      = { 9885, 9884, 8907, 5234, 6756, 5232, 1126, 21850, 21849 }
local MIGHT     = { 25291, 19838, 19837, 19836, 19835, 19834, 19740, 25916, 25782 }
local WISDOM    = { 25290, 19854, 19853, 19852, 19850, 19742, 25918, 25894 }
local KINGS     = { 20217, 25898 }
local EARTH     = { 8076, 8162, 8163, 10441, 25362 }    -- Force de la terre
local CRITICAL  = { 24907, 24932 }                      -- Sélénien, Chef de meute

--- Le buff de sa propre classe : la catégorie du même nom. Un
--- seul de la liste suffit, et peu importe qui l'a lancé. Une classe absente
--- d'ici et de `CLASS_WEAPON` n'a rien à prouver.
local CLASS_BUFFS = {
    MAGE = merge(INTELLECT, {
        22783, 22782, 6117, 10220, 10219, 7320, 7302, 7301, 7300, 168,
    }),
    PRIEST = merge(FORTITUDE, SPIRIT, {
        10952, 10951, 1006, 602, 7128, 588, 15473,
    }),
    DRUID = merge(WILD, { 9910, 9756, 8914, 1075, 782, 467 }),
    PALADIN = merge(MIGHT, WISDOM, KINGS, {
        19979, 19978, 19977, 25890, 1038, 25895,
    }),
    WARLOCK = { 11735, 11734, 11733, 1086, 706, 696, 687, 403619 },
    WARRIOR = { 25289, 11551, 11550, 11549, 6192, 5242, 6673 },
    HUNTER = {
        25296, 14322, 14321, 14320, 14319, 14318, 13165, 13163, 5118, 13159,
        1299447, 1299446, 1299445, 13161, 20190, 20043,
        20906, 20905, 19506, 1299348, 1299346,
    },
}

--- Rang à partir duquel un métier fabrique son objet de camp.
local CAMP_OBJECT_SKILL = 20

--- Ligne de compétence du métier -> ce qui couvre son objet de camp : le buff
--- de l'objet, puis le buff de classe dont il est la variante, qu'un autre
--- joueur du groupe peut fournir. La tente, l'ingénierie et la cuisine n'y sont
--- pas : leurs objets ne donnent aucune caractéristique.
local CAMP_BY_SKILL = {
    [129] = merge({ 1230124 }, FORTITUDE),      -- Secourisme, trousse
    [356] = merge({ 1230098 }, KINGS),          -- Pêche, bocal
    [171] = merge({ 1230587 }, WISDOM),         -- Alchimie, puits de mana
    [164] = merge({ 1230172 }, EARTH),          -- Forge, meule
    [186] = merge({ 1230164 }, MIGHT),          -- Minage, magnétite
    [333] = merge({ 1230653 }, WILD),           -- Enchantement, luth
    [182] = merge({ 1229513 }, INTELLECT),      -- Herboristerie, bougie
    [393] = merge({ 1229519 }, CRITICAL),       -- Dépeçage, chaise
    [197] = merge({ 1229718 }, SPIRIT),         -- Couture, bannière
}

--- Sorts actifs de la lecture en cours (règle 7).
local active = {}

---@param spells number[]
---@return boolean
local function anyActive(spells)
    for i = 1, #spells do
        if active[spells[i]] then return true end
    end
    return false
end

--- Un buff de camp ou son équivalent est-il actif, parmi ce que nos métiers
--- permettent de poser ? Sans métier à objet de camp, rien n'est attendu.
---
--- Le rang dit que l'objet est accessible ; le client ne publie pas si son
--- patron a été appris.
---@return boolean
local function campCovered()
    if not (GetProfessions and GetProfessionInfo) then return true end

    local expected = false
    local indices  = { GetProfessions() }

    for i = 1, select("#", GetProfessions()) do
        local index = indices[i]
        if index then
            local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
            local spells = not U.IsSecret(skillLine) and CAMP_BY_SKILL[skillLine]

            if spells and type(rank) == "number" and not U.IsSecret(rank)
               and rank >= CAMP_OBJECT_SKILL then
                expected = true
                if anyActive(spells) then return true end
            end
        end
    end
    return not expected
end

--- Les classes dont le buff est **sur l'arme** : pour elles, la catégorie Buffs
--- demande cet enchantement-là, et un buff reçu d'un autre ne la valide pas.
--- `spells` dit si le personnage sait le poser, `enchants` le reconnaît.
local CLASS_WEAPON = {
    SHAMAN = {
        spells = {
            16362, 10486, 8235, 8232, 16342, 16341, 16339, 8030, 8027, 8024,
            16356, 16355, 10456, 8038, 8033, 16316, 16315, 16314, 10399, 8019,
            8018, 8017,
        },
        enchants = set({
            29, 6, 1, 503, 1663, 683, 1664, 7568,   -- Arme croque-roc
            5, 4, 3, 523, 1665, 1666, 7567,         -- Arme langue de feu
            2, 12, 524, 1667, 1668, 7566,           -- Arme de givre
            283, 284, 525, 1669, 7569,              -- Arme Furie-des-vents
        }),
    },
    ROGUE = {
        spells = { 2842 },
        enchants = set({
            323, 324, 325, 623, 624, 625,           -- Instantané
            7, 8, 626, 627, 2630,                   -- Mortel
            35, 23, 643,                            -- Distraction mentale
            703, 704, 705, 706,                     -- Douloureux
            22, 603,                                -- Affaiblissant
            7254, 7255, 7256, 7542, 7651,           -- Propres à Forever
        }),
    },
}

--- Huiles d'enchanteur et pierres de forgeron : seules à valider la catégorie
--- Enchantement d'arme. Ni poison, ni arme de chaman, ni huile d'alchimiste.
local WEAPON_ENCHANTS = set({
    2623, 2624, 2625, 2626, 2627, 2628, 2629, 2685,         -- huiles
    40, 13, 14, 483, 1643, 2506, 2684, 7098,                -- à aiguiser
    19, 20, 21, 484, 1703,                                  -- à lester
})

--- Ce personnage sait-il lancer ce qu'on attend de lui ? Mémorisé jusqu'au
--- prochain changement de sorts : la liste compte plus d'une centaine de rangs.
---@type boolean|nil
local canCast

---@param spells number[]
---@return boolean
local function canCastBuff(spells)
    if canCast ~= nil then return canCast end

    local known = IsPlayerSpell or IsSpellKnown
    -- Sans réponse du client, on suppose que oui : mieux vaut une icône de trop
    -- qu'une catégorie validée sans raison.
    if not known then return true end

    canCast = false
    for i = 1, #spells do
        if known(spells[i]) then
            canCast = true
            break
        end
    end
    return canCast
end

--- « Bien nourri », dans toutes ses variantes de ce client.
local FOOD_AURAS = set({
    1248406, 1248420, 1248421, 1248422, 1248688, 1249519, 1249520, 1249521,
    1249523, 1225779, 1294007, 1319310,
    19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941,
    25661, 18125,
})

--- L'aura qui donne son nom à toutes les autres : son nom, dans la langue du
--- client, reconnaît un plat que la liste ci-dessus n'aurait pas.
local WELL_FED = 19705

--- Les objets de chaque catégorie de consommables.
local ITEMS = {
    flask = {
        274273, 274275, 274274, 274276, 13513, 13511, 13506, 13512, 13510,
    },
    elixir = {
        250328, 250350, 250335, 250347, 250343, 250338, 250351, 250337, 250329,
        250348, 250336, 250333, 250341, 20004, 9206, 13454, 13452, 246948,
        250327, 13453, 9179, 13445, 21546, 9264, 20007, 13447, 9088, 17708,
        9187, 9155, 6373, 8951,
    },
}

--- catégorie -> { ids = sorts, names = noms, pending = objets non résolus }
local resolved = {}

--- Résout les objets dont le client ne connaissait pas encore le sort. Un
--- objet absent du cache se demande, et revient par `GET_ITEM_INFO_RECEIVED`.
local function resolveItems()
    if not (C_Item and C_Item.GetItemSpell) then return end

    for category, items in pairs(ITEMS) do
        local entry = resolved[category]
        if not entry then
            entry = { ids = {}, names = {}, pending = {} }
            for i = 1, #items do entry.pending[items[i]] = true end
            resolved[category] = entry
        end

        for item in pairs(entry.pending) do
            local name, spellID = C_Item.GetItemSpell(item)
            if name and spellID then
                entry.names[name] = true
                entry.ids[spellID] = true
                entry.pending[item] = nil
            elseif C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(item)
            end
        end
    end
end

-- =========================================================================
--  Lecture
-- =========================================================================

--- Catégorie -> couverte. Conservé d'une lecture à l'autre : une lecture que
--- le client refuse ne doit rien changer à ce qui est affiché.
local covered = {}

--- Table de travail d'une lecture (règle 7).
local found = {}

--- Une aura appartient-elle à cette catégorie de consommables ?
---@param category string
---@param spellID number
---@param name string
---@return boolean
local function inItems(category, spellID, name)
    local entry = resolved[category]
    return entry ~= nil and (entry.ids[spellID] == true or entry.names[name] == true)
end

--- Passe en revue les enchantements temporaires des armes.
---@param classEnchants table|nil  ceux du buff d'arme de la classe
---@return boolean|nil oilOrStone  `nil` si le client refuse de répondre
---@return boolean classWeapon
local function readWeapons(classEnchants)
    if not (C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot) then
        return false, false
    end

    local oilOrStone, classWeapon = false, false
    for _, slot in pairs(Enum.WeaponSlot) do
        for _, enchant in pairs(C_Item.GetWeaponEnchantInfo(slot)) do
            local id = enchant.enchantID
            if U.IsSecret(id) then return nil, false end

            if U.IsTrue(enchant.hasEnchant) then
                if WEAPON_ENCHANTS[id] then oilOrStone = true end
                if classEnchants and classEnchants[id] then classWeapon = true end
            end
        end
    end
    return oilOrStone, classWeapon
end

--- Relit les buffs du joueur. Une valeur secrète interrompt la lecture sans
--- rien publier : conclure sur une liste incomplète ferait clignoter les
--- icônes.
local function scan()
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end

    wipe(found)
    wipe(active)
    local wellFed = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(WELL_FED)

    local index = 1
    local aura  = C_UnitAuras.GetBuffDataByIndex("player", index)
    while aura do
        local spellID, name = aura.spellId, aura.name
        if U.IsSecret(spellID) or U.IsSecret(name) then return end

        if spellID then active[spellID] = true end
        if FOOD_AURAS[spellID] or (wellFed and name == wellFed) then found.food = true end
        if inItems("flask", spellID, name)  then found.flask  = true end
        if inItems("elixir", spellID, name) then found.elixir = true end

        index = index + 1
        aura  = C_UnitAuras.GetBuffDataByIndex("player", index)
    end

    local classWeapon = CLASS_WEAPON[UnitClassBase("player")]
    local oilOrStone, onWeapon = readWeapons(classWeapon and classWeapon.enchants)
    if oilOrStone == nil then return end

    found.weapon = oilOrStone

    -- Deux catégories : son propre buff de classe, et un buff de camp permis
    -- par ses métiers. Sans rien à lancer ni à poser, rien n'est attendu.
    local class   = UnitClassBase("player")
    local ownList = CLASS_BUFFS[class]
    local ownBuff = true

    if classWeapon then
        ownBuff = onWeapon or not canCastBuff(classWeapon.spells)
    elseif ownList then
        ownBuff = anyActive(ownList) or not canCastBuff(ownList)
    end

    found.buff = ownBuff
    found.camp = campCovered()

    wipe(covered)
    for category, value in pairs(found) do covered[category] = value end
end

-- =========================================================================
--  Le cadre
-- =========================================================================

--- Le buff que ce personnage lancerait : le premier sort de sa classe qu'il
--- connaît, les listes allant du meilleur rang au moins bon.
---@return number|nil
local function classSpell()
    local class  = UnitClassBase("player")
    local weapon = CLASS_WEAPON[class]
    local spells = weapon and weapon.spells or CLASS_BUFFS[class]
    local known  = IsPlayerSpell or IsSpellKnown
    if not (spells and known) then return nil end

    for i = 1, #spells do
        if known(spells[i]) then return spells[i] end
    end
    return nil
end

--- Le clic sur le buff de classe. Le voleur n'a rien à lancer : son sort de
--- poisons n'ouvre que la fenêtre de fabrication.
---@return table|nil
local function classBuffAction()
    if UnitClassBase("player") == "ROGUE" then return nil end
    local spell = classSpell()
    return spell and { type = "spell", spell = spell, unit = "player" } or nil
end

--- Huiles d'enchanteur, puis pierres de forgeron, du meilleur au moins bon.
--- Les versions bénie et consacrée, réservées aux morts-vivants, passent après.
local OILS       = { 20749, 20748, 20750, 20747, 20746, 20745, 20744, 23123 }
local SHARPENING = { 18262, 12404, 7964, 2871, 2863, 2862, 23122 }
local WEIGHT     = { 12643, 7965, 3241, 3240, 3239 }

--- Sous-classes d'arme que chaque pierre accepte. Pour les armes de pugilat,
--- les deux.
local TAKES_SHARPENING = set({ 0, 1, 6, 7, 8, 13, 15 })  -- haches, armes d'hast, épées, dagues
local TAKES_WEIGHT     = set({ 4, 5, 10, 13 })           -- masses, bâtons

local MAIN_HAND = 16

--- Le premier objet de cette liste présent dans les sacs.
---@param items number[]
---@return number|nil
local function firstOwned(items)
    for i = 1, #items do
        if C_Item.GetItemCount(items[i]) > 0 then return items[i] end
    end
    return nil
end

--- Le meilleur objet des sacs que l'arme en main accepte.
---@return number|nil
local function weaponEnchantItem()
    if not (C_Item and C_Item.GetItemCount and C_Item.GetItemInfoInstant) then return nil end

    local weapon = GetInventoryItemID("player", MAIN_HAND)
    if not weapon then return nil end

    local subclass = select(7, C_Item.GetItemInfoInstant(weapon))
    return firstOwned(OILS)
        or (TAKES_SHARPENING[subclass] and firstOwned(SHARPENING))
        or (TAKES_WEIGHT[subclass] and firstOwned(WEIGHT))
        or nil
end

--- Le clic sur l'enchantement d'arme : cet objet, appliqué sur l'arme en main.
---@return table|nil
local function weaponEnchantAction()
    local item = weaponEnchantItem()
    if not item then return nil end

    return { type = "macro", macrotext = ("/use item:%d\n/use %d"):format(item, MAIN_HAND) }
end

--- Chaque catégorie : sa clé, le réglage qui la suit, son libellé, et ce qui
--- lui donne son image — un sort ou un objet, demandé au client. `action` est
--- ce que le clic déclenche, pour celles qui en ont un.
local CATEGORIES = {
    { key = "buff",   setting = "trackBuff",   title = "Buff tracker buff",   spell = 1243,
      action = classBuffAction },
    { key = "camp",   setting = "trackCamp",   title = "Buff tracker camp",   spell = 818 },
    { key = "weapon", setting = "trackWeapon", title = "Buff tracker weapon", item  = 12404,
      action = weaponEnchantAction },
    { key = "food",   setting = "trackFood",   title = "Buff tracker food",   spell = WELL_FED },
    { key = "flask",  setting = "trackFlask",  title = "Buff tracker flask",  item  = 13510 },
    { key = "elixir", setting = "trackElixir", title = "Buff tracker elixir", item  = 13452 },
}

local badge

---@param category table
---@return number|nil
local function categoryIcon(category)
    if category.key == "buff" then
        -- C'est le buff que le clic lancera. L'icône générique ne reste que
        -- faute de mieux.
        local spell = classSpell()
        if spell and C_Spell and C_Spell.GetSpellTexture then
            return C_Spell.GetSpellTexture(spell)
        end
    end

    if category.item then
        -- L'objet que le clic utilisera ; l'image de la catégorie sans objet.
        local item = category.key == "weapon" and weaponEnchantItem() or category.item
        return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)
    end
    return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(category.spell)
end

---@param mod table
---@param category table
---@return boolean
local function categoryShown(mod, category)
    if not mod:Get(category.setting) then return false end
    return mod:Get("preview") == true or not covered[category.key]
end

---@param mod table
local function apply(mod)
    -- Les cases cliquables sont protégées : tout attend la sortie de combat.
    if InCombatLockdown() then return end

    if not mod:Get("show") then
        if badge then badge:Stop() end
        return
    end

    if not badge then
        local slots = {}
        for i = 1, #CATEGORIES do
            local category  = CATEGORIES[i]
            local clickable = category.action
                and not (category.key == "buff" and UnitClassBase("player") == "ROGUE")
            slots[i] = {
                shown = function() return categoryShown(mod, category) end,
                reserved = function() return mod:Get(category.setting) == true end,
                icon  = function() return categoryIcon(category) end,
                title = L[category.title],
                tip   = L[clickable and "Buff tracker click tip" or "Buff tracker missing tip"],
                action = category.action,
            }
        end

        badge = W.IconBadge({
            slots      = slots,
            fixedSlots = true,
            isLocked   = function() return mod:Get("locked") == true end,
            isCentered = function() return mod:Get("centered") == true end,
            getPos     = function() return mod:Get("x"), mod:Get("y") end,
            setPos     = function(x, y)
                mod:Set("x", x)
                mod:Set("y", y)
            end,
            getScale   = function() return mod:Get("scale") end,
            setScale   = function(scale) mod:Set("scale", scale) end,
        })
        if not badge then return end
    end

    badge:ApplyScale()
    badge:ApplyLock()
    badge:ApplyPosition()
    badge:Refresh()
end

--- Relecture groupée : les auras changent en rafale (règle 7).
local queueRefresh = U.Debounce(T.TIMING.TRACKING_SETTLE, function()
    local mod = OUI.Modules:Get(MODULE)
    if not (mod and mod:IsEnabled()) then return end
    scan()
    apply(mod)
end)

--- Le cache d'objets se remplit : les noms attendus arrivent, on relit.
local queueItems = U.Debounce(T.TIMING.TRACKING_SETTLE, function()
    local mod = OUI.Modules:Get(MODULE)
    if not (mod and mod:IsEnabled()) then return end
    resolveItems()
    scan()
    apply(mod)
end)

-- =========================================================================
--  Déclaration du module
-- =========================================================================

--- Grise une ligne tant que l'interrupteur principal est éteint.
---@return boolean
local function notShown()
    local mod = OUI.Modules:Get(MODULE)
    return not (mod and mod:Get("show"))
end

---@param key string
---@param text string
---@return table
local function categoryOption(key, text)
    return { type = "toggle", key = key, text = L[text], disabled = notShown }
end

OUI:RegisterModule(MODULE, {
    title    = L["Buff tracker"],
    category = "MythicRaid",
    order    = 30,
    -- Ses cases cliquables sont protégées : ni allumage ni extinction en combat.
    secure   = true,

    defaults = {
        show        = false,
        preview     = false,
        locked      = false,
        centered    = false,
        trackBuff   = false,
        trackCamp   = false,
        trackWeapon = false,
        trackFood   = false,
        trackFlask  = false,
        trackElixir = false,
        -- Position et échelle du cadre : réglages sans contrôle dans la page,
        -- ils se changent en le faisant glisser ou en tirant son coin.
        x     = 0,
        y     = 0,
        scale = 1,
    },

    options = {
        { type = "header", text = L["Buff tracker frame"] },
        {
            type    = "toggle",
            key     = "show",
            text    = L["Buff tracker show"],
            tooltip = L["Buff tracker show tip"],
        },
        {
            type     = "toggle",
            key      = "preview",
            edit     = "preview",
            text     = L["Buff tracker preview"],
            tooltip  = L["Buff tracker preview tip"],
            disabled = notShown,
        },
        {
            type     = "toggle",
            key      = "locked",
            edit     = "lock",
            text     = L["Buff tracker lock"],
            tooltip  = L["Buff tracker lock tip"],
            disabled = notShown,
        },
        {
            type     = "toggle",
            key      = "centered",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = notShown,
        },

        { type = "header", text = L["Buff tracker categories"] },
        categoryOption("trackBuff",   "Buff tracker buff"),
        categoryOption("trackCamp",   "Buff tracker camp"),
        categoryOption("trackWeapon", "Buff tracker weapon"),
        categoryOption("trackFood",   "Buff tracker food"),
        categoryOption("trackFlask",  "Buff tracker flask"),
        categoryOption("trackElixir", "Buff tracker elixir"),
    },

    OnEnable = function(self)
        resolveItems()
        scan()
        apply(self)

        local function onPlayer(_, unit)
            if unit == "player" then queueRefresh() end
        end

        self:RegisterEvent("UNIT_AURA", onPlayer)
        -- Un enchantement d'arme temporaire n'est pas une aura : c'est
        -- l'inventaire qui annonce sa pose et sa fin.
        self:RegisterEvent("UNIT_INVENTORY_CHANGED", onPlayer)
        -- Un point de métier peut débloquer un objet de camp.
        self:RegisterEvent("SKILL_LINES_CHANGED", queueRefresh)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", queueRefresh)
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED", queueItems)
        -- Ce que le clic utilise dépend des sacs.
        self:RegisterEvent("BAG_UPDATE_DELAYED", queueRefresh)
        -- Rattrape ce que le combat a gelé.
        self:RegisterEvent("PLAYER_REGEN_ENABLED", queueRefresh)
        self:RegisterEvent("SPELLS_CHANGED", function()
            canCast = nil
            queueRefresh()
        end)
    end,

    OnDisable = function()
        if badge then badge:Stop() end
    end,

    OnSettingChanged = function(self)
        apply(self)
    end,
})
