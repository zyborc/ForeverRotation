-- Krieger, WoW Forever: Waffen, Furor (Schaden) und Schutz (Tank).
--
-- Forever-Besonderheiten (Stand Nov 2026, laut Klassen-Übersichten, im Spiel prüfen):
--   * Victory Rush und Tactical Mastery sind Grundfähigkeiten (Victory Rush 30 s CD, nach Todesstoß).
--   * Spearing Strike (Waffen-Talent): +75 % Waffenschaden gegen Riesen, Drachkin und Reiter.
--   * Slam hat 18 s Cooldown, Battle Shout hält 3 min, Demoralizing Shout 45 s, Thunder Clap 6 s CD.
--   * Wut ist im Kampf vermutlich geheim: Wut-Kosten prüft das Spiel über IsSpellUsable,
--     Heroic Strike/Cleave als Wut-Dump nutzen die Wut nur, wenn sie lesbar ist.
--   * Reaktive Fähigkeiten (Execute, Overpower, Revenge, Victory Rush) meldet IsSpellUsable
--     erst, wenn sie wirklich nutzbar sind – dafür braucht es kein Leben und kein Kampflog.

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Battle Stance"] = 2457, ["Defensive Stance"] = 71, ["Berserker Stance"] = 2458,
    ["Battle Shout"] = 5242, ["Demoralizing Shout"] = 1160, ["Bloodrage"] = 2687, ["Berserker Rage"] = 18499,
    ["Heroic Strike"] = 78, ["Cleave"] = 845, ["Rend"] = 772, ["Mortal Strike"] = 12294,
    ["Bloodthirst"] = 23881, ["Whirlwind"] = 1680, ["Execute"] = 5308, ["Overpower"] = 7384,
    ["Slam"] = 1464, ["Sunder Armor"] = 7386, ["Revenge"] = 6572, ["Shield Block"] = 2565,
    ["Shield Slam"] = 23922, ["Thunder Clap"] = 6343, ["Taunt"] = 355, ["Pummel"] = 6552,
    ["Shield Bash"] = 72, ["Victory Rush"] = 402927, ["Spearing Strike"] = 1310222,
    ["Death Wish"] = 12328, ["Recklessness"] = 1719, ["Sweeping Strikes"] = 12292,
    ["Concussion Blow"] = 12809, ["Devastate"] = 403196, ["Mocking Blow"] = 694,
}

ns.FORM_SPELLS["Berserker Stance"] = true

local function bigTarget(s)
    return s.targetType == R.GIANT or s.targetType == R.DRAGONKIN
end

local shoutRule = R.buff("Battle Shout", { group = "shout", refresh = 6, refreshOOC = 30,
    cond = function(s) return s.opt("shout") end, label = "{spell} halten" })

local buffGroups = {
    shout = { spells = { "Battle Shout" }, duration = 180 },
}
local debuffs = {
    rend   = { spells = { "Rend" }, duration = 15 },
    sunder = { spells = { "Sunder Armor" }, duration = 30 },
    demo   = { spells = { "Demoralizing Shout" }, duration = 45 },
    clap   = { spells = { "Thunder Clap" }, duration = 20 },
}

local commonOptions = {
    shout = { order = 5, default = true, label = "{Battle Shout} halten", desc = "Erinnert an {Battle Shout}, auch vor dem Kampf." },
    hsRage = { order = 25, default = 50, min = 15, max = 100, step = 5, label = "Wut-Dump ab Wut",
               desc = "{Heroic Strike}/{Cleave} erst ab so viel Wut – nur wirksam, wenn die Wut im Kampf lesbar ist (sonst immer als letzte Wahl)." },
    burst = R.opt.burst(30),
    interrupt = R.opt.interrupt("Pummel", 90),
}

---------------------------------------------------------------------------
-- Waffen
---------------------------------------------------------------------------

