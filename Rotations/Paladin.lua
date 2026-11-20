-- Paladin, WoW Forever: zwei Rotationen, gewählt nach ROLLE (nicht nach Talenten).
--   * Vergeltung / Schaden (role = DAMAGER)
--   * Schutz / Tank        (role = TANK, erkannt über Gruppenrolle oder Righteous Fury)
-- Ein Vergeltungs-Paladin in der Tankrolle bekommt also Seal of Fury + Righteous Fury.
--
-- Forever-Besonderheiten (Stand Nov 2026, laut Leveling-Guides):
--   * Judgement verbraucht das Siegel NICHT mehr und liegt nicht auf dem GCD.
--   * Siegel halten 30 Sekunden. Seal Twisting nur über das Talent Unsealed Wrath.
--   * Seal of Fury (Stufe 10): Heiligschaden pro Schlag + Schild (nur mit Schild);
--     Judgement mit Seal of Fury spottet auf 10 m.
--   * Righteous Fury (Stufe 10): +Bedrohung, Pflicht beim Tanken.
--   * Consecration (Stufe 20) trifft nur die ersten vier Gegner voll.
--   * Holy Shield ist ein Schutz-Talent (ab ca. 30).
-- Jede Regel prüft, ob der Zauber gelernt ist – fehlende Fähigkeiten werden übersprungen.
--
-- Sprache: Zauber stehen hier mit englischem Namen. SPELL_IDS übersetzt sie in die
-- Client-Sprache (IDs geprüft auf wowhead.com/forever, Nov 2026). Texte sind deutsch und
-- werden über Locale.lua übersetzt; {Zaubername} in Texten wird zum Namen im Client.

local _, ns = ...

local SPELL_IDS = {
    ["Seal of Command"] = 20375, ["Seal of Righteousness"] = 21084, ["Seal of the Crusader"] = 21082,
    ["Seal of Fury"] = 1311649, ["Seal of Wisdom"] = 20166, ["Seal of Light"] = 20165,
    ["Seal of Justice"] = 20164,
    ["Judgement"] = 20271, ["Holy Strike"] = 679, ["Consecration"] = 26573,
    ["Hammer of Wrath"] = 24275, ["Holy Wrath"] = 2812, ["Exorcism"] = 879, ["Holy Shock"] = 20473,
    ["Righteous Fury"] = 25780, ["Holy Shield"] = 20925, ["Unsealed Wrath"] = 1310735,
    ["Blessing of Might"] = 19740, ["Blessing of Wisdom"] = 19742, ["Blessing of Kings"] = 20217,
    ["Greater Blessing of Might"] = 25782, ["Greater Blessing of Wisdom"] = 25894,
    ["Greater Blessing of Kings"] = 25898,
    ["Devotion Aura"] = 465, ["Retribution Aura"] = 7294, ["Concentration Aura"] = 19746,
    ["Sanctity Aura"] = 20218, ["Shadow Resistance Aura"] = 19876, ["Frost Resistance Aura"] = 19888,
    ["Fire Resistance Aura"] = 19891,
    ["Hammer of Justice"] = 853,
}

local UNDEAD, DEMON = 6, 3

local function isUndeadOrDemon(s)
    return s.targetType == UNDEAD or s.targetType == DEMON
end

---------------------------------------------------------------------------
-- Gemeinsame Bausteine
---------------------------------------------------------------------------

local SEALS = { "Seal of Command", "Seal of Righteousness", "Seal of the Crusader",
                "Seal of Fury", "Seal of Wisdom", "Seal of Light", "Seal of Justice" }

local BLESSING_SPELLS = {
    { key = "might",     name = "Blessing of Might" },
    { key = "kings",     name = "Blessing of Kings" },
    { key = "wisdom",    name = "Blessing of Wisdom" },
}
local AURA_SPELLS = {
    { key = "devotion",      name = "Devotion Aura" },
    { key = "retribution",   name = "Retribution Aura" },
    { key = "concentration", name = "Concentration Aura" },
    { key = "sanctity",      name = "Sanctity Aura" },
}

