# Neue Rotation hinzufügen

1. Datei `Rotations/<Klasse>.lua` anlegen (eine Datei kann mehrere Spezialisierungen registrieren).
2. In `ForeverRotation.toc` vor `Display.lua` eintragen (nach `Locale.lua` und `Core.lua`).
3. `ns:RegisterRotation({...})` aufrufen:

```lua
local _, ns = ...

ns:RegisterRotation({
    id = "WARRIOR_ARMS",           -- eindeutig
    class = "WARRIOR",             -- Token aus UnitClass("player")
    spec = nil,                    -- optional: Index aus C_SpecializationInfo.GetSpecialization()
    role = "DAMAGER",              -- "TANK" | "DAMAGER" | "HEALER" – danach wählt der Kern die Rotation
    roleAura = nil,                -- optional: Buffs, die die Rolle verraten, z. B. { "Defensive Stance" }
    label = "Krieger – Waffen",
    rangeSpell = "Heroic Strike",  -- zählt Gegner in dieser Reichweite (Namensplaketten)

    -- Zauber-IDs (beliebiger Rang): Pflicht für nicht-englische Clients. Intern bleibt der
    -- englische Name der Schlüssel, das Spiel liefert den Namen in der Client-Sprache.
    -- IDs nachschlagen: https://www.wowhead.com/forever/spell=<ID>
    spellIds = { ["Battle Shout"] = 6673, ["Mortal Strike"] = 12294, ["Rend"] = 772 },

    -- Eigene Buffs, die im Kampf geheim sind: der Kern zählt sie über eigene Casts mit
    -- und gleicht sie außerhalb des Kampfs mit den echten Auren ab.
    buffGroups = {
        shout = { spells = { "Battle Shout" }, duration = 120 },
    },

    extraSpells = {},              -- Zauber, die nur in Bedingungen vorkommen (für s.known)

    -- Optionen erscheinen automatisch im Konfigurationsfenster (/frot):
    --   boolean -> Häkchen, Zahl mit min/max/step -> Minus/Plus, values -> Umschalt-Knopf
    options = {
        aoe   = { order = 1, default = 3, min = 1, max = 8, step = 1,
                  label = "Whirlwind ab Gegnern", desc = "Tooltip-Text" },
        shout = { order = 2, default = "battle", values = { "battle", "commanding" },
                  valueLabels = { battle = "Battle Shout", commanding = "Commanding Shout" },
                  label = "Ruf" },
        burst = { order = 3, default = true, label = "Cooldowns nutzen" },
    },

    rules = {                      -- Reihenfolge = Standard-Priorität (im Spiel änderbar)
        { spell = "Battle Shout", reason = "Ruf fehlt", label = "Battle Shout",
          cond = function(s) local n, rest = s.buff("shout"); return not n or rest < 5 end },
        -- Regeln mit gleicher `group` erscheinen im Prioritäten-Editor als EIN Eintrag
        { spell = "Rend", group = "dots", groupLabel = "DoTs", cond = function(s) return s.hasTarget end },
        { spell = "Mortal Strike", label = "Mortal Strike", cond = function(s) return s.hasTarget end },
    },

    hooks = {                      -- optional, eigener Zustand in `custom`
        onReset = function(custom) end,
        onTargetChanged = function(custom) end,
        onCast = function(spellName, s, custom) end,
    },
})
```

## Sprache

- **Zauber**: immer mit englischem Namen + Eintrag in `spellIds`. Ohne ID funktioniert der Zauber
  nur auf englischen Clients.
- **Texte** (`label`, `reason`, `desc`, `valueLabels`, `groupLabel`) deutsch schreiben und die
  englische Übersetzung in `Locale.lua` eintragen. Fehlt sie, erscheint der deutsche Text.
- Platzhalter: `{spell}` = Zauber der Regel, `{Mortal Strike}` = beliebiger Zauber – beides wird
  zum Namen in der Client-Sprache. Beispiel: `label = "{spell} (unter 20 %)"`.
