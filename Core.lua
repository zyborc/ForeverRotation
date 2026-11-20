-- ForeverRotation – Kern (klassenunabhängig).
--
-- Forever versteckt im Kampf Auren, Cooldown-Zeiten und Mana. Lesbar bleiben aber:
--   * eigene Casts (UNIT_SPELLCAST_SUCCEEDED mit Zauber-ID)
--   * Grund-Cooldown und GCD (GetSpellBaseCooldown)
--   * Nutzbarkeit / "nicht genug Mana" / Reichweite
--   * Ziel: Klassifizierung (elite), Kreaturtyp, Namensplaketten
-- Daraus baut der Kern einen "Schattenzustand": Cooldowns und eigene Buffs werden
-- selbst mitgezählt und außerhalb des Kampfs gegen die echten Werte abgeglichen.
--
-- Rotationen (Klasse + Spezialisierung) liegen in Rotations\*.lua und melden sich
-- über ns:RegisterRotation(def) an. Aufbau einer Definition: siehe Rotations\_Vorlage.md.

local ADDON_NAME, ns = ...
local L = ns.L   -- Texte: siehe Locale.lua (Schlüssel = deutscher Text)

ns.PREFIX = "|cffffcc00ForeverRotation|r: "

local isSecret = issecretvalue or function() return false end
ns.isSecret = isSecret

---------------------------------------------------------------------------
-- Sichere Aufrufe: geheime Werte werden zu nil, Fehler werden geschluckt.
---------------------------------------------------------------------------

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    if isSecret(a) then a = nil end
    if isSecret(b) then b = nil end
    if isSecret(c) then c = nil end
    if isSecret(d) then d = nil end
    return a, b, c, d
end
ns.safe = safe

local function getField(t, key)
    if type(t) ~= "table" or isSecret(t) then return nil end
    if issecrettable and issecrettable(t) then return nil end
    local ok, v = pcall(function() return t[key] end)
    if not ok or isSecret(v) then return nil end
    return v
end
ns.getField = getField

local function copyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

---------------------------------------------------------------------------
-- Sprache: Zauber werden intern mit englischem Schlüssel geführt ("Seal of Command")
-- und über ihre Zauber-ID in die Client-Sprache übersetzt. Texte laufen über L / T.
---------------------------------------------------------------------------

ns.SPELL_IDS = {}   -- [englischer Schlüssel] = Zauber-ID (beliebiger Rang), aus def.spellIds
local nameToKey = {} -- [Name in Client-Sprache] = englischer Schlüssel

-- Zaubername in der Client-Sprache
function ns:SpellName(key)
    local sp = self.spells and self.spells[key]
    if sp and sp.name then return sp.name end
    local id = self.SPELL_IDS[key]
    return (id and safe(C_Spell.GetSpellName, id)) or key
end

-- Alle Zauber aller Rotationen (Client-Sprache -> Schlüssel), z. B. für Gestalten,
-- die nicht in der aktiven Rotation vorkommen. Wird bei Bedarf einmal aufgebaut.
local allNames, allNamesCount = {}, -1

local function buildAllNames()
    local count = 0
    for _ in pairs(ns.SPELL_IDS) do count = count + 1 end
    if count == allNamesCount then return end
    wipe(allNames)
    for key, id in pairs(ns.SPELL_IDS) do
        local n = safe(C_Spell.GetSpellName, id)
        if n then allNames[n] = key end
    end
    allNamesCount = count
end

-- Name aus einem Ereignis (Client-Sprache) -> englischer Schlüssel
function ns:KeyOf(name)
    if nameToKey[name] then return nameToKey[name] end
    buildAllNames()
    return allNames[name] or name
end

-- Text übersetzen; {spell} = Zauber der Regel, {Seal of Command} = beliebiger Zauber
-- Fehlt eine Übersetzung, wird eine Vorlage gesucht: "{Battle Shout} halten" -> "{1} halten".
function ns:T(text, spell)
    if text == nil then return nil end
    text = tostring(text)
    local out = rawget(L, text)
    if not out and text:find("{", 1, true) then
        local tokens, n = {}, 0
        local tpl = text:gsub("{([^}]+)}", function(k)
            if k == "spell" then return "{spell}" end
            n = n + 1
            tokens[n] = k
            return "{" .. n .. "}"
        end)
        local t = rawget(L, tpl)
        if t then
            out = t:gsub("{(%d+)}", function(i) return "{" .. (tokens[tonumber(i)] or "?") .. "}" end)
        end
    end
    text = out or text
    if spell then text = (text:gsub("{spell}", function() return self:SpellName(spell) end)) end
    return (text:gsub("{([^}]+)}", function(k) return self:SpellName(k) end))
end

function ns:InInstance()
    local inInstance, kind = safe(IsInInstance)
    return inInstance and (kind == "party" or kind == "raid" or kind == "scenario") or false
end

function ns:RotLabel(def)
    return def and self:T(def.label) or L["keine"]
end

---------------------------------------------------------------------------
-- Rotations-Registrierung
---------------------------------------------------------------------------

ns.rotations = {}        -- [id] = def
ns.rotationOrder = {}    -- Reihenfolge der Registrierung

