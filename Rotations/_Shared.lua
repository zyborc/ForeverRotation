-- ForeverRotation – gemeinsame Bausteine für Rotationen (ns.R).
-- Jede Klassen-Datei baut ihre Regeln aus diesen Helfern; alle Texte sind deutsche
-- Schlüssel für Locale.lua, {spell} wird zum Zaubernamen in der Client-Sprache.

local _, ns = ...

local R = {}
ns.R = R

R.UNDEAD, R.DEMON, R.BEAST, R.DRAGONKIN, R.ELEMENTAL, R.GIANT, R.HUMANOID, R.MECHANICAL = 6, 3, 1, 2, 4, 5, 7, 9

function R.append(rules, more)
    for _, r in ipairs(more) do rules[#rules + 1] = r end
    return rules
end

-- Liste { key, name } -> Werte/Beschriftungen für Umschalt-Optionen
function R.keys(list, withOff)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.key end
    if withOff then out[#out + 1] = "off" end
    return out
end

function R.labels(list)
    local out = { off = "aus" }
    for _, e in ipairs(list) do out[e.key] = e.label or ("{" .. e.name .. "}") end
    return out
end

function R.names(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.name end
    return out
end

-- Gewünschter Zauber aus einer Umschalt-Option; nicht gelernt -> nächster gelernter der Liste
function R.wanted(s, optName, list)
    local choice = s.opt(optName)
    if choice == "off" then return nil end
    for _, e in ipairs(list) do
        if e.key == choice and s.known(e.name) then return e.name end
    end
    for _, e in ipairs(list) do
        if s.known(e.name) then return e.name end
    end
    return nil
end

-- Ziel lohnt Cooldowns? Option "burst": elite | always | off
function R.burstOK(s)
    local mode = s.opt("burst")
    if mode == "off" then return false end
    if mode == "always" then return s.inCombat and s.hasTarget end
    return s.inCombat and s.hasTarget and (s.targetElite or s.targetIsPlayer)
end

-- DoTs auf diesem Ziel? Option "dotTrash" = auch auf normale Gegner
function R.dotOK(s)
    return s.targetElite or s.targetIsPlayer or s.opt("dotTrash") ~= false
end

local function inRange(s, spell)
    return s.inRange(spell) ~= false
end
R.inRange = inRange

-- Ziel kämpft, greift aber nicht dich an (für Spott)
function R.looseTarget(s)
    return s.inCombat and s.hasTarget and s.targetInCombat and not s.targetIsPlayer and (s.threat or 0) < 2
end

---------------------------------------------------------------------------
-- Regel-Bausteine
---------------------------------------------------------------------------

-- Unterbrechen (Option "interrupt")
function R.interrupt(spell)
    return { spell = spell, reason = "Unterbrechen: Ziel zaubert", label = "{spell}: unterbrechen",
        cond = function(s)
            return s.opt("interrupt") and s.inCombat and s.hasTarget and s.targetCasting
                and s.targetInterruptible ~= false and inRange(s, spell)
        end }
end

-- Gestalt/Haltung halten
function R.form(spell, extra)
    ns.FORM_SPELLS[spell] = true
    return { spell = spell, reason = "Gestalt/Haltung fehlt", label = "{spell} halten",
        cond = function(s) return s.form ~= spell and (not extra or extra(s)) end }
end

-- Eigenen Buff halten. o: { group, refresh (s), ooc = nur außerhalb des Kampfs,
-- combat = nur im Kampf, cond = zusätzliche Bedingung, label, id }
function R.buff(spell, o)
    o = o or {}
    return { spell = spell, reason = o.reason or "Buff fehlt / läuft aus", label = o.label or "{spell} halten",
        group = o.entry, groupLabel = o.entryLabel, id = o.id,
        cond = function(s)
            if o.ooc and s.inCombat then return false end
            if o.combat and not s.inCombat then return false end
            if o.cond and not o.cond(s) then return false end
            local active, remain = s.buff(o.group or spell)
            local refresh = (s.inCombat and (o.refresh or 3)) or (o.refreshOOC or o.refresh or 3)
            return not active or remain < refresh
        end }
end

-- Eigenen DoT/Debuff auf dem Ziel halten. o: { group, cond, label, elite = nur Elites, id }
function R.dot(spell, o)
    o = o or {}
    return { spell = spell, reason = o.reason or "DoT fehlt / läuft aus", label = o.label or "{spell} halten",
        group = o.entry, groupLabel = o.entryLabel, id = o.id,
        cond = function(s)
            if not (s.inCombat and s.hasTarget and inRange(s, spell)) then return false end
            if o.cond and not o.cond(s) then return false end
            if not o.always and not R.dotOK(s) then return false end
            local active, remain = s.debuff(o.group or spell)
            return not active or remain < (s.opt("dotRefresh") or 1.5)
        end }
end

-- Zauber, sobald bereit (Nutzbarkeit/Reichweite prüft der Kern bzw. diese Regel)
function R.ready(spell, cond, label, reason)
    return { spell = spell, reason = reason or "{spell} bereit", label = label or "{spell}",
        cond = function(s)
            return s.hasTarget and inRange(s, spell) and (not cond or cond(s))
        end }
end

-- Nur nutzbar nach Ausweichen/Parieren/Blocken/Tod usw. – das prüft IsSpellUsable
function R.reactive(spell, label)
    return { spell = spell, reason = "Reaktiv: jetzt nutzbar", label = label or "{spell} (wenn nutzbar)",
        cond = function(s) return s.hasTarget and inRange(s, spell) end }
end

-- Nur unter 20 % Leben nutzbar (IsSpellUsable prüft das, obwohl das Leben geheim ist)
function R.execute(spell)
    return { spell = spell, reason = "Ziel unter 20 %", label = "{spell} (unter 20 %)",
        cond = function(s) return s.hasTarget and inRange(s, spell) end }
end

-- Flächenschaden ab X Gegnern (Option optName)
function R.aoe(spell, optName, cond)
    return { spell = spell, reason = "Gruppe in Reichweite", label = "{spell} (ab X Gegnern)",
        cond = function(s)
            return s.inCombat and s.enemies >= s.opt(optName or "aoe") and (not cond or cond(s))
        end }
end

-- Großer Cooldown (Option "burst")
function R.burst(spell, cond)
    return { spell = spell, reason = "Cooldown: starkes Ziel", label = "{spell} (Cooldown)",
        cond = function(s) return R.burstOK(s) and (not cond or cond(s)) end }
end

-- Mana/Energie zurückholen, wenn der Füller daran scheitert
function R.regen(spell, filler, cond)
    return { spell = spell, reason = "Mana/Energie fehlt", label = "{spell} (wenn Ressource fehlt)",
        cond = function(s) return s.inCombat and s.oom(filler) and (not cond or cond(s)) end }
end

-- Spott, wenn das Ziel nicht dich angreift (Option "taunt")
function R.taunt(spell)
    return { spell = spell, reason = "Spott: Ziel greift nicht dich an", label = "{spell} als Spott",
        cond = function(s) return s.opt("taunt") and R.looseTarget(s) and inRange(s, spell) end }
end

-- Pet beschwören (außerhalb des Kampfs, kein Pet da). wantedFn(s) liefert den Zauber.
function R.pet(spell, wantedFn)
    return { spell = spell, reason = "Begleiter fehlt", label = "Begleiter beschwören",
        group = "pet", groupLabel = "Begleiter beschwören",
        cond = function(s)
            return not s.hasPet and not s.inCombat and (not wantedFn or wantedFn(s) == spell)
        end }
end

-- Ressourcen-Dump (Heroic Strike, Maul): wenn die Ressource lesbar ist, ab Schwelle
function R.dump(spell, threshOpt, cond)
    return { spell = spell, reason = "Ressource übrig", label = "{spell} (Ressource übrig)",
        cond = function(s)
            if not (s.inCombat and s.hasTarget and inRange(s, spell)) then return false end
            if cond and not cond(s) then return false end
            if s.power and threshOpt then return s.power >= s.opt(threshOpt) end
            return true
        end }
end

---------------------------------------------------------------------------
-- Gemeinsame Optionen
---------------------------------------------------------------------------

R.opt = {}

function R.opt.interrupt(spell, order)
    return { order = order or 90, default = true, label = "{" .. spell .. "} zum Unterbrechen",
        desc = "Empfiehlt den Zauber, wenn dein Ziel einen Zauber wirkt, der sich unterbrechen lässt." }
end

function R.opt.aoe(spell, default, order)
    return { order = order or 20, default = default or 3, min = 1, max = 10, step = 1,
        label = "{" .. spell .. "} ab Gegnern", desc = "Anzahl Gegner im Kampf in Reichweite (über Namensplaketten gezählt)" }
end

function R.opt.burst(order)
    return { order = order or 30, default = "elite", values = { "elite", "always", "off" },
        valueLabels = { elite = "Elites/Bosse", always = "immer", off = "aus" },
        label = "Große Cooldowns", desc = "Wann Cooldowns wie Death Wish oder Combustion empfohlen werden" }
end

function R.opt.dotRefresh(order)
    return { order = order or 40, default = 1.5, min = 0, max = 6, step = 0.5, label = "DoTs erneuern ab Restzeit (s)",
        desc = "DoTs werden im Kampf mitgezählt (Auren sind geheim). Neu setzen, wenn weniger als so viele Sekunden übrig." }
end

function R.opt.dotTrash(order)
    return { order = order or 41, default = true, label = "DoTs auch auf normale Gegner",
        desc = "Aus: DoTs nur auf Elites, Bosse und Spieler (lohnt bei schnell sterbenden Gegnern nicht)." }
end

function R.opt.taunt(order)
    return { order = order or 10, default = true, label = "Spott, wenn Ziel nicht dich angreift",
        desc = "Bedrohung ist im Kampf lesbar: greift dein Ziel jemand anderen an, kommt der Spott zuerst." }
end

-- Mehrere Optionen zu einer Tabelle zusammenführen
function R.options(...)
    local out = {}
    for i = 1, select("#", ...) do
        for k, v in pairs(select(i, ...) or {}) do out[k] = v end
    end
    return out
end
