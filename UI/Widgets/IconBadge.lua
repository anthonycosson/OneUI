-- =========================================================================
--  OneUI — UI/Widgets/IconBadge.lua
--  Une rangée d'icônes cliquables, posée à même l'écran.
--
--  Même socle que la barre d'outils de groupe (`W.Panel`, voir
--  `UI/Widgets/MarkerBar.lua`) : un cadre, un fond, une position que le joueur
--  pose une fois pour toutes, une poignée d'échelle dans le coin. Rien dedans
--  que des icônes.
--
--  **Une icône vaut la phrase qu'on n'écrit pas.** Celles qu'on y met sont
--  celles du client — l'image que le joueur a déjà vue dans le menu où il
--  devra retourner —, et le cadre n'a donc rien à expliquer : il montre ce qui
--  manque, et le clic va le chercher. Ce qu'il y aurait à dire de plus tient
--  dans l'infobulle de chaque icône, qui est l'endroit de l'addon où vivent
--  les explications.
--
--  **La rangée se recompose à chaque passage.** Les cases sont construites une
--  fois pour toutes — les frames ne se détruisent pas (règle 7) —, mais seules
--  celles qui ont quelque chose à montrer sont posées, et le cadre se remesure
--  sur elles. Une case cachée ne laisse donc pas de trou : deux icônes, une
--  icône, ou pas de cadre du tout. L'appelant peut demander un nombre
--  d'icônes par ligne et le sens dans lequel le cadre grandit.
--
--  Le widget ne sait pas ce qu'il montre : chaque case lui donne une fonction
--  qui dit s'il y a lieu de paraître, une qui rend l'image, et ce que le clic
--  déclenche.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local W    = OUI.Widgets

---@class OUI.IconBadgeSlot
---@field shown fun(): boolean        y a-t-il lieu de montrer cette case ?
---@field icon fun(): any             son image : identifiant de fichier ou atlas
---@field title? string               titre de son infobulle
---@field tip? string                 corps de son infobulle
---@field onClick? fun()              ce que le clic déclenche
---@field reserved? fun(): boolean  garde-t-elle sa place dans la rangée ? (`fixedSlots`)
---@field action? fun(): table|nil   attributs de l'action sécurisée du clic (`type`, `spell`, `unit`, `macrotext`)
---@field count? fun(): number|nil   chiffre posé dans le coin de l'icône, montré à partir de 2

---@class OUI.IconBadgeOpts
---@field slots OUI.IconBadgeSlot[]
---@field getPos? fun(): number, number
---@field setPos? fun(x: number, y: number)
---@field isLocked? fun(): boolean
---@field isCentered? fun(): boolean
---@field fixedSlots? boolean        chaque case garde sa place, même quand une voisine est cachée
---@field getScale? fun(): number|nil
---@field setScale? fun(scale: number)
---@field getLayout? fun(): number|nil, string|nil  icônes par ligne (0 = toutes) et sens (`GROWTH`)

--- Sens d'agrandissement -> point du cadre qui reste fixe, coin d'où partent
--- les icônes, et sens des colonnes et des lignes. « Depuis le centre » garde
--- le cadre centré sur sa position, comme avant que le sens se choisisse.
local GROWTH = {
    CENTER     = { anchor = "CENTER",      corner = "TOPLEFT",     sx =  1, sy = -1 },
    RIGHT_DOWN = { anchor = "TOPLEFT",     corner = "TOPLEFT",     sx =  1, sy = -1 },
    LEFT_DOWN  = { anchor = "TOPRIGHT",    corner = "TOPRIGHT",    sx = -1, sy = -1 },
    RIGHT_UP   = { anchor = "BOTTOMLEFT",  corner = "BOTTOMLEFT",  sx =  1, sy =  1 },
    LEFT_UP    = { anchor = "BOTTOMRIGHT", corner = "BOTTOMRIGHT", sx = -1, sy =  1 },
}

--- Les sens proposés, dans l'ordre d'une liste de réglages.
W.ICON_BADGE_GROWTH = { "CENTER", "RIGHT_DOWN", "LEFT_DOWN", "RIGHT_UP", "LEFT_UP" }

--- Pose une image sur une texture. Un nom d'atlas ou un identifiant de
--- fichier : le premier est une chaîne, le second un nombre, et c'est tout ce
--- qu'il y a à distinguer.
---@param texture table
---@param source any
---@return boolean painted
local function paint(texture, source)
    if type(source) == "string" then
        return T.TrySetAtlas(texture, source)
    end

    if source then
        texture:SetTexture(source)
        return true
    end

    return false
end

--- Ce qu'une action sécurisée peut porter.
local ACTION_ATTRIBUTES = { "type", "spell", "unit", "macrotext" }

