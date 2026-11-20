-- ForeverRotation – Blizzard-Cooldown-Manager (CDM) als Datenquelle im Kampf.
--
-- Im Kampf sind Auren und Cooldown-Zeiten geheim. Zwei Wege liefern trotzdem ja/nein:
--   1. Der Cooldown-Manager (Edit Mode) zeigt Auren an. Ob ein Symbol eine aktive Aura hat,
--      ist lesbar (gemessen 17.11.): Zauber-Symbole mit Aura (z. B. Siegel) liefern
--      GetAuraDataUnit() = "player" und zeigen in GetSpellID() den aktiven Zauber
--      (ohne Siegel: Platzhalter "Seals"). Buff-Symbole: isActive + sichtbar.
--      Stapeltext: nil = 0–1 Stapel, geheim = ab 2.
--   2. Cooldown-Trick (aus MaxDps): Dauer-Objekt in ein verstecktes Cooldown-Frame geben und
--      nur IsShown() lesen. Die Restzeit bleibt geheim, "läuft noch / ist frei" nicht.
--      Wird außerhalb des Kampfs gegen die echten Werte geprüft und erst danach genutzt.

local _, ns = ...
local safe, isSecret, getField = ns.safe, ns.isSecret, ns.getField

local CDM = {}
ns.CDM = CDM

local VIEWERS = {
    { name = "EssentialCooldownViewer", kind = "spell" },
    { name = "UtilityCooldownViewer",   kind = "spell" },
    { name = "BuffIconCooldownViewer",  kind = "buff" },
    { name = "BuffBarCooldownViewer",   kind = "buff" },
}

local active = {}    -- [Schlüssel] = true: Aura liegt gerade
local tracked = {}   -- [Schlüssel] = true: Zustand bekannt (also "nicht aktiv" heißt wirklich aus)
local stacks = {}    -- [Schlüssel] = Stapel (2 = "ab 2", siehe atLeast)
local atLeast = {}   -- [Schlüssel] = true: Stapelzahl ist geheim, nur "mindestens" bekannt
local seenOnItem = setmetatable({}, { __mode = "k" })   -- [Symbol] = { [Schlüssel] = true }
local infoCache = {} -- [cooldownID] = { Schlüssel, ... }
local lastScan = -1

local function keyOfId(id)
    if type(id) ~= "number" or isSecret(id) then return nil end
    local n = safe(C_Spell.GetSpellName, id)
    return n and ns:KeyOf(n) or nil
end

local function itemsOf(viewer)
    if type(viewer) ~= "table" or type(viewer.GetItemFrames) ~= "function" then return nil end
    local ok, a = pcall(viewer.GetItemFrames, viewer)
    if not ok or type(a) ~= "table" then return nil end
    if a.GetObjectType then return { a } end   -- einzelnes Symbol statt Liste
    return a
end