-- def-Felder (Pflicht: id, class, label, rules):
--   id          eindeutiger Schlüssel, z. B. "PALADIN_RETRIBUTION"
--   class       Klassen-Token aus UnitClass, z. B. "PALADIN"
--   spec        optional: Index aus C_SpecializationInfo.GetSpecialization()
--   label       Anzeigename
--   rangeSpell  Nahkampf-/Reichweitenzauber zum Zählen der Gegner
--   buffGroups  { gruppe = { spells = {...}, duration = Sekunden } }
--   extraSpells weitere Zauber, die nur in Bedingungen vorkommen
--   options     { name = { default = Wert, desc = "Text" } }
--   rules       Liste { spell = "Name", cond = function(s) ... end, reason = "Text" }
--   hooks       optional: onCast(name, s, custom), onReset(custom), onTargetChanged(custom)
--   role        "TANK", "DAMAGER" (Standard) oder "HEALER" – danach wählt der Kern automatisch
--   roleAura    optional: Buffs, die diese Rolle verraten (z. B. { "Righteous Fury" })
--   spellIds    { ["Englischer Name"] = Zauber-ID } – damit jede Client-Sprache funktioniert
--   procs       optional: { ["Zauber"] = { label = "Text", color = {r, g, b} } } – Proc-Hinweis
--   debuffs     optional: { gruppe = { spells = {...}, duration = Sekunden | function(combo) } }
--               eigene DoTs/Debuffs auf dem Ziel, pro Ziel mitgezählt (im Kampf geheim)
--   combo       optional: { builders = { ["Zauber"] = Punkte }, finishers = { "Zauber", ... }, max = 5 }
--               Combo-Punkte mitzählen, falls das Spiel sie im Kampf nicht verrät
--   forms       optional: Gestalten/Haltungen, die diese Rotation auswählen (z. B. { "Cat Form" })
--   roleForm    optional: Gestalten/Haltungen, die die Rolle verraten (z. B. { "Defensive Stance" })
--   signature   optional: Zauber (meist Talente), an denen die Spezialisierung erkannt wird
function ns:RegisterRotation(def)
    assert(def.id and def.class and def.label and def.rules, "RegisterRotation: id, class, label und rules sind Pflicht")
    def.role = def.role or "DAMAGER"
    def.buffGroups = def.buffGroups or {}
    def.options = def.options or {}
    def.hooks = def.hooks or {}
    def.extraSpells = def.extraSpells or {}
    def.debuffs = def.debuffs or {}
    for key, id in pairs(def.spellIds or {}) do self.SPELL_IDS[key] = id end
    for _, list in ipairs({ def.forms or {}, def.roleForm or {} }) do
        for _, n in ipairs(list) do self.FORM_SPELLS[n] = true end
    end
    -- Einträge für den Prioritäten-Editor: Regeln mit gleicher `group` bilden einen Eintrag
    -- (z. B. alle Aura-Regeln). Schlüssel: group > id > Zauber + Begründung.
    def.entries = {}
    local byKey = {}
    for i, rule in ipairs(def.rules) do
        rule.key = rule.group or rule.id or (rule.spell .. "|" .. (rule.reason or tostring(i)))
        local entry = byKey[rule.key]
        if not entry then
            entry = { key = rule.key, rules = {}, spells = {}, label = rule.groupLabel or rule.label }
            byKey[rule.key] = entry
            def.entries[#def.entries + 1] = entry
        end
        entry.rules[#entry.rules + 1] = rule
        entry.spells[#entry.spells + 1] = rule.spell
    end
    self.rotations[def.id] = def
    table.insert(self.rotationOrder, def.id)
end

-- Anzeigename eines Prioritäten-Eintrags in der Client-Sprache
function ns:EntryLabel(entry)
    local rule = entry.rules[1]
    if entry.label then return self:T(entry.label, rule.spell) end
    local name = self:SpellName(rule.spell)
    return rule.reason and (name .. " – " .. self:T(rule.reason, rule.spell)) or name
end

function ns:CandidatesForPlayer()
    local _, class = UnitClass("player")
    local list = {}
    for _, id in ipairs(self.rotationOrder) do
        if self.rotations[id].class == class then list[#list + 1] = self.rotations[id] end
    end
    return list
end

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

---------------------------------------------------------------------------
-- Rolle: entscheidet, welche Rotation gilt (nicht die Talente). Ein Vergeltungs-
-- Paladin, der als Tank in der Gruppe ist, bekommt also die Tank-Rotation.
-- Reihenfolge der automatischen Erkennung:
--   1. Rolle in der Gruppe (Dungeonbrowser / Rollenabfrage)
--   2. Rollen-Buff aktiv (z. B. Righteous Fury -> Tank)
--   3. Schaden
---------------------------------------------------------------------------

ns.ROLES = { "auto", "TANK", "DAMAGER", "HEALER" }
ns.ROLE_LABEL = { auto = "Automatisch", TANK = "Tank", DAMAGER = "Schaden", HEALER = "Heiler" }

function ns:RoleLabel(role)
    return L[self.ROLE_LABEL[role] or role]
end

-- Quelle der Rollenerkennung: fester Text oder Name des Rollen-Buffs
local SOURCE_TEXT = { manuell = true, Gruppenrolle = true, Standard = true }
function ns:SourceLabel(source)
    return SOURCE_TEXT[source] and L[source] or self:SpellName(source)
end

local roleAuraActive = {}  -- [Buffname] = true, solange der Rollen-Buff (vermutlich) läuft

local function roleAuraNames()
    local names = {}
    for _, def in ipairs(ns:CandidatesForPlayer()) do
        for _, n in ipairs(def.roleAura or {}) do names[n] = def.role end
    end
    return names
end

-- Aktive Gestalt/Haltung (Gestaltwandel, Kampfhaltung, Schattengestalt, Verstohlenheit)
-- als englischer Schlüssel, nil = keine.
-- Ist die Gestalt im Kampf geheim, gilt die zuletzt gelesene bzw. zuletzt gezauberte.
ns.FORM_SPELLS = {}   -- [Schlüssel] = true für alle Gestalt-/Haltungszauber (aus forms/roleForm/R.form)
ns.formCache = nil

function ns:ActiveForm()
    local idx = safe(GetShapeshiftForm)
    if type(idx) ~= "number" then return self.formCache end   -- geheim: zuletzt bekannte
    if idx == 0 then
        self.formCache = nil
        return nil
    end
    local _, _, _, spellID = safe(GetShapeshiftFormInfo, idx)
    if not spellID then return self.formCache end
    local name = safe(C_Spell.GetSpellName, spellID)
    self.formCache = name and self:KeyOf(name) or nil
    return self.formCache
end

-- Kennt der Spieler den Zauber? Auch für Zauber, die nicht in der aktiven Rotation stehen.
function ns:IsKnownKey(key)
    local sp = self.spells[key]
    if sp then return sp.known end
    local id = self.SPELL_IDS[key]
    local name = (id and safe(C_Spell.GetSpellName, id)) or key
    local sid = getField(safe(C_Spell.GetSpellInfo, name), "spellID")
    if not sid then return false end
    return (safe(C_SpellBook and C_SpellBook.IsSpellKnown, sid) or safe(IsPlayerSpell, sid)) and true or false
end

-- Sind Auren gerade gesperrt? Neben dem Kampf auch während Bossbegegnungen, Mythisch+ und PvP
-- (C_RestrictedActions: 0 Combat, 1 Encounter, 2 ChallengeMode, 3 PvPMatch; 4 Map ist in der
-- offenen Welt immer aktiv und sperrt Auren nicht).
local AURA_RESTRICTIONS = { 0, 1, 2, 3 }
local function aurasRestricted()
    if InCombatLockdown() then return true end
    local getState = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
    if type(getState) ~= "function" then return false end
    for _, kind in ipairs(AURA_RESTRICTIONS) do
        local ok, st = pcall(getState, kind)
        if ok and not isSecret(st) and type(st) == "number" and st > 0 then return true end
    end
    return false
end
ns.AurasRestricted = aurasRestricted

-- Eigene Aura lesen: Tabelle = da, false = sicher nicht da, nil = nicht lesbar (dann nichts
-- überschreiben – "nicht lesbar" ist nicht "fehlt").
local function readPlayerAura(spellName, filter, restricted)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) or not spellName then return nil end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", spellName, filter)
    if not ok or isSecret(aura) then return nil end
    if type(aura) == "table" then
        if issecrettable and issecrettable(aura) then return nil end
        return aura
    end
    if restricted then return nil end   -- gesperrt: ein leeres Ergebnis beweist nichts
    return false
end

-- Außerhalb des Kampfs sind Auren lesbar: Rollen-Buffs prüfen.
function ns:ScanRoleAuras()
    if InCombatLockdown() then return end
    local restricted = aurasRestricted()
    for name in pairs(roleAuraNames()) do
        local aura = readPlayerAura(self:SpellName(name), "HELPFUL", restricted)
        if aura ~= nil then roleAuraActive[name] = aura ~= false end
    end
end

function ns:RoleMode()
    return self.db.roleMode[charKey()] or "auto"
end

-- Liefert Rolle und Quelle der Erkennung.
function ns:DetectRole()
    local mode = self:RoleMode()
    if mode ~= "auto" then return mode, "manuell" end
    if safe(IsInGroup) then
        local assigned = safe(UnitGroupRolesAssigned, "player")
        if assigned == "TANK" or assigned == "HEALER" or assigned == "DAMAGER" then
            return assigned, "Gruppenrolle"
        end
    end
    -- Gestalt/Haltung verrät die Rolle (Bärengestalt, Verteidigungshaltung) – auch im Kampf lesbar
    local form = self:ActiveForm()
    if form then
        for _, def in ipairs(self:CandidatesForPlayer()) do
            for _, f in ipairs(def.roleForm or {}) do
                if f == form then return def.role, form end
            end
        end
    end
    for name, role in pairs(roleAuraNames()) do
        if roleAuraActive[name] then return role, name end
    end
    return "DAMAGER", "Standard"
end

-- Auswahl: Rotationen der erkannten Rolle (gibt es keine, alle der Klasse),
-- darin gespeicherte Wahl > passende Spezialisierung > erste.
function ns:PickRotation()
    local candidates = self:CandidatesForPlayer()
    if #candidates == 0 then return nil end
    local role = self:DetectRole()
    local list = {}
    for _, def in ipairs(candidates) do
        if def.role == role then list[#list + 1] = def end
    end
    if #list == 0 then list = candidates end
    -- aktive Gestalt wählt die Rotation (Katze -> Wildheit, Mondkin -> Gleichgewicht)
    local form = self:ActiveForm()
    if form then
        for _, def in ipairs(list) do
            for _, f in ipairs(def.forms or {}) do
                if f == form then return def end
            end
        end
    end
    local chosen = self.db.selected[charKey() .. "|" .. role]
    for _, def in ipairs(list) do
        if def.id == chosen then return def end
    end
    -- Spezialisierung an gelernten Talenten erkennen
    for _, def in ipairs(list) do
        for _, n in ipairs(def.signature or {}) do
            if self:IsKnownKey(n) then return def end
        end
    end
    local spec = safe(C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    for _, def in ipairs(list) do
        if def.spec and def.spec == spec then return def end
    end
    return list[1]
end

-- Rolle neu bewerten und bei Bedarf die Rotation wechseln (geht auch im Kampf:
-- Cooldowns und gleichnamige Buff-Gruppen bleiben erhalten).
function ns:UpdateRotation()
    if not self.db then return end
    local def = self:PickRotation()
    if def and def ~= self.rotation then
        local hadRotation = self.rotation ~= nil
        self:SetRotation(def)
        if self.Display then self.Display:Init() end
        -- Gestaltwechsel (Druide) wechselt oft die Rotation: nur einmal pro Rotation melden
        if hadRotation and self.lastAnnounced ~= def.id then
            self.lastAnnounced = def.id
            local role, source = self:DetectRole()
            print(self.PREFIX .. string.format(L["Rotation: %s (Rolle %s, erkannt über %s)"],
                self:RotLabel(def), self:RoleLabel(role), self:SourceLabel(source)))
        end
        if self.Config and self.Config.frame and self.Config.frame:IsShown() then self.Config:Build() end
        if self.Priorities and self.Priorities.frame and self.Priorities.frame:IsShown() then self.Priorities:Build() end
    end
end

-- Rolle von Hand festlegen ("auto" = wieder automatisch erkennen).
function ns:SetRoleMode(mode)
    self.db.roleMode[charKey()] = (mode ~= "auto") and mode or nil
    self:UpdateRotation()
end

-- Rotation für diesen Charakter dauerhaft wählen (legt damit auch die Rolle fest).
function ns:SelectRotation(def)
    self.db.selected[charKey() .. "|" .. def.role] = def.id
    self.db.roleMode[charKey()] = def.role
    self:UpdateRotation()  -- meldet den Wechsel im Chat
end

function ns:SetRotation(def)
    self.rotation = def
    self.custom = {}
    if def.hooks.onReset then def.hooks.onReset(self.custom) end
    self:ResetBuffState()
    self:ResolveSpells()
    self:RebuildRules()
    self:SyncCooldowns()
    self:SyncBuffs()
end

---------------------------------------------------------------------------
-- Prioritäten: Reihenfolge und An/Aus pro Rotation (db.rulePrefs[id])
---------------------------------------------------------------------------

local function prefsFor(def)
    local all = ns.db.rulePrefs
    all[def.id] = all[def.id] or { disabled = {} }
    all[def.id].disabled = all[def.id].disabled or {}
    return all[def.id]
end

-- Einträge in aktueller Reihenfolge. Neue Einträge (nach einem Update) landen
-- hinter ihrem Vorgänger aus der Standardreihenfolge.
function ns:OrderedEntries(def)
    def = def or self.rotation
    if not def then return {} end
    local prefs = prefsFor(def)
    if not prefs.order then return { unpack(def.entries) } end
    local byKey, list, seen = {}, {}, {}
    for _, e in ipairs(def.entries) do byKey[e.key] = e end
    for _, key in ipairs(prefs.order) do
        if byKey[key] and not seen[key] then
            list[#list + 1] = byKey[key]
            seen[key] = true
        end
    end
    for i, e in ipairs(def.entries) do
        if not seen[e.key] then
            local pos = 0
            local prev = def.entries[i - 1]
            if prev then
                for j, x in ipairs(list) do if x.key == prev.key then pos = j end end
            end
            table.insert(list, pos + 1, e)
            seen[e.key] = true
        end
    end
    return list
end

function ns:EntryEnabled(key, def)
    def = def or self.rotation
    return not (def and prefsFor(def).disabled[key])
end

function ns:RebuildRules()
    local def = self.rotation
    self.activeRules = {}
    if not def then return end
    for _, e in ipairs(self:OrderedEntries(def)) do
        if self:EntryEnabled(e.key, def) then
            for _, rule in ipairs(e.rules) do self.activeRules[#self.activeRules + 1] = rule end
        end
    end
end

function ns:MoveEntry(key, delta)
    local def = self.rotation
    if not def then return end
    local list = self:OrderedEntries(def)
    for i, e in ipairs(list) do
        if e.key == key then
            local j = i + delta
            if j < 1 or j > #list then return end
            list[i], list[j] = list[j], list[i]
            break
        end
    end
    local order = {}
    for i, e in ipairs(list) do order[i] = e.key end
    prefsFor(def).order = order
    self:RebuildRules()
end

function ns:SetEntryEnabled(key, enabled)
    local def = self.rotation
    if not def then return end
    prefsFor(def).disabled[key] = (not enabled) or nil
    self:RebuildRules()
end

function ns:ResetPriorities()
    local def = self.rotation
    if not def then return end
    self.db.rulePrefs[def.id] = nil
    self:RebuildRules()
end

---------------------------------------------------------------------------
-- Datenbank und Optionen
---------------------------------------------------------------------------

local GLOBAL_DEFAULTS = {
    locked = true,
    showReason = true,
    scale = 1,
    showNext = true,      -- zweites Icon "danach"
    glow = true,          -- goldenes Pulsieren, wenn jetzt drücken
    classBorder = true,   -- Rahmen in Klassenfarbe
    swipe = true,         -- Cooldown-Spirale
    alphaOOC = 0.6,       -- Transparenz außerhalb des Kampfs
    shape = "round",      -- "round" oder "square"
    timeline = true,      -- Timeline an/aus
    timelinePos = "row",  -- "row" = in der Zeile neben dem großen Icon, "below" = darunter
    timelineSeconds = 12, -- wie weit die Timeline in die Zukunft schaut
    idleMode = "spell",   -- großes Icon, solange nichts dran ist: "spell", "empty" oder "auto"
    minimap = true,       -- Symbol am Rand der Minimap
    actionGlow = true,    -- empfohlenen Zauber auf der Aktionsleiste leuchten lassen
    actionGlowMode = "ready", -- "ready" = nur wenn jetzt drücken, "always" = auch schon vorher (grau)
    cooldownGlow = true,  -- auch im Blizzard-Cooldown-Manager leuchten lassen
    showWhen = "targetOrCombat", -- "targetOrCombat", "always", "combat", "target"
    hideMounted = true,   -- auf dem Reittier ausblenden
    hideVehicle = true,   -- im Fahrzeug ausblenden
    instanceScale = 1,    -- Größenfaktor in Dungeons/Schlachtzügen
    remindFood = "instance",   -- Essen-Erinnerung: "off", "instance", "always"
    remindWeapon = "off",      -- Waffenöl/-stein-Erinnerung: "off", "instance", "always"
    masque = true,        -- Masque-Skin nutzen, falls Masque installiert ist
    coach = true,         -- Coach: Auswertung nach dem Kampf
    coachChat = false,    -- Auswertung zusätzlich im Chat ausgeben
    coachToast = true,    -- Kurzinfo unter der Anzeige nach dem Kampf
    coachMin = 10,        -- nur Kämpfe ab so vielen Sekunden auswerten
    procAlert = true,     -- Proc-Hinweis (z. B. Seal of Command) an der Anzeige
    procSound = "MAP_PING", -- Ton bei Procs, "off" = still
    minimapAngle = 215,   -- Position am Minimap-Rand in Grad (0 = rechts, 90 = oben)
}

local function initDB()
    ForeverRotationDB = ForeverRotationDB or {}
    local db = ForeverRotationDB
    db.global = db.global or {}
    for k, v in pairs(GLOBAL_DEFAULTS) do
        if db.global[k] == nil then db.global[k] = v end
    end
    db.rotationOpts = db.rotationOpts or {}
    db.learnedCD = db.learnedCD or {}
    db.selected = db.selected or {}   -- ["Name-Realm|ROLLE"] = Rotations-ID
    db.roleMode = db.roleMode or {}   -- ["Name-Realm"] = "TANK" | "DAMAGER" | "HEALER" (fehlt = auto)
    db.rulePrefs = db.rulePrefs or {} -- [Rotations-ID] = { order = {Schlüssel...}, disabled = {[Schlüssel] = true} }
    db.coach = db.coach or { history = {} }   -- Coach: letzte Kämpfe
    db.coach.history = db.coach.history or {} -- Schutz vor einer unvollständigen Datei
    db.opts = nil -- Altlast aus 0.1.0
    -- 0.5: alte Standard-Vorschau von 6 s war für Classic-Rotationen zu kurz
    if not db.global.migrated05 then
        if db.global.timelineSeconds == 6 then db.global.timelineSeconds = 12 end
        db.global.migrated05 = true
    end
    -- 0.11: Coach hat ein eigenes Fenster, Chat-Ausgabe standardmäßig aus
    if not db.global.migrated011 then
        db.global.coachChat = false
        db.global.migrated011 = true
    end
    -- 0.5.3: Standard-Leerlauf ist "nächster Zauber steht schon im großen Icon"
    if not db.global.migrated053 then
        db.global.idleMode = "spell"
        db.global.migrated053 = true
    end
    ns.db = db
end

-- Option der aktiven Rotation lesen (mit Standardwert).
function ns:Opt(name)
    local def = self.rotation
    if not def then return nil end
    local store = self.db.rotationOpts[def.id]
    if store and store[name] ~= nil then return store[name] end
    local o = def.options[name]
    return o and o.default
end

function ns:SetOpt(name, value)
    local def = self.rotation
    if not def then return end
    self.db.rotationOpts[def.id] = self.db.rotationOpts[def.id] or {}
    self.db.rotationOpts[def.id][name] = value
end

---------------------------------------------------------------------------
-- Zauber auflösen: Zauber-ID -> Name in Client-Sprache -> höchster bekannter Rang
-- im Zauberbuch. Ohne ID wird der englische Name versucht (nur englischer Client).
---------------------------------------------------------------------------

ns.spells = {}   -- [Schlüssel] = { id, name (Client-Sprache), known, baseCD, gcd, icon }

local function collectSpellNames(def)
    local names = {}
    for _, rule in ipairs(def.rules) do names[rule.spell] = true end
    for _, group in pairs(def.buffGroups) do
        for _, n in ipairs(group.spells) do names[n] = true end
    end
    for _, group in pairs(def.debuffs) do
        for _, n in ipairs(group.spells) do names[n] = true end
    end
    for _, n in ipairs(def.extraSpells) do names[n] = true end
    for _, list in ipairs({ def.forms or {}, def.roleForm or {}, def.signature or {} }) do
        for _, n in ipairs(list) do names[n] = true end
    end
    if def.combo then
        for n in pairs(def.combo.builders or {}) do names[n] = true end
        for _, n in ipairs(def.combo.finishers or {}) do names[n] = true end
    end
    if def.rangeSpell then names[def.rangeSpell] = true end
    return names
end

function ns:ResolveSpells()
    wipe(self.spells)
    wipe(nameToKey)
    if not self.rotation then return end
    for name in pairs(collectSpellNames(self.rotation)) do
        -- IDs der eigenen Rotation zuerst (gleiche Namen bei verschiedenen Klassen, z. B. Lacerate)
        local baseId = (self.rotation.spellIds and self.rotation.spellIds[name]) or self.SPELL_IDS[name]
        local localName = baseId and safe(C_Spell.GetSpellName, baseId)
        local info = safe(C_Spell.GetSpellInfo, localName or name)
        if not getField(info, "spellID") and baseId then
            info = safe(C_Spell.GetSpellInfo, baseId)   -- noch nicht gelernt: Grundrang
        end
        local id = getField(info, "spellID")
        if id then
            local displayName = getField(info, "name") or localName or name
            nameToKey[displayName] = name
            if localName then nameToKey[localName] = name end
            local known = safe(C_SpellBook and C_SpellBook.IsSpellKnown, id)
            if not known then known = safe(IsPlayerSpell, id) end  -- passive Talente
            local baseCD, gcd = safe(GetSpellBaseCooldown, id)
            self.spells[name] = {
                id = id,
                name = displayName,
                known = known and true or false,
                baseCD = (baseCD or 0) / 1000,
                gcd = (gcd or 0) / 1000,
                icon = safe(C_Spell.GetSpellTexture, id) or getField(info, "iconID"),
            }
        end
    end
    self:RebuildKeybinds()
end

function ns:Known(name)
    local s = self.spells[name]
    return s and s.known
end

-- Echte Cooldown-Dauer: gelernt (außerhalb des Kampfs gemessen) oder Grundwert.
function ns:CooldownOf(name)
    local learned = self.db.learnedCD[name]
    if learned then return learned end
    local s = self.spells[name]
    return s and s.baseCD or 0
end

---------------------------------------------------------------------------
-- Schattenzustand: Cooldowns, GCD, Buff-Gruppen
---------------------------------------------------------------------------

local state = {
    readyAt = {},   -- [name] = GetTime(), ab wann wieder bereit
    cdStart = {},   -- [name] = Start des laufenden Cooldowns (für die Spirale)
    cdDur = {},     -- [name] = Dauer des laufenden Cooldowns
    gcdEnd = 0,
    gcdStart = 0,
    gcdDur = 0,
    buffs = {},     -- [gruppe] = { name, expires, exact }
    debuffs = {},   -- [Ziel-GUID oder "target"] = { [gruppe] = { name, expires } }
    combo = 0,      -- mitgezählte Combo-Punkte (falls das Spiel sie im Kampf verbirgt)
    combatStart = 0,   -- GetTime() beim Kampfbeginn
    swingSpeed = nil,  -- Waffengeschwindigkeit, außerhalb des Kampfs gemessen (im Kampf geheim)
}
ns.state = state

-- Angriffsgeschwindigkeit ist nur außerhalb des Kampfs lesbar: dann messen und merken.
function ns:MeasureSwing()
    if InCombatLockdown() then return end
    local speed = safe(UnitAttackSpeed, "player")
    if type(speed) == "number" and speed > 0.5 then state.swingSpeed = speed end
end

local buffGroupOf = {}    -- [Zaubername] = { Gruppe, ... } (ein Zauber kann mehrere Gruppen setzen,
                          -- z. B. Call of the Elements alle Totems)
local debuffGroupOf = {}  -- [Zaubername] = { Gruppe, ... } für Debuffs auf dem Ziel

local function addTo(map, name, group)
    map[name] = map[name] or {}
    table.insert(map[name], group)
end

-- Dauer einer Gruppe: Zahl oder Funktion der Combo-Punkte (Rip, Slice and Dice ...);
-- `durations = { [Zauber] = Sekunden }` überschreibt sie für einzelne Zauber der Gruppe.
local function groupDuration(gdef, combo, name)
    local d = (gdef.durations and name and gdef.durations[name]) or gdef.duration
    if type(d) == "function" then
        local ok, v = pcall(d, combo or 0)
        return ok and tonumber(v) or 0
    end
    return d or 0
end

-- Schlüssel des aktuellen Ziels für mitgezählte Debuffs (GUID; geheim -> "target")
local function targetKey()
    local guid = safe(UnitGUID, "target")
    return type(guid) == "string" and guid or "target"
end

-- Gleichnamige Gruppen behalten ihren Stand (Rotationswechsel mitten im Kampf).
function ns:ResetBuffState()
    local old = copyTable(state.buffs)
    wipe(state.buffs)
    wipe(buffGroupOf)
    wipe(debuffGroupOf)
    if not self.rotation then return end
    for group, def in pairs(self.rotation.buffGroups) do
        state.buffs[group] = old[group] or { name = nil, expires = 0, exact = false }
        for _, n in ipairs(def.spells) do addTo(buffGroupOf, n, group) end
    end
    for group, def in pairs(self.rotation.debuffs) do
        for _, n in ipairs(def.spells) do addTo(debuffGroupOf, n, group) end
    end
end

-- Combo-Punkte: lesbar (außerhalb des Kampfs oder falls Forever sie zeigt), sonst mitgezählt.
local function readCombo()
    local cp = safe(GetComboPoints, "player", "target")
    if type(cp) ~= "number" and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        cp = safe(UnitPower, "player", Enum.PowerType.ComboPoints)
    end
    return type(cp) == "number" and cp or nil
end

function ns:ComboPoints()
    local cp = readCombo()
    if cp then
        state.combo = cp
        return cp, true
    end
    return state.combo, false
end

-- Wirkung eines eigenen Casts auf Buffs, Debuffs und Combo-Punkte (live und in der Vorhersage)
local function applyCast(def, name, at, buffs, debuffs, combo)
    for _, group in ipairs(buffGroupOf[name] or {}) do
        local b = buffs[group] or {}
        buffs[group] = b
        b.name = name
        b.expires = at + groupDuration(def.buffGroups[group], combo, name)
        b.exact = false
        b.castAt = at   -- CDM braucht einen Moment, bis er den Wechsel zeigt
    end
    if debuffs then
        for _, group in ipairs(debuffGroupOf[name] or {}) do
            debuffs[group] = { name = name, expires = at + groupDuration(def.debuffs[group], combo, name) }
        end
    end
    local c = def.combo
    if c then
        local add = c.builders and c.builders[name]
        if add then
            combo = math.min(c.max or 5, combo + add)
        else
            for _, f in ipairs(c.finishers or {}) do
                if f == name then combo = 0 break end
            end
        end
    end
    return combo
end

-- Ausgelöste Effekte (z. B. der Schaden von Seal of Command) tragen den Namen des
-- Zaubers, haben aber eine andere ID, die nicht im Zauberbuch steht. Die sind kein Cast.
function ns:IsProc(name, spellID)
    local sp = self.spells[name]
    if sp and sp.id == spellID then return false end
    if safe(IsPlayerSpell, spellID) then return false end
    if sp then return true end
    -- nicht verfolgter Zauber: Proc nur, wenn die Rotation ihn als Proc kennt
    return self.rotation and self.rotation.procs and self.rotation.procs[name] ~= nil or false
end

local castLogUntil = 0

-- Diagnose: alle eigenen Zauber-Ereignisse eine Zeit lang im Chat ausgeben.
function ns:StartCastLog(seconds)
    castLogUntil = GetTime() + seconds
    print(self.PREFIX .. string.format(L["Protokoll eigener Zauber für %d s. Kämpfe jetzt."], seconds))
end

function ns:OnOwnCast(spellID)
    self.castSerial = (self.castSerial or 0) + 1   -- Vorhersage neu rechnen
    local localName = safe(C_Spell.GetSpellName, spellID)
    if not localName then return end
    local name = self:KeyOf(localName)
    local proc = self:IsProc(name, spellID)
    if GetTime() < castLogUntil then
        print(string.format("  |cff88ccff%s|r (ID %d) – %s", localName, spellID,
            proc and ("|cffffcc00" .. L["Proc/Effekt"] .. "|r") or L["Cast"]))
    end
    if proc then
        self:OnProc(name, spellID)
        return
    end
    -- Rollen-Buff gezaubert (z. B. Righteous Fury): Rolle neu bewerten
    if roleAuraNames()[name] and not roleAuraActive[name] then
        roleAuraActive[name] = true
        self:UpdateRotation()
    end
    -- Gestalt gezaubert: merken, falls sie im Kampf nicht lesbar ist
    if self.FORM_SPELLS[name] then self.formCache = name end
    if not self.rotation then return end
    local now = GetTime()
    if self.Coach then self.Coach:OnCast(name, now) end

    -- GCD gilt für jeden Zauber, auch für nicht verfolgte.
    local _, gcdMs = safe(GetSpellBaseCooldown, spellID)
    if gcdMs and gcdMs > 0 then
        state.gcdEnd = math.max(state.gcdEnd, now + gcdMs / 1000)
        state.gcdStart = now
        state.gcdDur = gcdMs / 1000
    end

    if self.spells[name] then
        local cd = self:CooldownOf(name)
        if cd > 0 then
            state.readyAt[name] = now + cd
            state.cdStart[name] = now
            state.cdDur[name] = cd
        end
    end

    -- Buffs, Debuffs auf dem Ziel und Combo-Punkte mitzählen
    local tkey = targetKey()
    state.debuffs[tkey] = state.debuffs[tkey] or {}
    local comboBefore = self:ComboPoints()
    state.combo = applyCast(self.rotation, name, now, state.buffs, state.debuffs[tkey], comboBefore)
    if buffGroupOf[name] and not InCombatLockdown() and C_Timer then
        -- Segen auf andere Spieler zählen nicht: außerhalb des Kampfs kurz danach echt abgleichen
        C_Timer.After(0.3, function() ns:SyncBuffs() end)
    end

    if self.rotation.hooks.onCast then
        self.rotation.hooks.onCast(name, self:Snapshot(), self.custom)
    end
end

-- Proc erkannt: Hinweis an der Anzeige und Ton (Rotation legt fest, welche Procs zählen).
local lastSound = 0
function ns:OnProc(name, spellID)
    local def = self.rotation
    local p = def and def.procs and def.procs[name]
    if not p or not self.db.global.procAlert then return end
    if self.Display then
        local icon = safe(C_Spell.GetSpellTexture, spellID) or (self.spells[name] and self.spells[name].icon)
        self.Display:ShowProc(p.label or name, icon, p.color)
    end
    local now = GetTime()
    if now - lastSound > 0.4 then   -- mehrere Procs auf einmal (Unsealed Wrath): nur ein Ton
        lastSound = now
        self:PlayProcSound()
    end
end

-- Töne aus dem Spiel (nur die, die es im Client gibt) + eigene Datei.
ns.PROC_SOUNDS = {
    { key = "off",                      label = "aus" },
    { key = "MAP_PING",                 label = "Kartenping" },
    { key = "TELL_MESSAGE",             label = "Flüstern" },
    { key = "UI_EPICLOOT_TOAST",        label = "Epischer Loot" },
    { key = "UI_LEGENDARY_LOOT_TOAST",  label = "Legendärer Loot" },
    { key = "READY_CHECK",              label = "Bereitschaftscheck" },
    { key = "RAID_WARNING",             label = "Schlachtzugswarnung" },
    { key = "ALARM_CLOCK_WARNING_3",    label = "Wecker" },
    { key = "custom",                   label = "eigene Datei (Sounds\\proc.ogg)" },
}
ns.CUSTOM_SOUND = "Interface\\AddOns\\ForeverRotation\\Sounds\\proc.ogg"

function ns:AvailableProcSounds()
    local list = {}
    for _, e in ipairs(self.PROC_SOUNDS) do
        if e.key == "off" or e.key == "custom" or (SOUNDKIT and SOUNDKIT[e.key]) then list[#list + 1] = e end
    end
    return list
end

function ns:PlayProcSound(key)
    key = key or self.db.global.procSound
    if key == "off" or not key then return end
    if key == "custom" then
        if not safe(PlaySoundFile, self.CUSTOM_SOUND, "Master") then
            print(self.PREFIX .. L["Eigene Datei nicht gefunden: "] .. self.CUSTOM_SOUND)
        end
        return
    end
    local id = SOUNDKIT and SOUNDKIT[key]
    if id then safe(PlaySound, id, "Master") end
end

-- Außerhalb des Kampfs sind Cooldowns lesbar: echte Werte übernehmen und lernen.
function ns:SyncCooldowns()
    if self.CDM then self.CDM:Calibrate(self.spells) end
    for name, s in pairs(self.spells) do
        local cdInfo = safe(C_Spell.GetSpellCooldown, s.id)
        local start = getField(cdInfo, "startTime")
        local duration = getField(cdInfo, "duration")
        if start and duration then
            if duration > 1.6 then
                state.readyAt[name] = start + duration
                state.cdStart[name] = start
                state.cdDur[name] = duration
                -- duration ist immer die volle Dauer (inkl. Talente), also direkt lernen.
                self.db.learnedCD[name] = math.floor(duration * 10 + 0.5) / 10
            elseif duration == 0 then
                state.readyAt[name] = 0
            end
        end
    end
end

-- Start und Dauer für die Cooldown-Spirale: eigener Cooldown oder, wenn länger, der GCD.
function ns:SwipeInfo(name)
    local now = GetTime()
    local cdLeft = (state.readyAt[name] or 0) - now
    local gcdLeft = state.gcdEnd - now
    local sp = self.spells[name]
    local usesGCD = sp and sp.gcd > 0
    if cdLeft > 0 and (not usesGCD or cdLeft >= gcdLeft) and state.cdDur[name] then
        return state.cdStart[name], state.cdDur[name]
    end
    if usesGCD and gcdLeft > 0 and state.gcdDur > 0 then
        return state.gcdStart, state.gcdDur
    end
    return nil
end

-- Außerhalb des Kampfs sind Auren lesbar: Buff-Gruppen gegen die Realität abgleichen.
function ns:SyncBuffs()
    if InCombatLockdown() or not self.rotation then return end
    local restricted = aurasRestricted()
    for group, def in pairs(self.rotation.buffGroups) do
        local b = state.buffs[group]
        local found, expires
        local unknown = false   -- Aura nicht lesbar: mitgezählten Stand behalten
        if def.totemSlot then
            -- Totem: GetTotemInfo(slot) = vorhanden, Name, Start, Dauer
            local have, tname, start, dur = safe(GetTotemInfo, def.totemSlot)
            if have and tname and tname ~= "" then
                local key = self:KeyOf(tname)
                found = key
                for _, n in ipairs(def.spells) do
                    if self.spells[n] and self.spells[n].name == tname then found = n end
                end
                expires = (start and dur and dur > 0) and (start + dur) or math.huge
            end
        elseif def.weaponEnchant then
            -- Waffenverzauberung (Schamanen-Waffen, Gifte, Öle): welche genau, verrät das Spiel nicht
            local hasMain, mainExp, _, _ = safe(GetWeaponEnchantInfo)
            local hasOff, offExp
            do
                local ok, _, _, _, _, ho, oe = pcall(GetWeaponEnchantInfo)
                if ok and not isSecret(ho) then hasOff, offExp = ho, oe end
            end
            local has, exp = hasMain, mainExp
            if def.weaponEnchant == "off" then has, exp = hasOff, offExp end
            if has then
                found = b.name or def.spells[1]
                expires = GetTime() + ((type(exp) == "number" and not isSecret(exp)) and exp / 1000 or 1800)
            end
        end
        for _, name in ipairs(def.spells) do
            if def.totemSlot or def.weaponEnchant then break end
            if self.spells[name] then
                local aura = readPlayerAura(self.spells[name].name, "HELPFUL", restricted)
                if aura then
                    found = name
                    local exp = getField(aura, "expirationTime")
                    expires = (exp and exp > 0) and exp or math.huge -- 0 = ohne Ablauf (z. B. Aura)
                    break
                elseif aura == nil then
                    unknown = true
                end
            end
        end
        if found or not unknown then
            b.name = found
            b.expires = found and expires or 0
            b.exact = found ~= nil
        end
    end
end

---------------------------------------------------------------------------
-- Im Kampf: Blizzard-Cooldown-Manager und Cooldown-Trick (siehe CooldownManager.lua)
-- korrigieren den Schattenzustand. Aufruf aus der Anzeige, höchstens 4x pro Sekunde.
---------------------------------------------------------------------------

local lastCombatSync = -1
function ns:CombatSync()
    if not (self.rotation and self.CDM) then return end
    local now = GetTime()
    if now - lastCombatSync < 0.25 then return end
    lastCombatSync = now
    if not aurasRestricted() then return end   -- außerhalb gelten die echten Werte (SyncBuffs)

    -- Buff-Gruppen: Der CDM verrät, OB eine verfolgte Aura liegt – bei Siegeln sogar WELCHE.
    for group, def in pairs(self.rotation.buffGroups) do
        local b = state.buffs[group]
        if b and not (def.totemSlot or def.weaponEnchant) and now - (b.castAt or 0) > 1 then
            local on
            for _, name in ipairs(def.spells) do
                if self.CDM:State(name) == true then on = name; break end
            end
            if on then
                if b.name ~= on or b.expires <= now then
                    b.name = on
                    b.expires = now + groupDuration(def, state.combo, on)
                    b.exact = false
                end
            elseif b.name and self.CDM:State(b.name) == false then
                b.name, b.expires, b.exact = nil, 0, false   -- Aura weg (abgelaufen, gebannt, Tod)
            end
        end
    end

    -- Cooldowns: nur ja/nein, und nur wenn der Trick vorher geprüft wurde. Während des GCD nur,
    -- wenn bestätigt ist, dass der Trick den GCD ausblendet (sonst hieße "läuft" vielleicht nur GCD).
    if self.CDM:CooldownTrusted() and (self.CDM:IgnoresGCD() or now > state.gcdEnd + 0.05) then
        for name, sp in pairs(self.spells) do
            if sp.known and self:CooldownOf(name) > 1.6 then
                local onCD = self.CDM:OnCooldown(sp.id)
                local readyAt = state.readyAt[name] or 0
                if onCD == false and readyAt > now + 0.3 then
                    state.readyAt[name] = now          -- vorzeitig frei (Proc, Talent, Reset)
                    state.cdDur[name] = nil
                elseif onCD == true and readyAt <= now then
                    state.readyAt[name] = now + 0.3    -- läuft doch noch: gleich erneut prüfen
                end
            end
        end
    end
end


---------------------------------------------------------------------------
-- Ziel und Gegner
---------------------------------------------------------------------------

local ELITE = { elite = true, rareelite = true, worldboss = true }

-- Zaubert das Ziel gerade? Liefert casting, interruptible (nil = unbekannt/geheim).
-- UnitCastingInfo: name, text, tex, start, end, trade, castID, notInterruptible, spellID
-- UnitChannelInfo: name, text, tex, start, end, trade, notInterruptible, spellID
local function targetCastState()
    local ok, name, _, _, _, _, _, _, notInt = pcall(UnitCastingInfo, "target")
    if not ok or isSecret(name) or not name then
        local nameC, notIntC
        ok, nameC, _, _, _, _, _, notIntC = pcall(UnitChannelInfo, "target")
        if not ok or isSecret(nameC) or not nameC then return false, nil end
        notInt = notIntC
    end
    if isSecret(notInt) then return true, nil end
    return true, notInt ~= true
end

-- Namensplaketten durchgehen kostet im Dungeon spürbar: höchstens 5x pro Sekunde zählen.
local enemyCache = { at = -1, count = 0 }
function ns:CountEnemiesInRange()
    local now = GetTime()
    if now - enemyCache.at < 0.2 then return enemyCache.count end
    enemyCache.at = now
    enemyCache.count = self:CountEnemiesNow()
    return enemyCache.count
end

function ns:CountEnemiesNow()
    local rangeName = self.rotation and self.rotation.rangeSpell
    local rangeId = rangeName and self.spells[rangeName] and self.spells[rangeName].id
    local plates = safe(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" then return 0 end
    local count = 0
    for i = 1, 40 do
        local plate = getField(plates, i)
        if not plate then break end
        local unit = getField(plate, "namePlateUnitToken")
        if not unit then
            unit = getField(getField(plate, "UnitFrame"), "unit")
        end
        if type(unit) == "string"
            and safe(UnitCanAttack, "player", unit)
            and safe(UnitAffectingCombat, unit)
            and not safe(UnitIsDead, unit) then
            local inRange
            if rangeId then inRange = safe(C_Spell.IsSpellInRange, rangeId, unit) end
            if inRange == nil then inRange = safe(CheckInteractDistance, unit, 3) end
            if inRange then count = count + 1 end
        end
    end
    return count
end

-- Momentaufnahme für die Regeln. Alles, was eine Rotation abfragen darf, steht hier.
-- Ohne Argument: Live-Zustand. Mit `sim`: simulierter Zustand für die Timeline-Vorhersage
-- (sim = { t, readyAt, gcdEnd, buffs, custom }). Ziel, Reichweite und Nutzbarkeit sind immer live.
-- Abfragen für die Regeln. Einmal pro Momentaufnahme-Tabelle angelegt; sie lesen die
-- aktuellen Werte aus s (s._readyAt, s._buffs, s._debuffs, s.now). So kann die Vorhersage
-- eine Tabelle für alle Schritte wiederverwenden statt pro Schritt zehn neue Funktionen zu bauen.
local function attachQueries(s)
    s.opt = function(name) return ns:Opt(name) end
    s.known = function(name) return ns:Known(name) end
    s.cdRemain = function(name) return math.max(0, (s._readyAt[name] or 0) - s.now) end
    s.onGCD = function(name)
        local sp = ns.spells[name]
        return sp and sp.gcd > 0
    end
    s.usable = function(name)
        local sp = ns.spells[name]
        if not sp then return false, false end
        local usable, noMana = safe(C_Spell.IsSpellUsable, sp.id)
        return usable and true or false, noMana and true or false
    end
    s.inRange = function(name)
        local sp = ns.spells[name]
        if not sp or not s.hasTarget then return nil end
        return safe(C_Spell.IsSpellInRange, sp.id, "target")
    end
    -- Buff-Gruppe: aktiver Name und Restzeit (geschätzt im Kampf, exakt außerhalb)
    s.buff = function(group)
        local b = s._buffs[group]
        if not b or not b.name then return nil, 0 end
        return b.name, math.max(0, b.expires - s.now)
    end
    -- Eigener Debuff/DoT auf dem aktuellen Ziel: Name und Restzeit (mitgezählt)
    s.debuff = function(group)
        local d = s._debuffs[group]
        if not d or not d.name or d.expires <= s.now then return nil, 0 end
        return d.name, d.expires - s.now
    end
    -- Zauber scheitert gerade nur an Mana/Wut/Energie
    s.oom = function(name)
        local usable, noMana = s.usable(name)
        return (not usable) and noMana
    end
    -- Blizzard-Cooldown-Manager (nur live, in der Vorhersage nil):
    -- cdm(name) = true aktiv / false sicher aus / nil unbekannt; cdmStacks(name) = Stapel, nurMindestens
    s.cdm = function(name)
        if s._sim or not ns.CDM then return nil end
        return ns.CDM:State(name)
    end
    s.cdmStacks = function(name)
        if s._sim or not ns.CDM then return nil end
        return ns.CDM:Stacks(name)
    end
    -- cdmStackTimes(name) = Zeitpunkt des Anstiegs auf 1 bzw. auf "ab 2" Stapel (Treffer messen)
    s.cdmStackTimes = function(name)
        if s._sim or not ns.CDM then return nil end
        return ns.CDM:StackTimes(name)
    end
end

-- Momentaufnahme für die Regeln. Alles, was eine Rotation abfragen darf, steht hier.
-- Ohne Argument: Live-Zustand. Mit `sim`: simulierter Zustand für die Timeline-Vorhersage
-- (sim = { t, readyAt, gcdEnd, buffs, custom }). Ziel, Reichweite und Nutzbarkeit sind immer live.
-- reuse: Tabelle einer früheren Momentaufnahme (nur mit sim.base), wird überschrieben.
function ns:Snapshot(sim, reuse)
    local now = sim and sim.t or GetTime()
    local s = (reuse and sim and sim.base) and reuse or {}
    if not s.opt then attachQueries(s) end
    s._sim = sim ~= nil
    s._readyAt = sim and sim.readyAt or state.readyAt
    s._buffs = sim and sim.buffs or state.buffs
    s.now = now
    s.gcdRemain = math.max(0, (sim and sim.gcdEnd or state.gcdEnd) - now)
    s.inCombat = InCombatLockdown()
    s.custom = sim and sim.custom or self.custom
    s.combatStart = state.combatStart
    s.swingSpeed = state.swingSpeed or 3.5
    if sim and sim.base then
        -- Vorhersage: Zielinfos nicht bei jedem Schritt neu abfragen
        local base = sim.base
        s.hasTarget = base.hasTarget
        s.targetClassification = base.targetClassification
        s.targetElite = base.targetElite
        s.targetType = base.targetType
        s.targetIsPlayer = base.targetIsPlayer
        s.targetInCombat = base.targetInCombat
        s.threat = base.threat
        s.role = base.role
        s.targetCasting = base.targetCasting
        s.targetInterruptible = base.targetInterruptible
        s.form, s.stealthed, s.hasPet = base.form, base.stealthed, base.hasPet
        s.power, s.powerMax = base.power, base.powerMax
        s.comboExact = base.comboExact
    else
        s.hasTarget = safe(UnitCanAttack, "player", "target") and not safe(UnitIsDead, "target") or false
    end
    if s.hasTarget and not (sim and sim.base) then
        s.targetClassification = safe(UnitClassification, "target")
        s.targetElite = s.targetClassification and ELITE[s.targetClassification] or false
        local _, typeId = safe(UnitCreatureType, "target")
        s.targetType = typeId   -- 1 Wildtier, 2 Drachkin, 3 Dämon, 4 Elementar, 5 Riese, 6 Untoter, 7 Humanoid ...
        s.targetIsPlayer = safe(UnitIsPlayer, "target") or false
        s.targetInCombat = safe(UnitAffectingCombat, "target") or false
        -- 3 = du tankst sicher, 2 = du tankst knapp, 1 = mehr Bedrohung als der Tank, 0/nil = nicht du
        s.threat = safe(UnitThreatSituation, "player", "target")
        -- Zauber des Ziels (zum Unterbrechen); interruptible nil = unbekannt
        s.targetCasting, s.targetInterruptible = targetCastState()
    end
    if not (sim and sim.base) then
        s.role = (ns:DetectRole())
        s.form = self:ActiveForm()                      -- Gestalt/Haltung (englischer Schlüssel) oder nil
        s.stealthed = safe(IsStealthed) and true or false
        s.hasPet = (safe(UnitExists, "pet") and not safe(UnitIsDead, "pet")) and true or false
        -- Ressource (Wut/Energie/Mana): nil, wenn im Kampf geheim
        local p, pm = safe(UnitPower, "player"), safe(UnitPowerMax, "player")
        s.power = type(p) == "number" and p or nil
        s.powerMax = type(pm) == "number" and pm or nil
    end
    -- Combo-Punkte: in der Vorhersage mitgezählt, sonst lesbar oder mitgezählt
    if sim then
        s.combo = sim.combo or 0
    else
        s.combo, s.comboExact = self:ComboPoints()
    end
    s._debuffs = (sim and sim.debuffs) or state.debuffs[targetKey()] or {}
    s.enemies = (sim and sim.enemies) or self:CountEnemiesInRange()
    return s
end

---------------------------------------------------------------------------
-- Vorhersage für die Timeline: die nächsten Züge simulieren, als würde man
-- jeden Zauber drücken, sobald er empfohlen wird.
---------------------------------------------------------------------------

function ns:Predict(count, horizon, base)
    local result = {}
    if not self.rotation then return result end
    local now = GetTime()
    base = base or self:Snapshot()
    local sim = {
        t = now,
        readyAt = copyTable(state.readyAt),
        gcdEnd = state.gcdEnd,
        buffs = {},
        custom = copyTable(self.custom or {}),
        enemies = base.enemies,
        base = base,
    }
    for group, b in pairs(state.buffs) do sim.buffs[group] = copyTable(b) end
    sim.debuffs = {}
    for group, d in pairs(state.debuffs[targetKey()] or {}) do sim.debuffs[group] = copyTable(d) end
    sim.combo = base.combo or 0

    -- Zeit schrittweise vorspulen: Ist gerade nichts bereit, höchstens 0,5 s weiter
    -- und neu bewerten. So erscheinen auch zeitabhängige Regeln (z. B. "Siegel
    -- läuft aus") an der richtigen Stelle.
    local steps = 0
    local snap = {}   -- eine Tabelle für alle Schritte (spart Müll für die Speicherbereinigung)
    sim.hookSnap = {}
    while #result < count and steps < 120 do
        steps = steps + 1
        local s = self:Snapshot(sim, snap)
        local rule, ready, noMana = self:Recommend(s)
        if not rule then break end
        ready = ready or 0
        if ready > s.gcdRemain + 0.3 then
            -- noch nichts bereit: Zeit vorspulen
            sim.t = sim.t + math.min(ready, 0.5)
            if sim.t - now > horizon then break end
        else
            local at = sim.t + ready
            if at - now > horizon then break end
            result[#result + 1] = { rule = rule, at = at, noMana = noMana }
            self:SimulateCast(sim, rule.spell, at)
        end
    end
    return result
end

-- Wirkung eines Casts im simulierten Zustand (wie OnOwnCast, aber ohne Live-Daten).
function ns:SimulateCast(sim, name, at)
    local sp = self.spells[name]
    sim.t = at
    local cd = self:CooldownOf(name)
    if cd > 0 then sim.readyAt[name] = at + cd end
    if sp and sp.gcd > 0 then sim.gcdEnd = at + sp.gcd end
    sim.combo = applyCast(self.rotation, name, at, sim.buffs, sim.debuffs, sim.combo or 0)
    if self.rotation.hooks.onCast then
        pcall(self.rotation.hooks.onCast, name, self:Snapshot(sim, sim.hookSnap), sim.custom)
    end
    -- Schutz vor Endlosschleifen bei Zaubern ohne Cooldown und GCD
    if cd <= 0 and not (sp and sp.gcd > 0) then sim.t = sim.t + 0.5 end
end

---------------------------------------------------------------------------
-- Empfehlung: erste passende Regel, die (fast) jetzt bereit ist.
---------------------------------------------------------------------------

function ns:Recommend(s, exclude)
    local rules = self.rotation and (self.activeRules or self.rotation.rules)
    if not rules then return nil end
    local best, bestReady, bestNoMana
    for _, rule in ipairs(rules) do
        local name = rule.spell
        if name ~= exclude and s.known(name) then
            local ok, pass = pcall(function() return not rule.cond or rule.cond(s) end)
            if ok and pass then
                local usable, noMana = s.usable(name)
                if usable or noMana then
                    local ready = s.cdRemain(name)
                    if s.onGCD(name) then ready = math.max(ready, s.gcdRemain) end
                    if ready <= s.gcdRemain + 0.3 then
                        return rule, ready, noMana
                    end
                    if not best or ready < bestReady then
                        best, bestReady, bestNoMana = rule, ready, noMana
                    end
                end
            end
        end
    end
    return best, bestReady, bestNoMana
end

---------------------------------------------------------------------------
-- Tastenbelegung zu einem Zauber finden
---------------------------------------------------------------------------

local keyCache = {}

local function bindingForSlot(slot)
    if slot <= 12 then return "ACTIONBUTTON" .. slot end
    if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON" .. (slot - 60) end
    if slot >= 49 and slot <= 60 then return "MULTIACTIONBAR2BUTTON" .. (slot - 48) end
    if slot >= 25 and slot <= 36 then return "MULTIACTIONBAR3BUTTON" .. (slot - 24) end
    if slot >= 37 and slot <= 48 then return "MULTIACTIONBAR4BUTTON" .. (slot - 36) end
end

local function shortKey(key)
    if not key then return nil end
    key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
    key = key:gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD"):gsub("MOUSEBUTTON", "M"):gsub("NUMPAD", "N")
    return key
end

function ns:RebuildKeybinds()
    wipe(keyCache)
    for slot = 1, 72 do
        local actionType, id = safe(GetActionInfo, slot)
        if actionType == "spell" and id then
            local name = safe(C_Spell.GetSpellName, id)
            if name and not keyCache[name] then
                local binding = bindingForSlot(slot)
                local key = binding and safe(GetBindingKey, binding)
                if key then keyCache[name] = shortKey(key) end
            end
        end
    end
end

function ns:KeyFor(name)
    return keyCache[self:SpellName(name)]
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")

local function registerRuntimeEvents()
    -- pcall: falls ein Event in Forever nicht existiert, soll der Rest trotzdem laufen.
    for _, ev in ipairs({ "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_ENABLED",
            "PLAYER_TARGET_CHANGED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
            "PLAYER_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
            "PLAYER_REGEN_DISABLED", "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
            "UPDATE_SHAPESHIFT_FORM", "PLAYER_TOTEM_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, ev)
    end
    pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player")
    pcall(frame.RegisterUnitEvent, frame, "UNIT_INVENTORY_CHANGED", "player")
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local addon, func = ...
        if addon == ADDON_NAME then
            print(ns.PREFIX .. "|cffff5555" .. L["Gesperrt:"] .. "|r " .. (isSecret(func) and L["GEHEIM"] or tostring(func)))
        end
    elseif event == "ADDON_LOADED" then
        if ... == ADDON_NAME then initDB() end
    elseif event == "PLAYER_LOGIN" then
        ns:ScanRoleAuras()
        local def = ns:PickRotation()
        if not def then
            print(ns.PREFIX .. L["Für deine Klasse gibt es noch keine Rotation."])
            return
        end
        registerRuntimeEvents()
        ns:MeasureSwing()
        ns:SetRotation(def)
        ns.lastAnnounced = def.id
        if ns.Display then ns.Display:Init() end
        local role, source = ns:DetectRole()
        print(ns.PREFIX .. string.format(L["geladen: %s (Rolle %s, %s). /frot öffnet die Einstellungen."],
            ns:RotLabel(def), ns:RoleLabel(role), ns:SourceLabel(source)))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if not isSecret(spellID) and type(spellID) == "number" then
            ns:OnOwnCast(spellID)
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if not InCombatLockdown() then ns:SyncCooldowns() end
    elseif event == "UNIT_AURA" then
        if not InCombatLockdown() then
            ns:ScanRoleAuras()
            ns:UpdateRotation()
            ns:SyncBuffs()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local hooks = ns.rotation and ns.rotation.hooks
        if hooks and hooks.onReset then hooks.onReset(ns.custom) end
        ns:ScanRoleAuras()
        ns:UpdateRotation()
        ns:MeasureSwing()
        wipe(state.debuffs)            -- Kampf vorbei: mitgezählte DoTs verwerfen
        state.combo = readCombo() or 0
        ns:SyncCooldowns()
        ns:SyncBuffs()
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.combatStart = GetTime()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ns:MeasureSwing()
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
        ns:ResolveSpells()
        ns:UpdateRotation()   -- Talente verraten die Spezialisierung
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        ns:UpdateRotation()   -- Gestalt/Haltung kann Rolle und Rotation ändern
    elseif event == "PLAYER_TOTEM_UPDATE" or event == "UNIT_INVENTORY_CHANGED" then
        if not InCombatLockdown() then ns:SyncBuffs() end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        ns:UpdateRotation()
    elseif event == "PLAYER_TARGET_CHANGED" then
        state.debuffs.target = nil   -- Ziel ohne lesbare GUID: Zählung neu beginnen
        local hooks = ns.rotation and ns.rotation.hooks
        if hooks and hooks.onTargetChanged then hooks.onTargetChanged(ns.custom) end
    elseif event == "SPELLS_CHANGED" then
        ns:ResolveSpells()
        if ns.CDM then ns.CDM:Reset() end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        ns:UpdateRotation()
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_BINDINGS" then
        ns:RebuildKeybinds()
    end
end)

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

local function fmtValue(v)
    if type(v) == "boolean" then return v and L["an"] or L["aus"] end
    return tostring(v)
end

local function printState()
    local s = ns:Snapshot()
    print(ns.PREFIX .. string.format(L["%s | GCD %.1fs | Gegner in Reichweite: %d | Ziel elite: %s, Typ: %s"],
        ns:RotLabel(ns.rotation), s.gcdRemain, s.enemies, tostring(s.targetElite), tostring(s.targetType)))
    local role, source = ns:DetectRole()
    print(string.format(L["  Rolle: %s (%s), Bedrohung auf Ziel: %s, Waffe: %.2fs"], ns:RoleLabel(role),
        ns:SourceLabel(source), tostring(s.threat), s.swingSpeed))
    for group in pairs(ns.rotation.buffGroups) do
        local name, remain = s.buff(group)
        local exact = state.buffs[group] and state.buffs[group].exact
        print(string.format(L["  Buff-Gruppe %s: %s (%s, %s)"], group, name and ns:SpellName(name) or "-",
            remain == math.huge and L["ohne Ablauf"] or string.format("%.1fs", remain), exact and L["exakt"] or L["geschätzt"]))
    end
    for group in pairs(ns.rotation.debuffs) do
        local name, remain = s.debuff(group)
        print(string.format(L["  Debuff auf dem Ziel %s: %s (%.1fs)"], group, name and ns:SpellName(name) or "-", remain))
    end
    if ns.rotation.combo then
        print(string.format(L["  Combo-Punkte: %d (%s)"], s.combo, s.comboExact and L["exakt"] or L["geschätzt"]))
    end
    if s.form then print(L["  Gestalt/Haltung: "] .. ns:SpellName(s.form)) end
    if ns.CDM then
        local c = ns.CDM.cdCheck
        print(string.format(L["  Cooldown-Manager: %s | Cooldown-Prüfung: %s (%d passend, %d abweichend)"],
            ns.CDM:Enabled() and L["an"] or L["aus"], ns.CDM:CooldownTrusted() and L["aktiv"] or L["noch nicht bestätigt"],
            c.agree, c.disagree))
        for group, def in pairs(ns.rotation.buffGroups) do
            for _, name in ipairs(def.spells) do
                local st = ns.CDM:State(name)
                if st ~= nil then
                    local n, more = ns.CDM:Stacks(name)
                    print(string.format(L["    CDM %s: %s, Stapel %s"], ns:SpellName(name), st and L["aktiv"] or L["aus"],
                        tostring(n) .. (more and "+" or "")))
                end
            end
        end
    end
    local names = {}
    for name in pairs(ns.spells) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local sp = ns.spells[name]
        if sp.known then
            print(string.format(L["  %s: bereit in %.1fs, CD %.1fs (%s), GCD %.1fs, Taste %s"],
                sp.name, s.cdRemain(name), ns:CooldownOf(name), ns.db.learnedCD[name] and L["gelernt"] or L["Grundwert"],
                sp.gcd, tostring(ns:KeyFor(name))))
        end
    end
end

local function printHelp()
    local def = ns.rotation
    print(ns.PREFIX .. string.format(L["Befehle (aktiv: %s):"], ns:RotLabel(def)))
    for _, line in ipairs({
        "  /frot – Konfigurationsfenster öffnen",
        "  /frot unlock | lock – Anzeige verschieben",
        "  /frot minimap – Minimap-Symbol an/aus",
        "  /frot prio – Prioritäten bearbeiten",
        "  /frot coach [reset] – Coach-Fenster öffnen (reset = Verlauf löschen)",
        "  /frot casts [Sekunden] – eigene Zauber und Procs im Chat protokollieren (Test)",
        "  /frot scale <Zahl> – Größe, z. B. 1.2",
        "  /frot state – Schattenzustand ausgeben",
        "  /frot list – verfügbare Rotationen deiner Klasse",
        "  /frot use <Nummer> – Rotation wählen (legt die Rolle fest)",
        "  /frot role auto | tank | dps | heal – Rolle festlegen oder automatisch erkennen",
        "  /frot reason – Begründung unter dem Icon an/aus",
        "  /frot relearn – gelernte Cooldowns zurücksetzen",
    }) do print(L[line]) end
    if def then
        print(L["  /frot opt <Name> [Wert] – Optionen dieser Rotation:"])
        local names = {}
        for name in pairs(def.options) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            print(string.format("    %s = %s  – %s", name, fmtValue(ns:Opt(name)), ns:T(def.options[name].desc) or ""))
        end
    end
end

SLASH_FOREVERROTATION1 = "/frot"
SlashCmdList.FOREVERROTATION = function(msg)
    if not ns.db then return end
    local cmd, arg, arg2 = (msg or ""):match("^%s*(%S*)%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local g = ns.db.global
    if cmd == "unlock" or cmd == "lock" then
        g.locked = (cmd == "lock")
        if ns.Display then ns.Display:ApplySettings() end
        print(ns.PREFIX .. (g.locked and L["Fixiert."] or L["Entsperrt: mit der linken Maustaste verschieben, dann /frot lock."]))
    elseif cmd == "scale" and tonumber(arg) then
        g.scale = math.max(0.5, math.min(3, tonumber(arg)))
        if ns.Display then ns.Display:ApplySettings() end
    elseif cmd == "reason" then
        g.showReason = not g.showReason
        print(ns.PREFIX .. L["Begründung anzeigen: "] .. fmtValue(g.showReason))
    elseif cmd == "state" and ns.rotation then
        printState()
    elseif cmd == "list" then
        for i, def in ipairs(ns:CandidatesForPlayer()) do
            print(string.format("  %d: %s%s", i, ns:RotLabel(def), def == ns.rotation and L[" (aktiv)"] or ""))
        end
    elseif cmd == "use" and tonumber(arg) then
        local def = ns:CandidatesForPlayer()[tonumber(arg)]
        if def then ns:SelectRotation(def) end
    elseif cmd == "coach" and ns.Coach then
        if arg == "reset" then ns.Coach:Reset() else ns.Coach:Report() end
    elseif cmd == "casts" then
        ns:StartCastLog(tonumber(arg) or 60)
    elseif cmd == "prio" and ns.Priorities then
        ns.Priorities:Toggle()
    elseif cmd == "help" then
        printHelp()
    elseif cmd == "minimap" then
        g.minimap = not g.minimap
        if ns.MinimapButton then ns.MinimapButton:Apply() end
        print(ns.PREFIX .. L["Minimap-Symbol: "] .. fmtValue(g.minimap))
    elseif cmd == "role" then
        local map = { auto = "auto", tank = "TANK", dps = "DAMAGER", damage = "DAMAGER", heal = "HEALER", healer = "HEALER" }
        local mode = map[arg:lower()]
        if mode then ns:SetRoleMode(mode) end
        local role, source = ns:DetectRole()
        print(ns.PREFIX .. string.format(L["Rolle: %s (%s), Rotation: %s"], ns:RoleLabel(role),
            ns:SourceLabel(source), ns:RotLabel(ns.rotation)))
    elseif cmd == "relearn" then
        wipe(ns.db.learnedCD)
        print(ns.PREFIX .. L["Gelernte Cooldowns gelöscht, werden neu gemessen."])
    elseif cmd == "opt" and ns.rotation and ns.rotation.options[arg] then
        local current = ns:Opt(arg)
        local value
        if type(current) == "boolean" then
            value = not current
        elseif type(current) == "number" then
            value = tonumber(arg2) or current
        else
            value = (arg2 ~= "" and arg2:lower()) or current
        end
        ns:SetOpt(arg, value)
        print(ns.PREFIX .. arg .. " = " .. fmtValue(value))
    elseif (cmd == "" or cmd == "config") and ns.Config then
        ns.Config:Toggle()
    else
        printHelp()
    end
end
