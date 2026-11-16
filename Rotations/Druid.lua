-- Druide, WoW Forever: Katze (Schaden), Gleichgewicht (Schaden), Bär (Tank), Wiederherstellung (Heiler).
-- Die aktive Gestalt wählt die Rotation: Katzengestalt -> Katze, Mondkingestalt -> Gleichgewicht,
-- Bärengestalt -> Bär (und Rolle Tank).
--
-- Forever-Besonderheiten (Stand Nov 2026, im Spiel prüfen):
--   * Omen of Clarity für alle Druiden (Selbstbuff), Feral Charge ab Stufe 20 (unterbricht).
--   * Primal Bite (Bär, viel Bedrohung), Lacerate (Bär, stapelbar), Berserk.
--   * Shifting Power: Mana in 40 Energie umwandeln (8 s Cooldown). Tiger's Fury entfernt.
--   * Eclipse: Wrath verkürzt die nächsten 2 Starfire (bis 4 Ladungen, 15 s).
--   * Combo-Punkte werden mitgezählt, falls das Spiel sie im Kampf verbirgt.

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Cat Form"] = 768, ["Bear Form"] = 5487, ["Dire Bear Form"] = 9634, ["Moonkin Form"] = 24858,
    ["Mark of the Wild"] = 1126, ["Thorns"] = 467, ["Omen of Clarity"] = 16864,
    ["Faerie Fire"] = 770, ["Insect Swarm"] = 5570, ["Moonfire"] = 8921, ["Wrath"] = 5176, ["Starfire"] = 2912,
    ["Hurricane"] = 16914, ["Eclipse"] = 408248, ["Starfall"] = 439748, ["Force of Nature"] = 467079,
    ["Prowl"] = 5215, ["Ravage"] = 6785, ["Pounce"] = 9005, ["Claw"] = 1082, ["Shred"] = 5221, ["Rake"] = 1822,
    ["Rip"] = 1079, ["Ferocious Bite"] = 22568, ["Shifting Power"] = 1322605, ["Tiger's Fury"] = 5217,
    ["Berserk"] = 417141, ["Maul"] = 6807, ["Swipe"] = 779, ["Lacerate"] = 414644, ["Primal Bite"] = 407995,
    ["Demoralizing Roar"] = 99, ["Growl"] = 6795, ["Feral Charge"] = 1238122, ["Enrage"] = 5229,
    ["Wild Growth"] = 408120, ["Swiftmend"] = 18562, ["Rejuvenation"] = 774,
}

local function buffs()
    return {
        R.buff("Mark of the Wild", { group = "mark", ooc = true, refreshOOC = 120 }),
        R.buff("Omen of Clarity", { group = "omen", ooc = true, refreshOOC = 60 }),
        R.buff("Thorns", { group = "thorns", ooc = true, refreshOOC = 60,
            cond = function(s) return s.opt("thorns") end, label = "{spell} halten (Option)" }),
    }
end

local buffGroups = {
    mark   = { spells = { "Mark of the Wild" }, duration = 3600 },
    omen   = { spells = { "Omen of Clarity" }, duration = 600 },
    thorns = { spells = { "Thorns" }, duration = 600 },
}

local thornsOption = { order = 49, default = false, label = "{Thorns} halten" }

---------------------------------------------------------------------------
-- Katze
---------------------------------------------------------------------------

local function finishAt(s) return s.opt("finishAt") end

local function catBuilder(s)
    if s.opt("builder") == "shred" and s.known("Shred") then return "Shred" end
    return "Claw"
end

