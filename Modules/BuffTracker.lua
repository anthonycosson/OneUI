-- =========================================================================
--  OneUI — Modules/BuffTracker.lua
--  Suivi des buffs : ce qui manque, dit par des icônes, dans deux cadres.
--
--  *Forever* seulement (sa ligne du `.toc` l'écarte de retail) : les
--  consommables et les buffs de camp listés ici sont ceux de ce client.
--
--  ## Les buffs perso
--
--  Ce qu'on peut se mettre seul. Une icône par buff de classe que le
--  personnage sait lancer (marque et épines pour un druide, armure et
--  intelligence pour un mage…), et une par catégorie pour le reste : camp,
--  enchantement d'arme, nourriture, flacon, élixir. Le chaman et le voleur
--  n'ont qu'une icône de classe, celle de leur enchantement d'arme, demandé sur
--  chaque arme portée. Un buff de classe se clique et se lance sur soi.
--
--  ## Les buffs de groupe
--
--  Ce que le groupe pourrait donner et qu'on n'a pas, dans un cadre à part,
--  montré seulement en groupe. Un buff n'est attendu que si une classe qui le
--  donne est présente, connectée, et à portée de groupe : les cris et les
--  auras ne touchent que son propre groupe dans un raid. Les bénédictions et
--  les auras de paladin se comptent : autant de différentes que de paladins.
--  Un buff de talent n'est attendu qu'une fois vu sur un membre du groupe :
--  rien d'autre ne dit qu'un prêtre a Esprit divin.
--
--  Détail et sources des identifiants : `dev/docs/API_NOTES.md`.
--
--  Réversibilité (règle 6) : les cadres se cachent, les abonnements tombent.
--  Rien n'est modifié dans le jeu, les auras ne sont que lues.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets
local L    = ns.L

local MODULE = "BuffTracker"

-- =========================================================================
--  Les buffs, par famille
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

-- Chaque liste va du meilleur rang au moins bon : le premier sort connu est
-- celui que le clic lance. Les versions de groupe viennent après.
local INTELLECT    = { 10157, 10156, 1461, 1460, 1459, 23028 }
local MAGE_ARMOR   = { 22783, 22782, 6117, 10220, 10219, 7320, 7302, 7301, 7300, 168 }
local FORTITUDE    = { 10938, 10937, 2791, 1245, 1244, 1243, 21564, 21562 }
local INNER_FIRE   = { 10952, 10951, 1006, 602, 7128, 588 }
local SPIRIT       = { 27841, 14819, 14818, 14752, 27681 }
local SHADOW_PROT  = { 10958, 10957, 976, 27683 }
local WILD         = { 9885, 9884, 8907, 5234, 6756, 5232, 1126, 21850, 21849 }
local THORNS       = { 9910, 9756, 8914, 1075, 782, 467 }
local DEMON_ARMOR  = { 11735, 11734, 11733, 1086, 706, 696, 687, 403619 }
local BATTLE_SHOUT = { 25289, 11551, 11550, 11549, 6192, 5242, 6673 }
local ASPECTS      = {
    25296, 14322, 14321, 14320, 14319, 14318, 13165, 13163, 5118, 13159,
    1299447, 1299446, 1299445, 13161, 20190, 20043,
}
local TRUESHOT     = { 20906, 20905, 19506, 1299348, 1299346 }

-- Bénédictions : une par paladin et par cible, d'où le compte par famille.
local KINGS     = { 20217, 25898 }
local MIGHT     = { 25291, 19838, 19837, 19836, 19835, 19834, 19740, 25916, 25782 }
local WISDOM    = { 25290, 19854, 19853, 19852, 19850, 19742, 25918, 25894 }
local SALVATION = { 1038, 25895 }
local LIGHT     = { 19979, 19978, 19977, 25890 }
local SANCTUARY = { 20914, 20913, 20912, 20911, 25899 }
local BLESSINGS = { KINGS, MIGHT, WISDOM, SALVATION, LIGHT, SANCTUARY }

-- Auras : une par paladin, et chacune ne touche que son groupe.
local DEVOTION      = { 10293, 10292, 10291, 1032, 643, 10290, 465 }
local RETRIBUTION   = { 10301, 10300, 10299, 10298, 7294 }
local CONCENTRATION = { 19746 }
local SANCTITY      = { 20218 }
local SHADOW_AURA   = { 19896, 19895, 19876 }
local FROST_AURA    = { 19898, 19897, 19888 }
local FIRE_AURA     = { 19900, 19899, 19891 }
local AURAS = { DEVOTION, RETRIBUTION, CONCENTRATION, SANCTITY, SHADOW_AURA, FROST_AURA, FIRE_AURA }

--- Une liste qui réunit plusieurs sorts différents porte son propre libellé :
--- le nom de son premier sort ne parlerait que de lui.
---@param list table
---@param title string
---@return table
local function titled(list, title)
    list.title = title
    return list
end

--- Les buffs de classe perso : une icône par liste, attendue dès que le
--- personnage en connaît un rang. N'importe quel rang, lancé par n'importe qui,
--- la valide.
local CLASS_BUFFS = {
    MAGE    = { INTELLECT, titled(MAGE_ARMOR, "Buff tracker armor") },
    PRIEST  = { FORTITUDE, INNER_FIRE, SPIRIT, SHADOW_PROT },
    DRUID   = { WILD, THORNS },
    PALADIN = {
        titled(merge(KINGS, MIGHT, WISDOM, LIGHT, SALVATION, SANCTUARY), "Buff tracker blessing"),
        titled(merge(DEVOTION, RETRIBUTION, CONCENTRATION, SANCTITY, SHADOW_AURA, FROST_AURA, FIRE_AURA),
               "Buff tracker aura"),
    },
    WARLOCK = { DEMON_ARMOR },
    WARRIOR = { BATTLE_SHOUT },
    HUNTER  = { titled(ASPECTS, "Buff tracker aspect"), TRUESHOT },
}

--- Les classes dont le buff est **sur l'arme**, demandé sur chaque arme portée.
--- `spells` dit si le personnage sait le poser, `enchants` le reconnaît.
--- `cast` : le clic lance le sort. Le sort de poisons du voleur n'ouvre que
--- la fenêtre de fabrication, il n'a donc rien à lancer.
local CLASS_WEAPON = {
    SHAMAN = {
        cast   = true,
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
        cast   = false,
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

--- Les buffs de groupe. `class` donne le buff, `party` le limite à son propre
--- groupe dans un raid, `talent` ne l'attend qu'une fois vu dans le groupe.
--- `families` se compte : il en faut autant de différentes que de donneurs.
local GROUP_BUFFS = {
    { key = "fortitude", class = "PRIEST",  spells = FORTITUDE },
    { key = "spirit",    class = "PRIEST",  spells = SPIRIT, talent = true },
    { key = "shadow",    class = "PRIEST",  spells = SHADOW_PROT },
    { key = "intellect", class = "MAGE",    spells = INTELLECT },
    { key = "wild",      class = "DRUID",   spells = WILD },
    { key = "blessings", class = "PALADIN", families = BLESSINGS, icon = KINGS[1],
      title = "Buff tracker blessings" },
    { key = "auras",     class = "PALADIN", families = AURAS, icon = DEVOTION[1], party = true,
      title = "Buff tracker auras" },
    { key = "shout",     class = "WARRIOR", spells = BATTLE_SHOUT, party = true },
    { key = "trueshot",  class = "HUNTER",  spells = TRUESHOT, party = true, talent = true },
}

-- =========================================================================
--  Camp, armes et consommables
-- =========================================================================

--- Les auras du camp : son récapitulatif, et celle de chaque objet. Une seule
--- suffit.
local CAMP_AURAS = set({
    1229741,
    1230124, 1230098, 1230587, 1230172, 1230164, 1230653, 1229513, 1229519,
    1229718, 1230552,
})

local EARTH    = { 25362, 10441, 8163, 8162, 8076 }   -- Force de la Terre (totem)
local CRITICAL = { 24907, 24932 }                      -- Sélénien, Chef de la meute

--- Chaque objet de camp, dans l'ordre où on le cherche dans les sacs, et le
--- buff de classe qui fait le même effet. N'importe quel rang de ce buff couvre
--- l'objet, qu'il soit plus fort ou plus faible.
local CAMP_OBJECTS = {
    { items = { 279968 },         spells = FORTITUDE },   -- trousse
    { items = { 279967 },         spells = KINGS },       -- bocal
    { items = { 279956 },         spells = WISDOM },      -- puits de mana
    { items = { 279944 },         spells = EARTH },       -- meule
    { items = { 279960 },         spells = MIGHT },       -- magnétite
    { items = { 279976 },         spells = WILD },        -- luth
    { items = { 279962 },         spells = INTELLECT },   -- bougie
    { items = { 279979 },         spells = CRITICAL },    -- chaise
    { items = { 279972, 279973 }, spells = SPIRIT },      -- bannière
}

--- Les objets de camp, pour l'icône et le clic, dans l'ordre où on les cherche.
local CAMP_ITEMS = {}
for i = 1, #CAMP_OBJECTS do
    local items = CAMP_OBJECTS[i].items
    for j = 1, #items do CAMP_ITEMS[#CAMP_ITEMS + 1] = items[j] end
end

--- Huiles d'enchanteur et pierres de forgeron : seules à valider la catégorie
--- Enchantement d'arme. Ni poison, ni arme de chaman, ni huile d'alchimiste.
local WEAPON_ENCHANTS = set({
    2623, 2624, 2625, 2626, 2627, 2628, 2629, 2685,         -- huiles
    40, 13, 14, 483, 1643, 2506, 2684, 7098,                -- à aiguiser
    19, 20, 21, 484, 1703,                                  -- à lester
})

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
local OFF_HAND  = 17

--- « Bien nourri », dans toutes ses variantes de ce client.
local FOOD_AURAS = set({
    1248406, 1248420, 1248421, 1248422, 1248688, 1249519, 1249520, 1249521,
    1249523, 1225779, 1294007, 1319310,
    19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941,
    25661, 18125,
})

--- Les plats qui donnent « Bien nourri », du plus nourrissant au moins
--- nourrissant.
local FOOD_ITEMS = {
    21023, 238638, 13935, 250067, 250070, 250069, 13933, 13934, 13932, 250075,
    250068, 20452, 250066, 250071, 250072, 13810, 16971, 13927, 12212, 12218,
    13931, 250076, 18254, 250065, 17222, 6887, 18045, 287973, 4457, 250074,
    274971, 6038, 250078, 20074, 12215, 13851, 8364, 274976, 250073, 12216,
    3728, 3664, 3665, 5527, 3666, 3727, 5480, 12209, 4592, 12214, 12210, 21217,
    1017, 3729, 2685, 3726, 3220, 250080, 12213, 2684, 2683, 5479, 3662, 2687,
    268912, 268913, 724, 1082, 787, 21072, 250077, 2888, 6290, 11584, 7807,
    7808, 2682, 12224, 17198, 17197, 6888, 5472, 7806, 3663, 263512, 5095,
    2681, 5474, 263509, 6890, 2680, 5477, 250079,
}

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
--  Ce que le personnage connaît et porte
-- =========================================================================

--- Liste -> premier sort connu, ou `false`. Mémorisé jusqu'au prochain
--- changement de sorts : certaines listes comptent une vingtaine de rangs.
local knownCache = {}

---@param spells number[]
---@return number|nil
local function firstKnown(spells)
    local cached = knownCache[spells]
    if cached ~= nil then return cached or nil end

    local known = IsPlayerSpell or IsSpellKnown
    ---@type number|false
    local spell = false
    if known then
        for i = 1, #spells do
            if known(spells[i]) then
                spell = spells[i]
                break
            end
        end
    end

    knownCache[spells] = spell
    return spell or nil
end

--- L'objet de cette liste présent dans les sacs, s'il y en a un.
---@param items number[]
---@return number|nil
local function firstOwned(items)
    if not (C_Item and C_Item.GetItemCount) then return nil end

    for i = 1, #items do
        if C_Item.GetItemCount(items[i]) > 0 then return items[i] end
    end
    return nil
end

--- Le nombre d'armes portées : la main droite, et la main gauche quand elle
--- tient une arme et non un bouclier ou un objet de main gauche.
---@return number
local function equippedWeapons()
    local count = GetInventoryItemID("player", MAIN_HAND) and 1 or 0

    local off = GetInventoryItemID("player", OFF_HAND)
    if off and C_Item and C_Item.GetItemInfoInstant then
        local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
        if select(6, C_Item.GetItemInfoInstant(off)) == weaponClass then count = count + 1 end
    end
    return count
end

-- =========================================================================
--  Lecture
-- =========================================================================

--- Sorts actifs sur le joueur, de la lecture en cours (règle 7).
local active = {}

---@param spells number[]
---@return boolean
local function anyActive(spells)
    for i = 1, #spells do
        if active[spells[i]] then return true end
    end
    return false
end

--- Clé de case -> couverte. Conservé d'une lecture à l'autre : une lecture
--- que le client refuse ne doit rien changer à ce qui est affiché.
local covered = {}

--- Buff de groupe -> nombre manquant. Même règle de conservation.
local missing = {}

--- Tables de travail d'une lecture (règle 7).
local found, providers, partyProviders, seen = {}, {}, {}, {}

--- Un objet de camp des sacs est-il déjà couvert par son buff de classe ?
---@return boolean
local function campEquivalent()
    for i = 1, #CAMP_OBJECTS do
        local object = CAMP_OBJECTS[i]
        if firstOwned(object.items) and anyActive(object.spells) then return true end
    end
    return false
end

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
---@return number classCount       armes portant l'enchantement de la classe
local function readWeapons(classEnchants)
    if not (C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot) then
        return false, 0
    end

    local oilOrStone, classCount = false, 0
    for _, slot in pairs(Enum.WeaponSlot) do
        for _, enchant in pairs(C_Item.GetWeaponEnchantInfo(slot)) do
            local id = enchant.enchantID
            if U.IsSecret(id) then return nil, 0 end

            if U.IsTrue(enchant.hasEnchant) then
                if WEAPON_ENCHANTS[id] then oilOrStone = true end
                if classEnchants and classEnchants[id] then classCount = classCount + 1 end
            end
        end
    end
    return oilOrStone, classCount
end

--- Relit les buffs du joueur. Une valeur secrète interrompt la lecture sans
--- rien publier : conclure sur une liste incomplète ferait clignoter les
--- icônes.
---@return boolean read
local function scanPlayer()
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return false end

    wipe(found)
    wipe(active)
    local wellFed = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(WELL_FED)

    local index = 1
    local aura  = C_UnitAuras.GetBuffDataByIndex("player", index)
    while aura do
        local spellID, name = aura.spellId, aura.name
        if U.IsSecret(spellID) or U.IsSecret(name) then return false end

        if spellID then active[spellID] = true end
        if FOOD_AURAS[spellID] or (wellFed and name == wellFed) then found.food = true end
        if CAMP_AURAS[spellID] then found.camp = true end
        if inItems("flask", spellID, name)  then found.flask  = true end
        if inItems("elixir", spellID, name) then found.elixir = true end

        index = index + 1
        aura  = C_UnitAuras.GetBuffDataByIndex("player", index)
    end

    local class  = UnitClassBase("player")
    local weapon = CLASS_WEAPON[class]
    local oilOrStone, classCount = readWeapons(weapon and weapon.enchants)
    if oilOrStone == nil then return false end

    found.weapon = oilOrStone
    found.camp   = found.camp or campEquivalent()
    if weapon then found.classWeapon = classCount >= math.max(equippedWeapons(), 1) end

    local lists = CLASS_BUFFS[class]
    if lists then
        for i = 1, #lists do found["class" .. i] = anyActive(lists[i]) end
    end

    wipe(covered)
    for key, value in pairs(found) do covered[key] = value end
    return true
end

--- Les membres du groupe, un par un : le joueur, puis les autres. `party`
--- s'en tient à son propre groupe, ce qui dans un raid est son sous-groupe.
---@param party boolean
---@param fn fun(unit: string)
local function eachMember(party, fn)
    if IsInRaid() and not party then
        for i = 1, GetNumGroupMembers() do fn("raid" .. i) end
        return
    end

    fn("player")
    for i = 1, GetNumSubgroupMembers() do fn("party" .. i) end
end

--- Les buffs de talent vus sur ce membre du groupe.
---@param unit string
---@param talentSpells table<number, string>  sort -> clé du buff
---@return boolean read
local function scanTalents(unit, talentSpells)
    local index = 1
    local aura  = C_UnitAuras.GetBuffDataByIndex(unit, index)
    while aura do
        local spellID = aura.spellId
        if U.IsSecret(spellID) then return false end
        if talentSpells[spellID] then seen[talentSpells[spellID]] = true end

        index = index + 1
        aura  = C_UnitAuras.GetBuffDataByIndex(unit, index)
    end
    return true
end

--- Sort de talent -> clé du buff de groupe, construit une fois.
local TALENT_SPELLS = {}
for i = 1, #GROUP_BUFFS do
    local entry = GROUP_BUFFS[i]
    if entry.talent then
        for j = 1, #entry.spells do TALENT_SPELLS[entry.spells[j]] = entry.key end
    end
end

--- Relit ce que le groupe pourrait donner. Suppose `active` à jour.
local function scanGroup()
    wipe(missing)
    if not IsInGroup() then return end

    wipe(providers)
    wipe(partyProviders)
    wipe(seen)

    local unreadable = false

    -- Classes présentes et connectées, au raid et à son propre groupe.
    eachMember(false, function(unit)
        if not UnitIsConnected(unit) then return end
        local class = UnitClassBase(unit)
        if class then providers[class] = (providers[class] or 0) + 1 end
        if not scanTalents(unit, TALENT_SPELLS) then unreadable = true end
    end)

    eachMember(true, function(unit)
        if not UnitIsConnected(unit) then return end
        local class = UnitClassBase(unit)
        if class then partyProviders[class] = (partyProviders[class] or 0) + 1 end
    end)

    if unreadable then return end

    for i = 1, #GROUP_BUFFS do
        local entry = GROUP_BUFFS[i]
        local count = (entry.party and partyProviders or providers)[entry.class] or 0

        if count > 0 and entry.families then
            local have = 0
            for j = 1, #entry.families do
                if anyActive(entry.families[j]) then have = have + 1 end
            end
            local lack = math.min(count, #entry.families) - have
            if lack > 0 then missing[entry.key] = lack end
        elseif count > 0 and (not entry.talent or seen[entry.key]) and not anyActive(entry.spells) then
            missing[entry.key] = 1
        end
    end
end

-- =========================================================================
--  Les clics
-- =========================================================================

---@param spells number[]
---@return table|nil
local function castAction(spells)
    local spell = firstKnown(spells)
    return spell and { type = "spell", spell = spell, unit = "player" } or nil
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

--- Le clic sur le buff de camp : pose l'objet de camp des sacs.
---@return table|nil
local function campAction()
    local item = firstOwned(CAMP_ITEMS)
    return item and { type = "macro", macrotext = ("/use item:%d"):format(item) } or nil
end

--- Le meilleur plat des sacs que le personnage a le niveau de manger. Un plat
--- dont le client ne connaît pas encore le niveau est tenté quand même.
---@return number|nil
local function foodItem()
    if not (C_Item and C_Item.GetItemCount) then return nil end

    local level = UnitLevel("player")
    for i = 1, #FOOD_ITEMS do
        local item = FOOD_ITEMS[i]
        if C_Item.GetItemCount(item) > 0 then
            local minLevel = C_Item.GetItemInfo and select(5, C_Item.GetItemInfo(item))
            if not minLevel or minLevel <= level then return item end
        end
    end
    return nil
end

--- Le clic sur la nourriture : mange le plat choisi.
---@return table|nil
local function foodAction()
    local item = foodItem()
    return item and { type = "macro", macrotext = ("/use item:%d"):format(item) } or nil
end

-- =========================================================================
--  Les cases
-- =========================================================================

---@param spell number|nil
---@return any
local function spellIcon(spell)
    return spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)
end

---@param item number|nil
---@return any
local function itemIcon(item)
    return item and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)
end

---@param spell number
---@param fallback string
---@return string
local function spellTitle(spell, fallback)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
    return name or fallback
end

--- Les catégories perso après les buffs de classe : leur clé, le réglage qui
--- les suit, leur libellé, leur image et leur clic.
local CATEGORIES = {
    { key = "camp",   setting = "trackCamp",   title = "Buff tracker camp",
      icon = function() return itemIcon(firstOwned(CAMP_ITEMS)) or spellIcon(818) end,
      action = campAction },
    { key = "weapon", setting = "trackWeapon", title = "Buff tracker weapon",
      icon = function() return itemIcon(weaponEnchantItem() or 12404) end,
      action = weaponEnchantAction },
    { key = "food",   setting = "trackFood",   title = "Buff tracker food",
      icon = function() return itemIcon(foodItem()) or spellIcon(WELL_FED) end,
      action = foodAction },
    { key = "flask",  setting = "trackFlask",  title = "Buff tracker flask",
      icon = function() return itemIcon(13510) end },
    { key = "elixir", setting = "trackElixir", title = "Buff tracker elixir",
      icon = function() return itemIcon(13452) end },
}

--- Les cases des buffs de classe : une par liste de `CLASS_BUFFS`, ou une
--- seule pour une classe à enchantement d'arme. Une liste que le personnage
--- ne sait pas lancer ne garde pas de place.
---@param mod table
---@param slots table
local function addClassSlots(mod, slots)
    local class = UnitClassBase("player")

    local function slot(key, spells, action)
        local function expected() return firstKnown(spells) ~= nil end
        slots[#slots + 1] = {
            reserved = function() return mod:Get("trackBuff") == true and expected() end,
            shown    = function()
                if not (mod:Get("trackBuff") and expected()) then return false end
                return mod:Get("preview") == true or not covered[key]
            end,
            icon     = function() return spellIcon(firstKnown(spells) or spells[1]) end,
            title    = spells.title and L[spells.title] or spellTitle(spells[1], L["Buff tracker buff"]),
            tip      = L[action and "Buff tracker click tip" or "Buff tracker missing tip"],
            action   = action,
        }
    end

    local weapon = CLASS_WEAPON[class]
    if weapon then
        slot("classWeapon", weapon.spells,
             weapon.cast and function() return castAction(weapon.spells) end or nil)
        return
    end

    local lists = CLASS_BUFFS[class] or {}
    for i = 1, #lists do
        local spells = lists[i]
        slot("class" .. i, spells, function() return castAction(spells) end)
    end
end

---@param mod table
---@return table
local function personalSlots(mod)
    local slots = {}
    addClassSlots(mod, slots)

    for i = 1, #CATEGORIES do
        local category = CATEGORIES[i]
        slots[#slots + 1] = {
            reserved = function() return mod:Get(category.setting) == true end,
            shown    = function()
                if not mod:Get(category.setting) then return false end
                return mod:Get("preview") == true or not covered[category.key]
            end,
            icon     = category.icon,
            title    = L[category.title],
            tip      = L[category.action and "Buff tracker click tip" or "Buff tracker missing tip"],
            action   = category.action,
        }
    end
    return slots
end

---@param mod table
---@return table
local function groupSlots(mod)
    local slots = {}
    for i = 1, #GROUP_BUFFS do
        local entry = GROUP_BUFFS[i]
        local icon  = entry.icon or entry.spells[1]
        slots[i] = {
            shown = function()
                if mod:Get("previewGroup") then return true end
                return IsInGroup() and missing[entry.key] ~= nil
            end,
            icon  = function() return spellIcon(icon) end,
            count = function() return missing[entry.key] end,
            title = entry.title and L[entry.title] or spellTitle(icon, L["Buff tracker group"]),
            tip   = L[entry.families and "Buff tracker group count tip" or "Buff tracker group tip"],
        }
    end
    return slots
end

-- =========================================================================
--  Les cadres
-- =========================================================================

local badge, groupBadge

---@param mod table
local function applyPersonal(mod)
    -- Les cases cliquables sont protégées : tout attend la sortie de combat.
    if InCombatLockdown() then return end

    if not mod:Get("show") then
        if badge then badge:Stop() end
        return
    end

    if not badge then
        badge = W.IconBadge({
            slots      = personalSlots(mod),
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
            getLayout  = function() return mod:Get("iconsPerRow"), mod:Get("growth") end,
        })
        if not badge then return end
    end

    badge:ApplyScale()
    badge:ApplyLock()
    badge:ApplyPosition()
    badge:Refresh()
end

---@param mod table
local function applyGroup(mod)
    if not mod:Get("showGroup") then
        if groupBadge then groupBadge:Stop() end
        return
    end

    if not groupBadge then
        groupBadge = W.IconBadge({
            slots      = groupSlots(mod),
            isLocked   = function() return mod:Get("lockedGroup") == true end,
            isCentered = function() return mod:Get("centeredGroup") == true end,
            getPos     = function() return mod:Get("groupX"), mod:Get("groupY") end,
            setPos     = function(x, y)
                mod:Set("groupX", x)
                mod:Set("groupY", y)
            end,
            getScale   = function() return mod:Get("groupScale") end,
            setScale   = function(scale) mod:Set("groupScale", scale) end,
            getLayout  = function() return mod:Get("groupIconsPerRow"), mod:Get("groupGrowth") end,
        })
        if not groupBadge then return end
    end

    groupBadge:ApplyScale()
    groupBadge:ApplyLock()
    groupBadge:ApplyPosition()
    groupBadge:Refresh()
end

---@param mod table
local function apply(mod)
    applyPersonal(mod)
    applyGroup(mod)
end

--- Relit tout. Le groupe se relit sur les auras du joueur : une lecture du
--- joueur refusée laisse le groupe tel qu'il était.
local function scan()
    if scanPlayer() then scanGroup() end
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

--- Grise une ligne tant que l'interrupteur qui la commande est éteint.
---@param key string
---@return fun(): boolean
local function requires(key)
    return function()
        local mod = OUI.Modules:Get(MODULE)
        return not (mod and mod:Get(key))
    end
end

---@param key string
---@param text string
---@return table
local function categoryOption(key, text)
    return { type = "toggle", key = key, text = L[text], disabled = requires("show") }
end

--- Les sens d'agrandissement, pour une liste déroulante.
local GROWTH_VALUES = {}
for i = 1, #W.ICON_BADGE_GROWTH do
    local value = W.ICON_BADGE_GROWTH[i]
    GROWTH_VALUES[i] = { value = value, label = L["Growth " .. value] }
end

--- Combien d'icônes par ligne, pour un cadre.
---@param key string
---@param needs string
---@return table
local function perRowOption(key, needs)
    return {
        type     = "slider",
        key      = key,
        text     = L["Icons per row"],
        tooltip  = L["Icons per row tip"],
        min      = 0,
        max      = T.SIZE.BADGE_PER_ROW_MAX,
        step     = 1,
        disabled = requires(needs),
    }
end

--- La taille d'un cadre, en chiffres : la même que sa poignée.
---@param key string
---@param needs string
---@return table
local function scaleOption(key, needs)
    return {
        type     = "slider",
        key      = key,
        text     = L["Frame scale"],
        tooltip  = L["Frame scale tip"],
        min      = T.SIZE.BADGE_SCALE_MIN,
        max      = T.SIZE.BADGE_SCALE_MAX,
        step     = T.SIZE.FRAME_SCALE_STEP,
        decimals = 2,
        disabled = requires(needs),
    }
end

--- Dans quel sens un cadre grandit.
---@param key string
---@param needs string
---@return table
local function growthOption(key, needs)
    return {
        type     = "dropdown",
        key      = key,
        text     = L["Growth direction"],
        tooltip  = L["Growth direction tip"],
        values   = GROWTH_VALUES,
        disabled = requires(needs),
    }
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
        -- Position et échelle des cadres : réglages sans contrôle dans la
        -- page, ils se changent en les faisant glisser ou en tirant leur coin.
        x     = 0,
        y     = 0,
        scale = 1,
        -- Zéro : toutes les icônes sur une ligne. Depuis le centre : le cadre
        -- reste centré sur sa position, comme avant que le sens se choisisse.
        iconsPerRow = 0,
        growth      = "CENTER",

        showGroup     = false,
        previewGroup  = false,
        lockedGroup   = false,
        centeredGroup = false,
        -- Sous le cadre perso, pour que les deux ne se recouvrent pas.
        groupX     = 0,
        groupY     = -2 * T.SIZE.BADGE_ICON,
        groupScale = 1,
        groupIconsPerRow = 0,
        groupGrowth      = "CENTER",
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
            disabled = requires("show"),
        },
        {
            type     = "toggle",
            key      = "locked",
            edit     = "lock",
            text     = L["Buff tracker lock"],
            tooltip  = L["Buff tracker lock tip"],
            disabled = requires("show"),
        },
        {
            type     = "toggle",
            key      = "centered",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = requires("show"),
        },
        scaleOption("scale", "show"),
        perRowOption("iconsPerRow", "show"),
        growthOption("growth", "show"),

        { type = "header", text = L["Buff tracker categories"], indent = true },
        categoryOption("trackBuff",   "Buff tracker buff"),
        categoryOption("trackCamp",   "Buff tracker camp"),
        categoryOption("trackWeapon", "Buff tracker weapon"),
        categoryOption("trackFood",   "Buff tracker food"),
        categoryOption("trackFlask",  "Buff tracker flask"),
        categoryOption("trackElixir", "Buff tracker elixir"),

        { type = "header", text = L["Buff tracker group"] },
        {
            type    = "toggle",
            key     = "showGroup",
            text    = L["Buff tracker group show"],
            tooltip = L["Buff tracker group show tip"],
        },
        {
            type     = "toggle",
            key      = "previewGroup",
            edit     = "preview",
            text     = L["Buff tracker preview"],
            tooltip  = L["Buff tracker group preview tip"],
            disabled = requires("showGroup"),
        },
        {
            type     = "toggle",
            key      = "lockedGroup",
            edit     = "lock",
            text     = L["Buff tracker lock"],
            tooltip  = L["Buff tracker lock tip"],
            disabled = requires("showGroup"),
        },
        {
            type     = "toggle",
            key      = "centeredGroup",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = requires("showGroup"),
        },
        scaleOption("groupScale", "showGroup"),
        perRowOption("groupIconsPerRow", "showGroup"),
        growthOption("groupGrowth", "showGroup"),
    },

    OnEnable = function(self)
        resolveItems()
        scan()
        apply(self)

        -- Le joueur, et les membres du groupe : un buff de talent se repère
        -- sur eux.
        local function onUnit(_, unit)
            if unit == "player" or (type(unit) == "string"
               and (unit:find("^party%d+$") or unit:find("^raid%d+$"))) then
                queueRefresh()
            end
        end

        self:RegisterEvent("UNIT_AURA", onUnit)
        -- Un enchantement d'arme temporaire n'est pas une aura : c'est
        -- l'inventaire qui annonce sa pose et sa fin.
        self:RegisterEvent("UNIT_INVENTORY_CHANGED", onUnit)
        self:RegisterEvent("UNIT_CONNECTION", onUnit)
        self:RegisterEvent("GROUP_ROSTER_UPDATE", queueRefresh)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", queueRefresh)
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED", queueItems)
        -- Ce que le clic utilise dépend des sacs.
        self:RegisterEvent("BAG_UPDATE_DELAYED", queueRefresh)
        -- Rattrape ce que le combat a gelé.
        self:RegisterEvent("PLAYER_REGEN_ENABLED", queueRefresh)
        self:RegisterEvent("SPELLS_CHANGED", function()
            wipe(knownCache)
            queueRefresh()
        end)
    end,

    OnDisable = function()
        if badge then badge:Stop() end
        if groupBadge then groupBadge:Stop() end
    end,

    OnSettingChanged = function(self)
        apply(self)
    end,
})
