-- =========================================================================
--  OneUI — Modules/Quest.lua
--  Quêtes : acceptation et rendu automatiques, et l'XP des quêtes terminées
--  montrée sur la barre d'XP du client.
--
--  Le module ne dessine rien : le vert de la barre d'XP est posé par
--  `UI/Widgets/QuestXPFill.lua`, qui reçoit le total calculé ici.
--
--  Réversibilité : les abonnements passent par `self:RegisterEvent`, le
--  crochet de taille par `U.GuardedScript` ; `OnDisable` cache le vert.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local T    = OUI.Theme
local U    = OUI.Util
local W    = OUI.Widgets
local L    = ns.L

local MODULE = "Quest"

-- =========================================================================
--  Garde-fous communs
-- =========================================================================

--- L'automatisation est-elle suspendue à cet instant ?
--- Deux raisons possibles : la touche de contournement est maintenue, ou le
--- joueur est en train de faire autre chose avec l'interface de quête.
---@param mod table
---@return boolean
local function suspended(mod)
    return U.IsModifierHeld(mod:Get("bypassModifier"))
end

--- Faut-il laisser cette quête tranquille parce qu'elle est triviale ?
---@param mod table
---@param isTrivial boolean|nil
---@return boolean
local function skipBecauseTrivial(mod, isTrivial)
    return mod:Get("skipTrivial") and isTrivial == true
end

-- =========================================================================
--  Acceptation
-- =========================================================================

local function onQuestDetail(mod)
    if not mod:Get("autoAccept") or suspended(mod) then return end

    local questID = GetQuestID and GetQuestID() or nil
    if questID and questID ~= 0 and C_QuestLog and C_QuestLog.IsQuestTrivial then
        if skipBecauseTrivial(mod, C_QuestLog.IsQuestTrivial(questID)) then return end
    end

    AcceptQuest()

    -- Une quête déclenchée par un objet ou par une zone s'accepte sans PNJ :
    -- la fenêtre reste alors ouverte et il faut la refermer nous-mêmes.
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        CloseQuest()
    end
end

--- Quêtes qui demandent une confirmation supplémentaire (escortes, quêtes de
--- groupe déjà prises par un coéquipier).
local function onQuestAcceptConfirm(mod)
    if not mod:Get("autoAccept") or suspended(mod) then return end
    ConfirmAcceptQuest()
end

-- =========================================================================
--  Rendu
-- =========================================================================

local function onQuestProgress(mod)
    if not mod:Get("autoTurnIn") or suspended(mod) then return end
    if IsQuestCompletable and IsQuestCompletable() then
        CompleteQuest()
    end
end

local function onQuestComplete(mod)
    if not mod:Get("autoTurnIn") or suspended(mod) then return end

    -- Dès qu'il y a un vrai choix de récompense, on rend la main au joueur :
    -- prendre la récompense à sa place serait irréversible.
    if GetNumQuestChoices and GetNumQuestChoices() > 1 then return end

    GetQuestReward(1)
end

-- =========================================================================
--  Dialogues de PNJ
-- =========================================================================

--- Interface de dialogue moderne (`C_GossipInfo`).
local function onGossipShow(mod)
    if suspended(mod) then return end
    if not C_GossipInfo then return end

    if mod:Get("autoTurnIn") and C_GossipInfo.GetActiveQuests then
        for _, info in ipairs(C_GossipInfo.GetActiveQuests()) do
            if info.isComplete and not skipBecauseTrivial(mod, info.isTrivial) then
                C_GossipInfo.SelectActiveQuest(info.questID)
                return -- une seule interaction par ouverture : le client
                       -- renvoie GOSSIP_SHOW après chaque sélection
            end
        end
    end

    if mod:Get("autoAccept") and C_GossipInfo.GetAvailableQuests then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests()) do
            if not skipBecauseTrivial(mod, info.isTrivial) then
                C_GossipInfo.SelectAvailableQuest(info.questID)
                return
            end
        end
    end
end

--- Ancienne interface de salutation, encore utilisée par certains PNJ.
local function onQuestGreeting(mod)
    if suspended(mod) then return end

    if mod:Get("autoTurnIn") then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            local isTrivial = IsActiveQuestTrivial and IsActiveQuestTrivial(i)
            if isComplete and not skipBecauseTrivial(mod, isTrivial) then
                SelectActiveQuest(i)
                return
            end
        end
    end

    if mod:Get("autoAccept") then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial = IsAvailableQuestTrivial and IsAvailableQuestTrivial(i)
            if not skipBecauseTrivial(mod, isTrivial) then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

