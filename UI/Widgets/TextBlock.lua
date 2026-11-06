-- =========================================================================
--  OneUI — UI/Widgets/TextBlock.lua
--  Quelques lignes de texte, posées à même l'écran.
--
--  Même socle que la rangée d'icônes (`W.Panel`, voir
--  `UI/Widgets/IconBadge.lua`) : une position que le joueur pose une fois pour
--  toutes, une poignée d'échelle dans le coin, un verrou. **Sans habillage** :
--  ce qu'on lit là se lit comme un texte du jeu, pas comme une fenêtre.
--
--  **Une ligne peut être faite de morceaux**, posés côte à côte à un écart
--  qu'on règle au pixel. C'est pour le « 63 / 150 » des niveaux de métier :
--  collés, les deux nombres se lisaient comme un seul, et le plus petit blanc
--  qu'une police du client sache écrire — l'espace — les éloignait trop. Une
--  image transparente glissée dans le texte n'a pas mieux fait : le client
--  ajoute son propre blanc autour, et 1 px ou 2 px y donnaient le même écart.
--  Écrire chaque morceau dans son propre texte est le seul écart qu'on tienne.
--
--  Le widget ne sait pas ce qu'il écrit : l'appelant lui donne une fonction
--  qui rend les lignes, relue à chaque `Refresh`. Rien à écrire, pas de cadre.
--
--  **Verrouillé, il laisse passer les clics.** Un texte posé au milieu du
--  monde ne doit pas voler le clic qu'on y fait pour viser ou se déplacer :
--  la souris ne lui sert qu'à être déplacé, et le verrou dit qu'on a fini.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local W    = OUI.Widgets

---@alias OUI.TextBlockLine string|string[]   une chaîne, ou ses morceaux

---@class OUI.TextBlockOpts
---@field lines fun(): OUI.TextBlockLine[]   les lignes à écrire, dans l'ordre
---@field getPos? fun(): number, number
---@field setPos? fun(x: number, y: number)
---@field isLocked? fun(): boolean
---@field isCentered? fun(): boolean
---@field getScale? fun(): number|nil
---@field setScale? fun(scale: number)

--- Bloc de texte, masqué au départ.
---@param opts OUI.TextBlockOpts
---@return table
function W.TextBlock(opts)
    local pad = T.SIZE.TEXT_BLOCK_PAD

    -- Taille provisoire : le cadre se mesure sur son texte, à chaque passage.
    local panel = W.Panel({
        width      = pad * 2,
        height     = pad * 2,
        chrome     = "none",
        getPos     = opts.getPos,
        setPos     = opts.setPos,
        isLocked   = opts.isLocked,
        isCentered = opts.isCentered,
        minScale   = T.SIZE.TEXT_BLOCK_SCALE_MIN,
        maxScale   = T.SIZE.TEXT_BLOCK_SCALE_MAX,
        getScale   = opts.getScale,
        setScale   = opts.setScale,
    })

    -- La poignée pend dehors, comme sur la rangée d'icônes : dans le coin,
    -- elle couvrirait la fin de la dernière ligne.
    if panel.ResizeGrip then
        panel.ResizeGrip:ClearAllPoints()
        panel.ResizeGrip:SetPoint("TOPLEFT", panel, "BOTTOMRIGHT", 0, 0)
    end

    --- ligne -> morceau -> texte. Créés à la demande, jamais détruits (règle 7) :
    --- une ligne de moins cache ses textes, elle ne les jette pas.
    local rows = {}

    ---@param line number
    ---@param piece number
    ---@return table
    local function fontString(line, piece)
        local row = rows[line]
        if not row then
            row = {}
            rows[line] = row
        end

        local text = row[piece]
        if not text then
            text = panel:CreateFontString(nil, "ARTWORK", T.FONT.TEXT_BLOCK)
            text:SetJustifyH("LEFT")
            text:SetWordWrap(false)
            row[piece] = text
        end
        return text
    end

    --- Pose une ligne à la hauteur `y` et rend sa largeur et sa hauteur.
    ---@param line number
    ---@param content OUI.TextBlockLine
    ---@param y number
    ---@return number width
    ---@return number height
    local function layLine(line, content, y)
        local pieces = type(content) == "table" and content or { content }
        local x, height = pad, 0

        for piece = 1, #pieces do
            local text = fontString(line, piece)
            text:SetText(pieces[piece])
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
            text:Show()

            x = x + text:GetStringWidth()
            if piece < #pieces then x = x + T.SIZE.TEXT_BLOCK_PIECE_GAP end
            height = math.max(height, text:GetStringHeight())
        end

        -- Les morceaux d'une ligne plus longue, passée, restent à cacher.
        local row = rows[line]
        for piece = #pieces + 1, #row do row[piece]:Hide() end

        return x - pad, height
    end

    --- Relit les lignes, les écrit et remesure le cadre. Rien à écrire, pas de
    --- cadre : un panneau vide se saisirait sous le curseur pour rien.
    function panel:Refresh()
        local lines = opts.lines and opts.lines() or nil
        if not lines or #lines == 0 then
            self:Hide()
            return
        end

        local y, width = pad, 0
        for line = 1, #lines do
            local w, h = layLine(line, lines[line], y)
            width = math.max(width, w)
            y = y + h
            if line < #lines then y = y + T.SIZE.TEXT_BLOCK_LINE_GAP end
        end

        for line = #lines + 1, #rows do
            local row = rows[line]
            for piece = 1, #row do row[piece]:Hide() end
        end

        self:SetSize(width + pad * 2, y + pad)
        self:Show()
    end

    --- Le verrou du socle range la poignée ; celui-ci rend aussi les clics au
    --- monde (voir l'en-tête).
    local applyLock = panel.ApplyLock
    function panel:ApplyLock()
        applyLock(self)
        self:EnableMouse(not (opts.isLocked and opts.isLocked() == true))
    end

    --- Range le cadre. Position et taille restent : rallumer ne redemande
    --- rien.
    function panel:Stop()
        self:Hide()
    end

    panel:ApplyScale()
    panel:ApplyLock()

    panel:Hide()
    return panel
end