--- Pose l'action d'un clic ; sans action, le clic ne fait plus rien.
---@param button table
---@param action table|nil
local function arm(button, action)
    for i = 1, #ACTION_ATTRIBUTES do
        local name = ACTION_ATTRIBUTES[i]
        button:SetAttribute(name, action and action[name] or nil)
    end
end

--- Rangée d'icônes, masquée au départ.
---@param opts OUI.IconBadgeOpts
---@return table
function W.IconBadge(opts)
    local slots = opts.slots or {}

    -- **Une case sécurisée protège tout le cadre** : en combat, le client
    -- refuse de le montrer, le cacher, le retailler ou le déplacer. La rangée
    -- reste alors telle quelle, et l'appelant la relit à la sortie de combat.
    local secure = false
    for index = 1, #slots do
        if slots[index].action then secure = true end
    end

    ---@return boolean
    local function frozen()
        return secure and InCombatLockdown()
    end

    --- Icônes par ligne (0 = toutes sur une) et sens d'agrandissement.
    ---@return number perRow, table growth
    local function layout()
        local perRow, growth
        if opts.getLayout then perRow, growth = opts.getLayout() end
        return math.max(math.floor(tonumber(perRow) or 0), 0), GROWTH[growth] or GROWTH.CENTER
    end

    -- Taille provisoire : le cadre se mesure sur les cases qu'il montre, à
    -- chaque passage.
    local panel = W.Panel({
        width    = T.SIZE.BADGE_ICON,
        height   = T.SIZE.BADGE_ICON,
        getPos   = opts.getPos,
        setPos   = opts.setPos,
        isLocked = function()
            return frozen() or (opts.isLocked ~= nil and opts.isLocked() == true)
        end,
        isCentered = opts.isCentered,
        getAnchor  = function()
            local _, growth = layout()
            return growth.anchor
        end,

        -- Le cadre ne se retaille pas, il change d'**échelle** : ce que le
        -- joueur règle est de quelle taille il voit la rangée, et les icônes
        -- grossissent avec elle. Le verrou range la poignée avec la position.
        minScale = T.SIZE.BADGE_SCALE_MIN,
        maxScale = T.SIZE.BADGE_SCALE_MAX,
        getScale = opts.getScale,
        setScale = opts.setScale,
    })

    -- **La poignée sort du cadre.** Il n'y a plus de marge où la loger, et la
    -- poser dans le coin la mettrait sur ce qui se clique : le geste de
    -- redimensionner disputerait ses pixels au geste que ce cadre existe pour
    -- offrir. Accrochée par son propre coin haut-gauche au coin bas-droit du
    -- panneau, elle pend dehors, ne recouvre rien, et disparaît avec le verrou
    -- comme avant.
    if panel.ResizeGrip then
        panel.ResizeGrip:ClearAllPoints()
        panel.ResizeGrip:SetPoint("TOPLEFT", panel, "BOTTOMRIGHT", 0, 0)
    end

    local buttons = {}

    for index = 1, #slots do
        local slot   = slots[index]
        local template = slot.action and T.Template("SECURE_ACTION")
        local button = CreateFrame("Button", nil, panel, template or nil)
        button:SetSize(T.SIZE.BADGE_ICON, T.SIZE.BADGE_ICON)
        button:Hide()

        -- Au relâchement seulement, pour que l'action ne parte pas deux fois
        -- (voir `UI/Widgets/SecureMenu.lua`).
        if template then
            button:RegisterForClicks("AnyUp")
            button:SetAttribute("useOnKeyDown", false)
            button.secureAction = true
        end

        local image = button:CreateTexture(nil, "ARTWORK")
        image:SetAllPoints(button)
        button.image = image

        -- **La surbrillance du client, et par-dessus l'icône.** La lueur
        -- centrale des boutons de la barre d'outils passe derrière, ce qui
        -- marche pour un marqueur de raid — troué — et pas du tout pour une
        -- icône de sort, qui est un carré plein : rien ne s'allumerait sous le
        -- curseur, et rien n'annoncerait que ça se clique.
        button:SetHighlightTexture(T.TEXTURE.ICON_HIGHLIGHT, "ADD")

        -- Le chiffre dit combien il en manque, quand une icône en vaut plusieurs.
        if slot.count then
            local count = button:CreateFontString(nil, "OVERLAY", T.FONT.SLOT_BADGE)
            count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -T.SIZE.BADGE_GAP, T.SIZE.BADGE_GAP)
            button.count = count
        end

        if slot.onClick then
            button:SetScript("OnClick", function() slot.onClick() end)
        end

        -- **C'est ici que l'explication vit.** Le cadre ne porte aucun texte :
        -- une case dit ce qui manque par son image, et le reste — son nom, ce
        -- que le clic fera — se lit au survol, comme partout ailleurs dans
        -- l'addon. Chaque case a son titre : elle ne montre jamais qu'une
        -- seule chose.
        if slot.title or slot.tip then
            W.Tooltip(button, slot.title, slot.tip)
        end

        buttons[index] = button
    end

    --- Place de chaque case dans la grille (à partir de 0). Une seule table,
    --- réemployée (règle 7).
    local places = {}

    --- Pose les cases visibles sur la grille et remesure le cadre.
    ---
    --- Avec `fixedSlots`, la place d'une case ne dépend que des cases
    --- réservées, jamais de celles qu'on montre : une case cachée laisse son
    --- trou, et rien ne glisse quand elle revient. Sans, les cases visibles se
    --- suivent.
    ---
    --- **Le cadre est la grille, au pixel près** : aucune marge, ni pour
    --- respirer ni pour loger la poignée. Il porte des icônes, qui sont déjà des
    --- carrés finis, et l'habillage les cerne de lui-même en débordant vers
    --- l'extérieur (voir `W.PanelChrome`).
    ---@param visible table  indices des cases à montrer, dans l'ordre
    local function reflow(visible)
        wipe(places)
        local count = 0

        if opts.fixedSlots then
            for index = 1, #slots do
                if slots[index].reserved == nil or slots[index].reserved() then
                    places[index] = count
                    count = count + 1
                end
            end
        end

        -- Une case visible sans place réservée prend la suivante.
        for i = 1, #visible do
            if not places[visible[i]] then
                places[visible[i]] = count
                count = count + 1
            end
        end

        local perRow, growth = layout()
        local columns = (perRow > 0 and perRow < count) and perRow or count
        local rows    = math.ceil(count / columns)
        local icon, gap = T.SIZE.BADGE_ICON, T.SIZE.BADGE_GAP
        local step    = icon + gap

        panel:SetSize(columns * icon + (columns - 1) * gap, rows * icon + (rows - 1) * gap)

        -- Posées depuis le coin d'où le cadre grandit, qui est aussi celui qui
        -- reste fixe à l'écran (voir `W.Panel`).
        for i = 1, #visible do
            local place  = places[visible[i]]
            local button = buttons[visible[i]]
            button:ClearAllPoints()
            button:SetPoint(growth.corner, panel, growth.corner,
                growth.sx * (place % columns) * step,
                growth.sy * math.floor(place / columns) * step)
            button:Show()
        end
    end

    --- Les cases à montrer, du passage en cours. Une seule table, réemployée :
    --- elle est refaite à chaque relecture, et en créer une par passage ne
    --- servirait qu'à donner du travail au ramasse-miettes (règle 7).
    local showing = {}

    --- Ce qui a lieu de paraître, et ce qui reste rangé.
    ---@return table visible
    local function collect()
        wipe(showing)

        for index = 1, #slots do
            local slot   = slots[index]
            local button = buttons[index]
            local show   = slot.shown == nil or slot.shown() == true

            if show and paint(button.image, slot.icon and slot.icon()) then
                if button.secureAction then arm(button, slot.action()) end
                if button.count then
                    local n = slot.count()
                    button.count:SetText(n and n > 1 and tostring(n) or "")
                end
                showing[#showing + 1] = index
            else
                button:Hide()
            end
        end

        return showing
    end

    --- Relit toutes les cases et repose le cadre. Rien à montrer, pas de
    --- cadre : un panneau vide est un panneau qui se déplace tout seul sous le
    --- curseur pour rien.
    ---
    --- C'est la seule voie de rafraîchissement, et c'est voulu : ce que ce
    --- cadre montre ne change qu'à l'annonce du client, jamais avec le temps.
    --- Poser une boucle pour relire une image qui ne bouge qu'au clic serait
    --- payer pour rien (règle 7).
    function panel:Refresh()
        if frozen() then return end

        local visible = collect()

        if #visible == 0 then
            self:Hide()
            return
        end

        reflow(visible)
        -- Le sens peut avoir changé, et avec lui le point fixe du cadre.
        self:ApplyPosition()
        self:Show()
    end

    --- Range le cadre. Position et taille restent : rallumer ne redemande
    --- rien.
    function panel:Stop()
        if frozen() then return end
        self:Hide()
    end

    -- L'échelle rangée est reposée tout de suite, et la position avec elle :
    -- la seconde se convertit dans la première (voir `W.Panel:ApplyPosition`).
    panel:ApplyScale()
    panel:ApplyLock()

    panel:Hide()
    return panel
end
