-- =========================================================================
--  OneUI — Modules/Windows.lua
--  Déplacer et redimensionner les fenêtres du client, et s'en souvenir.
--
--  Ce fichier ne déplace rien : il déclare des réglages et les rend lisibles au
--  moteur, `UI/Move.lua`. Le moteur ne connaît pas la base de données, le module
--  ne connaît pas les cadres du client, et l'un ne parle à l'autre que par
--  l'*hôte* construit ci-dessous. C'est la même séparation que le mode sombre :
--  `UI/Shade.lua` sait teinter, `Modules/General.lua` sait ce qu'il faut teindre.
--
--  `secure = true` : le moteur repositionne des cadres **protégés** (le cadre de
--  recherche de groupe en est un). Il le fait par l'environnement restreint,
--  jamais par un appel direct — mais la règle 6 demande de le déclarer dès qu'on
--  y touche, et le core diffère alors l'activation à la sortie de combat.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local W    = OUI.Widgets
local L    = ns.L

local MODULE = "Windows"

--- Le nom sous lequel le moteur range la fenêtre de jet (voir `UI/Move.lua`).
local LOOT_FRAME = "LootRoll"

--- Grise une ligne tant que l'interrupteur qui la commande est éteint.
---@param key string
---@return fun(): boolean
local function requires(key)
    return function()
        local mod = OUI.Modules:Get(MODULE)
        return not (mod and mod:Get(key))
    end
end

-- =========================================================================
--  Réglages enregistrés par fenêtre
-- =========================================================================
-- Deux tables associatives, indexées par le nom global du cadre :
--
--     positions = { CharacterFrame = { x = -180, y = 40 } }
--     scales    = { CharacterFrame = 1.15 }
--
-- Elles sont **mutées en place** plutôt que réécrites par `self:Set`. Ce n'est
-- pas un contournement de la règle 4, qui interdit d'aller lire `OneUIDB` en
-- direct : la table vient bien de `self:Get`, donc du profil actif, avec la
-- fusion des défauts et le nettoyage à la déconnexion que cela implique.
--
-- Ce qu'on évite en n'appelant pas `Set` : reconstruire une table de soixante
-- entrées à chaque cran de molette, et surtout émettre un message de changement
-- de réglage à chaque image d'un glisser. Aucun widget n'affiche ces valeurs —
-- il n'y a donc personne à prévenir.

---@param mod table
---@return table
local function positions(mod)
    return mod:Get("positions") or {}
end

---@param mod table
---@return table
local function scales(mod)
    return mod:Get("scales") or {}
end

--- Construit l'hôte que le moteur interroge.
---@param mod table
---@return OUI.MoveHost
local function makeHost(mod)
    return {
        CanMove  = function() return mod:Get("movable") == true end,
        CanScale = function() return mod:Get("scalable") == true end,
        Modifier = function() return mod:Get("moveModifier") or "SHIFT" end,

        GetPosition = function(name)
            return positions(mod)[name]
        end,

        SetPosition = function(name, x, y)
            local stored = positions(mod)
            if x == nil or y == nil then
                stored[name] = nil
                return
            end

            -- La table d'une fenêtre déjà déplacée est réutilisée : un glisser
            -- en produirait une par image (règle 7).
            local pos = stored[name]
            if pos then
                pos.x, pos.y = x, y
            else
                stored[name] = { x = x, y = y }
            end
        end,

        GetScale = function(name)
            return scales(mod)[name]
        end,

        SetScale = function(name, scale)
            scales(mod)[name] = scale
        end,

        -- La fenêtre de jet de butin. Trois réponses et rien de plus : le
        -- moteur sait la poser, il n'a pas à savoir sous quelles clés le
        -- joueur l'a demandée.
        PlaceLoot   = function() return mod:Get("lootMove") == true end,
        LootLocked  = function() return mod:Get("lootLocked") == true end,
        LootCentered = function() return mod:Get("lootCentered") == true end,
        LootPreview = function() return mod:Get("lootPreview") == true end,
    }
end

-- =========================================================================
--  Réinitialisation
-- =========================================================================

---@param mod table
local function resetLayout(mod)
    W.Confirm(L["Reset windows confirm"], function()
        OUI.Move:ResetAll()

        -- `ResetAll` a vidé les entrées une à une, par l'hôte. Les tables
        -- elles-mêmes sont vidées ici : une fenêtre retirée du registre entre
        -- deux versions y aurait laissé une entrée que le moteur ne connaît plus
        -- et ne peut donc pas effacer.
        wipe(positions(mod))
        wipe(scales(mod))

        mod:Print(L["Window layout reset"])
    end)
end

-- =========================================================================
--  Déclaration du module
-- =========================================================================

