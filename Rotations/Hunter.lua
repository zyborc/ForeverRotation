-- Jäger, WoW Forever: Fernkampf (Tierherrschaft/Treffsicherheit) und Überleben (Nahkampf-Mischung).
--
-- Forever-Besonderheiten (Stand Nov 2026, im Spiel prüfen):
--   * Aimed Shot für alle (2 s Zauberzeit), Multi-Shot 6 s Cooldown.
--   * Summon Hawk (Tierherrschaft): Falke greift 18 s an, teilt den Cooldown mit Arcane Shot.
--   * Sniper Shot (Treffsicherheit): 4 s Zauberzeit, +10 m Reichweite für die nächsten Schüsse.
--   * Überleben: Strider Kick (Nahkampf, Tempo), Lacerate (Blutung 21 s), Lacerating Strikes.
--   * Aspekte sind Auren ohne Ablauf; außerhalb des Kampfs exakt abgeglichen.

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Hunter's Mark"] = 1130, ["Aspect of the Hawk"] = 13165, ["Aspect of the Monkey"] = 13163,
    ["Aspect of the Cheetah"] = 5118, ["Aspect of the Viper"] = 415423,
    ["Serpent Sting"] = 1978, ["Arcane Shot"] = 3044, ["Multi-Shot"] = 2643, ["Aimed Shot"] = 19434,
    ["Steady Shot"] = 409957, ["Sniper Shot"] = 1310687, ["Summon Hawk"] = 1293241, ["Rapid Fire"] = 3045,
    ["Bestial Wrath"] = 19574, ["Kill Command"] = 409379, ["Raptor Strike"] = 2973, ["Mongoose Bite"] = 1495,
    ["Wing Clip"] = 2974, ["Strider Kick"] = 1317257, ["Lacerate"] = 24118, ["Counterattack"] = 19306,
    ["Wyvern Sting"] = 24335, ["Expose Prey"] = 1310532, ["Call Pet"] = 883, ["Revive Pet"] = 982,
    ["Volley"] = 1510, ["Explosive Trap"] = 13813,
    ["Trueshot Aura"] = 19506,
}

local ASPECTS = {
    { key = "hawk", name = "Aspect of the Hawk" },
    { key = "monkey", name = "Aspect of the Monkey" },
}

-- Gewünschter Aspekt: Viper, wenn das Mana fehlt (und gelernt), sonst Option
local function aspectWanted(s, filler)
    if s.inCombat and s.known("Aspect of the Viper") and s.oom(filler) then return "Aspect of the Viper" end
    local w = R.wanted(s, "aspect", ASPECTS)
    return w
end

local function aspectRules(filler)
    local rules = {}
    for _, name in ipairs({ "Aspect of the Viper", "Aspect of the Hawk", "Aspect of the Monkey" }) do
        rules[#rules + 1] = { spell = name, reason = "Aspekt fehlt", group = "aspect", groupLabel = "Aspekt (Option, Viper bei Manamangel)",
            cond = function(s)
                local active = s.buff("aspect")
                return aspectWanted(s, filler) == name and active ~= name
            end }
    end
    return rules
end

local function petRules()
    return {
        { spell = "Call Pet", reason = "Begleiter fehlt", group = "pet", groupLabel = "Begleiter rufen/wiederbeleben",
          cond = function(s) return s.opt("pet") and not s.hasPet and not s.inCombat end },
        { spell = "Revive Pet", reason = "Begleiter fehlt", group = "pet",
          cond = function(s) return s.opt("pet") and not s.hasPet and not s.inCombat end },
    }
end

local function markRule()
    return R.dot("Hunter's Mark", { group = "mark", always = true, reason = "Debuff fehlt / läuft aus",
        cond = function(s)
            local mode = s.opt("mark")
            return mode == "always" or (mode == "elite" and (s.targetElite or s.targetIsPlayer))
        end, label = "{spell} (Option)" })
end

local function inMelee(s)
    return s.hasTarget and s.inRange("Raptor Strike") == true
end

local buffGroups = {
    aspect = { spells = { "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Viper", "Aspect of the Cheetah" }, duration = 86400 },
}
local debuffs = {
    mark    = { spells = { "Hunter's Mark" }, duration = 120 },
    serpent = { spells = { "Serpent Sting" }, duration = 15 },
    lacerate = { spells = { "Lacerate" }, duration = 21 },
}

local function sharedOptions(extra)
    return R.options({
        aspect = { order = 50, default = "hawk", values = R.keys(ASPECTS, true), valueLabels = R.labels(ASPECTS),
                   label = "Aspekt", desc = "Mit {Aspect of the Viper} wechselt die Rotation bei Manamangel automatisch." },
        pet  = { order = 51, default = true, label = "An Begleiter erinnern", desc = "Außerhalb des Kampfs, wenn kein Begleiter da ist." },
        mark = { order = 3, default = "elite", values = { "elite", "always", "off" },
                 valueLabels = { elite = "Elites/Bosse", always = "immer", off = "aus" }, label = "{Hunter's Mark}" },
        serpent = { order = 4, default = true, label = "{Serpent Sting} halten" },
        aoe = R.opt.aoe("Volley", 4, 20),
        burst = R.opt.burst(30),
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
    }, extra)
