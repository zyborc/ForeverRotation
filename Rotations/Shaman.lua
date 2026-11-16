-- Schamane, WoW Forever: Elementar, Verstärkung (Schaden) und Wiederherstellung (Heiler).
--
-- Forever-Besonderheiten (Stand Nov 2026, im Spiel prüfen):
--   * Totems halten meist 5 min; Call of the Elements/Ancestors/Spirits setzt bis zu 4 Totems
--     der Totemleiste auf einmal. Totems werden im Kampf mitgezählt, außerhalb exakt abgeglichen.
--   * Lava Burst (+20 % mit Flame Shock), Lightning Mastery (statt Elemental Mastery),
--     Rage of the Farseer (+30 % Angriffstempo), Water Shield, Riptide.
--   * Lightning Bolt 2,5 s, Chain Lightning 2 s Zauberzeit.

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Flame Shock"] = 8050, ["Earth Shock"] = 8042, ["Frost Shock"] = 8056, ["Lava Burst"] = 408490,
    ["Lightning Bolt"] = 403, ["Chain Lightning"] = 421, ["Lightning Shield"] = 324, ["Water Shield"] = 408510,
    ["Lightning Mastery"] = 16166, ["Rage of the Farseer"] = 425336, ["Stormstrike"] = 17364, ["Lava Lash"] = 408507,
    ["Fire Nova"] = 408341,
    ["Windfury Weapon"] = 8232, ["Flametongue Weapon"] = 8024, ["Rockbiter Weapon"] = 8017, ["Frostbrand Weapon"] = 8033,
    ["Searing Totem"] = 3599, ["Magma Totem"] = 8190, ["Flametongue Totem"] = 8227,
    ["Strength of Earth Totem"] = 8075, ["Stoneskin Totem"] = 8071, ["Tremor Totem"] = 8143,
    ["Windfury Totem"] = 8512, ["Grace of Air Totem"] = 8835,
    ["Mana Spring Totem"] = 5675, ["Healing Stream Totem"] = 5394, ["Mana Tide Totem"] = 16190,
    ["Call of the Elements"] = 66842, ["Call of the Ancestors"] = 66843, ["Call of the Spirits"] = 66844,
    ["Riptide"] = 408521,
}

local CALLS = { "Call of the Elements", "Call of the Ancestors", "Call of the Spirits" }

local TOTEMS = {
    fire  = { slot = 1, label = "Feuertotem",
              list = { { key = "searing", name = "Searing Totem" }, { key = "magma", name = "Magma Totem" },
                       { key = "flametongue", name = "Flametongue Totem" } } },
    earth = { slot = 2, label = "Erdtotem",
              list = { { key = "strength", name = "Strength of Earth Totem" }, { key = "stoneskin", name = "Stoneskin Totem" },
                       { key = "tremor", name = "Tremor Totem" } } },
    water = { slot = 3, label = "Wassertotem",
              list = { { key = "manaspring", name = "Mana Spring Totem" }, { key = "healingstream", name = "Healing Stream Totem" } } },
    air   = { slot = 4, label = "Lufttotem",
              list = { { key = "windfury", name = "Windfury Totem" }, { key = "grace", name = "Grace of Air Totem" } } },
}
local ELEMENTS = { "fire", "earth", "air", "water" }

local IMBUES = {
    { key = "windfury", name = "Windfury Weapon" },
    { key = "flametongue", name = "Flametongue Weapon" },
    { key = "rockbiter", name = "Rockbiter Weapon" },
    { key = "frostbrand", name = "Frostbrand Weapon" },
}

local function missingTotems(s)
    local n = 0
    for _, el in ipairs(ELEMENTS) do
        if s.opt("totem_" .. el) ~= "off" and not s.buff(el) then n = n + 1 end
    end
    return n
end

-- Totems im Kampf setzen (Heiler auch ohne feindliches Ziel)
local function totemTime(s)
    return s.inCombat and (s.hasTarget or s.role == "HEALER")
end

-- Totem-Regeln: zuerst "Call of ..." (wenn mehrere fehlen), dann einzelne Totems
local function totemRules()
    local rules = {}
    for _, call in ipairs(CALLS) do
        rules[#rules + 1] = { spell = call, reason = "Totems fehlen", group = "call", groupLabel = "Totemruf (mehrere Totems fehlen)",
            cond = function(s)
                if s.opt("call") == "off" or not totemTime(s) or missingTotems(s) < 2 then return false end
                for _, c in ipairs(CALLS) do
                    if s.known(c) then return c == call end   -- erster bekannter Ruf
                end
                return false
            end }
    end
    for _, el in ipairs(ELEMENTS) do
        local t = TOTEMS[el]
        for _, e in ipairs(t.list) do
            local name = e.name
            rules[#rules + 1] = { spell = name, reason = "Totem fehlt", group = "totem_" .. el, groupLabel = t.label,
                cond = function(s)
                    return totemTime(s) and not s.buff(el) and R.wanted(s, "totem_" .. el, t.list) == name
                end }
        end
    end
    return rules