-- =========================================================================
--  L'XP des quêtes terminées, sur la barre d'XP
-- =========================================================================

--- Le total de XP que rapporteraient les quêtes du journal prêtes à rendre.
---
--- **Par identifiant de quête**, jamais par la quête sélectionnée :
--- `GetQuestLogRewardXP` sans argument lit la quête ouverte dans le journal,
--- et la sélectionner pour la lire changerait ce que le joueur regarde.
---
--- Une quête **prête à rendre**, pas seulement « complète » : `ReadyForTurnIn`
--- d'abord, `IsComplete` à défaut — un client qui n'aurait que le second dit
--- la même chose pour une quête du journal.
---@return number
local function completedQuestXP()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        return 0
    end
    if type(GetQuestLogRewardXP) ~= "function" then return 0 end

    local ready = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete
    if type(ready) ~= "function" then return 0 end

    local total = 0
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info    = C_QuestLog.GetInfo(index)
        local questID = info and not U.IsTrue(info.isHeader) and info.questID

        if type(questID) == "number" and not U.IsSecret(questID)
           and U.IsTrue(ready(questID)) then
            local xp = GetQuestLogRewardXP(questID)
            if type(xp) == "number" and not U.IsSecret(xp) and xp > 0 then
                total = total + xp
            end
        end
    end
    return total
end

---@param mod table
local function applyQuestXP(mod)
    if not (mod:IsEnabled() and mod:Get("questXPBar")) then
        W.QuestXPFill.Hide()
        return
    end
    W.QuestXPFill.Show(completedQuestXP())
end

--- Le journal annonce ses changements en rafale : un seul calcul par rafale
--- (règle 7).
local queueQuestXP = U.Debounce(T.TIMING.QUEST_XP_SETTLE, function()
    local mod = OUI.Modules:Get(MODULE)
    if mod then applyQuestXP(mod) end
end)

-- =========================================================================
--  XP par heure
-- =========================================================================
-- Moyenne de la session : l'XP gagnée depuis la connexion (ou le dernier
-- `/reload`), divisée par le temps écoulé. Le temps avant le niveau suivant
-- en découle. Un niveau franchi compte ce qui restait à faire au niveau
-- d'avant, puis ce qui est déjà fait au nouveau.

local session = {}

--- L'XP du joueur et le maximum du niveau, ou rien quand le client les tait.
---@return number|nil xp, number|nil max
local function readXP()
    local xp, max = UnitXP("player"), UnitXPMax("player")
    if type(xp) ~= "number" or type(max) ~= "number" then return nil, nil end
    if U.IsSecret(xp) or U.IsSecret(max) then return nil, nil end
    return xp, max
end

---@return boolean
local function atMaxLevel()
    if IsPlayerAtEffectiveMaxLevel then return U.IsTrue(IsPlayerAtEffectiveMaxLevel()) end
    if GetMaxPlayerLevel then return UnitLevel("player") >= GetMaxPlayerLevel() end
    return false
end

local function startSession()
    session.start  = GetTime()
    session.gained = 0
    session.xp, session.max = readXP()
    session.level  = UnitLevel("player")
end

--- L'XP a bougé : ajoute ce qui a été gagné depuis la dernière lecture.
local function countXP()
    local xp, max = readXP()
    if not xp then return end

    local level = UnitLevel("player")
    if session.xp and session.max then
        if level > (session.level or level) then
            session.gained = session.gained + (session.max - session.xp) + xp
        elseif xp > session.xp then
            session.gained = session.gained + (xp - session.xp)
        end
    end
    session.xp, session.max, session.level = xp, max, level
end

---@param value number
---@return string
local function formatNumber(value)
    local whole = math.floor(value + 0.5)
    if whole < 1000 then return tostring(whole) end

    -- 1 000 → « 1k », 48 250 → « 48,3k », 1 200 000 → « 1,2M ».
    local unit, scaled = L["Thousands"], whole / 1000
    if whole >= 1000000 then unit, scaled = L["Millions"], whole / 1000000 end
    local text = ("%.1f"):format(scaled):gsub("%.0$", ""):gsub("%.", L["Decimal separator"])
    return unit:format(text)
end