-- Le nom du module reste `Windows` : c'est une clé de base de données, et la
-- renommer casserait les réglages de tout le monde (règle 4). Seul l'intitulé
-- change, et il dit désormais de quelles fenêtres il s'agit — celles du client,
-- par opposition à la fenêtre d'options de l'addon.
OUI:RegisterModule(MODULE, {
    title    = L["Game windows"],
    category = "QoL",
    order    = 10,
    secure   = true,

    defaults = {
        -- Éteint par défaut, comme tout le reste de l'addon : installer OneUI
        -- ne doit rien changer tant qu'on n'a rien coché.
        movable  = false,
        scalable = false,

        -- Un modificateur par défaut, et non « aucun » : sans lui, un glisser
        -- dans le corps d'une fenêtre la déplace, y compris quand on voulait
        -- seulement faire glisser autre chose. Le choix « aucun » reste offert à
        -- qui le préfère.
        moveModifier = "SHIFT",

        -- La fenêtre de jet de butin. Aucune position par défaut : tant que le
        -- joueur n'a pas posé l'aperçu, la table reste vide et le cadre
        -- appartient entièrement au client. Cocher la première case ne déplace
        -- donc rien — c'est le glisser de l'aperçu qui décide, et c'est à
        -- l'infobulle de le dire.
        lootMove    = false,
        lootPreview = false,
        lootLocked  = false,
        lootCentered = false,

        positions = {},
        scales    = {},
    },

    options = {
        { type = "header", text = L["Moving"] },
        {
            type    = "toggle",
            key     = "movable",
            text    = L["Move windows"],
            tooltip = L["Move windows tip"],
        },
        {
            type     = "dropdown",
            key      = "moveModifier",
            text     = L["Move modifier"],
            tooltip  = L["Move modifier tip"],
            disabled = requires("movable"),
            values   = {
                { value = "SHIFT", label = L["Shift"] },
                { value = "CTRL",  label = L["Ctrl"] },
                { value = "ALT",   label = L["Alt"] },
                { value = "NONE",  label = L["No modifier"] },
            },
        },

        { type = "header", text = L["Size"] },
        {
            type    = "toggle",
            key     = "scalable",
            text    = L["Scale windows"],
            tooltip = L["Scale windows tip"],
        },

        { type = "header", text = L["Loot roll window"] },
        {
            type    = "toggle",
            key     = "lootMove",
            text    = L["Move loot roll window"],
            tooltip = L["Move loot roll window tip"],
        },
        {
            type     = "toggle",
            key      = "lootPreview",
            edit     = "preview",
            text     = L["Loot roll preview"],
            tooltip  = L["Loot roll preview tip"],
            disabled = requires("lootMove"),
        },
        {
            type     = "toggle",
            key      = "lootLocked",
            edit     = "lock",
            text     = L["Lock loot roll window"],
            tooltip  = L["Lock loot roll window tip"],
            disabled = requires("lootMove"),
        },
        {
            type     = "toggle",
            key      = "lootCentered",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = requires("lootMove"),
        },
        {
            -- Rangée avec les échelles des autres fenêtres : la poignée de
            -- l'aperçu écrit au même endroit (voir `UI/Move.lua`).
            type     = "slider",
            text     = L["Frame scale"],
            tooltip  = L["Frame scale tip"],
            min      = T.SIZE.LOOT_SCALE_MIN,
            max      = T.SIZE.LOOT_SCALE_MAX,
            step     = T.SIZE.FRAME_SCALE_STEP,
            decimals = 2,
            get      = function()
                local mod = OUI.Modules:Get(MODULE)
                return mod and scales(mod)[LOOT_FRAME] or 1
            end,
            set      = function(value)
                local mod = OUI.Modules:Get(MODULE)
                local stored = mod and mod:Get("scales")
                if not stored then return end
                stored[LOOT_FRAME] = value
                OUI.Move:RefreshLoot()
            end,
            disabled = requires("lootMove"),
        },

        { type = "header", text = L["Reset"] },
        {
            type    = "button",
            text    = L["Reset window layout"],
            label   = L["Reset"],
            tooltip = function()
                return string.format(L["Reset window layout tip"], OUI.Move:CountPinned())
            end,
            onClick = function()
                local mod = OUI.Modules:Get(MODULE)
                if mod then resetLayout(mod) end
            end,
        },
    },

    OnEnable = function(self)
        OUI.Move:SetHost(makeHost(self))
        OUI.Move:Start()

        -- La moitié des fenêtres du client vit dans un addon chargé à la
        -- demande : elles n'existent pas encore ici.
        self:RegisterEvent("ADDON_LOADED", function(_, addonName)
            OUI.Move:OnAddonLoaded(addonName)
        end)

        -- Le capteur de molette ne s'arme que pendant que le modificateur est
        -- tenu. Hors de ces instants-là, il n'existe pas.
        self:RegisterEvent("MODIFIER_STATE_CHANGED", function()
            OUI.Move:OnModifierChanged()
        end)

        -- Un cadre protégé ne se repositionne pas en combat : ce qui a été
        -- refusé pendant le combat est rattrapé ici.
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            OUI.Move:Refresh()
        end)
    end,

    OnDisable = function()
        -- Rend chaque fenêtre à l'ancrage et à l'échelle où on l'a trouvée, puis
        -- débranche le moteur. Les positions restent en base : rallumer le
        -- module doit retrouver la disposition, pas la redemander.
        OUI.Move:Stop()
    end,

    OnSettingChanged = function(self, key)
        if key == nil then
            -- Changement de profil : la disposition n'est plus la même. On rend
            -- d'abord les fenêtres à leur état d'origine, sans quoi celles que
            -- l'ancien profil déplaçait et que le nouveau ignore resteraient là
            -- où le profil précédent les avait mises.
            OUI.Move:Stop()
            OUI.Move:SetHost(makeHost(self))
            OUI.Move:Start()
            return
        end

        if key == "scalable" then
            -- Décocher pendant que le modificateur est tenu doit rendre la
            -- molette au jeu tout de suite, pas au relâchement.
            OUI.Move:OnModifierChanged()
            return
        end

        if key == "lootMove" or key == "lootPreview" or key == "lootLocked"
            or key == "lootCentered" then
            OUI.Move:RefreshLoot()
        end
    end,
})
