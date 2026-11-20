# ForeverRotation

Rotationshelfer für **World of Warcraft: Forever** (Client 1.60, `Interface 16001`). Zeigt den nächsten
Zauber als großes Icon mit Timeline, lässt ihn auf der Aktionsleiste leuchten und wertet nach dem Kampf
aus, wie nah du an der Empfehlung warst (Coach). Alle neun Klassen, Rolle wird automatisch erkannt.

*English below.*

## Installation

1. Unter [**Releases**](https://github.com/zyborc/ForeverRotation/releases) die neueste
   `ForeverRotation-vX.Y.Z.zip` herunterladen.
2. Entpacken nach `World of Warcraft/_forever_/Interface/AddOns/`.
   Danach muss es `…/AddOns/ForeverRotation/ForeverRotation.toc` geben.
3. Spiel (neu) starten, in der Charakterauswahl unter *AddOns* prüfen, dass es aktiv ist.

> Nicht den grünen „Code → Download ZIP“-Knopf nehmen: der Ordner heißt dann
> `ForeverRotation-main` und WoW lädt ihn nicht (umbenennen in `ForeverRotation` hilft).

Aktualisieren: neue ZIP drüber entpacken. Bei neuen Dateien den Client neu starten, sonst reicht `/reload`.

## Bedienung

- **`/frot`** oder Klick aufs **Minimap-Symbol** öffnet die Einstellungen
  (Anzeige, Hinweise, Rotation, Coach). **Shift-Klick** öffnet direkt den Coach, Rechtsklick
  entsperrt/fixiert die Anzeige zum Verschieben.
- **Rolle**: automatisch über Gruppenrolle, Rollen-Buff (Righteous Fury) oder Gestalt/Haltung
  (Bärengestalt, Verteidigungshaltung). Von Hand: `/frot role tank | dps | heal | auto`.
- **Prioritäten** pro Rotation umsortieren oder abschalten: `/frot prio`.
- `/frot help` zeigt alle Befehle.

## Klassen

| Klasse | Rotationen |
|---|---|
| Krieger | Waffen, Furor, Schutz (Tank) |
| Paladin | Vergeltung (mit Seal Twisting über Unsealed Wrath), Schutz (Tank), Heilig |
| Jäger | Fernkampf, Überleben (Nahkampf) |
| Schurke | eine Rotation, Aufbauer wählbar (Mutilate, Hemorrhage, Backstab, Sinister Strike) |
| Priester | Schatten, Heiler |
| Schamane | Elementar, Verstärkung, Wiederherstellung (Totems, Schilde, Waffen) |
| Magier | Feuer, Frost, Arkan |
| Hexenmeister | Gebrechen, Dämonologie, Zerstörung (Flüche **und** Banes) |
| Druide | Katze, Gleichgewicht, Bär (Tank), Wiederherstellung – die Gestalt wählt die Rotation |

## Was das Addon kann – und was nicht

WoW Forever versteckt im Kampf viele Werte („secret values“): Leben, Mana/Wut/Energie, alle Auren,
Cooldown-Zeiten und das Kampflog. ForeverRotation liest deshalb nur, was lesbar bleibt (eigene Zauber,
Nutzbarkeit, Reichweite, Ziel-Infos, Bedrohung) und **zählt den Rest selbst mit**: Cooldowns, eigene
Buffs, DoTs pro Ziel, Combo-Punkte, Totems. Außerhalb des Kampfs gleicht es alles mit den echten Werten ab.
Im Kampf hilft zusätzlich Blizzards **Cooldown-Manager** (Edit Mode): Verfolgt er eine Aura (z. B. dein
Siegel), erkennt das Addon, ob – und beim Siegel welches – gerade aktiv ist. Außerdem prüft es, ob ein
Cooldown vorzeitig frei geworden ist (nur ja/nein, die Restzeit bleibt geheim). Beim Seal Twisting
zählt es die gespeicherten Kopien von Unsealed Wrath über dessen Buff-Symbol im Cooldown-Manager
(1 Kopie genau, ab 2 „mindestens 2“) statt nur über die Waffengeschwindigkeit zu schätzen.
Optional füllen sich Bögen links und rechts vom Charakter mit jeder Kopie (in der Farbe ihres Siegels)
und leuchten in der Farbe des Zielsiegels, sobald der Wechsel fällig ist – ähnlich Maelstrom Weapon.

Folgen davon:
- Procs (Hot Streak, Fingers of Frost, …) und Combo-Punkte aus kritischen Treffern sieht das Addon nicht.
- Heiler-Rotationen erinnern an Buffs und Cooldowns. Wen du heilst, entscheidest du selbst (Leben ist geheim).
- Execute, Overpower, Revenge, Victory Rush usw. erscheinen trotzdem genau dann, wenn sie nutzbar sind.

## Feedback

Fehler oder falsche Empfehlungen bitte als [Issue](https://github.com/zyborc/ForeverRotation/issues)
melden: Klasse, Stufe, Rotation (`/frot list`), was empfohlen wurde und was richtig gewesen wäre.
Lua-Fehler sichtbar machen mit `/console scriptErrors 1`. Hilfreich ist außerdem die Ausgabe von `/frot state`.

---

## English

Rotation helper for **World of Warcraft: Forever**. Shows your next spell as a big icon with a
timeline, highlights it on your action bars, and reviews each fight afterwards (coach). Supports all nine
classes; your role is detected automatically. The interface follows your client language (German/English).

**Install:** download the latest `ForeverRotation-vX.Y.Z.zip` from
[Releases](https://github.com/zyborc/ForeverRotation/releases), extract it into
`World of Warcraft/_forever_/Interface/AddOns/` so that `AddOns/ForeverRotation/ForeverRotation.toc`
exists, then restart the game.

**Use:** `/frot` or the minimap button opens the settings, shift-click opens the coach, `/frot help` lists
all commands, `/frot role tank|dps|heal|auto` sets your role.

**Limits:** Forever hides health, resources, auras, cooldown timers and the combat log during combat.
The addon tracks cooldowns, buffs, DoTs, combo points and totems from your own casts instead, and syncs
them with the real values out of combat. In combat, Blizzard's Cooldown Manager (Edit Mode) also tells the
addon whether a tracked aura (e.g. your seal) is active, and whether a cooldown is ready early (yes/no only).
Seal twisting counts the stored Unsealed Wrath copies from its Cooldown Manager buff icon, with an
optional effect around your character (arcs filling per copy, target color when it's time to switch).
Procs are mostly invisible to addons; healer rotations only cover buffs and cooldowns.

License: [MIT](LICENSE)