local catRules = buffs()
R.append(catRules, {
    R.form("Cat Form"),
    -- Opener aus Prowl
    { spell = "Ravage", reason = "Opener aus der Verstohlenheit", group = "opener", groupLabel = "Opener aus der Verstohlenheit",
      cond = function(s) return s.stealthed and s.hasTarget and s.opt("opener") == "ravage" end },
    { spell = "Pounce", reason = "Opener aus der Verstohlenheit", group = "opener",
      cond = function(s) return s.stealthed and s.hasTarget and s.opt("opener") == "pounce" end },
    R.burst("Berserk", function(s) return s.form == "Cat Form" end),
    { spell = "Shifting Power", reason = "Energie fehlt", label = "{spell} (wenn Energie fehlt)",
      cond = function(s) return s.inCombat and s.hasTarget and s.oom(catBuilder(s)) end },
    { spell = "Rip", reason = "Finisher: Blutung fehlt", label = "{spell} (Finisher, Option)",
      cond = function(s)
          local mode = s.opt("rip")
          if mode == "off" or not (s.inCombat and s.hasTarget) then return false end
          if mode == "elite" and not (s.targetElite or s.targetIsPlayer) then return false end
          return s.combo >= finishAt(s) and not s.debuff("rip")
      end },
    { spell = "Ferocious Bite", reason = "Finisher: genug Combo-Punkte", label = "{spell} (Finisher)",
      cond = function(s) return s.hasTarget and s.combo >= finishAt(s) and R.inRange(s, "Ferocious Bite") end },
    R.dot("Rake", { group = "rake", cond = function(s) return s.combo < finishAt(s) end }),
    { spell = "Shred", reason = "Combo-Punkte aufbauen", group = "builder", groupLabel = "Aufbauer (Option)",
      cond = function(s) return s.hasTarget and catBuilder(s) == "Shred" end },
    { spell = "Claw", reason = "Combo-Punkte aufbauen", group = "builder",
      cond = function(s) return s.hasTarget and catBuilder(s) == "Claw" end },
})

ns:RegisterRotation({
    id = "DRUID_CAT",
    class = "DRUID",
    role = "DAMAGER",
    forms = { "Cat Form" },
    label = "Druide – Katze (Schaden)",
    rangeSpell = "Claw",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = {
        rake = { spells = { "Rake" }, duration = 9 },
        rip  = { spells = { "Rip" }, duration = 12 },
    },
    combo = {
        builders = { ["Claw"] = 1, ["Shred"] = 1, ["Rake"] = 1, ["Ravage"] = 1, ["Pounce"] = 1 },
        finishers = { "Rip", "Ferocious Bite" },
        max = 5,
    },
    options = {
        builder = { order = 1, default = "claw", values = { "claw", "shred" },
                    valueLabels = { claw = "{Claw}", shred = "{Shred}" }, label = "Aufbauer",
                    desc = "{Shred} nur, wenn du sicher hinter dem Ziel stehst." },
        finishAt = { order = 2, default = 5, min = 1, max = 5, step = 1, label = "Finisher ab Combo-Punkten",
                     desc = "Combo-Punkte werden mitgezählt; Extrapunkte durch kritische Treffer sieht das Addon nicht." },
        rip = { order = 3, default = "elite", values = { "elite", "always", "off" },
                valueLabels = { elite = "Elites/Bosse", always = "immer", off = "aus" }, label = "{Rip} als Finisher" },
        opener = { order = 4, default = "ravage", values = { "ravage", "pounce", "off" },
                   valueLabels = { ravage = "{Ravage}", pounce = "{Pounce}", off = "aus" }, label = "Opener aus der Verstohlenheit" },
        thorns = thornsOption,
        burst = R.opt.burst(30),
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
    },
    rules = catRules,
})

---------------------------------------------------------------------------
-- Gleichgewicht
---------------------------------------------------------------------------

-- Eclipse-Ladungen: Wrath +2 (max. 4), Starfire -1, verfallen nach 15 s
local function eclipseCharges(s)
    if s.now - (s.custom.eclipseAt or 0) > 15 then return 0 end
    return s.custom.eclipse or 0
end

local function useEclipse(s)
    return s.opt("eclipse") and s.known("Eclipse") and s.known("Starfire")
end