end

-- Nahkampf-Notfall, wenn der Gegner an dir klebt
local function meleeRules()
    return {
        { spell = "Mongoose Bite", reason = "Reaktiv: jetzt nutzbar", label = "{spell} (wenn nutzbar)",
          cond = function(s) return inMelee(s) end },
        { spell = "Strider Kick", reason = "Nahkampf", label = "{spell} (Nahkampf)",
          cond = function(s) return inMelee(s) end },
        { spell = "Raptor Strike", reason = "Nahkampf", label = "{spell} (Nahkampf)",
          cond = function(s) return inMelee(s) end },
        { spell = "Wing Clip", reason = "Nahkampf", label = "{spell} (Option)",
          cond = function(s) return s.opt("wingClip") and inMelee(s) and not s.targetElite end },
    }
end

---------------------------------------------------------------------------
-- Fernkampf
---------------------------------------------------------------------------

local rangedRules = aspectRules("Arcane Shot")
R.append(rangedRules, petRules())
R.append(rangedRules, meleeRules())
R.append(rangedRules, {
    markRule(),
    R.dot("Serpent Sting", { group = "serpent", cond = function(s)
        return s.opt("serpent") and s.targetType ~= R.ELEMENTAL and s.targetType ~= R.MECHANICAL end }),
    R.burst("Bestial Wrath", function(s) return s.hasPet end),
    R.burst("Rapid Fire"),
    R.ready("Kill Command", function(s) return s.hasPet end),
    R.aoe("Volley", "aoe"),
    R.ready("Aimed Shot", function(s) return s.opt("aimed") end, "{spell} (Option)"),
    R.ready("Multi-Shot"),
    R.ready("Summon Hawk", function(s) return s.opt("hawk") end, "{spell} (statt {Arcane Shot})"),
    R.ready("Arcane Shot"),
    R.ready("Sniper Shot", function(s) return s.opt("sniper") end, "{spell} (Option)"),
    R.ready("Steady Shot"),
})

ns:RegisterRotation({
    id = "HUNTER_RANGED",
    class = "HUNTER",
    role = "DAMAGER",
    label = "Jäger – Fernkampf (Schaden)",
    signature = { "Bestial Wrath", "Summon Hawk", "Sniper Shot", "Trueshot Aura" },
    rangeSpell = "Arcane Shot",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = debuffs,
    options = sharedOptions({
        aimed = { order = 5, default = true, label = "{Aimed Shot} einbauen", desc = "2 s Zauberzeit – im Stehen lohnend." },
        hawk  = { order = 6, default = true, label = "{Summon Hawk} vor {Arcane Shot}", desc = "Teilt sich den Cooldown mit {Arcane Shot}." },
        sniper = { order = 7, default = false, label = "{Sniper Shot} einbauen", desc = "4 s Zauberzeit; vor allem auf Distanz." },
        wingClip = { order = 8, default = false, label = "{Wing Clip} im Nahkampf" },
    }),
    rules = rangedRules,
})

---------------------------------------------------------------------------
-- Überleben (Nahkampf zuerst, Fernkampf als Ersatz)
---------------------------------------------------------------------------

local svRules = aspectRules("Raptor Strike")
R.append(svRules, petRules())
R.append(svRules, {
    markRule(),
    R.reactive("Counterattack"),
    R.reactive("Mongoose Bite"),
    R.dot("Lacerate", { group = "lacerate" }),
    R.ready("Strider Kick"),
    R.ready("Raptor Strike"),
    R.ready("Wing Clip", function(s) return s.opt("wingClip") and not s.targetElite end, "{spell} (Option)"),
    -- nicht im Nahkampf: Fernkampf
    R.dot("Serpent Sting", { group = "serpent", cond = function(s)
        return s.opt("serpent") and not inMelee(s) and s.targetType ~= R.ELEMENTAL and s.targetType ~= R.MECHANICAL end }),
    R.burst("Rapid Fire", function(s) return not inMelee(s) end),
    R.ready("Multi-Shot", function(s) return not inMelee(s) end, "{spell} (auf Distanz)"),
    R.ready("Arcane Shot", function(s) return not inMelee(s) end, "{spell} (auf Distanz)"),
})

ns:RegisterRotation({
    id = "HUNTER_SURVIVAL",
    class = "HUNTER",
    role = "DAMAGER",
    label = "Jäger – Überleben (Nahkampf)",
    signature = { "Counterattack", "Wyvern Sting", "Expose Prey" },
    rangeSpell = "Raptor Strike",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = debuffs,
    options = sharedOptions({
        aspect = { order = 50, default = "monkey", values = R.keys(ASPECTS, true), valueLabels = R.labels(ASPECTS),
                   label = "Aspekt", desc = "Mit {Aspect of the Viper} wechselt die Rotation bei Manamangel automatisch." },
        wingClip = { order = 8, default = false, label = "{Wing Clip} im Nahkampf" },
    }),
    rules = svRules,
})
