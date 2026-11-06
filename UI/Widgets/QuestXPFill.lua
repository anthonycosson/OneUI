-- =========================================================================
--  OneUI — UI/Widgets/QuestXPFill.lua
--  Sur la barre d'XP du client : l'XP que rapporteraient les quêtes terminées.
--
--  **On ajoute une texture, on ne touche à rien d'autre.** La barre reste celle
--  du client — son remplissage, son repos, son texte. On pose par-dessus un
--  remplissage vert — celui de la réputation amicale —, à la manière exacte
--  de celui du repos
--  (`ExhaustionLevelFillBar`, `Blizzard_StatusTrackingBar/Mainline/ExpBar.xml`) :
--  une texture de la barre elle-même, accrochée au bord gauche, dont seule la
--  largeur change. Le remplissage de l'XP, porté par la barre de statut — un
--  cadre enfant, donc dessiné au-dessus —, en couvre le début ; ce qui dépasse
--  est ce que les quêtes ajouteraient.
--
--  Une couche au-dessus de celle du repos : là où les deux se recouvrent, le
--  vert l'emporte, et le bleu du repos reprend au-delà. C'est l'ordre dans
--  lequel l'XP arrivera.
--
--  **Il y a une barre d'XP par conteneur.** Le client en construit une dans
--  chacun de ses deux emplacements de barres (`InitializeBars`), et montre
--  celle de l'emplacement où il range l'XP. On habille les deux : celle qui
--  n'est pas montrée ne coûte rien.
--
--  Le widget ne compte rien : l'appelant lui donne le total de XP à montrer.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets

--- barre d'XP du client -> notre texture. Une par barre, créée une fois.
local fills = {}

--- Les barres d'XP du client, dans tous les conteneurs qui en ont une.
---@param out table  vidée puis remplie
---@return table
local function expBars(out)
    wipe(out)

    local manager = StatusTrackingBarManager
    local info    = StatusTrackingBarInfo
    if type(manager) ~= "table" or type(manager.barContainers) ~= "table" then return out end
    if type(info) ~= "table" or type(info.BarsEnum) ~= "table" then return out end

    local index = info.BarsEnum.Experience
    for _, container in ipairs(manager.barContainers) do
        local bar = type(container.bars) == "table" and container.bars[index]
        if bar and bar.StatusBar then out[#out + 1] = bar end
    end

    return out
end

local bars = {}

--- La texture verte d'une barre, créée au premier besoin.
---@param bar table
---@return table|nil
local function fillOf(bar)
    local fill = fills[bar]
    if fill then return fill end

    -- La couche du repos est `ARTWORK` -1 : on se pose juste au-dessus.
    fill = bar:CreateTexture(nil, "ARTWORK", nil, 0)
    if not T.TrySetAtlas(fill, T.ATLAS.XP_QUEST_FILL) then return nil end
    fill:SetPoint("TOPLEFT", bar.StatusBar, "TOPLEFT")
    fill:SetPoint("BOTTOMLEFT", bar.StatusBar, "BOTTOMLEFT")
    fill:Hide()

    -- **Éclairci par une seconde couche, en mode additif.** Une texture ne se
    -- teint que vers le sombre : une couleur de sommet au-delà de 1 n'existe
    -- pas. La même image, ajoutée à elle-même à demi-opacité, monte la clarté
    -- sans changer le grain ni la teinte.
    local glow = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    if T.TrySetAtlas(glow, T.ATLAS.XP_QUEST_FILL) then
        glow:SetBlendMode("ADD")
        glow:SetAlpha(T.ALPHA.XP_QUEST_GLOW)
        glow:SetAllPoints(fill)
        glow:Hide()
        fill.glow = glow
    end

    fills[bar] = fill
    return fill
end

--- Montre ou cache le vert d'une barre, sa couche d'éclat avec lui.
---@param fill table
---@param shown boolean
local function setShown(fill, shown)
    fill:SetShown(shown)
    if fill.glow then fill.glow:SetShown(shown) end
end

--- Le bloc qu'on rend à l'appelant.
local QuestXPFill = {}
W.QuestXPFill = QuestXPFill

--- L'XP actuelle et le maximum du niveau, ou `nil` quand le client ne les
--- donne pas lisibles.
---@return number|nil current
---@return number|nil max
local function playerXP()
    local current, max = UnitXP("player"), UnitXPMax("player")
    if type(current) ~= "number" or U.IsSecret(current) then return nil end
    if type(max) ~= "number" or U.IsSecret(max) or max <= 0 then return nil end
    return current, max
end

--- Montre `gain` points d'XP à la suite de l'XP actuelle. Rien à montrer —
--- aucun gain, XP illisible — cache le vert.
---@param gain number
function QuestXPFill.Show(gain)
    local current, max = playerXP()

    for _, bar in ipairs(expBars(bars)) do
        local fill = fillOf(bar)
        if fill then
            local width = bar.StatusBar:GetWidth()
            if current and gain > 0 and width and width > 0 then
                -- Au-delà du niveau, la barre est pleine : le vert va au bord,
                -- comme le repos qui déborde.
                local ratio = math.min((current + gain) / max, 1)
                fill:SetWidth(math.max(ratio * width, 1))
                setShown(fill, true)
            else
                setShown(fill, false)
            end
        end
    end
end

--- Retire le vert de toutes les barres (règle 6).
function QuestXPFill.Hide()
    for _, fill in pairs(fills) do setShown(fill, false) end
end

--- Les barres d'XP du client, pour qui veut s'accrocher à leur taille.
---@return table
function QuestXPFill.Bars()
    return expBars({})
end
