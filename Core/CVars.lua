-- =========================================================================
--  OneUI — Core/CVars.lua
--  Le prêt de CVars : un module emprunte un réglage du client, et le rend.
--
--  Chaque module qui prenait la main sur une CVar gardait jusqu'ici l'ancienne
--  valeur dans une table à lui, en mémoire. Ça suffit tant qu'un seul module
--  touche une CVar donnée, et qu'il la rend dans la même session. Deux cas
--  cassent ce motif, et la pêche et les scintillements les réunissent :
--
--  1. **Deux modules sur la même CVar.** Tous deux veulent `SoftTargetInteract`.
--     Chacun gardant « l'avant » pour soi, le second retiendrait la valeur du
--     premier comme celle d'origine, et la rendrait — le réglage du joueur
--     serait perdu au premier aller-retour.
--  2. **Un `/reload` pendant le prêt.** La pêche monte les effets sonores le
--     temps d'une prise. Un rechargement à ce moment efface la mémoire, et le
--     son reste monté pour toujours.
--
--  D'où un seul prêteur, qui **écrit** ce qu'il prête : l'origine de chaque
--  CVar, et qui l'emprunte à quelle valeur. Le registre vit au compte
--  (`DB:AccountData`), comme la plupart des CVars qu'il couvre — le son et le
--  graphisme se règlent au compte, pas au personnage.
--
--  ## Les règles
--
--  - L'origine est relevée **au premier emprunt**, jamais au suivant : c'est ce
--    qui règle le cas 1.
--  - La CVar porte la valeur du **dernier** emprunt en date. Quand celui-ci est
--    rendu et qu'il reste des emprunteurs, l'un d'eux reprend la main ; quand il
--    n'en reste plus, l'origine revient.
--  - **Un changement venu d'ailleurs devient la nouvelle origine.** Le joueur qui
--    bouge son volume pendant la pêche a choisi un volume : c'est lui qu'on rend
--    à la fin, pas celui d'avant. Un emprunt `hold` reprend en plus la main sur
--    ce changement — c'est le cas d'un préréglage graphique qui écrase tout d'un
--    coup, et derrière lequel il faut repasser.
--  - Une CVar que ce client ne connaît pas ne s'emprunte pas (règle 1 — un test
--    de capacité, pas un pari sur le client).
--  - À la connexion, ce qu'un module **éteint** tient encore est rendu : un
--    plantage du jeu ne rend rien, et le prochain démarrage rattrape.
-- =========================================================================

local _, ns = ...
local OUI = ns.OUI
local U   = OUI.Util

local CVars = {}
OUI.CVars = CVars

--- Espace du registre dans les données au compte. Ce n'est pas un module : le
--- nom ne peut entrer en collision avec aucun, il commence par un souligné.
local STORE = "_CVarLoans"

--- Écart en deçà duquel deux valeurs numériques sont la même : le client rend
--- « 1.000000 » là où l'on a écrit « 1 ».
local EPSILON = 0.001

--- nom de CVar -> { original = valeur d'avant, by = { [emprunteur] = valeur },
--- last = dernier emprunteur, hold = { [emprunteur] = true } }
---@return table
local function store()
    return OUI.DB:AccountData(STORE)
end

---@param a any
---@param b any
---@return boolean
local function same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < EPSILON end
    return tostring(a) == tostring(b)
end

--- Écrit une valeur si elle diffère : le client annonce chaque écriture, et une
--- écriture inutile réveillerait tous ceux qui l'écoutent.
---@param name string
---@param value any
local function write(name, value)
    if same(U.GetCVar(name), value) then return end
    pcall(U.SetCVar, name, value)
end

--- L'emprunteur qui tient la CVar quand le dernier en date l'a rendue : le
--- premier par ordre de nom, pour que le choix ne dépende pas du hasard d'une
--- table.
---@param loan table
---@return string|nil
local function anyOwner(loan)
    local keys = U.SortedKeys(loan.by)
    return keys[1]
end

-- =========================================================================
--  Emprunter, rendre
-- =========================================================================

