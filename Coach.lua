-- ForeverRotation – Coach: Auswertung nach dem Kampf.
--
-- Vergleicht deine echten Casts (UNIT_SPELLCAST_SUCCEEDED, im Kampf lesbar) mit der
-- Empfehlung, die in dem Moment angezeigt wurde:
--   * Anteil der Zauber nach Empfehlung
--   * Reaktionszeit: wie lange ein Zauber "jetzt drücken" war, bevor du ihn gedrückt hast
--   * ungenutzte GCD-Zeit: Zeit, in der etwas bereit war, der GCD frei, aber nichts gedrückt
--   * ausgelaufene Buffs (z. B. Siegel) im Kampf
-- Gezählt werden nur Zauber, die in der Rotation vorkommen (Heilung, Reittier usw. nicht).

local _, ns = ...
local L = ns.L

local Coach = {}
ns.Coach = Coach

local fight            -- laufender Kampf oder nil
local MAX_DELAY = 10   -- längere "Verzögerungen" sind Pausen, keine Reaktionszeit
local HISTORY = 10     -- so viele Kämpfe werden gespeichert

local function inRotation(key)
    local def = ns.rotation
    if not def then return false end
    for _, rule in ipairs(def.rules) do
        if rule.spell == key then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Erfassen
---------------------------------------------------------------------------

function Coach:Start()
    if not ns.db.global.coach then fight = nil return end
    fight = {
        start = GetTime(), lastTick = GetTime(),
        casts = 0, match = 0,
        delaySum = 0, delayN = 0,
        idle = 0,
        perSpell = {},   -- [Schlüssel] = { n, delay }
        instead = {},    -- [Schlüssel] = Anzahl Casts gegen die Empfehlung
        drops = {},      -- [Buff-Gruppe] = Anzahl ausgelaufen
        dropSeen = {},
        cur = nil, curSince = 0, curAvail = nil,
    }
end

-- Aus der Anzeige (20x pro Sekunde): aktuelle Empfehlung
function Coach:OnRecommend(rule, readyNow, s)
    if not fight or not s.inCombat then return end
    local now = s.now
    local dt = math.min(now - fight.lastTick, 0.25)
    fight.lastTick = now

    local key = (rule and readyNow) and rule.spell or nil
    if key ~= fight.cur then
        fight.cur = key
        fight.curSince = now
        fight.curAvail = nil
    end
    -- Ab wann war der Zauber wirklich drückbar? (GCD vorbei oder Zauber ohne GCD)
    if key and not fight.curAvail and (s.gcdRemain <= 0 or not s.onGCD(key)) then
        fight.curAvail = now
    end
    -- Etwas ist drückbar, aber nichts gedrückt (die ersten 0,3 s gelten als Reaktionszeit)
    if fight.curAvail and now - fight.curAvail > 0.3 then
        fight.idle = fight.idle + dt
    end

    -- Buffs mit kurzer Dauer (Siegel), die im Kampf auslaufen
    local def = ns.rotation
    for group, gdef in pairs(def.buffGroups) do
        local d = gdef.duration   -- Zahl oder Funktion der Combo-Punkte (z. B. Slice and Dice)
        if type(d) ~= "number" or d <= 60 then
            local b = ns.state.buffs[group]
            if b and b.name and b.expires < now and fight.dropSeen[group] ~= b.expires then
                fight.dropSeen[group] = b.expires
                fight.drops[group] = (fight.drops[group] or 0) + 1
            end
        end
    end
end

-- Aus dem Kern: eigener Cast (Schlüssel = englischer Name)
function Coach:OnCast(key, now)
    if not fight or not inRotation(key) then return end
    if not fight.cur then
        -- nichts war "jetzt" dran (z. B. früh gedrückt): weder richtig noch falsch
        fight.curSince = now
        return
    end
    fight.casts = fight.casts + 1
    if fight.cur == key then
        fight.match = fight.match + 1
        local delay = fight.curAvail and math.max(0, now - fight.curAvail) or 0
        if delay <= MAX_DELAY then
            fight.delaySum = fight.delaySum + delay
            fight.delayN = fight.delayN + 1
            local p = fight.perSpell[key] or { n = 0, delay = 0 }
            p.n = p.n + 1
            p.delay = p.delay + delay
            fight.perSpell[key] = p
        end
    else
        fight.instead[key] = (fight.instead[key] or 0) + 1
    end
    fight.cur = nil   -- neue Empfehlung abwarten
    fight.curSince = now
    fight.curAvail = nil
end

---------------------------------------------------------------------------
-- Auswerten
---------------------------------------------------------------------------

local function summarize(f, duration)
    local r = {
        time = time(), duration = duration, rotation = ns.rotation and ns.rotation.id,
        casts = f.casts, match = f.match, idle = f.idle,
        avgDelay = f.delayN > 0 and f.delaySum / f.delayN or 0,
        drops = f.drops, instead = f.instead, perSpell = f.perSpell,
    }
    -- langsamster Zauber (mindestens 2-mal gedrückt)
    local worst, worstAvg, worstN
    for key, p in pairs(f.perSpell) do
        local avg = p.delay / p.n
        if p.n >= 2 and (not worstAvg or avg > worstAvg) then worst, worstAvg, worstN = key, avg, p.n end
    end
    r.slowest, r.slowestAvg, r.slowestN = worst, worstAvg, worstN
    return r
end

local function gradeColor(pct)
    if pct >= 90 then return "|cff40ff40" end
    if pct >= 70 then return "|cffffd040" end
    return "|cffff5050"
end

-- Für das Coach-Fenster ----------------------------------------------------