---@param seconds number
---@return string
local function formatDuration(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes < 60 then return L["Duration minutes"]:format(minutes) end
    return L["Duration hours"]:format(math.floor(minutes / 60), minutes % 60)
end

--- Lignes du bloc, réemployées (règle 7).
local rateLines, ratePieces = {}, {}

---@param line number
---@param label string
---@param value string
local function rateLine(line, label, value)
    local pieces = ratePieces[line] or {}
    ratePieces[line] = pieces
    pieces[1] = L["Stat line"]:format(T.COLOR.NORMAL:WrapTextInColorCode(label), value)
    rateLines[line] = pieces
end

---@return table
local function collectRate()
    wipe(rateLines)
    if atMaxLevel() or not session.start then return rateLines end

    local xp, max = readXP()
    if not xp then return rateLines end

    local elapsed = GetTime() - session.start
    local perHour = elapsed > 0 and session.gained / elapsed * 3600 or 0

    if perHour <= 0 then
        rateLine(1, L["XP per hour"], L["XP rate waiting"])
        rateLine(2, L["Time to level"], L["XP rate waiting"])
        return rateLines
    end

    rateLine(1, L["XP per hour"], formatNumber(perHour))
    rateLine(2, L["Time to level"], formatDuration((max - xp) / perHour * 3600))
    return rateLines
end

local rateBlock
---@type table|nil
local rateTicker

---@param mod table
local function applyRate(mod)
    if not (mod:IsEnabled() and mod:Get("showXPRate")) then
        if rateBlock then rateBlock:Stop() end
        if rateTicker then
            rateTicker:Cancel()
            rateTicker = nil
        end
        return
    end

    if not rateBlock then
        rateBlock = W.TextBlock({
            lines      = collectRate,
            isLocked   = function() return mod:Get("lockXPRate") == true end,
            isCentered = function() return mod:Get("centerXPRate") == true end,
            getPos     = function() return mod:Get("xpRateX"), mod:Get("xpRateY") end,
            setPos     = function(x, y)
                mod:Set("xpRateX", x)
                mod:Set("xpRateY", y)
            end,
            getScale   = function() return mod:Get("xpRateScale") end,
            setScale   = function(scale) mod:Set("xpRateScale", scale) end,
            button     = {
                texture = T.TEXTURE.TEXT_BLOCK_RESET,
                title   = L["Reset XP rate"],
                tooltip = L["Reset XP rate tip"],
                onClick = function()
                    startSession()
                    if rateBlock then rateBlock:Refresh() end
                end,
            },
        })
        if not rateBlock then return end
    end

    rateBlock:ApplyScale()
    rateBlock:ApplyLock()
    rateBlock:ApplyPosition()
    rateBlock:Refresh()

    -- La moyenne baisse aussi quand rien ne se passe : le bloc se relit à
    -- intervalle lent, et seulement tant qu'il est allumé (règle 7).
    if not rateTicker then
        rateTicker = C_Timer.NewTicker(T.TIMING.XP_RATE_TICK, function()
            if rateBlock then rateBlock:Refresh() end
        end)
    end
end

-- =========================================================================
--  Déclaration du module
-- =========================================================================

local MODIFIER_VALUES = {
    { value = "NONE",  label = L["None"] },
    { value = "SHIFT", label = L["Shift"] },
    { value = "CTRL",  label = L["Ctrl"] },
    { value = "ALT",   label = L["Alt"] },
}

OUI:RegisterModule(MODULE, {
    title    = L["Quest"],
    category = "QoL",
    order    = 30,

    defaults = {
        autoAccept     = false,
        autoTurnIn     = false,
        skipTrivial    = false,
        bypassModifier = "SHIFT",
        questXPBar     = false,

        showXPRate   = false,
        lockXPRate   = false,
        centerXPRate = false,
        -- Position et échelle du bloc : il se fait glisser, et sa taille se
        -- règle par son coin ou par la glissière.
        xpRateX      = 0,
        xpRateY      = 0,
        xpRateScale  = 1,
    },

    options = {
        { type = "header", text = L["Automation"] },
        {
            type    = "toggle",
            key     = "autoAccept",
            text    = L["Auto-accept quests"],
            tooltip = L["Auto-accept quests tip"],
        },
        {
            type    = "toggle",
            key     = "autoTurnIn",
            text    = L["Auto-turn-in quests"],
            tooltip = L["Auto-turn-in quests tip"],
        },

        { type = "header", text = L["Filters"] },
        {
            type    = "toggle",
            key     = "skipTrivial",
            text    = L["Skip trivial quests"],
            tooltip = L["Skip trivial quests tip"],
            -- Inutile tant qu'aucune automatisation n'est active.
            disabled = function()
                local mod = OUI.Modules:Get(MODULE)
                return not (mod:Get("autoAccept") or mod:Get("autoTurnIn"))
            end,
        },
        {
            type    = "dropdown",
            key     = "bypassModifier",
            text    = L["Bypass modifier"],
            tooltip = L["Bypass modifier tip"],
            values  = MODIFIER_VALUES,
        },

        { type = "header", text = L["Experience bar"] },
        {
            type    = "toggle",
            key     = "questXPBar",
            text    = L["Completed quests XP"],
            tooltip = L["Completed quests XP tip"],
        },
        {
            type    = "toggle",
            key     = "showXPRate",
            text    = L["Show XP rate"],
            tooltip = L["Show XP rate tip"],
        },
        {
            type     = "toggle",
            key      = "lockXPRate",
            edit     = "lock",
            text     = L["Lock profession levels"],
            tooltip  = L["Lock profession levels tip"],
            disabled = function()
                local mod = OUI.Modules:Get(MODULE)
                return not (mod and mod:Get("showXPRate"))
            end,
        },
        {
            type     = "toggle",
            key      = "centerXPRate",
            text     = L["Center on screen"],
            tooltip  = L["Center on screen tip"],
            disabled = function()
                local mod = OUI.Modules:Get(MODULE)
                return not (mod and mod:Get("showXPRate"))
            end,
        },
        {
            type     = "slider",
            key      = "xpRateScale",
            text     = L["Frame scale"],
            tooltip  = L["Frame scale tip"],
            min      = T.SIZE.TEXT_BLOCK_SCALE_MIN,
            max      = T.SIZE.TEXT_BLOCK_SCALE_MAX,
            step     = T.SIZE.FRAME_SCALE_STEP,
            decimals = 2,
            disabled = function()
                local mod = OUI.Modules:Get(MODULE)
                return not (mod and mod:Get("showXPRate"))
            end,
        },
    },

    OnEnable = function(self)
        applyQuestXP(self)

        startSession()
        applyRate(self)
        self:RegisterEvent("PLAYER_XP_UPDATE", function()
            countXP()
            if rateBlock and self:Get("showXPRate") then rateBlock:Refresh() end
        end)

        -- Une quête remplie, rendue, abandonnée ; l'XP qui bouge ; un niveau
        -- de plus, qui change le maximum de la barre.
        self:RegisterEvent("QUEST_LOG_UPDATE",     queueQuestXP)
        self:RegisterEvent("PLAYER_XP_UPDATE",     queueQuestXP)
        self:RegisterEvent("PLAYER_LEVEL_UP",      queueQuestXP)
        self:RegisterEvent("PLAYER_ENTERING_WORLD", queueQuestXP)

        -- La barre change de largeur avec la disposition (mode édition, barre
        -- d'action du bas) : le vert se remesure avec elle.
        for _, bar in ipairs(W.QuestXPFill.Bars()) do
            U.GuardedScript(bar.StatusBar, "OnSizeChanged", queueQuestXP, function()
                local mod = OUI.Modules:Get(MODULE)
                return mod ~= nil and mod:IsEnabled()
            end)
        end

        self:RegisterEvent("QUEST_DETAIL",         function() onQuestDetail(self) end)
        self:RegisterEvent("QUEST_ACCEPT_CONFIRM", function() onQuestAcceptConfirm(self) end)
        self:RegisterEvent("QUEST_PROGRESS",       function() onQuestProgress(self) end)
        self:RegisterEvent("QUEST_COMPLETE",       function() onQuestComplete(self) end)
        self:RegisterEvent("GOSSIP_SHOW",          function() onGossipShow(self) end)
        self:RegisterEvent("QUEST_GREETING",       function() onQuestGreeting(self) end)
    end,

    -- Le vert posé sur la barre d'XP se cache ; le reste — les abonnements,
    -- le crochet de taille rendu inerte — est défait par le core.
    OnDisable = function(self)
        W.QuestXPFill.Hide()
        applyRate(self)
    end,

    OnSettingChanged = function(self)
        applyQuestXP(self)
        applyRate(self)
    end,
})
