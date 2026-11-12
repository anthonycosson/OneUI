-- =========================================================================
--  OneUI — UI/Widgets/Panel.lua
--  Petit panneau posé à même l'écran, déplaçable à la souris.
--
--  Plusieurs pièces de l'addon vivent en dehors de la fenêtre d'options : le
--  suivi des résurrections de combat, la barre de marqueurs, le rappel de file et
--  la rangée de ressource de classe. Elles ont toutes le même besoin — un fond,
--  une bordure, un titre facultatif, et une position que le joueur pose une fois
--  pour toutes. Écrire quatre fois ce socle donnerait quatre marges et quatre
--  façons de retenir une position ; il vit donc ici, et chaque pièce n'écrit que
--  ce qui la distingue.
--
--  **Une position est un décalage de centre à centre**, jamais un ancrage. C'est
--  la même règle que pour les fenêtres du client (voir `UI/Move.lua` et
--  `dev/docs/API_NOTES.md`) : le panneau se repose toujours en `CENTER`/`CENTER`,
--  ce qui reste juste quel que soit son contenu — un panneau qui grandit vers le
--  bas ne se déplace pas parce qu'une ligne s'y est ajoutée.
--
--  Le panneau ne connaît pas la base de données : l'appelant lui donne deux
--  fonctions, `getPos` et `setPos`, et c'est le module qui décide où la position
--  est rangée.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets

---@class OUI.PanelOpts
---@field width number
---@field height number
---@field title? string
---@field strata? string
---@field chrome? string                  "panel" (défaut) ou "none"
---@field getPos? fun(): number, number   décalage du centre, en pixels d'écran
---@field setPos? fun(x: number, y: number)
---@field isLocked? fun(): boolean        gèle la position et retire la poignée
---@field isCentered? fun(): boolean      garde le centre sur l'axe vertical de l'écran
---@field getAnchor? fun(): string        point du panneau qui reste fixe ("CENTER", "TOPLEFT"…)
---@field minScale? number                donne une poignée d'échelle
---@field maxScale? number
---@field getScale? fun(): number|nil
---@field setScale? fun(scale: number)
---@field canScale? fun(): boolean        refuse la poignée quand elle rendrait faux

