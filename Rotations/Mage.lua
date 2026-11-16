-- Magier, WoW Forever: Feuer, Frost, Arkan (alle Schaden). Spezialisierung über Talente erkannt.
--
-- Forever-Besonderheiten (Stand Nov 2026, im Spiel prüfen):
--   * Frostfire Bolt für alle Magier, Arcane Blast (1,5 s Zauberzeit, jede Wiederholung
--     verstärkt ihn und verdoppelt die Kosten), Arcane Wrath (neu, skaliert mit max. Mana).
--   * Procs (Hot Streak/Heating Up, Fingers of Frost, Missile Barrage) sind Auren und damit im
--     Kampf geheim – das Addon kann sie nicht anzeigen.
--   * Mana ist geheim: scheitert der Füller nur am Mana, empfiehlt die Rotation Evocation.

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Fireball"] = 133, ["Scorch"] = 2948, ["Fire Blast"] = 2136, ["Pyroblast"] = 11366,
    ["Combustion"] = 11129, ["Blast Wave"] = 11113, ["Flamestrike"] = 2120, ["Frostfire Bolt"] = 401502,
    ["Frostbolt"] = 116, ["Ice Lance"] = 400640, ["Cone of Cold"] = 120, ["Blizzard"] = 10,
    ["Ice Barrier"] = 11426, ["Cold Snap"] = 12472, ["Icy Veins"] = 425121,
    ["Arcane Blast"] = 400574, ["Arcane Missiles"] = 5143, ["Arcane Power"] = 12042,
    ["Presence of Mind"] = 12043, ["Arcane Wrath"] = 1326079, ["Arcane Explosion"] = 1449,
    ["Arcane Intellect"] = 1459, ["Mage Armor"] = 6117, ["Ice Armor"] = 7302, ["Frost Armor"] = 168,
    ["Molten Armor"] = 428741, ["Counterspell"] = 2139, ["Evocation"] = 12051,
}

local ARMORS = {
    { key = "mage", name = "Mage Armor" },
    { key = "ice", name = "Ice Armor" },
    { key = "frost", name = "Frost Armor" },
    { key = "molten", name = "Molten Armor" },
}

local function armorWanted(s)
    local w = R.wanted(s, "armor", ARMORS)
    if s.opt("armor") ~= "off" and not w and s.known("Frost Armor") then return "Frost Armor" end
    return w
end