local armsRules = {
    R.interrupt("Pummel"),
    R.form("Battle Stance"),
    shoutRule,
    R.burst("Death Wish"),
    R.burst("Recklessness", function(s) return s.opt("reckless") end),
    { spell = "Bloodrage", reason = "Wut im Kampf", label = "{spell} (Kampfbeginn)",
      cond = function(s) return s.inCombat and s.hasTarget end },
    R.reactive("Victory Rush"),
    R.execute("Execute"),
    R.reactive("Overpower"),
    { spell = "Spearing Strike", reason = "Riese/Drachkin: Bonusschaden", label = "{spell} (Riesen/Drachkin)",
      cond = function(s) return s.hasTarget and bigTarget(s) and R.inRange(s, "Spearing Strike") end },
    R.aoe("Sweeping Strikes", "aoe", function(s) return s.enemies >= 2 end),
    R.ready("Mortal Strike"),
    R.aoe("Whirlwind", "aoe"),
    R.dot("Rend", { group = "rend", cond = function(s) return s.opt("rend") end, label = "{spell} halten (Option)" }),
    R.ready("Slam"),
    R.ready("Spearing Strike", nil, "{spell}"),
    R.aoe("Thunder Clap", "aoe"),
    R.dot("Demoralizing Shout", { group = "demo", always = true, cond = function(s) return s.opt("demo") end,
        reason = "Debuff fehlt / läuft aus", label = "{spell} halten (Option)" }),
    R.dump("Cleave", "hsRage", function(s) return s.enemies >= 2 end),
    R.dump("Heroic Strike", "hsRage"),
}

ns:RegisterRotation({
    id = "WARRIOR_ARMS",
    class = "WARRIOR",
    role = "DAMAGER",
    label = "Krieger – Waffen (Schaden)",
    signature = { "Mortal Strike", "Sweeping Strikes" },
    rangeSpell = "Rend",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = debuffs,
    options = R.options(commonOptions, {
        aoe   = R.opt.aoe("Whirlwind", 3, 20),
        rend  = { order = 2, default = true, label = "{Rend} halten", desc = "Blutung auf dem Ziel (nicht gegen Untote/Elementare sinnvoll)." },
        demo  = { order = 3, default = false, label = "{Demoralizing Shout} halten", desc = "Meist Aufgabe des Tanks." },
        reckless = { order = 31, default = false, label = "{Recklessness} nutzen", desc = "Teilt sich in Classic den Cooldown mit anderen Notfall-Fähigkeiten." },
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
    }),
    rules = armsRules,
})

---------------------------------------------------------------------------
-- Furor
---------------------------------------------------------------------------

local function furyStance(s)
    return s.known("Berserker Stance") and "Berserker Stance" or "Battle Stance"
end

local furyRules = {
    R.interrupt("Pummel"),
    { spell = "Berserker Stance", reason = "Gestalt/Haltung fehlt", label = "{spell} halten",
      cond = function(s) return s.form ~= "Berserker Stance" end },
    { spell = "Battle Stance", reason = "Gestalt/Haltung fehlt", label = "{spell} (ohne Berserkerhaltung)",
      cond = function(s) return furyStance(s) == "Battle Stance" and s.form ~= "Battle Stance" end },
    shoutRule,
    R.burst("Death Wish"),
    R.burst("Recklessness", function(s) return s.opt("reckless") end),
    { spell = "Bloodrage", reason = "Wut im Kampf", label = "{spell} (Kampfbeginn)",
      cond = function(s) return s.inCombat and s.hasTarget end },
    { spell = "Berserker Rage", reason = "Wut im Kampf", label = "{spell} (Option)",
      cond = function(s) return s.opt("berserkerRage") and s.inCombat and s.hasTarget end },
    R.reactive("Victory Rush"),
    R.execute("Execute"),
    R.ready("Bloodthirst"),
    R.ready("Whirlwind", nil, "{spell}"),
    { spell = "Spearing Strike", reason = "Riese/Drachkin: Bonusschaden", label = "{spell} (Riesen/Drachkin)",
      cond = function(s) return s.hasTarget and bigTarget(s) and R.inRange(s, "Spearing Strike") end },
    R.ready("Slam", function(s) return s.opt("slam") end, "{spell} (Option)"),
    R.dump("Cleave", "hsRage", function(s) return s.enemies >= 2 end),
    R.dump("Heroic Strike", "hsRage"),
}