--- Panneau autonome, masqué au départ.
---@param opts OUI.PanelOpts
---@return table
function W.Panel(opts)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(opts.width, opts.height)
    panel:SetFrameStrata(opts.strata or "MEDIUM")
    panel:SetClampedToScreen(true)
    panel:Hide()

    -- **Deux habillages, un seul socle.** Un panneau qu'on regarde ou dont on
    -- clique les pièces porte celui de la fenêtre d'options ; un panneau qui
    -- n'est **qu'une icône** n'a rien du tout — un cadre autour d'une icône de
    -- sort en ferait une pièce rapportée là où le jeu n'en met jamais.
    --
    -- Aucun des deux n'apporte de barre de titre : ces panneaux tiennent en une
    -- rangée, et une bande vide au-dessus n'aurait fait que les allonger.
    local chrome = opts.chrome or "panel"

    if chrome ~= "none" then
        W.PanelChrome(panel)

        -- **Le contour se prend à la souris, comme le reste du panneau.**
        -- L'habillage est dessiné *en dehors* du cadre (voir `W.PanelChrome`),
        -- donc en dehors de ce que le cadre reçoit : un panneau dont le contenu
        -- occupe toute la surface — une rangée d'icônes cliquables, par
        -- exemple — ne laissait plus un pixel pour le saisir, et se retrouvait
        -- cloué à l'écran alors qu'il est fait pour être posé.
        --
        -- Des retraits **négatifs** agrandissent la zone sensible : elle
        -- rejoint le bord visible au lieu de s'arrêter au bord logique. On ne
        -- le fait que pour un panneau habillé — sans habillage il n'y a pas de
        -- contour, et l'agrandir ferait prendre des clics à côté de rien.
        local reach = T.SIZE.PANEL_CHROME_BLEED + T.SIZE.PANEL_BORDER_OUTSET
        panel:SetHitRectInsets(-reach, -reach, -reach, -reach)
    end

    if opts.title then
        local title = panel:CreateFontString(nil, "ARTWORK", T.FONT.SECTION)
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", T.SIZE.TOOL_PAD, -T.SIZE.TOOL_PAD)
        title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -T.SIZE.TOOL_PAD, -T.SIZE.TOOL_PAD)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetTextColor(T.COLOR.NORMAL:GetRGB())
        title:SetText(opts.title)
        panel.title = title
    end

    --- Change le titre. Sans titre déclaré à la construction, sans effet : un
    --- panneau qui n'en avait pas n'a pas réservé la hauteur pour en porter un.
    ---@param text string
    function panel:SetTitle(text)
        if self.title then self.title:SetText(text or "") end
    end

    -- ---------------------------------------------------------------------
    --  Position
    -- ---------------------------------------------------------------------

    ---@return boolean
    local function locked()
        return opts.isLocked ~= nil and opts.isLocked() == true
    end

    ---@return boolean
    local function centered()
        return opts.isCentered ~= nil and opts.isCentered() == true
    end

    --- Le point du panneau qui reste fixe quand il change de taille. Centré, il
    --- perd sa part gauche ou droite : c'est son milieu qui reste sur l'axe.
    ---@return string
    local function anchor()
        local point = opts.getAnchor and opts.getAnchor() or "CENTER"
        if centered() then
            point = point:gsub("LEFT", ""):gsub("RIGHT", "")
            if point == "" then point = "CENTER" end
        end
        return point
    end

    --- Coordonnées d'un point du cadre, dans l'échelle de ce cadre.
    ---@param frame table
    ---@param point string
    ---@return number|nil x, number|nil y
    local function pointOf(frame, point)
        local cx, cy = frame:GetCenter()
        if not cx then return nil, nil end

        local x = point:find("LEFT") and frame:GetLeft()
            or point:find("RIGHT") and frame:GetRight() or cx
        local y = point:find("TOP") and frame:GetTop()
            or point:find("BOTTOM") and frame:GetBottom() or cy
        return x, y
    end

    --- Relève la position du point fixe et la rend à l'appelant, en décalage
    --- depuis le centre de l'écran et en pixels de `UIParent`.
    ---@param point string
    local function savePosition(point)
        if not opts.setPos then return end

        local x, y   = pointOf(panel, point)
        local px, py = UIParent:GetCenter()
        if not (x and px) then return end

        -- Les deux points sont exprimés chacun dans l'échelle de son cadre : on
        -- les ramène en pixels d'écran avant de les soustraire, sinon un panneau
        -- mis à l'échelle par le joueur se décale de la différence.
        local scale  = panel:GetEffectiveScale()
        local parent = UIParent:GetEffectiveScale()

        -- Centré, le glisser ne retient que la hauteur : le panneau a suivi le
        -- curseur de côté le temps du geste, il revient sur l'axe au lâcher.
        local dx = centered() and 0 or (x * scale - px * parent) / parent
        opts.setPos(dx, (y * scale - py * parent) / parent)
    end

    --- Le point fixe de la dernière pose. Quand il change, la position rangée
    --- est relevée sur le nouveau point avant d'être reposée : le panneau ne
    --- saute pas quand on change son sens d'agrandissement.
    local appliedAnchor

    --- Repose le panneau à la position que l'appelant a rangée.
    ---
    --- **Le décalage d'un ancrage s'exprime dans l'échelle du cadre ancré**, pas
    --- dans celle de son point d'accrochage : à l'échelle double, un décalage de
    --- cent vaut deux cents pixels d'écran. La position rangée, elle, est en
    --- unités de `UIParent` — c'est la seule qui reste vraie quand l'échelle
    --- change. On la convertit donc ici, et un panneau agrandi grandit autour de
    --- son centre au lieu de partir en diagonale.
    ---
    --- **Centré, le décalage horizontal est ramené à zéro — et rangé ainsi.**
    --- Forcer le zéro à l'affichage seul aurait suffi pour le panneau, pas pour
    --- ce qu'il représente : l'aperçu de la fenêtre de jet pose la vraie fenêtre
    --- à la position rangée. On range donc le zéro, une fois, et tout ce qui lit
    --- la position la voit centrée sans avoir à connaître le réglage.
    function panel:ApplyPosition()
        local point = anchor()
        if appliedAnchor and appliedAnchor ~= point then savePosition(point) end
        appliedAnchor = point

        local x, y = 0, 0
        if opts.getPos then x, y = opts.getPos() end

        if centered() and (x or 0) ~= 0 then
            x = 0
            if opts.setPos then opts.setPos(0, y or 0) end
        end

        local factor = UIParent:GetEffectiveScale() / self:GetEffectiveScale()

        self:ClearAllPoints()
        self:SetPoint(point, UIParent, "CENTER", (x or 0) * factor, (y or 0) * factor)
    end

    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        -- Verrouillé, le panneau ne bouge pas d'un pixel : c'est tout l'intérêt
        -- du réglage. On refuse le geste plutôt que de reposer le panneau après
        -- coup, ce qui le ferait sauter sous le curseur.
        if locked() then return end
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(anchor())
        -- Reposé tout de suite en centre à centre : `StartMoving` laisse le
        -- cadre ancré par le coin que le moteur a choisi, et un ancrage par un
        -- coin ferait glisser le panneau dès que son contenu change de taille.
        self:ApplyPosition()
    end)

    -- ---------------------------------------------------------------------
    --  Échelle
    -- ---------------------------------------------------------------------
    -- La disposition d'un panneau est arrêtée à sa construction ; ce que le
    -- joueur règle, c'est de quelle **taille** il la voit. L'échelle emporte
    -- tout d'un coup — vignettes, libellés, bordure —, là où retailler le cadre
    -- aurait laissé les textes au corps où ils sont.

    ---@param scale number
    ---@return number
    local function clampScale(scale)
        if opts.minScale and scale < opts.minScale then return opts.minScale end
        if opts.maxScale and scale > opts.maxScale then return opts.maxScale end
        return scale
    end

    if opts.minScale and opts.maxScale and opts.setScale then
        W.ScaleGrip(panel, {
            min      = opts.minScale,
            max      = opts.maxScale,
            setScale = opts.setScale,
            -- Pendant le geste, le panneau se repose à chaque cran : sans cela
            -- il grandirait à partir du coin que l'ancrage lui donne à l'échelle
            -- courante, et glisserait sous le curseur au lieu de gonfler sur
            -- place.
            onScale  = function() panel:ApplyPosition() end,
            allow    = function()
                if locked() then return false end
                return opts.canScale == nil or opts.canScale() == true
            end,
        })
    end

    --- Repose l'échelle que l'appelant a rangée, et la position avec elle : la
    --- seconde se convertit dans la première (voir `ApplyPosition`).
    function panel:ApplyScale()
        if not opts.getScale then return end
        self:SetScale(clampScale(opts.getScale() or 1))
        self:ApplyPosition()
    end

    --- Gèle ou libère la position. Le panneau reste utilisable : verrouiller
    --- range la prise, pas les boutons.
    function panel:ApplyLock()
        if not self.ResizeGrip then return end
        self.ResizeGrip:SetShown(not locked())
    end

    -- ---------------------------------------------------------------------
    --  Effacement au repos
    -- ---------------------------------------------------------------------
    -- Un panneau d'outils sert par intermittence : entre deux pulls il n'a rien
    -- à dire et occupe pourtant sa place. L'effacer tant que le curseur n'est
    -- pas dessus le rend invisible sans le rendre inaccessible — il garde sa
    -- souris, c'est le survol qui le rallume.
    --
    -- **Sondage plutôt qu'`OnEnter`/`OnLeave`.** Le curseur qui passe de la marge
    -- à un bouton *sort* du panneau au sens du client : le panneau s'éteindrait
    -- sous la main qui va cliquer. `IsMouseOver` répond pour le cadre **et** ce
    -- qu'il contient. Bridé, comme tout `OnUpdate` (règle 7), et un cadre caché
    -- n'en reçoit pas — au repos complet il ne coûte rien.

    local watch = U.Throttle(T.TIMING.HOVER, function()
        panel:SetAlpha(panel:IsMouseOver() and 1 or 0)
    end)

    --- Efface le panneau tant que le curseur n'est pas dessus.
    ---@param enabled boolean
    function panel:SetRevealOnHover(enabled)
        if not enabled then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)
            return
        end

        self:SetScript("OnUpdate", watch)
        -- Tout de suite, et pas au prochain passage : le réglage vient d'être
        -- coché, le panneau doit s'effacer sous les yeux de qui l'a coché.
        self:SetAlpha(self:IsMouseOver() and 1 or 0)
    end

    panel:ApplyPosition()
    panel:ApplyLock()
    return panel
end
