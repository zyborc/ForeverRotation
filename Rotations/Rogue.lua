-- Schurke, WoW Forever: eine Rotation für alle Spezialisierungen, der Aufbauer ist wählbar.
--
-- Forever-Besonderheiten (Stand Nov 2026, im Spiel prüfen):
--   * Mutilate (Meucheln) ist trainierbar/Talent und gibt 2 Combo-Punkte.
--   * Shank (ab Stufe 24): Schlag mit der Nebenhand, erzeugt 15 Energie; mit dem Talent Venom
--     verstärkt er zusätzlich deine Gifte für 6 s.
--   * Combo-Punkte bleiben beim Zielwechsel auf dem ursprünglichen Ziel, Energie fließt gleichmäßig.
--   * Combo-Punkte sind im Kampf vermutlich geheim: sie werden über eigene Casts mitgezählt
--     (Kritische Treffer mit Seal Fate o. ä. sieht das Addon nicht – lieber etwas zu früh beenden).

local _, ns = ...
local R = ns.R

local SPELL_IDS = {
    ["Stealth"] = 1784, ["Ambush"] = 8676, ["Cheap Shot"] = 1833, ["Garrote"] = 703,
    ["Sinister Strike"] = 1752, ["Backstab"] = 53, ["Hemorrhage"] = 16511, ["Mutilate"] = 1241585,
    ["Ghostly Strike"] = 14278, ["Riposte"] = 14251, ["Shank"] = 1329283,
    ["Slice and Dice"] = 5171, ["Rupture"] = 1943, ["Eviscerate"] = 2098, ["Expose Armor"] = 8647,
    ["Kick"] = 1766, ["Blade Flurry"] = 13877, ["Adrenaline Rush"] = 13750, ["Cold Blood"] = 14177,
}

local BUILDERS = {
    { key = "mutilate", name = "Mutilate" },
    { key = "hemorrhage", name = "Hemorrhage" },
    { key = "backstab", name = "Backstab" },
    { key = "sinister", name = "Sinister Strike" },
}

-- Aufbauer: "auto" = Mutilate > Hemorrhage > Sinister Strike (Backstab nur auf Wunsch, Position unbekannt)
local function builder(s)
    local choice = s.opt("builder")
    if choice ~= "auto" then
        for _, e in ipairs(BUILDERS) do
            if e.key == choice and s.known(e.name) then return e.name end
        end
    end
    for _, n in ipairs({ "Mutilate", "Hemorrhage", "Sinister Strike" }) do
        if s.known(n) then return n end
    end
    return "Sinister Strike"
end

local function finishAt(s) return s.opt("finishAt") end

local rules = {
    R.interrupt("Kick"),

    -- Opener aus der Verstohlenheit
    { spell = "Ambush", reason = "Opener aus der Verstohlenheit", group = "opener", groupLabel = "Opener aus der Verstohlenheit",
      cond = function(s) return s.stealthed and s.hasTarget and s.opt("opener") == "ambush" end },
    { spell = "Cheap Shot", reason = "Opener aus der Verstohlenheit", group = "opener",
      cond = function(s) return s.stealthed and s.hasTarget and s.opt("opener") == "cheap" end },
    { spell = "Garrote", reason = "Opener aus der Verstohlenheit", group = "opener",
      cond = function(s) return s.stealthed and s.hasTarget and s.opt("opener") == "garrote" end },

    R.reactive("Riposte"),

    -- Finisher
    { spell = "Slice and Dice", reason = "Buff fehlt / läuft aus", label = "{spell} halten",
      cond = function(s)
          if not (s.inCombat and s.hasTarget and s.opt("snd")) then return false end
          local active, remain = s.buff("snd")
          return s.combo >= 1 and (not active or remain < 2)
      end },
    R.burst("Cold Blood", function(s) return s.combo >= finishAt(s) end),
    { spell = "Rupture", reason = "Finisher: Blutung fehlt", label = "{spell} (Finisher, Option)",
      cond = function(s)
          local mode = s.opt("rupture")
          if mode == "off" or not (s.inCombat and s.hasTarget) then return false end
          if mode == "elite" and not (s.targetElite or s.targetIsPlayer) then return false end
          if s.combo < finishAt(s) then return false end
          return not s.debuff("rupture")
      end },
    { spell = "Eviscerate", reason = "Finisher: genug Combo-Punkte", label = "{spell} (Finisher)",
      cond = function(s) return s.hasTarget and s.combo >= finishAt(s) and R.inRange(s, "Eviscerate") end },

    -- Cooldowns
    R.aoe("Blade Flurry", "aoe"),
    R.burst("Adrenaline Rush"),

    -- Energie
    { spell = "Shank", reason = "Energie fehlt", label = "{spell} (Energie, Option)",
      cond = function(s)
          local mode = s.opt("shank")
          if mode == "off" or not (s.inCombat and s.hasTarget) then return false end
          if mode == "cooldown" then return R.inRange(s, "Shank") end
          return s.oom(builder(s))
      end },

    -- Aufbauer
    R.ready("Ghostly Strike", function(s) return s.combo < finishAt(s) end),
    { spell = "Mutilate", reason = "Combo-Punkte aufbauen", group = "builder", groupLabel = "Aufbauer (Option)",
      cond = function(s) return s.hasTarget and builder(s) == "Mutilate" end },
    { spell = "Hemorrhage", reason = "Combo-Punkte aufbauen", group = "builder",
      cond = function(s) return s.hasTarget and builder(s) == "Hemorrhage" end },
    { spell = "Backstab", reason = "Combo-Punkte aufbauen", group = "builder",
      cond = function(s) return s.hasTarget and builder(s) == "Backstab" end },
    { spell = "Sinister Strike", reason = "Combo-Punkte aufbauen", group = "builder",
      cond = function(s) return s.hasTarget and builder(s) == "Sinister Strike" end },
}