-- Gemeinsamer Anfang: Unterbrechen, Rüstung, Arkane Intelligenz
local function startRules()
    local rules = { R.interrupt("Counterspell") }
    for _, e in ipairs(ARMORS) do
        local name = e.name
        rules[#rules + 1] = { spell = name, reason = "Buff fehlt / läuft aus", group = "armor", groupLabel = "Rüstung (Option)",
            cond = function(s)
                local active, remain = s.buff("armor")
                return armorWanted(s) == name and (not active or (not s.inCombat and remain < 60))
            end }
    end
    rules[#rules + 1] = R.buff("Arcane Intellect", { group = "intellect", ooc = true, refreshOOC = 120 })
    return rules
end

local buffGroups = {
    armor = { spells = R.names(ARMORS), duration = 1800 },
    intellect = { spells = { "Arcane Intellect" }, duration = 3600 },
    barrier = { spells = { "Ice Barrier" }, duration = 60 },
}

local function sharedOptions(defArmor, aoeSpell, extra)
    return R.options({
        armor = { order = 50, default = defArmor, values = R.keys(ARMORS, true), valueLabels = R.labels(ARMORS),
                  label = "Rüstung", desc = "Nicht gelernt: {Frost Armor}." },
        aoe = R.opt.aoe(aoeSpell, 4, 20),
        burst = R.opt.burst(30),
        interrupt = R.opt.interrupt("Counterspell", 90),
    }, extra)
end

local function filler(s, frostfire, default)
    if s.opt("filler") == "frostfire" and s.known("Frostfire Bolt") then return "Frostfire Bolt" end
    return default
end

---------------------------------------------------------------------------
-- Feuer
---------------------------------------------------------------------------

local fireRules = startRules()
R.append(fireRules, {
    { spell = "Evocation", reason = "Mana fehlt", label = "{spell} (wenn Mana fehlt)",
      cond = function(s) return s.inCombat and s.oom("Fireball") end },
    { spell = "Pyroblast", reason = "Opener", label = "{spell} als Opener (Option)",
      cond = function(s) return s.opt("pyroOpener") and s.hasTarget and not s.targetInCombat and R.inRange(s, "Pyroblast") end },
    { spell = "Scorch", reason = "Feuer-Debuff aufbauen", label = "{spell} stapeln (Option)",
      cond = function(s)
          local want = s.opt("scorch")
          if want == 0 or not (s.inCombat and s.hasTarget and R.dotOK(s)) then return false end
          local active, remain = s.debuff("scorch")
          return (s.custom.scorchStacks or 0) < want or not active or remain < 5
      end },
    R.burst("Combustion"),
    R.aoe("Blast Wave", "aoe"),
    R.aoe("Flamestrike", "aoe"),
    R.ready("Fire Blast", function(s) return s.opt("fireBlast") end, "{spell} auf Cooldown (Option)"),
    { spell = "Frostfire Bolt", reason = "Füller", label = "Füller: {spell} (Option)",
      cond = function(s) return s.hasTarget and filler(s, true, "Fireball") == "Frostfire Bolt" end },
    { spell = "Fireball", reason = "Füller", label = "Füller: {spell}",
      cond = function(s) return s.hasTarget and R.inRange(s, "Fireball") end },
})

ns:RegisterRotation({
    id = "MAGE_FIRE",
    class = "MAGE",
    role = "DAMAGER",
    label = "Magier – Feuer (Schaden)",
    signature = { "Combustion", "Pyroblast", "Blast Wave" },
    rangeSpell = "Fireball",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = { scorch = { spells = { "Scorch" }, duration = 30 } },
    options = sharedOptions("mage", "Flamestrike", {
        scorch = { order = 1, default = 0, min = 0, max = 5, step = 1, label = "{Scorch}-Stapel aufbauen",
                   desc = "Mit dem Talent für verwundbares Feuer: so oft {Scorch} zu Kampfbeginn (Elites), dann halten. 0 = aus." },
        fireBlast = { order = 2, default = true, label = "{Fire Blast} auf Cooldown" },
        pyroOpener = { order = 3, default = true, label = "{Pyroblast} als Opener", desc = "Nur, solange das Ziel noch nicht kämpft." },
        filler = { order = 4, default = "fireball", values = { "fireball", "frostfire" },
                   valueLabels = { fireball = "{Fireball}", frostfire = "{Frostfire Bolt}" }, label = "Füller" },
        dotTrash = R.opt.dotTrash(41),
    }),
    rules = fireRules,
    hooks = {
        onReset = function(custom) custom.scorchStacks = 0 end,
        onTargetChanged = function(custom) custom.scorchStacks = 0 end,
        onCast = function(name, s, custom)
            if name == "Scorch" then custom.scorchStacks = math.min(5, (custom.scorchStacks or 0) + 1) end
        end,
    },
})

---------------------------------------------------------------------------
-- Frost
---------------------------------------------------------------------------

local frostRules = startRules()
R.append(frostRules, {
    { spell = "Evocation", reason = "Mana fehlt", label = "{spell} (wenn Mana fehlt)",
      cond = function(s) return s.inCombat and s.oom("Frostbolt") end },
    R.buff("Ice Barrier", { group = "barrier", combat = true, refresh = 0, cond = function(s) return s.opt("barrier") end,
        label = "{spell} halten (Option)" }),
    R.burst("Icy Veins"),
    R.aoe("Cone of Cold", "aoeMelee", function(s) return R.inRange(s, "Frostbolt") end),
    R.aoe("Blizzard", "aoe"),
    R.ready("Ice Lance", function(s) return s.opt("iceLance") end, "{spell} (Option)"),
    { spell = "Frostfire Bolt", reason = "Füller", label = "Füller: {spell} (Option)",
      cond = function(s) return s.hasTarget and filler(s, true, "Frostbolt") == "Frostfire Bolt" end },
    { spell = "Frostbolt", reason = "Füller", label = "Füller: {spell}",
      cond = function(s) return s.hasTarget and R.inRange(s, "Frostbolt") end },
})

ns:RegisterRotation({
    id = "MAGE_FROST",
    class = "MAGE",
    role = "DAMAGER",
    label = "Magier – Frost (Schaden)",
    signature = { "Ice Barrier", "Cold Snap" },
    rangeSpell = "Frostbolt",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    options = sharedOptions("ice", "Blizzard", {
        barrier = { order = 1, default = true, label = "{Ice Barrier} halten", desc = "Im Kampf auf Cooldown." },
        iceLance = { order = 2, default = false, label = "{Ice Lance} einbauen",
                     desc = "Lohnt nur gegen eingefrorene Ziele; Procs sind im Kampf nicht lesbar." },
        aoeMelee = { order = 21, default = 3, min = 1, max = 10, step = 1, label = "{Cone of Cold} ab Gegnern",
                     desc = "Anzahl Gegner im Kampf in Reichweite (über Namensplaketten gezählt)" },
        filler = { order = 4, default = "frostbolt", values = { "frostbolt", "frostfire" },
                   valueLabels = { frostbolt = "{Frostbolt}", frostfire = "{Frostfire Bolt}" }, label = "Füller" },
    }),
    rules = frostRules,
})

---------------------------------------------------------------------------
-- Arkan
---------------------------------------------------------------------------

-- Arcane Blast stapelt sich (ca. 6 s): N-mal Blast, dann Missiles zum Abbauen
local function blastStacks(s)
    if s.now - (s.custom.lastBlast or 0) > 6 then return 0 end
    return s.custom.blasts or 0
end

local arcaneRules = startRules()
R.append(arcaneRules, {
    { spell = "Evocation", reason = "Mana fehlt", label = "{spell} (wenn Mana fehlt)",
      cond = function(s) return s.inCombat and s.oom("Arcane Missiles") end },
    R.burst("Arcane Power"),
    R.burst("Presence of Mind"),
    R.aoe("Arcane Explosion", "aoe"),
    R.ready("Arcane Wrath"),
    { spell = "Arcane Blast", reason = "Stapel aufbauen", label = "{spell} stapeln",
      cond = function(s) return s.hasTarget and R.inRange(s, "Arcane Blast") and blastStacks(s) < s.opt("blasts") end },
    { spell = "Arcane Missiles", reason = "Füller", label = "Füller: {spell}",
      cond = function(s) return s.hasTarget and R.inRange(s, "Arcane Missiles") end },
    { spell = "Frostbolt", reason = "Füller", label = "Füller: {spell} (niedrige Stufe)",
      cond = function(s) return s.hasTarget and not s.known("Arcane Missiles") end },
})

ns:RegisterRotation({
    id = "MAGE_ARCANE",
    class = "MAGE",
    role = "DAMAGER",
    label = "Magier – Arkan (Schaden)",
    signature = { "Arcane Power", "Presence of Mind" },
    rangeSpell = "Arcane Missiles",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    options = sharedOptions("mage", "Arcane Explosion", {
        blasts = { order = 1, default = 3, min = 0, max = 4, step = 1, label = "{Arcane Blast} vor {Arcane Missiles}",
                   desc = "Jeder {Arcane Blast} verstärkt den nächsten und verdoppelt die Kosten. Danach {Arcane Missiles}. 0 = kein {Arcane Blast}." },
    }),
    rules = arcaneRules,
    hooks = {
        onReset = function(custom) custom.blasts = 0 end,
        onCast = function(name, s, custom)
            if name == "Arcane Blast" then
                custom.blasts = blastStacks(s) + 1
                custom.lastBlast = s.now
            elseif name == "Arcane Missiles" then
                custom.blasts = 0
            end
        end,
    },
})