-- Zauber hinter einem Buff-Symbol über die Cooldown-ID (statische Daten, im Kampf lesbar).
local function infoKeys(item)
    local cid = rawget(item, "cooldownID")
    if cid == nil and type(item.GetCooldownID) == "function" then cid = safe(item.GetCooldownID, item) end
    if type(cid) ~= "number" or isSecret(cid) then return nil end
    local keys = infoCache[cid]
    if keys then return keys end
    local getInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local info = type(getInfo) == "function" and safe(getInfo, cid)
    if type(info) ~= "table" then return nil end
    keys = {}
    local function add(id)
        local k = keyOfId(id)
        if k then keys[#keys + 1] = k end
    end
    add(getField(info, "spellID"))
    keys.base = keys[1]   -- Grundzauber des Symbols (beim Siegel der Platzhalter "Seals")
    add(getField(info, "overrideSpellID"))
    add(getField(info, "overrideTooltipSpellID"))
    local linked = getField(info, "linkedSpellIDs")
    if type(linked) == "table" then
        for _, id in ipairs(linked) do add(id) end
    end
    infoCache[cid] = keys
    return keys
end

-- Stapel aus dem Text im Symbol: nil/"" = 0–1, geheim = ab 2, sonst die Zahl.
local function readStacks(item)
    if type(item.GetApplicationsFontString) ~= "function" then return 1, false end
    local ok, fs = pcall(item.GetApplicationsFontString, item)
    if not ok or type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 1, false end
    local okT, txt = pcall(fs.GetText, fs)
    if not okT then return 1, false end
    if isSecret(txt) then return 2, true end
    return tonumber(txt) or 1, false
end

local function mark(keys, on, n, more)
    for _, k in ipairs(keys) do
        tracked[k] = true
        if on then
            active[k] = true
            stacks[k], atLeast[k] = n, more
        end
    end
end

function CDM:Enabled()
    local cv = C_CVar and safe(C_CVar.GetCVar, "cooldownViewerEnabled")
    return cv ~= "0"
end

function CDM:Scan()
    local now = GetTime()
    if now - lastScan < 0.2 then return end
    lastScan = now
    wipe(active); wipe(tracked); wipe(stacks); wipe(atLeast)
    if not self:Enabled() then return end
    for _, v in ipairs(VIEWERS) do
        for _, item in ipairs(itemsOf(_G[v.name]) or {}) do
            if type(item) == "table" and item.GetObjectType then
                if v.kind == "spell" then
                    -- Zauber-Symbol: nur interessant, wenn es eine Aura anzeigt (Siegel)
                    if type(item.GetAuraDataUnit) == "function" then
                        local ok, unit = pcall(item.GetAuraDataUnit, item)
                        if ok and not isSecret(unit) then
                            -- Alle Zauber, die das Symbol abdeckt (Siegel-Symbol: alle Siegel, über die
                            -- Cooldown-ID; im Kampf lesbar). Dazu früher darauf gesehene Auren.
                            local cover = infoKeys(item) or {}
                            local seen = seenOnItem[item]
                            if unit == nil then
                                -- keine Aura auf dem Symbol: alles Abgedeckte ist sicher aus
                                mark(cover, false)
                                if seen then
                                    for k in pairs(seen) do tracked[k] = true end
                                end
                            elseif unit == "player" then
                                -- WELCHE Aura: nur lesbar, wenn sie vor dem Kampf gesetzt wurde. Im Kampf
                                -- neu gesetzt ist die Zauber-ID geheim -> "irgendeine liegt", also unbekannt.
                                local k1 = keyOfId(safe(item.GetSpellID, item))
                                local k2 = type(item.GetAuraSpellID) == "function"
                                    and keyOfId(safe(item.GetAuraSpellID, item)) or nil
                                local k = k2 or k1
                                -- Platzhalter ("Seals") sagt nicht, welche Aura liegt
                                if k and k == cover.base and #cover > 1 then k = nil end
                                if k then
                                    if not seen then seen = {}; seenOnItem[item] = seen end
                                    seen[k] = true
                                    mark(cover, false)
                                    if seen then
                                        for s in pairs(seen) do tracked[s] = true end
                                    end
                                    mark({ k }, true, readStacks(item))
                                end
                            end
                            -- unit "target": Aura auf dem Ziel (z. B. Betäubung) – kein eigener Buff
                        end
                    end
                else
                    local keys = infoKeys(item)
                    if keys then
                        local isActive = rawget(item, "isActive")
                        if not isSecret(isActive) then
                            local on = isActive == true and safe(item.IsShown, item) == true
                            if on then
                                mark(keys, true, readStacks(item))
                            else
                                mark(keys, false)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- true = aktiv, false = vom CDM verfolgt und sicher aus, nil = unbekannt
function CDM:State(key)
    self:Scan()
    if active[key] then return true end
    if tracked[key] then return false end
    return nil
end

-- Stapel einer verfolgten Aura: Zahl (0 = aus) und ob es nur "mindestens" ist; nil = unbekannt.
function CDM:Stacks(key)
    self:Scan()
    if active[key] then return stacks[key] or 1, atLeast[key] or false end
    if tracked[key] then return 0, false end
    return nil
end

-- Leisten/Symbole umgebaut: gemerkte Zuordnungen verwerfen.
function CDM:Reset()
    wipe(infoCache)
    for k in pairs(seenOnItem) do seenOnItem[k] = nil end
    lastScan = -1
end

---------------------------------------------------------------------------
-- Cooldown-Trick: läuft der Cooldown (ja/nein), auch im Kampf.
---------------------------------------------------------------------------

local scratch            -- verstecktes Cooldown-Frame; false = nicht verfügbar
local passGCDFlag = true -- GetSpellCooldownDuration(id, true) = ohne GCD (falls unterstützt)

local check = { agree = 0, disagree = 0, onAgree = 0, offAgree = 0, gcdAgree = 0, gcdDisagree = 0 }
CDM.cdCheck = check

local function getScratch()
    if scratch ~= nil then return scratch end
    scratch = false
    if not (C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function") then return scratch end
    local ok, f = pcall(CreateFrame, "Cooldown", nil, UIParent, "CooldownFrameTemplate")
    if not ok or type(f) ~= "table" or type(f.SetCooldownFromDurationObject) ~= "function" then return scratch end
    f:SetSize(1, 1)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -20, 20)
    f:SetAlpha(0)
    if f.SetDrawBling then f:SetDrawBling(false) end
    if f.SetDrawEdge then f:SetDrawEdge(false) end
    -- kein Hide(): Das Frame zeigt/versteckt sich selbst je nach Cooldown – genau das wird gelesen
    scratch = f
    return scratch
end

-- true = Cooldown läuft, false = frei, nil = nicht feststellbar
function CDM:OnCooldown(spellID)
    local f = getScratch()
    if not f or type(spellID) ~= "number" then return nil end
    local ok, obj
    if passGCDFlag then
        ok, obj = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
        if not ok then passGCDFlag = false end
    end
    if not passGCDFlag then ok, obj = pcall(C_Spell.GetSpellCooldownDuration, spellID) end
    if not ok or obj == nil then return nil end
    local result
    if pcall(f.SetCooldownFromDurationObject, f, obj) then
        local okS, shown = pcall(f.IsShown, f)
        if okS and not isSecret(shown) then result = shown == true end
    end
    pcall(f.SetCooldown, f, 0, 0)   -- zurücksetzen (wie MaxDps)
    return result
end

-- Nur nutzen, wenn der Trick außerhalb des Kampfs zuverlässig mit den echten Werten übereinstimmte.
function CDM:CooldownTrusted()
    return check.onAgree >= 2 and check.offAgree >= 3 and check.disagree * 20 <= check.agree
end

-- Blendet der Trick den GCD aus? (gemessen 18.11.: ja, mit GetSpellCooldownDuration(id, true))
-- Dann darf auch während des GCD geprüft werden.
function CDM:IgnoresGCD()
    return passGCDFlag and check.gcdAgree >= 2 and check.gcdDisagree == 0
end

-- Außerhalb des Kampfs: Trick gegen den echten Cooldown halten (duration lesbar).
local lastCalib = -1
function CDM:Calibrate(spells)
    if InCombatLockdown() then return end
    local now = GetTime()
    if now - lastCalib < 1 then return end
    lastCalib = now
    for _, sp in pairs(spells) do
        if sp.known and sp.id then
            local info = safe(C_Spell.GetSpellCooldown, sp.id)
            local duration = getField(info, "duration")
            local expected
            if duration == 0 then expected = false elseif type(duration) == "number" and duration > 1.6 then expected = true end
            if type(duration) == "number" and duration > 0 and duration <= 1.6 and getField(info, "isOnGCD") == true then
                -- nur der GCD läuft: Der Trick sollte "frei" melden
                local got = self:OnCooldown(sp.id)
                if got == false then check.gcdAgree = check.gcdAgree + 1
                elseif got == true then check.gcdDisagree = check.gcdDisagree + 1 end
            end
            if expected ~= nil then
                local got = self:OnCooldown(sp.id)
                if got ~= nil then
                    if got == expected then
                        check.agree = check.agree + 1
                        if expected then check.onAgree = check.onAgree + 1 else check.offAgree = check.offAgree + 1 end
                    else
                        check.disagree = check.disagree + 1
                    end
                end
            end
        end
    end
end
