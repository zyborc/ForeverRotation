-- Hexenmeister, WoW Forever: Gebrechen/Dämonologie (DoTs) und Zerstörung.
--
-- Forever-Besonderheiten (Stand Nov 2026, im Spiel prüfen):
--   * Curse of Agony/Doom heißen jetzt Bane of Agony/Doom. Banes zählen getrennt von Flüchen:
--     ein Fluch UND ein Bane pro Ziel gleichzeitig.
--   * Bane of Havoc (5 min, 15 % deines Schadens springt auf das verfluchte Ziel über).
--   * Wrack (Gebrechen): Kanalisierung, während der deine DoTs schneller ticken.
--   * Incinerate (Zerstörung): +25 % Schaden, wenn Immolate auf dem Ziel ist.
--   * DoTs sind Auren und im Kampf geheim: sie werden über eigene Casts pro Ziel mitgezählt.

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Corruption"] = 172, ["Bane of Agony"] = 980, ["Bane of Doom"] = 603, ["Bane of Havoc"] = 1225228,
    ["Curse of the Elements"] = 440892, ["Curse of Recklessness"] = 704, ["Curse of Weakness"] = 702,
    ["Curse of Tongues"] = 1714, ["Immolate"] = 348, ["Siphon Life"] = 18265, ["Shadow Bolt"] = 686,
    ["Incinerate"] = 412758, ["Conflagrate"] = 17962, ["Shadowburn"] = 17877, ["Soul Fire"] = 6353,
    ["Drain Life"] = 689, ["Drain Soul"] = 1120, ["Life Tap"] = 1454, ["Wrack"] = 1316697,
    ["Demon Armor"] = 706, ["Demon Skin"] = 687, ["Fel Armor"] = 403619, ["Searing Pain"] = 5676,
    ["Summon Imp"] = 688, ["Summon Voidwalker"] = 697, ["Summon Succubus"] = 712, ["Summon Felhunter"] = 691,
    ["Summon Felguard"] = 427733, ["Hellfire"] = 1949, ["Rain of Fire"] = 5740,
}

local CURSES = {
    { key = "elements", name = "Curse of the Elements" },
    { key = "recklessness", name = "Curse of Recklessness" },
    { key = "weakness", name = "Curse of Weakness" },
    { key = "tongues", name = "Curse of Tongues" },
}
local BANES = {
    { key = "agony", name = "Bane of Agony" },
    { key = "doom", name = "Bane of Doom" },
}
local PETS = {
    { key = "imp", name = "Summon Imp" },
    { key = "voidwalker", name = "Summon Voidwalker" },
    { key = "succubus", name = "Summon Succubus" },
    { key = "felhunter", name = "Summon Felhunter" },
    { key = "felguard", name = "Summon Felguard" },
}
local ARMORS = {
    { key = "fel", name = "Fel Armor" },
    { key = "demon", name = "Demon Armor" },
}

local function armorWanted(s)
    local choice = s.opt("armor")
    if choice == "off" then return nil end
    if choice == "fel" and s.known("Fel Armor") then return "Fel Armor" end
    if s.known("Demon Armor") then return "Demon Armor" end
    return s.known("Demon Skin") and "Demon Skin" or nil
end

-- Bane of Doom lohnt nur auf langen Kämpfen (Elites)
local function baneWanted(s)
    local w = R.wanted(s, "bane", BANES)
    if w == "Bane of Doom" and not (s.targetElite or s.targetIsPlayer) then
        return s.known("Bane of Agony") and "Bane of Agony" or nil
    end
    return w
end

local function startRules()
    local rules = {}
    for _, name in ipairs({ "Fel Armor", "Demon Armor", "Demon Skin" }) do
        rules[#rules + 1] = { spell = name, reason = "Buff fehlt / läuft aus", group = "armor", groupLabel = "Rüstung (Option)",
            cond = function(s)
                local active, remain = s.buff("armor")
                return armorWanted(s) == name and (not active or (not s.inCombat and remain < 60))
            end }
    end
    for _, e in ipairs(PETS) do
        rules[#rules + 1] = R.pet(e.name, function(s)
            return s.opt("pet") ~= "off" and R.wanted(s, "pet", PETS) or nil
        end)
    end
    return rules
end

local function curseRules(rules)
    for _, e in ipairs(CURSES) do
        local name = e.name
        rules[#rules + 1] = R.dot(name, { group = "curse", entry = "curse", entryLabel = "Fluch (Option)",
            reason = "Fluch fehlt", cond = function(s) return R.wanted(s, "curse", CURSES) == name end })
    end
    for _, e in ipairs(BANES) do
        local name = e.name
        rules[#rules + 1] = R.dot(name, { group = "bane", entry = "bane", entryLabel = "Bane (Option)",
            cond = function(s) return baneWanted(s) == name end })
    end
    return rules
end

local buffGroups = {
    armor = { spells = { "Fel Armor", "Demon Armor", "Demon Skin" }, duration = 1800 },
}
local debuffs = {
    curse      = { spells = R.names(CURSES), duration = 300 },
    bane       = { spells = { "Bane of Agony", "Bane of Doom" }, duration = 24, durations = { ["Bane of Doom"] = 60 } },
    corruption = { spells = { "Corruption" }, duration = 18 },
    immolate   = { spells = { "Immolate" }, duration = 15 },
    siphon     = { spells = { "Siphon Life" }, duration = 30 },
}