end

local function shieldRule(name)
    return R.buff(name, { group = "shield", refresh = 0, refreshOOC = 60, entry = "shield", entryLabel = "Schild (Option)",
        cond = function(s) return s.opt("shield") == (name == "Water Shield" and "water" or "lightning") end })
end

local function imbueRules()
    local rules = {}
    for _, hand in ipairs({ "main", "off" }) do
        for _, e in ipairs(IMBUES) do
            local name = e.name
            rules[#rules + 1] = { spell = name, reason = "Waffenverzauberung fehlt", group = "imbue_" .. hand,
                groupLabel = hand == "main" and "Waffenverzauberung Haupthand" or "Waffenverzauberung Nebenhand",
                cond = function(s)
                    if s.inCombat then return false end
                    if hand == "off" and not ns.safe(OffhandHasWeapon) then return false end
                    local active, remain = s.buff("imbue_" .. hand)
                    return (not active or remain < 60) and R.wanted(s, "imbue_" .. hand, IMBUES) == name
                end }
        end
    end
    return rules
end

local function buffGroups()
    local g = {
        shield = { spells = { "Lightning Shield", "Water Shield" }, duration = 600 },
        imbue_main = { spells = R.names(IMBUES), duration = 1800, weaponEnchant = "main" },
        imbue_off = { spells = R.names(IMBUES), duration = 1800, weaponEnchant = "off" },
    }
    for _, el in ipairs(ELEMENTS) do
        local spells = R.names(TOTEMS[el].list)
        for _, c in ipairs(CALLS) do spells[#spells + 1] = c end
        g[el] = { spells = spells, duration = 300, totemSlot = TOTEMS[el].slot }
    end
    return g
end

local function totemOptions(defaults)
    local o = {
        call = { order = 60, default = "on", values = { "on", "off" }, valueLabels = { on = "an", off = "aus" },
                 label = "Totemruf nutzen", desc = "{Call of the Elements} usw. setzt die Totems deiner Totemleiste, wenn zwei oder mehr fehlen." },
    }
    for i, el in ipairs(ELEMENTS) do
        local t = TOTEMS[el]
        o["totem_" .. el] = { order = 60 + i, default = defaults[el], values = R.keys(t.list, true),
                              valueLabels = R.labels(t.list), label = t.label }
    end
    return o
end

local function imbueOptions(main, off)
    return {
        imbue_main = { order = 70, default = main, values = R.keys(IMBUES, true), valueLabels = R.labels(IMBUES),
                       label = "Waffenverzauberung Haupthand" },
        imbue_off  = { order = 71, default = off, values = R.keys(IMBUES, true), valueLabels = R.labels(IMBUES),
                       label = "Waffenverzauberung Nebenhand", desc = "Nur mit zwei Waffen." },
        shield     = { order = 72, default = "lightning", values = { "lightning", "water", "off" },
                       valueLabels = { lightning = "{Lightning Shield}", water = "{Water Shield}", off = "aus" }, label = "Schild" },
    }
end

---------------------------------------------------------------------------
-- Elementar
---------------------------------------------------------------------------

local eleRules = { R.interrupt("Earth Shock"), shieldRule("Lightning Shield"), shieldRule("Water Shield") }
R.append(eleRules, imbueRules())
R.append(eleRules, totemRules())
R.append(eleRules, {
    R.burst("Lightning Mastery"),
    R.dot("Flame Shock", { group = "flameshock" }),
    R.ready("Lava Burst"),
    R.aoe("Fire Nova", "aoe"),
    R.ready("Chain Lightning", function(s) return s.enemies >= 2 or s.opt("chainST") end, "{spell} (ab 2 Gegnern oder Option)"),
    { spell = "Lightning Bolt", reason = "Füller", label = "Füller: {spell}",
      cond = function(s) return s.hasTarget and R.inRange(s, "Lightning Bolt") end },
})

ns:RegisterRotation({
    id = "SHAMAN_ELEMENTAL",
    class = "SHAMAN",
    role = "DAMAGER",
    label = "Schamane – Elementar (Schaden)",
    signature = { "Lightning Mastery", "Lava Burst" },
    rangeSpell = "Lightning Bolt",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups(),
    debuffs = { flameshock = { spells = { "Flame Shock" }, duration = 12 } },
    options = R.options(totemOptions({ fire = "searing", earth = "strength", air = "grace", water = "manaspring" }),
        imbueOptions("flametongue", "off"), {
        chainST = { order = 2, default = false, label = "{Chain Lightning} auch gegen ein Ziel" },
        aoe = R.opt.aoe("Fire Nova", 3, 20),
        burst = R.opt.burst(30),
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
        interrupt = R.opt.interrupt("Earth Shock", 90),
    }),
    rules = eleRules,
})

---------------------------------------------------------------------------
-- Verstärkung
---------------------------------------------------------------------------

local SHOCKS = {
    { key = "earth", name = "Earth Shock" },
    { key = "flame", name = "Flame Shock" },
    { key = "frost", name = "Frost Shock" },
}

local enhRules = { R.interrupt("Earth Shock"), shieldRule("Lightning Shield"), shieldRule("Water Shield") }
R.append(enhRules, imbueRules())
R.append(enhRules, totemRules())
R.append(enhRules, {
    R.burst("Rage of the Farseer"),
    R.ready("Stormstrike"),
    R.dot("Flame Shock", { group = "flameshock", cond = function(s) return s.opt("shock") == "flame" end,
        label = "{spell} halten (Schock-Option)" }),
    R.ready("Lava Lash"),
    R.aoe("Fire Nova", "aoe"),
    { spell = "Earth Shock", reason = "{spell} bereit", group = "shock", groupLabel = "Schock (Option)",
      cond = function(s) return s.hasTarget and s.opt("shock") == "earth" and R.inRange(s, "Earth Shock") end },
    { spell = "Frost Shock", reason = "{spell} bereit", group = "shock",
      cond = function(s) return s.hasTarget and s.opt("shock") == "frost" and R.inRange(s, "Frost Shock") end },
    { spell = "Lightning Bolt", reason = "Auf Distanz", label = "{spell} (auf Distanz)",
      cond = function(s) return s.hasTarget and s.inRange("Stormstrike") == false and R.inRange(s, "Lightning Bolt") end },
})

ns:RegisterRotation({
    id = "SHAMAN_ENHANCEMENT",
    class = "SHAMAN",
    role = "DAMAGER",
    label = "Schamane – Verstärkung (Schaden)",
    signature = { "Stormstrike", "Rage of the Farseer" },
    rangeSpell = "Stormstrike",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups(),
    debuffs = { flameshock = { spells = { "Flame Shock" }, duration = 12 } },
    options = R.options(totemOptions({ fire = "searing", earth = "strength", air = "windfury", water = "manaspring" }),
        imbueOptions("windfury", "flametongue"), {
        shock = { order = 2, default = "earth", values = R.keys(SHOCKS, true), valueLabels = R.labels(SHOCKS), label = "Schock" },
        aoe = R.opt.aoe("Fire Nova", 3, 20),
        burst = R.opt.burst(30),
        dotRefresh = R.opt.dotRefresh(40),
        dotTrash = R.opt.dotTrash(41),
        interrupt = R.opt.interrupt("Earth Shock", 90),
    }),
    rules = enhRules,
})

---------------------------------------------------------------------------
-- Wiederherstellung (Heiler): Schild, Totems, Waffe, Riptide auf Cooldown
---------------------------------------------------------------------------

local restoRules = { shieldRule("Water Shield"), shieldRule("Lightning Shield") }
R.append(restoRules, imbueRules())
R.append(restoRules, totemRules())
R.append(restoRules, {
    { spell = "Riptide", reason = "Auf Cooldown halten", label = "{spell} auf Cooldown (Option)",
      cond = function(s) return s.opt("riptide") and s.inCombat end },
    R.dot("Flame Shock", { group = "flameshock", cond = function(s) return s.opt("dps") end, label = "{spell} (Schaden, Option)" }),
    R.ready("Lightning Bolt", function(s) return s.opt("dps") end, "{spell} (Schaden, Option)"),
})

ns:RegisterRotation({
    id = "SHAMAN_RESTORATION",
    class = "SHAMAN",
    role = "HEALER",
    label = "Schamane – Wiederherstellung (Buffs & Totems)",
    rangeSpell = "Lightning Bolt",
    spellIds = SPELL_IDS,
    buffGroups = buffGroups(),
    debuffs = { flameshock = { spells = { "Flame Shock" }, duration = 12 } },
    options = R.options(totemOptions({ fire = "off", earth = "stoneskin", air = "grace", water = "manaspring" }),
        imbueOptions("flametongue", "off"), {
        shield = { order = 72, default = "water", values = { "lightning", "water", "off" },
                   valueLabels = { lightning = "{Lightning Shield}", water = "{Water Shield}", off = "aus" }, label = "Schild" },
        riptide = { order = 1, default = true, label = "{Riptide} auf Cooldown" },
        dps = { order = 3, default = false, label = "Schaden, wenn nichts zu heilen ist",
                desc = "Leben ist im Kampf geheim – schalte das ein, wenn du zwischendurch Schaden machen willst." },
        dotRefresh = R.opt.dotRefresh(40),
    }),
    rules = restoRules,
})