ns:RegisterRotation({
    id = "WARRIOR_FURY",
    class = "WARRIOR",
    role = "DAMAGER",
    label = "Krieger – Furor (Schaden)",
    signature = { "Bloodthirst" },
    rangeSpell = "Rend",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = debuffs,
    options = R.options(commonOptions, {
        reckless = { order = 31, default = false, label = "{Recklessness} nutzen", desc = "Teilt sich in Classic den Cooldown mit anderen Notfall-Fähigkeiten." },
        berserkerRage = { order = 32, default = false, label = "{Berserker Rage} für Wut", desc = "Mit passendem Talent erzeugt {Berserker Rage} Wut." },
        slam = { order = 33, default = false, label = "{Slam} einbauen", desc = "In Forever hat {Slam} 18 s Cooldown – mit langsamer Zweihandwaffe lohnend." },
    }),
    rules = furyRules,
})

---------------------------------------------------------------------------
-- Schutz / Tank
---------------------------------------------------------------------------

local protRules = {
    R.interrupt("Shield Bash"),
    R.form("Defensive Stance"),
    R.taunt("Taunt"),
    shoutRule,
    R.dot("Demoralizing Shout", { group = "demo", always = true, cond = function(s) return s.opt("demo") end,
        reason = "Debuff fehlt / läuft aus", label = "{spell} halten" }),
    R.dot("Thunder Clap", { group = "clap", always = true, cond = function(s) return s.opt("clap") end,
        reason = "Debuff fehlt / läuft aus", label = "{spell} halten" }),
    { spell = "Bloodrage", reason = "Wut im Kampf", label = "{spell} (Kampfbeginn)",
      cond = function(s) return s.inCombat and s.hasTarget end },
    { spell = "Shield Block", reason = "Block: Revenge freischalten", label = "{spell} (Option)",
      cond = function(s) return s.opt("shieldBlock") and s.inCombat and s.hasTarget and s.threat == 3 end },
    R.reactive("Revenge"),
    R.ready("Shield Slam"),
    R.reactive("Victory Rush"),
    R.ready("Concussion Blow", function(s) return s.opt("stun") end, "{spell} (Option)"),
    R.aoe("Thunder Clap", "aoe"),
    R.ready("Sunder Armor", nil, "{spell} (Bedrohung)"),
    R.dump("Cleave", "hsRage", function(s) return s.enemies >= 2 end),
    R.dump("Heroic Strike", "hsRage"),
}

ns:RegisterRotation({
    id = "WARRIOR_PROTECTION",
    class = "WARRIOR",
    role = "TANK",
    roleForm = { "Defensive Stance" },   -- Verteidigungshaltung = du tankst
    label = "Krieger – Schutz (Tank)",
    rangeSpell = "Sunder Armor",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = debuffs,
    options = R.options(commonOptions, {
        interrupt = R.opt.interrupt("Shield Bash", 90),
        taunt = R.opt.taunt(1),
        aoe   = R.opt.aoe("Thunder Clap", 2, 20),
        demo  = { order = 3, default = true, label = "{Demoralizing Shout} halten", desc = "Senkt die Angriffskraft des Ziels." },
        clap  = { order = 4, default = false, label = "{Thunder Clap} halten", desc = "Verlangsamt die Angriffe; auch gegen Einzelziele." },
        shieldBlock = { order = 6, default = true, label = "{Shield Block} nutzen", desc = "Wenn du sicher tankst: Block schaltet {Revenge} frei." },
        stun  = { order = 7, default = false, label = "{Concussion Blow} nutzen" },
        hsRage = { order = 25, default = 60, min = 15, max = 100, step = 5, label = "Wut-Dump ab Wut",
                   desc = "{Heroic Strike}/{Cleave} erst ab so viel Wut – nur wirksam, wenn die Wut im Kampf lesbar ist (sonst immer als letzte Wahl)." },
        dotRefresh = R.opt.dotRefresh(40),
    }),
    rules = protRules,
})