local balanceRules = buffs()
R.append(balanceRules, {
    { spell = "Moonkin Form", reason = "Gestalt/Haltung fehlt", label = "{spell} halten",
      cond = function(s) return s.form ~= "Moonkin Form" end },
    R.dot("Faerie Fire", { group = "faerie", always = true, reason = "Debuff fehlt / läuft aus",
        cond = function(s) return s.opt("faerie") and (s.targetElite or s.targetIsPlayer) end,
        label = "{spell} (Elites, Option)" }),
    R.burst("Force of Nature"),
    R.aoe("Starfall", "aoe"),
    R.aoe("Hurricane", "aoe"),
    R.dot("Insect Swarm", { group = "swarm" }),
    R.dot("Moonfire", { group = "moonfire" }),
    { spell = "Starfire", reason = "Eclipse-Ladung nutzen", label = "{spell} mit Eclipse-Ladung",
      cond = function(s) return s.hasTarget and useEclipse(s) and eclipseCharges(s) > 0 end },
    { spell = "Wrath", reason = "Eclipse aufladen", label = "{spell} für Eclipse",
      cond = function(s) return s.hasTarget and useEclipse(s) and eclipseCharges(s) == 0 end },
    { spell = "Starfire", reason = "Füller", label = "Füller: {spell} (Option)",
      cond = function(s) return s.hasTarget and s.opt("filler") == "starfire" and R.inRange(s, "Starfire") end },
    { spell = "Wrath", reason = "Füller", label = "Füller: {spell}",
      cond = function(s) return s.hasTarget and R.inRange(s, "Wrath") end },
})

ns:RegisterRotation({
    id = "DRUID_BALANCE",
    class = "DRUID",
    role = "DAMAGER",
    forms = { "Moonkin Form" },
    signature = { "Moonkin Form", "Insect Swarm" },
    label = "Druide – Gleichgewicht (Schaden)",
    rangeSpell = "Wrath",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = {
        faerie   = { spells = { "Faerie Fire" }, duration = 40 },
        swarm    = { spells = { "Insect Swarm" }, duration = 12 },
        moonfire = { spells = { "Moonfire" }, duration = 12 },
    },
    options = {
        eclipse = { order = 1, default = true, label = "Eclipse-Muster",
                    desc = "Mit dem Talent Eclipse: {Wrath} lädt auf, dann zwei {Starfire} mit kürzerer Zauberzeit." },
        filler = { order = 2, default = "starfire", values = { "starfire", "wrath" },
                   valueLabels = { starfire = "{Starfire}", wrath = "{Wrath}" }, label = "Füller ohne Eclipse" },
        faerie = { order = 3, default = true, label = "{Faerie Fire} auf Elites" },
        thorns = thornsOption,
        aoe = R.opt.aoe("Hurricane", 4, 20),
        burst = R.opt.burst(30),
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
    },
    rules = balanceRules,
    hooks = {
        onReset = function(custom) custom.eclipse = 0 end,
        onCast = function(name, s, custom)
            if name == "Wrath" then
                custom.eclipse = math.min(4, eclipseCharges(s) + 2)
                custom.eclipseAt = s.now
            elseif name == "Starfire" then
                custom.eclipse = math.max(0, eclipseCharges(s) - 1)
            end
        end,
    },
})

---------------------------------------------------------------------------
-- Bär / Tank
---------------------------------------------------------------------------

local function bearForm(s)
    return s.known("Dire Bear Form") and "Dire Bear Form" or "Bear Form"
end

local function inBear(s)
    return s.form == "Bear Form" or s.form == "Dire Bear Form"
end

-- Lacerate stapelt bis 5: Stapel über eigene Casts mitzählen (15 s)
local function lacerateStacks(s)
    local _, remain = s.debuff("lacerate")
    if remain <= 0 then return 0 end
    return s.custom.lacerate or 0
end