ns:RegisterRotation({
    id = "ROGUE",
    class = "ROGUE",
    role = "DAMAGER",
    label = "Schurke (Schaden)",
    rangeSpell = "Sinister Strike",
    spellIds = SPELL_IDS,
    buffGroups = {
        snd = { spells = { "Slice and Dice" }, duration = function(cp) return 6 + 3 * math.max(1, cp) end },
    },
    debuffs = {
        rupture = { spells = { "Rupture" }, duration = function(cp) return 6 + 2 * math.max(1, cp) end },
        garrote = { spells = { "Garrote" }, duration = 18 },
    },
    combo = {
        builders = { ["Sinister Strike"] = 1, ["Backstab"] = 1, ["Hemorrhage"] = 1, ["Mutilate"] = 2,
                     ["Ghostly Strike"] = 1, ["Ambush"] = 1, ["Cheap Shot"] = 2, ["Garrote"] = 1 },
        finishers = { "Slice and Dice", "Rupture", "Eviscerate", "Expose Armor" },
        max = 5,
    },
    options = {
        builder = { order = 1, default = "auto", label = "Aufbauer",
                    values = { "auto", "mutilate", "hemorrhage", "backstab", "sinister" },
                    valueLabels = { auto = "automatisch", mutilate = "{Mutilate}", hemorrhage = "{Hemorrhage}",
                                    backstab = "{Backstab}", sinister = "{Sinister Strike}" },
                    desc = "automatisch = {Mutilate} > {Hemorrhage} > {Sinister Strike}. {Backstab} nur, wenn du sicher hinter dem Ziel stehst (Dolch)." },
        finishAt = { order = 2, default = 5, min = 1, max = 5, step = 1, label = "Finisher ab Combo-Punkten",
                     desc = "Combo-Punkte werden mitgezählt; Extrapunkte durch kritische Treffer sieht das Addon nicht." },
        snd      = { order = 3, default = true, label = "{Slice and Dice} halten" },
        rupture  = { order = 4, default = "elite", values = { "elite", "always", "off" },
                     valueLabels = { elite = "Elites/Bosse", always = "immer", off = "aus" },
                     label = "{Rupture} als Finisher", desc = "Vor {Eviscerate}, wenn keine Blutung auf dem Ziel ist." },
        opener   = { order = 5, default = "ambush", values = { "ambush", "cheap", "garrote", "off" },
                     valueLabels = { ambush = "{Ambush}", cheap = "{Cheap Shot}", garrote = "{Garrote}", off = "aus" },
                     label = "Opener aus der Verstohlenheit" },
        shank    = { order = 6, default = "energy", values = { "energy", "cooldown", "off" },
                     valueLabels = { energy = "bei Energiemangel", cooldown = "auf Cooldown", off = "aus" },
                     label = "{Shank}", desc = "{Shank} erzeugt Energie; mit dem Talent Venom lohnt er sich auf Cooldown." },
        aoe      = R.opt.aoe("Blade Flurry", 2, 20),
        burst    = R.opt.burst(30),
        interrupt = R.opt.interrupt("Kick", 90),
    },
    rules = rules,
})