function Coach:Pct(r)
    return (r and r.casts > 0) and math.floor(r.match / r.casts * 100 + 0.5) or 0
end

function Coach:GradeRGB(pct)
    if pct >= 90 then return 0.25, 1, 0.25 end
    if pct >= 70 then return 1, 0.82, 0.25 end
    return 1, 0.31, 0.31
end

function Coach:History()
    return ns.db.coach.history
end

-- Durchschnitt über alle gespeicherten Kämpfe
function Coach:Average()
    local hist = self:History()
    if #hist == 0 then return nil end
    local casts, match, delay, idle, dur = 0, 0, 0, 0, 0
    for _, r in ipairs(hist) do
        casts, match = casts + r.casts, match + r.match
        delay = delay + r.avgDelay * r.casts
        idle, dur = idle + r.idle, dur + r.duration
    end
    return {
        fights = #hist,
        pct = casts > 0 and math.floor(match / casts * 100 + 0.5) or 0,
        avgDelay = casts > 0 and delay / casts or 0,
        idlePerMin = dur > 0 and idle / dur * 60 or 0,
    }
end

-- Konkrete Tipps aus einem Kampf (höchstens drei, wichtigste zuerst)
function Coach:Tips(r)
    local tips = {}
    if not r then return tips end
    for group, n in pairs(r.drops or {}) do
        if group == "seal" then
            tips[#tips + 1] = string.format(L["Dein Siegel ist %d× im Kampf ausgelaufen. Erneuere es früher (Option „Siegel erneuern ab Restzeit“)."], n)
        end
    end
    if r.slowest and r.slowestAvg and r.slowestAvg >= 0.8 then
        tips[#tips + 1] = string.format(L["%s drückst du im Schnitt %.1f s zu spät. Leg ihn auf eine gut erreichbare Taste."],
            ns:SpellName(r.slowest), r.slowestAvg)
    end
    local topKey, topN = nil, 0
    for key, n in pairs(r.instead or {}) do
        if n > topN then topKey, topN = key, n end
    end
    if topKey and topN >= 2 then
        tips[#tips + 1] = string.format(L["%s hast du %d× statt der Empfehlung gedrückt. Passt die Priorität für dich? (Prioritäten bearbeiten)"],
            ns:SpellName(topKey), topN)
    end
    if r.duration > 0 and r.idle / r.duration * 60 >= 5 then
        tips[#tips + 1] = L["Viel ungenutzte GCD-Zeit. Das Leuchten auf der Aktionsleiste hilft, schneller zu reagieren."]
    end
    if #tips == 0 then tips[1] = L["Sauber gespielt – weiter so!"] end
    while #tips > 3 do table.remove(tips) end
    return tips
end

function Coach:Print(r, title)
    if not r then
        print(ns.PREFIX .. L["Coach: noch keine Auswertung (Kampf zu kurz oder zu wenige Zauber)."])
        return
    end
    local pct = r.casts > 0 and math.floor(r.match / r.casts * 100 + 0.5) or 0
    print(ns.PREFIX .. string.format(L["%s – Kampf %d s: %s%d %%|r nach Empfehlung (%d von %d), Ø Reaktion %.1f s, ungenutzte GCD-Zeit %.1f s"],
        title or L["Coach"], r.duration, gradeColor(pct), pct, r.match, r.casts, r.avgDelay, r.idle))
    local extra = {}
    if r.slowest then
        extra[#extra + 1] = string.format(L["am langsamsten: %s Ø %.1f s (%d×)"], ns:SpellName(r.slowest), r.slowestAvg, r.slowestN)
    end
    for group, n in pairs(r.drops or {}) do
        extra[#extra + 1] = string.format(L["%s ausgelaufen: %d×"], group == "seal" and L["Siegel"] or group, n)
    end
    local instead = {}
    for key, n in pairs(r.instead or {}) do instead[#instead + 1] = ns:SpellName(key) .. " " .. n .. "×" end
    if #instead > 0 then
        extra[#extra + 1] = L["gegen die Empfehlung: "] .. table.concat(instead, ", ")
    end
    if #extra > 0 then print("  " .. table.concat(extra, " · ")) end
end

function Coach:Finish()
    if not fight then return end
    local f = fight
    fight = nil
    local duration = GetTime() - f.start
    local g = ns.db.global
    if duration < (g.coachMin or 10) or f.casts < 3 then return end
    local r = summarize(f, math.floor(duration + 0.5))
    local hist = ns.db.coach.history
    table.insert(hist, 1, r)
    while #hist > HISTORY do table.remove(hist) end
    self.selected = 1   -- im Fenster den neuen Kampf zeigen
    if g.coachChat then self:Print(r) end
    if g.coachToast and ns.Display then
        local pct = self:Pct(r)
        local cr, cg, cb = self:GradeRGB(pct)
        ns.Display:ShowToast(string.format(L["Coach: %d %% nach Empfehlung"], pct), cr, cg, cb)
    end
    self:Refresh()
end

-- Coach-Reiter neu zeichnen, falls offen
function Coach:Refresh()
    local C = ns.Config
    if C and C.frame and C.frame:IsShown() and C.tab == "coach" then C:Build() end
end

-- /frot coach: Fenster mit dem Coach-Reiter öffnen
function Coach:Report()
    if ns.Config then ns.Config:Open("coach") end
end

function Coach:Reset()
    wipe(ns.db.coach.history)
    self.selected = 1
    print(ns.PREFIX .. L["Coach-Verlauf gelöscht."])
    self:Refresh()
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if not ns.db or not ns.rotation then return end
    if event == "PLAYER_REGEN_DISABLED" then
        Coach:Start()
    else
        Coach:Finish()
    end
end)