local function sharedOptions(defaults, extra)
    return R.options({
        curse = { order = 1, default = defaults.curse, values = R.keys(CURSES, true), valueLabels = R.labels(CURSES), label = "Fluch" },
        bane  = { order = 2, default = defaults.bane, values = R.keys(BANES, true), valueLabels = R.labels(BANES), label = "Bane",
                  desc = "{Bane of Doom} nur auf Elites/Bossen, sonst {Bane of Agony}." },
        pet   = { order = 48, default = defaults.pet, values = R.keys(PETS, true), valueLabels = R.labels(PETS),
                  label = "Begleiter", desc = "Erinnert außerhalb des Kampfs, wenn kein Begleiter da ist. Nicht gelernt: nächster bekannter." },
        armor = { order = 49, default = "fel", values = { "fel", "demon", "off" },
                  valueLabels = { fel = "{Fel Armor}", demon = "{Demon Armor}", off = "aus" }, label = "Rüstung" },
        aoe   = R.opt.aoe("Rain of Fire", 4, 20),
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
    }, extra)
end

---------------------------------------------------------------------------
-- Gebrechen (auch Dämonologie)
---------------------------------------------------------------------------

local function makeAffliction(id, label, signature, defaults)
    local rules = startRules()
    R.append(rules, {
        R.regen("Life Tap", "Shadow Bolt"),
    })
    curseRules(rules)
    R.append(rules, {
        R.dot("Corruption", { group = "corruption" }),
        R.dot("Siphon Life", { group = "siphon" }),
        R.dot("Immolate", { group = "immolate", cond = function(s) return s.opt("immolate") end,
            label = "{spell} halten (Option)" }),
        { spell = "Wrack", reason = "DoTs verstärken", label = "{spell} (wenn DoTs laufen)",
          cond = function(s)
              return s.opt("wrack") and s.inCombat and s.hasTarget and s.debuff("corruption") ~= nil
                  and s.debuff("bane") ~= nil and R.inRange(s, "Wrack")
          end },
        R.aoe("Rain of Fire", "aoe"),
        { spell = "Shadow Bolt", reason = "Füller", label = "Füller: {spell}",
          cond = function(s) return s.hasTarget and R.inRange(s, "Shadow Bolt") end },
    })
    ns:RegisterRotation({
        id = id,
        class = "WARLOCK",
        role = "DAMAGER",
        label = label,
        signature = signature,
        rangeSpell = "Shadow Bolt",
        spellIds = SPELL_IDS,
        buffGroups = buffGroups,
        debuffs = debuffs,
        options = sharedOptions(defaults, {
            immolate = { order = 3, default = false, label = "{Immolate} halten", desc = "Kostet viel Mana für wenig Schaden im Gebrechen-Baum." },
            wrack = { order = 4, default = true, label = "{Wrack} nutzen", desc = "Kanalisieren, solange {Corruption} und ein Bane laufen." },
        }),
        rules = rules,
    })
end

makeAffliction("WARLOCK_AFFLICTION", "Hexenmeister – Gebrechen (Schaden)", { "Siphon Life", "Wrack" },
    { curse = "elements", bane = "agony", pet = "imp" })

---------------------------------------------------------------------------
-- Zerstörung
---------------------------------------------------------------------------

local function destroFiller(s)
    if s.opt("filler") == "incinerate" and s.known("Incinerate") and s.debuff("immolate") then return "Incinerate" end
    return "Shadow Bolt"
end

local destroRules = startRules()
R.append(destroRules, { R.regen("Life Tap", "Shadow Bolt") })
curseRules(destroRules)
R.append(destroRules, {
    R.dot("Immolate", { group = "immolate" }),
    R.ready("Conflagrate", function(s) return s.debuff("immolate") ~= nil end, "{spell} (mit {Immolate})"),
    R.dot("Corruption", { group = "corruption", cond = function(s) return s.opt("corruption") end,
        label = "{spell} halten (Option)" }),
    R.ready("Shadowburn", function(s) return s.opt("shadowburn") end, "{spell} (Option, kostet Seelensplitter)"),
    R.aoe("Rain of Fire", "aoe"),
    { spell = "Incinerate", reason = "Füller", label = "Füller: {spell} (mit {Immolate})",
      cond = function(s) return s.hasTarget and destroFiller(s) == "Incinerate" end },
    { spell = "Shadow Bolt", reason = "Füller", label = "Füller: {spell}",
      cond = function(s) return s.hasTarget and R.inRange(s, "Shadow Bolt") end },
})

ns:RegisterRotation({
    id = "WARLOCK_DESTRUCTION",
    class = "WARLOCK",
    role = "DAMAGER",
    label = "Hexenmeister – Zerstörung (Schaden)",
    signature = { "Conflagrate", "Shadowburn", "Incinerate" },
    rangeSpell = "Shadow Bolt",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups,
    debuffs = debuffs,
    options = sharedOptions({ curse = "elements", bane = "off", pet = "imp" }, {
        corruption = { order = 3, default = true, label = "{Corruption} halten" },
        shadowburn = { order = 4, default = false, label = "{Shadowburn} nutzen" },
        filler = { order = 5, default = "incinerate", values = { "incinerate", "shadowbolt" },
                   valueLabels = { incinerate = "{Incinerate}", shadowbolt = "{Shadow Bolt}" }, label = "Füller",
                   desc = "{Incinerate} nur, solange {Immolate} auf dem Ziel ist." },
    }),
    rules = destroRules,
})

makeAffliction("WARLOCK_DEMONOLOGY", "Hexenmeister – Dämonologie (Schaden)", { "Summon Felguard" },
    { curse = "elements", bane = "agony", pet = "felguard" })
