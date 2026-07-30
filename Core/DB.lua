-- =========================================================================
--  OneUI — Core/DB.lua
--  Réglages persistants.
--
--  Forme du SavedVariables (compte) :
--      OneUIDB = {
--          schema   = 1,
--          profiles = { ["Default"] = { modules = { Quest = { autoAccept = true } } } },
--      }
--
--  Forme du SavedVariables (personnage) :
--      OneUICharDB = { profile = "Default" }
--
--  Deux invariants tenus par ce fichier :
--    1. Les valeurs par défaut ne sont **jamais** écrites sur le disque. Elles
--       sont fusionnées en mémoire à la connexion et retirées à la déconnexion.
--       Le fichier ne contient donc que les choix explicites de l'utilisateur,
--       et changer un défaut dans le code change le comportement de tout le
--       monde sans migration.
--    2. Un module lit et écrit toujours via ce fichier, jamais directement dans
--       le global.
-- =========================================================================

local _, ns = ...
local BUI = ns.BUI
local U   = BUI.Util

local DB = {}
BUI.DB = DB

local SCHEMA_VERSION   = 1
local DEFAULT_PROFILE  = "Default"

--- moduleName -> table de défauts (référence, pas une copie)
local defaultsRegistry = {}

local initialized = false

-- =========================================================================
--  Accès interne
-- =========================================================================

local function profileName()
    return (OneUICharDB and OneUICharDB.profile) or DEFAULT_PROFILE
end

local function profileTable()
    local name = profileName()
    local profiles = OneUIDB.profiles
    if not profiles[name] then
        profiles[name] = { modules = {} }
    elseif not profiles[name].modules then
        profiles[name].modules = {}
    end
    return profiles[name]
end

local function moduleTable(moduleName)
    local modules = profileTable().modules
    if not modules[moduleName] then modules[moduleName] = {} end
    return modules[moduleName]
end

--- (Re)fusionne les défauts de tous les modules connus dans le profil actif.
local function applyAllDefaults()
    for moduleName, defaults in pairs(defaultsRegistry) do
        U.MergeDefaults(moduleTable(moduleName), defaults)
    end
end

-- =========================================================================
--  Cycle de vie
-- =========================================================================

--- Appelé sur ADDON_LOADED de notre addon, donc avant PLAYER_LOGIN.
function DB:Initialize()
    if initialized then return end

    OneUIDB     = OneUIDB     or {}
    OneUICharDB = OneUICharDB or {}

    OneUIDB.profiles = OneUIDB.profiles or {}
    OneUIDB.schema   = OneUIDB.schema   or SCHEMA_VERSION

    if not OneUICharDB.profile then
        OneUICharDB.profile = DEFAULT_PROFILE
    end

    self:RunMigrations()
    applyAllDefaults()

    initialized = true
end

--- Point d'entrée unique des migrations de schéma.
--- Chaque palier est idempotent et fait progresser `schema` d'exactement un.
--- Ne jamais modifier un palier déjà publié : en ajouter un nouveau.
function DB:RunMigrations()
    local from = OneUIDB.schema or SCHEMA_VERSION

    -- if from < 2 then
    --     ... transformation ...
    --     from = 2
    -- end

    OneUIDB.schema = math.max(from, SCHEMA_VERSION)
end

--- Retire les valeurs égales aux défauts juste avant l'écriture du fichier.
local function onLogout()
    if not initialized then return end
    for _, profile in pairs(OneUIDB.profiles) do
        if profile.modules then
            for moduleName, settings in pairs(profile.modules) do
                local defaults = defaultsRegistry[moduleName]
                if defaults then U.StripDefaults(settings, defaults) end
                if not next(settings) then profile.modules[moduleName] = nil end
            end
        end
    end
end

BUI:RegisterEvent("PLAYER_LOGOUT", onLogout)

-- =========================================================================
--  Défauts
-- =========================================================================

--- Déclare les défauts d'un module. Appelé par Core/Module.lua ; un module ne
--- l'appelle pas lui-même.
---@param moduleName string
---@param defaults table
function DB:RegisterDefaults(moduleName, defaults)
    defaultsRegistry[moduleName] = defaults
    if initialized then
        U.MergeDefaults(moduleTable(moduleName), defaults)
    end
end

---@param moduleName string
---@return table|nil
function DB:GetDefaults(moduleName)
    return defaultsRegistry[moduleName]
end

-- =========================================================================
--  Lecture / écriture
-- =========================================================================

--- Table de réglages d'un module dans le profil actif.
---@param moduleName string
---@return table
function DB:Module(moduleName)
    return moduleTable(moduleName)
end

---@param moduleName string
---@param key string
---@return any
function DB:Get(moduleName, key)
    return moduleTable(moduleName)[key]
end

--- Écrit un réglage et notifie. C'est le seul chemin d'écriture autorisé :
--- il garantit que l'UI et le module concerné sont prévenus.
---@param moduleName string
---@param key string
---@param value any
function DB:Set(moduleName, key, value)
    local settings = moduleTable(moduleName)
    if settings[key] == value then return end
    settings[key] = value
    BUI:SendMessage(BUI.MESSAGES.SETTING_CHANGED, moduleName, key, value)
end

--- Remet un module à ses défauts.
---@param moduleName string
function DB:ResetModule(moduleName)
    local settings = moduleTable(moduleName)
    wipe(settings)
    local defaults = defaultsRegistry[moduleName]
    if defaults then U.MergeDefaults(settings, defaults) end
    BUI:SendMessage(BUI.MESSAGES.SETTING_CHANGED, moduleName, nil, nil)
end

-- =========================================================================
--  Profils
-- =========================================================================

---@return string
function DB:GetProfileName()
    return profileName()
end

---@return string[]
function DB:ListProfiles()
    return U.SortedKeys(OneUIDB.profiles)
end

--- Bascule le personnage courant sur un profil (créé s'il n'existe pas).
---@param name string
function DB:SetProfile(name)
    if type(name) ~= "string" or name == "" then return end
    if not OneUIDB.profiles[name] then
        OneUIDB.profiles[name] = { modules = {} }
    end
    OneUICharDB.profile = name
    applyAllDefaults()
    BUI:SendMessage(BUI.MESSAGES.PROFILE_CHANGED, name)
end

--- Duplique le profil actif sous un nouveau nom, sans y basculer.
---@param name string
---@return boolean created
function DB:CopyProfileTo(name)
    if type(name) ~= "string" or name == "" then return false end
    if OneUIDB.profiles[name] then return false end
    OneUIDB.profiles[name] = U.DeepCopy(profileTable())
    return true
end

---@param name string
---@return boolean deleted
function DB:DeleteProfile(name)
    if name == profileName() then return false end          -- jamais le profil actif
    if not OneUIDB.profiles[name] then return false end
    OneUIDB.profiles[name] = nil
    return true
end