--- Emprunte `name` pour `owner`, à la valeur `value`.
---@param owner string   nom du module emprunteur
---@param name string
---@param value any
---@param hold? boolean  reprendre la main quand quelqu'un d'autre l'écrase
---@return boolean  faux si ce client ne connaît pas la CVar
function CVars:Lend(owner, name, value, hold)
    local current = U.GetCVar(name)
    if current == nil then return false end

    value = tostring(value)
    local loans = store()
    local loan = loans[name]
    if type(loan) ~= "table" or type(loan.by) ~= "table" or type(loan.hold) ~= "table" then
        loan = { original = current, by = {}, hold = {} }
        loans[name] = loan
    end

    loan.by[owner]   = value
    loan.hold[owner] = hold and true or nil
    loan.last        = owner
    write(name, value)
    return true
end

--- Rend `name`. Sans effet si `owner` ne l'empruntait pas.
---@param owner string
---@param name string
function CVars:Return(owner, name)
    local loans = store()
    local loan = loans[name]
    if not (type(loan) == "table" and type(loan.by) == "table"
            and loan.by[owner] ~= nil) then
        return
    end

    loan.by[owner] = nil
    if type(loan.hold) == "table" then loan.hold[owner] = nil end

    local heir = anyOwner(loan)
    if heir then
        loan.last = heir
        write(name, loan.by[heir])
        return
    end

    loans[name] = nil
    if type(loan.original) == "string" then
        write(name, loan.original)
    end
end

--- Rend tout ce que `owner` emprunte.
---@param owner string
function CVars:ReturnAll(owner)
    local names = {}
    for name, loan in pairs(store()) do
        if type(loan) == "table" and type(loan.by) == "table" and loan.by[owner] ~= nil then
            names[#names + 1] = name
        end
    end
    for i = 1, #names do self:Return(owner, names[i]) end
end

-- =========================================================================
--  Ce qui vient d'ailleurs
-- =========================================================================

--- Repasse les emprunts `hold` qu'on a écrasés. Hors combat : certains réglages
--- graphiques refusent de s'écrire en combat, et le rater laisserait le joueur
--- sans ce qu'il a coché jusqu'au prochain changement.
local waitingCombat = false

local function reapply()
    if InCombatLockdown() then
        if not waitingCombat then
            waitingCombat = true
            OUI:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                waitingCombat = false
                reapply()
            end)
        end
        return
    end

    for name, loan in pairs(store()) do
        if type(loan) == "table" and loan.last and loan.hold and loan.hold[loan.last] then
            write(name, loan.by[loan.last])
        end
    end
end

--- Relit les CVars prêtées, et prend acte de celles qui ne portent plus ce
--- qu'on leur prête.
---
--- **Toutes, à chaque annonce, et pas celle que l'annonce nomme.** Le premier
--- argument de `CVAR_UPDATE` s'appelle `eventName` dans la documentation du
--- client, et ce n'est pas toujours le nom de la CVar. Il y en a une poignée à
--- relire : se passer de lui ne coûte rien, s'y fier pourrait tout manquer.
local function audit()
    local overridden = false

    for name, loan in pairs(store()) do
        if type(loan) == "table" and loan.last then
            local value = U.GetCVar(name)
            -- Le client annonce aussi nos propres écritures : une valeur égale à
            -- celle qu'on prête est la nôtre.
            if value ~= nil and not U.IsSecret(value)
               and not same(value, loan.by[loan.last]) then
                loan.original = tostring(value)
                if loan.hold and loan.hold[loan.last] then overridden = true end
            end
        end
    end

    if overridden then reapply() end
end

-- =========================================================================
--  À la connexion
-- =========================================================================
-- Les modules s'allument à `PLAYER_LOGIN` (voir `Core/Module.lua`) ; le
-- rattrapage passe juste après, quand chacun a repris ce qu'il voulait garder.

OUI:RegisterEventOnce("PLAYER_LOGIN", function()
    -- Un préréglage graphique écrit ses CVars en rafale : on relit une fois la
    -- rafale retombée, pas à chaque écriture. Branché ici et non au chargement
    -- du fichier : le thème, qui porte ce délai, charge après `Core/`.
    OUI:RegisterEvent("CVAR_UPDATE", U.Debounce(OUI.Theme.TIMING.CVAR_SETTLE, audit))

    C_Timer.After(0, function()
        local owners = {}
        for _, loan in pairs(store()) do
            if type(loan) == "table" and type(loan.by) == "table" then
                for owner in pairs(loan.by) do owners[owner] = true end
            end
        end

        for owner in pairs(owners) do
            local mod = OUI.Modules:Get(owner)
            if not (mod and mod._active) then CVars:ReturnAll(owner) end
        end
    end)
end)