- In Bedingungen und Hooks bekommst du immer den englischen Schlüssel (`onCast(name, …)`).

## Prioritäten-Editor

`/frot` → „Prioritäten bearbeiten“ (oder `/frot prio`): Einträge per Pfeil verschieben, per Häkchen
abschalten, gespeichert pro Rotation in `db.rulePrefs`. Eintrag = Regel oder Gruppe (`group`).
Anzeigename: `groupLabel` > `label` > „Zauber – reason“. Kommen nach einem Update neue Regeln dazu,
landen sie hinter ihrem Vorgänger aus der Standardreihenfolge. Schlüssel einer Regel:
`group` > `id` > Zauber + reason – also `reason` nicht ohne Grund umbenennen, sonst geht die
gespeicherte Reihenfolge für diese Regel verloren.

## Rolle statt Talente

Welche Rotation gilt, entscheidet die **Rolle**, nicht der Talentbaum. Ein Vergeltungs-Paladin
in der Tankrolle bekommt die Tank-Rotation. Automatische Erkennung (`/frot role auto`):

1. Rolle in der Gruppe (`UnitGroupRolesAssigned`)
2. ein Buff aus `roleAura` ist aktiv (außerhalb des Kampfs geprüft, im Kampf über eigene Casts)
3. sonst Schaden

Von Hand: `/frot role tank|dps|heal` oder im Fenster unter „Rolle“. Gibt es für eine Rolle keine
Rotation der Klasse, wird die erste Rotation der Klasse genommen. Mehrere Klassen-Dateien können
sich Hilfsfunktionen teilen, siehe `Paladin.lua` (gemeinsame Aura-/Segen-Regeln).

## Was eine Bedingung `s` abfragen kann

Nur Werte, die in Forever **im Kampf lesbar** sind (gemessen mit ForeverProbe):

| Feld / Funktion | Bedeutung |
|---|---|
| `s.now`, `s.inCombat`, `s.gcdRemain` | Zeit, Kampfstatus, Rest-GCD (mitgezählt) |
| `s.hasTarget`, `s.targetElite`, `s.targetClassification` | angreifbares Ziel, elite/rareelite/worldboss |
| `s.targetType` | Kreaturtyp-ID: 1 Wildtier, 3 Dämon, 6 Untoter, 7 Humanoid … |
| `s.targetIsPlayer` | Ziel ist Spieler |
| `s.targetInCombat` | Ziel ist im Kampf |
| `s.threat` | Bedrohung auf das Ziel: 3 du tankst sicher, 2 knapp, 1/0/nil nicht du (für Spott-Regeln) |
| `s.role` | erkannte Rolle: TANK, DAMAGER, HEALER |
| `s.targetCasting`, `s.targetInterruptible` | Ziel wirkt einen Zauber; unterbrechbar (`false` = nein, `nil` = unbekannt) |
| `s.combatStart` | GetTime() beim Kampfbeginn |
| `s.swingSpeed` | Waffengeschwindigkeit (außerhalb des Kampfs gemessen, sonst 3,5) – zum Schätzen von Schlägen |
| `s.enemies` | Gegner im Kampf in Reichweite von `rangeSpell` |
| `s.known(name)` | Zauber gelernt |
| `s.cdRemain(name)` | Rest-Cooldown (mitgezählt, außerhalb des Kampfs exakt) |
| `s.usable(name)` | nutzbar, zu wenig Mana (prüft z. B. Execute-Phasen automatisch) |
| `s.inRange(name)` | true / false / nil (kein Reichweitenzauber) |
| `s.buff(gruppe)` | aktiver Buff der Gruppe und Restzeit (geschätzt im Kampf) |
| `s.opt(name)` | Option der Rotation |
| `s.custom` | eigener Zustand der Rotation (Hooks) |

**Nicht** verfügbar (im Kampf geheim): Leben/Mana in Zahlen, Auren-Inhalte, echte Cooldown-Zeiten, Kampflog.