local bearRules = buffs()
R.append(bearRules, {
    R.interrupt("Feral Charge"),
    { spell = "Dire Bear Form", reason = "Gestalt/Haltung fehlt", group = "bearform", groupLabel = "Bärengestalt halten",
      cond = function(s) return not inBear(s) and bearForm(s) == "Dire Bear Form" end },
    { spell = "Bear Form", reason = "Gestalt/Haltung fehlt", group = "bearform",
      cond = function(s) return not inBear(s) and bearForm(s) == "Bear Form" end },
    R.taunt("Growl"),
    R.dot("Demoralizing Roar", { group = "roar", always = true, reason = "Debuff fehlt / läuft aus",
        cond = function(s) return s.opt("roar") end, label = "{spell} halten" }),
    { spell = "Enrage", reason = "Wut im Kampf", label = "{spell} (Kampfbeginn, Option)",
      cond = function(s) return s.opt("enrage") and s.inCombat and s.hasTarget end },
    R.burst("Berserk", function(s) return inBear(s) end),
    R.ready("Primal Bite"),
    { spell = "Lacerate", reason = "Stapel aufbauen / halten", label = "{spell} stapeln und halten",
      cond = function(s)
          if not (s.inCombat and s.hasTarget and R.inRange(s, "Lacerate")) then return false end
          local _, remain = s.debuff("lacerate")
          return lacerateStacks(s) < s.opt("lacerate") or remain < 3
      end },
    R.aoe("Swipe", "aoe"),
    R.dump("Maul", "maulRage"),
})

ns:RegisterRotation({
    id = "DRUID_BEAR",
    class = "DRUID",
    role = "TANK",
    forms = { "Bear Form", "Dire Bear Form" },
    roleForm = { "Bear Form", "Dire Bear Form" },
    label = "Druide – Bär (Tank)",
    rangeSpell = "Maul",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = {
        roar = { spells = { "Demoralizing Roar" }, duration = 30 },
        lacerate = { spells = { "Lacerate" }, duration = 15 },
    },
    options = {
        taunt = R.opt.taunt(1),
        roar = { order = 2, default = true, label = "{Demoralizing Roar} halten" },
        lacerate = { order = 3, default = 5, min = 0, max = 5, step = 1, label = "{Lacerate}-Stapel",
                     desc = "So viele Stapel aufbauen und halten. 0 = nur halten." },
        enrage = { order = 4, default = false, label = "{Enrage} für Wut" },
        maulRage = { order = 25, default = 40, min = 10, max = 100, step = 5, label = "{Maul} ab Wut",
                     desc = "Nur wirksam, wenn die Wut im Kampf lesbar ist (sonst immer als letzte Wahl)." },
        aoe = R.opt.aoe("Swipe", 2, 20),
        thorns = thornsOption,
        burst = R.opt.burst(30),
        dotRefresh = R.opt.dotRefresh(40),
        interrupt = R.opt.interrupt("Feral Charge", 90),
    },
    rules = bearRules,
    hooks = {
        onReset = function(custom) custom.lacerate = 0 end,
        onTargetChanged = function(custom) custom.lacerate = 0 end,
        onCast = function(name, s, custom)
            if name == "Lacerate" then custom.lacerate = math.min(5, lacerateStacks(s) + 1) end
        end,
    },
})

---------------------------------------------------------------------------
-- Wiederherstellung (Heiler)
---------------------------------------------------------------------------

local restoRules = buffs()
R.append(restoRules, {
    { spell = "Wild Growth", reason = "Auf Cooldown halten", label = "{spell} auf Cooldown (Option)",
      cond = function(s) return s.opt("wildGrowth") and s.inCombat end },
    R.dot("Moonfire", { group = "moonfire", cond = function(s) return s.opt("dps") end, label = "{spell} (Schaden, Option)" }),
    R.ready("Wrath", function(s) return s.opt("dps") end, "{spell} (Schaden, Option)"),
})

ns:RegisterRotation({
    id = "DRUID_RESTORATION",
    class = "DRUID",
    role = "HEALER",
    label = "Druide – Wiederherstellung (Buffs & Cooldowns)",
    rangeSpell = "Wrath",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = { moonfire = { spells = { "Moonfire" }, duration = 12 } },
    options = {
        wildGrowth = { order = 1, default = false, label = "{Wild Growth} auf Cooldown",
                       desc = "Heilt die Gruppe deines Ziels – nur sinnvoll, wenn die Gruppe Schaden nimmt." },
        dps = { order = 3, default = false, label = "Schaden, wenn nichts zu heilen ist",
                desc = "Leben ist im Kampf geheim – schalte das ein, wenn du zwischendurch Schaden machen willst." },
        thorns = thornsOption,
        dotRefresh = R.opt.dotRefresh(40),
    },
    rules = restoRules,
})
