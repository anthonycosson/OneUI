-- =========================================================================
--  OneUI — UI/Widgets/ManaBar.lua
--  Une barre de mana autonome, posée à même l'écran.
--
--  Le widget ne sait pas à qui est ce mana : l'appelant lui donne une taille et
--  deux nombres. Ces nombres peuvent être secrets : ils sont transmis à la barre
--  sans être lus.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets

---@class OUI.ManaBarOpts
---@field getPos? fun(): number, number
---@field setPos? fun(x: number, y: number)
---@field isLocked? fun(): boolean
---@field isCentered? fun(): boolean

--- Barre de mana, masquée au départ.
---@param opts OUI.ManaBarOpts
---@return table
function W.ManaBar(opts)
    local panel = W.Panel({
        width      = T.SIZE.MANA_BAR_W,
        height     = T.SIZE.MANA_BAR_H,
        chrome     = "none",
        getPos     = opts.getPos,
        setPos     = opts.setPos,
        isLocked   = opts.isLocked,
        isCentered = opts.isCentered,
    })

    local background = panel:CreateTexture(nil, "BACKGROUND")
    -- Le fond et le dégradé de la ressource personnelle du client, avec les
    -- débords de son propre fond. Les aplats ne servent que si l'atlas manque.
    if T.TrySetAtlas(background, T.ATLAS.MANA_BAR_BG) then
        background:SetPoint("TOPLEFT", panel, "TOPLEFT", T.SIZE.MANA_BAR_BG_LEFT, T.SIZE.MANA_BAR_BG_TOP)
        background:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", T.SIZE.MANA_BAR_BG_RIGHT, T.SIZE.MANA_BAR_BG_BOTTOM)
    else
        background:SetAllPoints(panel)
        background:SetColorTexture(T.COLOR.SHADE:GetRGB())
    end

    local known = not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(T.ATLAS.MANA_BAR_FILL)
    local bar   = CreateFrame("StatusBar", nil, panel)
    bar:SetAllPoints(panel)
    bar:SetStatusBarTexture(known and T.ATLAS.MANA_BAR_FILL or T.TEXTURE.STATUSBAR_FLAT)
    bar:SetStatusBarColor(T.COLOR.MANA_BAR:GetRGB())

    --- Change la taille et garde le centre de la barre à sa place.
    ---@param width number
    ---@param height number
    function panel:SetBarSize(width, height)
        self:SetSize(
            U.Clamp(width or T.SIZE.MANA_BAR_W, T.SIZE.MANA_BAR_W_MIN, T.SIZE.MANA_BAR_W_MAX),
            U.Clamp(height or T.SIZE.MANA_BAR_H, T.SIZE.MANA_BAR_H_MIN, T.SIZE.MANA_BAR_H_MAX))
        self:ApplyPosition()
    end

    --- Peint le mana courant.
    ---@param value any  éventuellement secret
    ---@param max any    éventuellement secret
    function panel:SetMana(value, max)
        bar:SetMinMaxValues(0, max)
        bar:SetValue(value)
    end

    return panel
end
