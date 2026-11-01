-- =========================================================================
--  OneUI — UI/Widgets/KeyBind.lua
--  Choix d'une touche : un bouton qui affiche la touche, et qui écoute la
--  suivante quand on le clique.
--
--  **Pourquoi pas le menu Raccourcis du client.** Y paraître exige un
--  `Bindings.xml` et deux globales par entrée (`BINDING_HEADER_…`,
--  `BINDING_NAME_…`), ce que la règle 3 refuse. Et la touche n'y gagnerait
--  rien : le module qui la reçoit la pose lui-même, par une liaison prioritaire
--  (`SetOverrideBinding…`), qui se défait en un appel quand il s'éteint — ce
--  qu'une liaison enregistrée chez le client ne fait pas.
--
--  Le geste est celui du menu du client :
--      clic gauche   écouter la prochaine touche (Échap annule)
--      clic droit    retirer la touche
--  Les modificateurs se combinent dans l'ordre que le client écrit lui-même,
--  `ALT-CTRL-SHIFT-` ; une touche de modificateur seule ne se prend pas.
-- =========================================================================

local _, ns = ...
local BUI = ns.BUI
local T    = BUI.Theme
local W    = BUI.Widgets
local L    = ns.L

---@class BUI.KeyBindOpts
---@field text string
---@field tooltip? string
---@field indent? boolean
---@field get fun(): string   la touche, ou "" quand il n'y en a pas
---@field set fun(value: string)

--- Touches qui ne font que modifier une autre : seules, elles ne se prennent pas.
local MODIFIERS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL  = true, RCTRL  = true,
    LALT   = true, RALT   = true,
    LMETA  = true, RMETA  = true,
    UNKNOWN = true,
}

--- Boutons de souris qu'on accepte, sous le nom que leur donnent les liaisons.
--- Ni le gauche ni le droit : ils servent à ce bouton-ci, et les prendre
--- reviendrait à ne plus pouvoir cliquer dans le monde.
local MOUSE = {
    MiddleButton = "BUTTON3",
    Button4      = "BUTTON4",
    Button5      = "BUTTON5",
}

---@param key string
---@return string
local function withModifiers(key)
    local prefix = ""
    if IsAltKeyDown()     then prefix = prefix .. "ALT-"   end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-"  end
    if IsShiftKeyDown()   then prefix = prefix .. "SHIFT-" end
    return prefix .. key
end

---@param key string
---@return string
local function display(key)
    if key == "" then return L["Not bound"] end
    if type(GetBindingText) == "function" then
        local ok, text = pcall(GetBindingText, key)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return key
end

--- Ligne « libellé + bouton de touche ».
---@param parent table
---@param opts BUI.KeyBindOpts
---@return table row
function W.KeyBind(parent, opts)
    local row = W.Row(parent, opts.text, opts.indent)

    local button = CreateFrame("Button", nil, row, T.Template("BUTTON"))
    button:SetSize(T.SIZE.CONTROL_W, T.SIZE.ROW_H - 2)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    W.PlaceControl(row, button)

    local listening = false

    local function stop()
        listening = false
        button:EnableKeyboard(false)
        button:SetScript("OnKeyDown", nil)
        button:SetScript("OnMouseDown", nil)
        row:Refresh()
    end

    local function take(key)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        stop()
        opts.set(key)
        row:Refresh()
    end

    local function listen()
        listening = true
        button:SetText(L["Press a key"])
        button:EnableKeyboard(true)

        -- La touche s'arrête ici, sans quoi elle ferait aussi ce qu'elle fait
        -- d'habitude — Échap fermerait la fenêtre d'options. C'est le
        -- comportement par défaut d'une frame qui écoute le clavier : on ne
        -- l'écrit pas, `SetPropagateKeyboardInput` étant refusé en combat.
        button:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then
                stop()
                return
            end
            if MODIFIERS[key] then return end
            take(withModifiers(key))
        end)

        button:SetScript("OnMouseDown", function(_, mouseButton)
            local key = MOUSE[mouseButton]
            if key then take(withModifiers(key)) end
        end)
    end

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if listening then stop() end
            take("")
            return
        end
        if listening then
            stop()
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            listen()
        end
    end)

    -- Une fenêtre fermée en pleine écoute n'écoute plus : sans quoi la
    -- prochaine touche frappée en jeu serait prise ici, sans qu'on le voie.
    button:SetScript("OnHide", function()
        if listening then stop() end
    end)

    row:EnableMouse(true)
    W.Tooltip(row, opts.text, opts.tooltip)
    W.Tooltip(button, opts.text, opts.tooltip)

    function row:Refresh()
        if listening then return end
        local key = opts.get()
        button:SetText(display(type(key) == "string" and key or ""))
    end

    row:Refresh()
    return row
end