local function names(list, extra)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.name end
    for _, n in ipairs(extra or {}) do out[#out + 1] = n end
    return out
end

local function keys(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.key end
    out[#out + 1] = "off"
    return out
end

local function labels(list)
    local out = { off = "aus" }
    for _, e in ipairs(list) do out[e.key] = "{" .. e.name .. "}" end
    return out
end

-- Gewünschter Zauber aus einer Option; nicht gelernt -> Ersatz; "off" -> nil.
local function wanted(s, optName, list, fallback)
    local choice = s.opt(optName)
    if choice == "off" then return nil end
    for _, e in ipairs(list) do
        if e.key == choice and s.known(e.name) then return e.name end
    end
    if s.known(fallback) then return fallback end
    return nil
end

local function sealActive(s)
    return (s.buff("seal"))
end

local function needSeal(s, name)
    local active, remain = s.buff("seal")
    return active ~= name or remain < s.opt("sealRefresh")
end

-- Unterbrechen: Hammer of Justice betäubt und unterbricht damit den Zauber des Ziels.
-- Ob das Ziel zaubert, ist im Kampf hoffentlich lesbar (sonst bleibt die Regel stumm).
local function interruptRule()
    return { spell = "Hammer of Justice", reason = "Unterbrechen: Ziel zaubert", label = "{spell}: unterbrechen",
        cond = function(s)
            return s.opt("interrupt") and s.inCombat and s.hasTarget and s.targetCasting
                and s.targetInterruptible ~= false and s.inRange("Hammer of Justice") ~= false
        end }
end

-- Auren liegen in Forever auf der Haltungsleiste: GetShapeshiftForm ist auch im Kampf und bei
-- Bossen lesbar, anders als die Aura-Daten. Aktive Haltung zählt daher als "Aura aktiv".
local AURA_SET = {}
for _, e in ipairs(AURA_SPELLS) do AURA_SET[e.name] = true end
for _, n in ipairs({ "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" }) do AURA_SET[n] = true end

local function auraActive(s)
    return s.buff("aura") ~= nil or (s.form ~= nil and AURA_SET[s.form] == true)
end

-- Regeln für Aura (immer) und Segen (nur vor dem Kampf), vorne einzuhängen.
local function buffRules(rules)
    for _, e in ipairs(AURA_SPELLS) do
        local name = e.name
        rules[#rules + 1] = { spell = name, reason = "Aura fehlt", group = "aura", groupLabel = "Aura (wenn keine aktiv)",
            cond = function(s)
                return not auraActive(s) and wanted(s, "aura", AURA_SPELLS, "Devotion Aura") == name
            end }
    end
    for _, e in ipairs(BLESSING_SPELLS) do
        local name = e.name
        rules[#rules + 1] = { spell = name, reason = "Segen fehlt / läuft aus",
            group = "blessing", groupLabel = "Segen (vor dem Kampf)",
            cond = function(s)
                if s.inCombat then return false end
                local active, remain = s.buff("blessing")
                return (not active or remain < 30)
                    and wanted(s, "blessing", BLESSING_SPELLS, "Blessing of Might") == name
            end }
    end
    return rules
end

local function sharedBuffGroups(extra)
    local groups = {
        seal     = { spells = SEALS, duration = 30 },
        blessing = { spells = names(BLESSING_SPELLS, { "Greater Blessing of Might", "Greater Blessing of Kings",
                         "Greater Blessing of Wisdom" }), duration = 300 },
        aura     = { spells = names(AURA_SPELLS, { "Shadow Resistance Aura", "Frost Resistance Aura",
                         "Fire Resistance Aura" }), duration = 86400 },
    }
    for k, v in pairs(extra or {}) do groups[k] = v end
    return groups
end

local function sharedOptions(defaults, extra)
    local opts = {
        aura     = { order = 50, default = defaults.aura, values = keys(AURA_SPELLS), valueLabels = labels(AURA_SPELLS),
                     label = "Aura", desc = "Wird empfohlen, wenn keine Aura aktiv ist. Nicht gelernt: {Devotion Aura}." },
        blessing = { order = 51, default = defaults.blessing, values = keys(BLESSING_SPELLS),
                     valueLabels = labels(BLESSING_SPELLS),
                     label = "Segen (vor dem Kampf)", desc = "Erinnert außerhalb des Kampfs an den Segen. Nicht gelernt: {Blessing of Might}." },
        interrupt = { order = 49, default = true, label = "{Hammer of Justice} zum Unterbrechen",
                      desc = "Empfiehlt {Hammer of Justice}, wenn dein Ziel einen Zauber wirkt, der sich unterbrechen lässt. Bosse sind meist immun." },
        sealRefresh = { order = 52, default = 2, min = 0, max = 10, step = 0.5, label = "Siegel erneuern ab Restzeit (s)",
                        desc = "Siegel neu setzen, wenn weniger als so viele Sekunden übrig" },
    }
    for k, v in pairs(extra) do opts[k] = v end
    return opts
end

local function append(rules, more)
    for _, r in ipairs(more) do rules[#rules + 1] = r end
    return rules
end

-- Gemeinsames Ende beider Rotationen: Hinrichten und Untote/Dämonen
local function finisherRules(aoeOpt)
    return {
        { spell = "Hammer of Wrath", reason = "Ziel unter 20 %", label = "{spell} (unter 20 %)",
          cond = function(s) return s.hasTarget end },  -- nur nutzbar unter 20 %, das prüft IsSpellUsable
        { spell = "Holy Wrath", reason = "Untote/Dämonen-Gruppe", label = "{spell} (Untote/Dämonen-Gruppe)",
          cond = function(s) return isUndeadOrDemon(s) and s.enemies >= s.opt(aoeOpt) end },
        { spell = "Exorcism", reason = "Untot/Dämon", label = "{spell} (Untot/Dämon)",
          cond = function(s) return s.hasTarget and isUndeadOrDemon(s) and s.inRange("Exorcism") ~= false end },
    }
end

---------------------------------------------------------------------------
-- Vergeltung / Schaden
---------------------------------------------------------------------------

-- Welches Schadenssiegel? Option "seal": auto | command | righteousness
local function damageSeal(s)
    local choice = s.opt("seal")
    if choice == "righteousness" then return "Seal of Righteousness" end
    if choice == "command" or s.known("Seal of Command") then return "Seal of Command" end
    return "Seal of Righteousness"
end

-- Kreuzfahrer-Opener: pro Ziel (GUID) gemerkt, solange der Kampf läuft – Zielwechsel hin und
-- zurück startet ihn also nicht neu. Außerhalb des Kampfs ist der Debuff selbst lesbar
-- (auch von anderen Paladinen); im Kampf wirft die Aura-Abfrage, dann zählt nur die eigene Zählung.
local JOTC_ID = 21183   -- Judgement of the Crusader (Debuff)

local function targetKey()
    local guid = ns.safe(UnitGUID, "target")
    return type(guid) == "string" and guid or "target"
end

-- Nur außerhalb des Kampfs lesen (im Kampf wirft die Abfrage – teuer bei 20 Bewertungen pro
-- Sekunde samt Vorhersage) und pro Ziel kurz zwischenspeichern.
local jotcCache = { key = nil, at = -1, val = false }
local function crusaderOnTarget()
    if InCombatLockdown() or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return false end
    local key, now = targetKey(), GetTime()
    if jotcCache.key == key and now - jotcCache.at < 0.5 then return jotcCache.val end
    local name = ns.safe(C_Spell.GetSpellName, JOTC_ID) or "Judgement of the Crusader"
    local val = ns.safe(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HARMFUL") ~= nil
    jotcCache.key, jotcCache.at, jotcCache.val = key, now, val
    return val
end

local function crusaderDone(s)
    local done = s.custom.crusaderTargets
    return (done and done[targetKey()]) or crusaderOnTarget()
end

-- Kreuzfahrer-Opener steht noch aus?
local function openerPending(s)
    return s.opt("crusader") and s.hasTarget and s.targetElite
        and s.known("Seal of the Crusader") and not crusaderDone(s)
        and not (s.opt("crusaderAoe") and s.enemies >= s.opt("aoe"))
end

-- Seal Twisting mit Unsealed Wrath (Forever, 31er-Vergeltungstalent):
-- Jeder Treffer speichert eine Kopie des aktiven Siegels (15 s, bis 3 Stapel). Ein Treffer
-- mit einem ANDEREN Siegel löst alle Stapel aus. Also: ~3 Schläge Command, dann Righteousness,
-- dann wieder Command ... Treffer sind nicht lesbar (Kampflog gesperrt) – geschätzt wird über
-- die Waffengeschwindigkeit, die außerhalb des Kampfs gemessen wird.
local TWIST_PARTNER = { ["Seal of Command"] = "Seal of Righteousness", ["Seal of Righteousness"] = "Seal of Command" }
local SEAL_SET = {}
for _, n in ipairs(SEALS) do SEAL_SET[n] = true end

local function twistActive(s)
    local mode = s.opt("twist")
    if mode == "off" then return false end
    if not (s.known("Seal of Command") and s.known("Seal of Righteousness")) then return false end
    return mode == "on" or s.known("Unsealed Wrath")
end

-- Wie lange sammelt das aktive Siegel schon Kopien? (erst ab Kampfbeginn, vorher keine Treffer)
local function sealAge(s)
    return s.now - math.max(s.custom.sealSince or 0, s.combatStart or 0)
end

local function twistInterval(s)
    return math.min(14, s.opt("twistSwings") * s.swingSpeed)  -- Kopien halten 15 s
end

-- Siegel, auf das jetzt gewechselt werden soll (oder nil)
local function twistTarget(s)
    if not (s.inCombat and s.hasTarget and twistActive(s)) then return nil end
    local partner = TWIST_PARTNER[sealActive(s)]
    if not partner or s.inRange("Holy Strike") == false then return nil end
    if sealAge(s) < twistInterval(s) then return nil end
    return partner
end

-- Beim Twisten zählt jedes Siegel des Paares als "Schadenssiegel aktiv".
local function needDamageSeal(s, name)
    if s.inCombat and twistActive(s) then
        local active, remain = s.buff("seal")
        if TWIST_PARTNER[active] and remain >= s.opt("sealRefresh") then return false end
    end
    return needSeal(s, name)
end

local retRules = buffRules({ interruptRule() })
append(retRules, {
    -- Elite-Opener: Kreuzfahrer-Siegel setzen und richten
    { spell = "Seal of the Crusader", reason = "Elite: Kreuzfahrer-Opener", label = "Kreuzfahrer-Opener: {spell} (Elites)",
      cond = function(s) return openerPending(s) and sealActive(s) ~= "Seal of the Crusader" end },
    { spell = "Judgement", reason = "Kreuzfahrer richten", label = "Kreuzfahrer-Opener: {spell}",
      cond = function(s)
          return openerPending(s) and sealActive(s) == "Seal of the Crusader" and s.inRange("Judgement") ~= false
      end },

    -- Schadenssiegel aktiv halten
    { spell = "Seal of Command", reason = "Siegel fehlt / läuft aus", group = "seal", groupLabel = "Schadenssiegel",
      cond = function(s)
          return not openerPending(s) and damageSeal(s) == "Seal of Command" and needDamageSeal(s, "Seal of Command")
      end },
    { spell = "Seal of Righteousness", reason = "Siegel fehlt / läuft aus", group = "seal",
      cond = function(s)
          return not openerPending(s) and damageSeal(s) == "Seal of Righteousness" and needDamageSeal(s, "Seal of Righteousness")
      end },

    -- Seal Twisting (nur mit Unsealed Wrath oder Option "immer")
    { spell = "Seal of Righteousness", reason = "Twist: Kopien von {Seal of Command} auslösen", group = "twist",
      groupLabel = "Seal Twisting ({Unsealed Wrath})",
      cond = function(s) return not openerPending(s) and twistTarget(s) == "Seal of Righteousness" end },
    { spell = "Seal of Command", reason = "Twist: Kopien von {Seal of Righteousness} auslösen", group = "twist",
      cond = function(s) return not openerPending(s) and twistTarget(s) == "Seal of Command" end },
})
-- Hinrichten und Untote/Dämonen VOR dem Füller, sonst verdrängt Holy Strike sie
append(retRules, finisherRules("aoe"))
append(retRules, {
    -- Kernrotation
    { spell = "Judgement", reason = "{spell} bereit", label = "{spell}",
      cond = function(s) return s.hasTarget and sealActive(s) ~= nil and s.inRange("Judgement") ~= false end },
    { spell = "Holy Strike", reason = "{spell} bereit", label = "{spell}",
      cond = function(s) return s.hasTarget and s.inRange("Holy Strike") ~= false end },
    { spell = "Consecration", reason = "Gruppe in Reichweite", label = "{spell} (ab X Gegnern)",
      cond = function(s) return s.inCombat and s.enemies >= s.opt("aoe") end },
})
append(retRules, {
    { spell = "Holy Shock", reason = "Mana übrig", label = "{spell} (Option)",
      cond = function(s) return s.opt("holyShock") and s.hasTarget end },
})

ns:RegisterRotation({
    id = "PALADIN_RETRIBUTION",
    class = "PALADIN",
    role = "DAMAGER",
    label = "Paladin – Vergeltung (Schaden)",
    rangeSpell = "Holy Strike",
    spellIds = SPELL_IDS,
    extraSpells = { "Unsealed Wrath" },  -- Talent: schaltet Twisting frei
    -- Procs: Hinweis + Ton, wenn der Schaden von Seal of Command auslöst
    procs = { ["Seal of Command"] = { label = "Command!", color = { 1, 0.85, 0.3 } } },
    buffGroups = sharedBuffGroups(),

    options = sharedOptions({ aura = "retribution", blessing = "might" }, {
        seal     = { order = 1, default = "auto", label = "Schadenssiegel",
                     values = { "auto", "command", "righteousness" },
                     valueLabels = { auto = "automatisch", command = "{Seal of Command}", righteousness = "{Seal of Righteousness}" },
                     desc = "automatisch = {Seal of Command}, sobald gelernt, sonst {Seal of Righteousness}" },
        crusader = { order = 2, default = true, label = "Kreuzfahrer-Opener gegen Elites",
                     desc = "{Seal of the Crusader} setzen und richten, dann Schadenssiegel" },
        crusaderAoe = { order = 2.5, default = true, label = "Kein Kreuzfahrer-Opener bei Gruppen",
                        desc = "Kämpfst du gegen so viele Gegner wie bei {Consecration} eingestellt, wird der Opener übersprungen und gleich das Schadenssiegel empfohlen." },
        aoe      = { order = 3, default = 2, min = 1, max = 8, step = 1, label = "{Consecration} ab Gegnern",
                     desc = "Anzahl Gegner im Kampf in Nahkampfreichweite" },
        holyShock = { order = 4, default = false, label = "{Holy Shock} nutzen",
                      desc = "Kostet viel Mana, daher standardmäßig aus" },
        twist    = { order = 5, default = "auto", label = "Seal Twisting",
                     values = { "auto", "on", "off" },
                     valueLabels = { auto = "mit {Unsealed Wrath}", on = "immer", off = "aus" },
                     desc = "Wechselt im Kampf zwischen {Seal of Command} und {Seal of Righteousness}, damit {Unsealed Wrath} die gespeicherten Siegel-Kopien auslöst.\nmit {Unsealed Wrath} = nur, wenn das Talent geskillt ist." },
        twistSwings = { order = 6, default = 3, min = 1, max = 3, step = 1, label = "Twisten nach Schlägen",
                        desc = "{Unsealed Wrath} speichert bis zu 3 Kopien. Die Schläge werden über deine Waffengeschwindigkeit geschätzt (außerhalb des Kampfs gemessen)." },
    }),

    rules = retRules,

    hooks = {
        onReset = function(custom) custom.crusaderTargets = {} end,
        onCast = function(name, s, custom)
            if SEAL_SET[name] then custom.sealSince = s.now end  -- für Twisting
            -- Judgement mit aktivem Kreuzfahrer-Siegel = Opener auf diesem Ziel erledigt.
            -- Neue Tabelle statt Ändern: die Vorhersage kopiert custom nur flach.
            if name == "Judgement" and sealActive(s) == "Seal of the Crusader" then
                local done = {}
                for k, v in pairs(custom.crusaderTargets or {}) do done[k] = v end
                done[targetKey()] = true
                custom.crusaderTargets = done
            end
        end,
    },
})

---------------------------------------------------------------------------
-- Schutz / Tank
---------------------------------------------------------------------------

-- Tanksiegel: fury | righteousness | command (nicht gelernt -> Righteousness)
local function tankSeal(s)
    local choice = s.opt("tankSeal")
    if choice == "command" and s.known("Seal of Command") then return "Seal of Command" end
    if choice == "fury" and s.known("Seal of Fury") then return "Seal of Fury" end
    return "Seal of Righteousness"
end

-- Ziel kämpft, greift aber nicht dich an (Bedrohung lesbar über UnitThreatSituation)
local function looseTarget(s)
    return s.inCombat and s.hasTarget and s.targetInCombat and not s.targetIsPlayer
        and (s.threat or 0) < 2
end

local protRules = buffRules({ interruptRule() })
append(protRules, {
    { spell = "Righteous Fury", reason = "{spell} fehlt", label = "{spell}",
      cond = function(s)
          local active, remain = s.buff("fury")
          return not active or (not s.inCombat and remain < 60)
      end },
})
for _, seal in ipairs({ "Seal of Fury", "Seal of Righteousness", "Seal of Command" }) do
    protRules[#protRules + 1] = { spell = seal, reason = "Tanksiegel fehlt / läuft aus",
        group = "tankseal", groupLabel = "Tanksiegel",
        cond = function(s) return tankSeal(s) == seal and needSeal(s, seal) end }
end
append(protRules, {
    -- Spott: Judgement mit Seal of Fury holt das Ziel zurück
    { spell = "Judgement", reason = "Spott: Ziel greift nicht dich an", label = "{spell} als Spott",
      cond = function(s)
          return s.opt("taunt") and looseTarget(s) and sealActive(s) == "Seal of Fury"
              and s.inRange("Judgement") ~= false
      end },
    { spell = "Holy Shield", reason = "Block + Bedrohung", label = "{spell}",
      cond = function(s) return s.inCombat and s.hasTarget end },
    { spell = "Consecration", reason = "Gruppe: Bedrohung auf alle", label = "{spell} (ab X Gegnern)",
      cond = function(s) return s.inCombat and s.enemies >= s.opt("aoe") end },
})
append(protRules, finisherRules("aoe"))
append(protRules, {
    { spell = "Judgement", reason = "{spell} bereit", label = "{spell} auf Cooldown",
      cond = function(s)
          return s.opt("judgeCD") and s.hasTarget and sealActive(s) ~= nil and s.inRange("Judgement") ~= false
      end },
    { spell = "Holy Strike", reason = "{spell} bereit", label = "{spell}",
      cond = function(s) return s.hasTarget and s.inRange("Holy Strike") ~= false end },
})

ns:RegisterRotation({
    id = "PALADIN_PROTECTION",
    class = "PALADIN",
    role = "TANK",
    roleAura = { "Righteous Fury" },   -- Righteous Fury aktiv = du tankst
    label = "Paladin – Schutz (Tank)",
    rangeSpell = "Holy Strike",
    spellIds = SPELL_IDS,
    procs = { ["Seal of Command"] = { label = "Command!", color = { 1, 0.85, 0.3 } } },
    buffGroups = sharedBuffGroups({
        fury = { spells = { "Righteous Fury" }, duration = 1800 },
    }),

    options = sharedOptions({ aura = "devotion", blessing = "kings" }, {
        tankSeal = { order = 1, default = "fury", label = "Tanksiegel",
                     values = { "fury", "righteousness", "command" },
                     valueLabels = { fury = "{Seal of Fury}", righteousness = "{Seal of Righteousness}", command = "{Seal of Command}" },
                     desc = "{Seal of Fury}: Bedrohung, Schild (nur mit Schild) und {Judgement} spottet." },
        taunt    = { order = 2, default = true, label = "{Judgement} als Spott",
                     desc = "{Judgement} zuerst, wenn dein Ziel kämpft, aber nicht dich angreift (nur mit {Seal of Fury})." },
        aoe      = { order = 3, default = 2, min = 1, max = 8, step = 1, label = "{Consecration} ab Gegnern",
                     desc = "{Consecration} trifft nur die ersten vier Gegner voll. 1 = auch gegen Einzelziele (viel Mana)." },
        judgeCD  = { order = 4, default = true, label = "{Judgement} auf Cooldown",
                     desc = "Aus: {Judgement} nur noch als Spott (spart Mana)." },
    }),

    rules = protRules,
})

---------------------------------------------------------------------------
-- Heilig / Heiler: Leben ist im Kampf geheim – nur Aura, Segen, Siegel und Cooldowns
---------------------------------------------------------------------------

local holyRules = buffRules({ interruptRule() })
append(holyRules, {
    { spell = "Seal of Wisdom", reason = "Siegel fehlt / läuft aus", label = "{spell} halten (Option)",
      cond = function(s) return s.opt("wisdomSeal") and s.inCombat and needSeal(s, "Seal of Wisdom") end },
    { spell = "Judgement", reason = "Mana über {Seal of Wisdom}", label = "{spell} mit {Seal of Wisdom} (Option)",
      cond = function(s)
          return s.opt("wisdomSeal") and s.hasTarget and sealActive(s) == "Seal of Wisdom" and s.inRange("Judgement") ~= false
      end },
    { spell = "Exorcism", reason = "Untot/Dämon", label = "{spell} (Untot/Dämon, Option)",
      cond = function(s)
          return s.opt("dps") and s.hasTarget and isUndeadOrDemon(s) and s.inRange("Exorcism") ~= false
      end },
    { spell = "Holy Shock", reason = "Schaden, wenn nichts zu heilen ist", label = "{spell} (Schaden, Option)",
      cond = function(s) return s.opt("dps") and s.hasTarget end },
})

ns:RegisterRotation({
    id = "PALADIN_HOLY",
    class = "PALADIN",
    role = "HEALER",
    label = "Paladin – Heilig (Buffs & Siegel)",
    rangeSpell = "Holy Strike",
    spellIds = SPELL_IDS,
    buffGroups = sharedBuffGroups(),
    options = sharedOptions({ aura = "concentration", blessing = "wisdom" }, {
        wisdomSeal = { order = 1, default = false, label = "{Seal of Wisdom} und richten",
                       desc = "Mana zurück über {Judgement} mit {Seal of Wisdom} – lohnt, wenn du ein Ziel in Reichweite hast." },
        dps = { order = 3, default = false, label = "Schaden, wenn nichts zu heilen ist",
                desc = "Leben ist im Kampf geheim – schalte das ein, wenn du zwischendurch Schaden machen willst." },
    }),
    rules = holyRules,
})
