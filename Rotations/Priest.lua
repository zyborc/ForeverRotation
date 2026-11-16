-- Priester, WoW Forever: Schatten (Schaden) und Heiler (Disziplin/Heilig).
--
-- Forever-Besonderheiten (Stand Nov 2026, im Spiel prüfen):
--   * Devouring Plague hat nur noch 24 s Cooldown, Shadow Word: Death ist trainierbar.
--   * Penance (Disziplin), Prayer of Mending (Heilig), Chastise und weitere Rassenzauber.
--   * Power Word: Fortitude / Divine Spirit halten 60 min.
--
-- Heiler: Leben ist im Kampf geheim. Die Heiler-Rotation erinnert deshalb nur an Buffs und
-- an Zauber, die man auf Cooldown nutzt – wen du heilst, entscheidest du selbst.

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Shadowform"] = 15473, ["Inner Fire"] = 588, ["Power Word: Fortitude"] = 1243, ["Divine Spirit"] = 14752,
    ["Shadow Protection"] = 976, ["Shadow Word: Pain"] = 589, ["Vampiric Embrace"] = 15286,
    ["Devouring Plague"] = 2944, ["Vampiric Touch"] = 402668, ["Mind Blast"] = 8092, ["Mind Flay"] = 15407,
    ["Shadow Word: Death"] = 401955, ["Silence"] = 15487, ["Smite"] = 585, ["Holy Fire"] = 14914,
    ["Penance"] = 402174, ["Prayer of Mending"] = 401859, ["Power Infusion"] = 10060, ["Inner Focus"] = 14751,
    ["Starshards"] = 10797, ["Shadowfiend"] = 401977,
}

local function buffs()
    return {
        R.buff("Inner Fire", { group = "innerfire", refresh = 0, refreshOOC = 60 }),
        R.buff("Power Word: Fortitude", { group = "fortitude", ooc = true, refreshOOC = 120 }),
        R.buff("Divine Spirit", { group = "spirit", ooc = true, refreshOOC = 120 }),
        R.buff("Shadow Protection", { group = "shadowprot", ooc = true, refreshOOC = 120,
            cond = function(s) return s.opt("shadowProt") end, label = "{spell} halten (Option)" }),
    }
end

local buffGroups = {
    innerfire  = { spells = { "Inner Fire" }, duration = 600 },
    fortitude  = { spells = { "Power Word: Fortitude" }, duration = 3600 },
    spirit     = { spells = { "Divine Spirit" }, duration = 3600 },
    shadowprot = { spells = { "Shadow Protection" }, duration = 600 },
}

---------------------------------------------------------------------------
-- Schatten (auch Leveln ohne Schattengestalt: Smite/Holy Fire als Füller)
---------------------------------------------------------------------------

local function shadowFiller(s)
    return s.known("Mind Flay") and "Mind Flay" or "Smite"
end

local shadowRules = { R.interrupt("Silence"), R.form("Shadowform") }
R.append(shadowRules, buffs())
R.append(shadowRules, {
    R.dot("Vampiric Embrace", { group = "embrace", always = true, reason = "Debuff fehlt / läuft aus",
        cond = function(s) return s.opt("embrace") end, label = "{spell} halten (Option)" }),
    R.burst("Shadowfiend"),
    R.burst("Inner Focus"),
    R.dot("Vampiric Touch", { group = "touch" }),
    R.dot("Shadow Word: Pain", { group = "pain" }),
    R.dot("Devouring Plague", { group = "plague" }),
    R.ready("Mind Blast"),
    R.ready("Shadow Word: Death", function(s) return s.opt("death") end, "{spell} (Option)"),
    R.ready("Starshards"),
    R.ready("Penance", function(s) return s.form ~= "Shadowform" end, "{spell} (ohne {Shadowform})"),
    R.dot("Holy Fire", { group = "holyfire", cond = function(s) return s.form ~= "Shadowform" end,
        label = "{spell} (ohne {Shadowform})" }),
    { spell = "Mind Flay", reason = "Füller", label = "Füller: {spell}",
      cond = function(s) return s.hasTarget and R.inRange(s, "Mind Flay") end },
    { spell = "Smite", reason = "Füller", label = "Füller: {spell} (ohne {Mind Flay})",
      cond = function(s) return s.hasTarget and shadowFiller(s) == "Smite" and s.form ~= "Shadowform" end },
})

ns:RegisterRotation({
    id = "PRIEST_SHADOW",
    class = "PRIEST",
    role = "DAMAGER",
    roleForm = { "Shadowform" },
    label = "Priester – Schatten (Schaden)",
    signature = { "Shadowform", "Mind Flay" },
    rangeSpell = "Shadow Word: Pain",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = {
        pain     = { spells = { "Shadow Word: Pain" }, duration = 18 },
        plague   = { spells = { "Devouring Plague" }, duration = 24 },
        touch    = { spells = { "Vampiric Touch" }, duration = 15 },
        embrace  = { spells = { "Vampiric Embrace" }, duration = 60 },
        holyfire = { spells = { "Holy Fire" }, duration = 10 },
    },
    options = {
        embrace = { order = 1, default = false, label = "{Vampiric Embrace} halten", desc = "Heilt die Gruppe über deinen Schattenschaden." },
        death = { order = 2, default = false, label = "{Shadow Word: Death} einbauen", desc = "Starker Sofortzauber, verursacht aber Rückschlagschaden." },
        shadowProt = { order = 49, default = false, label = "{Shadow Protection} halten" },
        burst = R.opt.burst(30),
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
        interrupt = R.opt.interrupt("Silence", 90),
    },
    rules = shadowRules,
})

---------------------------------------------------------------------------
-- Heiler
---------------------------------------------------------------------------

local healRules = buffs()
R.append(healRules, {
    { spell = "Prayer of Mending", reason = "Auf Cooldown halten", label = "{spell} auf Cooldown (Option)",
      cond = function(s) return s.opt("mending") and s.inCombat end },
    { spell = "Inner Focus", reason = "Auf Cooldown halten", label = "{spell} auf Cooldown (Option)",
      cond = function(s) return s.opt("focus") and s.inCombat end },
    R.dot("Shadow Word: Pain", { group = "pain", cond = function(s) return s.opt("dps") end,
        label = "{spell} (Schaden, Option)" }),
    R.ready("Penance", function(s) return s.opt("dps") end, "{spell} (Schaden, Option)"),
    R.ready("Smite", function(s) return s.opt("dps") end, "{spell} (Schaden, Option)"),
})

ns:RegisterRotation({
    id = "PRIEST_HEALER",
    class = "PRIEST",
    role = "HEALER",
    label = "Priester – Heiler (Buffs & Cooldowns)",
    rangeSpell = "Smite",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = { pain = { spells = { "Shadow Word: Pain" }, duration = 18 } },
    options = {
        mending = { order = 1, default = true, label = "{Prayer of Mending} auf Cooldown" },
        focus = { order = 2, default = false, label = "{Inner Focus} auf Cooldown" },
        dps = { order = 3, default = false, label = "Schaden, wenn nichts zu heilen ist",
                desc = "Leben ist im Kampf geheim – schalte das ein, wenn du zwischendurch Schaden machen willst." },
        shadowProt = { order = 49, default = false, label = "{Shadow Protection} halten" },
        dotRefresh = R.opt.dotRefresh(40),
    },
    rules = healRules,
})
