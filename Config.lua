-- ForeverRotation – Konfigurationsfenster.
-- Baut sich dynamisch aus den Optionen der aktiven Rotation auf:
--   boolean -> Häkchen, Zahl (min/max/step) -> Minus/Plus, values -> Umschalt-Knopf.

local _, ns = ...

local Config = {}
ns.Config = Config
local L = ns.L
-- Alle Bausteine übersetzen ihre Texte selbst (ns:T: Sprache + {Zauber}-Platzhalter).
local function T(text) return ns:T(text) end

local WIDTH = 400
local LEFT = 20

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function createWindow()
    local ok, f = pcall(CreateFrame, "Frame", "ForeverRotationConfig", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
        f = CreateFrame("Frame", "ForeverRotationConfig", UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    f:SetSize(2 * WIDTH, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -12)
    end
    title:SetText("ForeverRotation")

    -- Mit Escape schließen
    table.insert(UISpecialFrames, "ForeverRotationConfig")
    f:SetScript("OnShow", function() Config:Build() end)
    return f
end

---------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------

local function addTooltip(widget, title, desc)
    if not desc or desc == "" then return end
    title, desc = T(title), T(desc)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(desc, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local Builder = {}
Builder.__index = Builder

local function NewBuilder(parent)
    return setmetatable({ parent = parent, y = -8 }, Builder)
end

function Builder:header(text)
    self.y = self.y - 8
    local fs = self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", LEFT, self.y)
    fs:SetText(T(text))
    self.y = self.y - 26
end

function Builder:note(text)
    local fs = self.parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", LEFT, self.y)
    fs:SetWidth(WIDTH - 2 * LEFT)
    fs:SetJustifyH("LEFT")
    fs:SetText(T(text))
    self.y = self.y - (fs:GetStringHeight() + 8)
end

function Builder:label(text, desc)
    local fs = self.parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", LEFT, self.y - 4)
    fs:SetText(T(text))
    -- unsichtbarer Bereich für den Tooltip
    local hit = CreateFrame("Frame", nil, self.parent)
    hit:SetPoint("TOPLEFT", fs, "TOPLEFT")
    hit:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT")
    hit:EnableMouse(true)
    addTooltip(hit, text, desc)
    return fs
end

function Builder:checkbox(text, desc, get, set)
    local cb = CreateFrame("CheckButton", nil, self.parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", LEFT - 4, self.y)
    cb:SetChecked(get() and true or false)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    label:SetText(T(text))
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    addTooltip(cb, text, desc)
    self.y = self.y - 30
end

function Builder:stepper(text, desc, get, set, min, max, step)
    self:label(text, desc)
    local value = self.parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local minus = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
    local plus = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
    minus:SetSize(26, 22); plus:SetSize(26, 22)
    minus:SetText("-"); plus:SetText("+")
    plus:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -LEFT, self.y)
    value:SetPoint("RIGHT", plus, "LEFT", -8, 0)
    value:SetWidth(40)
    value:SetJustifyH("CENTER")
    minus:SetPoint("RIGHT", value, "LEFT", -8, 0)

    local function refresh()
        local v = get()
        value:SetText((step or 1) < 1 and string.format("%.1f", v) or tostring(v))
    end
    local function change(delta)
        local v = get() + delta
        if min then v = math.max(min, v) end
        if max then v = math.min(max, v) end
        v = math.floor(v * 100 + 0.5) / 100
        set(v)
        refresh()
    end
    minus:SetScript("OnClick", function() change(-(step or 1)) end)
    plus:SetScript("OnClick", function() change(step or 1) end)
    refresh()
    self.y = self.y - 30
end

function Builder:cycle(text, desc, values, get, set, display)
    self:label(text, desc)
    local btn = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
    btn:SetSize(160, 22)
    btn:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -LEFT, self.y)
    local function refresh()
        local v = get()
        btn:SetText(T(display and display(v) or tostring(v)))
    end
    btn:SetScript("OnClick", function()
        local current = get()
        local idx = 1
        for i, v in ipairs(values) do
            if v == current then idx = i end
        end
        set(values[idx % #values + 1])
        refresh()
    end)
    addTooltip(btn, text, desc)
    refresh()
    self.y = self.y - 30
end

function Builder:buttons(list)
    local x = LEFT
    for _, item in ipairs(list) do
        local btn = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        btn:SetSize(item.width or 170, 24)
        btn:SetPoint("TOPLEFT", x, self.y)
        btn:SetText(T(item.text))
        btn:SetScript("OnClick", item.onClick)
        addTooltip(btn, item.text, item.desc)
        x = x + (item.width or 170) + 10
    end
    self.y = self.y - 32
end

---------------------------------------------------------------------------
-- Inhalt
---------------------------------------------------------------------------

local function sortedOptions(def)
    local list = {}
    for name, o in pairs(def.options) do list[#list + 1] = { name = name, o = o } end
    table.sort(list, function(a, b)
        local oa, ob = a.o.order or 99, b.o.order or 99
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return list
end

local function applyDisplay()
    if ns.Display then ns.Display:ApplySettings() end
end

-- Spalten-Paar für einen Reiter: liefert linken und rechten Builder.
local function columns(content)
    local leftCol = CreateFrame("Frame", nil, content)
    leftCol:SetPoint("TOPLEFT")
    leftCol:SetSize(WIDTH, 1)
    local rightCol = CreateFrame("Frame", nil, content)
    rightCol:SetPoint("TOPLEFT", WIDTH, 0)
    rightCol:SetSize(WIDTH, 1)
    return NewBuilder(leftCol), NewBuilder(rightCol)
end

local MODE_LABELS = { off = "aus", instance = "nur in Dungeons", always = "immer" }
local function modeLabel(v) return MODE_LABELS[v] or v end

---------------------------------------------------------------------------
-- Reiter 1: Anzeige
---------------------------------------------------------------------------

local function buildDisplayTab(left, right, g)
    local b = left
    b:header("Anzeige")
    b:checkbox("Anzeige gesperrt", "Entsperrt lässt sich die Anzeige mit der Maus verschieben.",
        function() return g.locked end,
        function(v) g.locked = v; applyDisplay() end)
    b:checkbox("Symbol an der Minimap", "Linksklick öffnet dieses Fenster, Rechtsklick sperrt/entsperrt die Anzeige. Am Rand entlang ziehbar.",
        function() return g.minimap end,
        function(v) g.minimap = v; ns.MinimapButton:Apply() end)
    b:checkbox("Begründung unter dem Icon", "Zeigt, warum ein Zauber empfohlen wird.",
        function() return g.showReason end,
        function(v) g.showReason = v end)
    b:stepper("Größe", "Skalierung der Anzeige.",
        function() return g.scale or 1 end,
        function(v) g.scale = v; applyDisplay() end, 0.5, 3, 0.1)
    b:stepper("Größe in Dungeons (Faktor)", "Zusätzlicher Faktor in Dungeons und Schlachtzügen, z. B. 1.2 = 20 % größer.",
        function() return g.instanceScale or 1 end,
        function(v) g.instanceScale = v; applyDisplay() end, 0.5, 2, 0.1)
    b:stepper("Transparenz außerhalb des Kampfs", "1 = voll sichtbar, 0.1 = fast unsichtbar.",
        function() return g.alphaOOC or 0.6 end,
        function(v) g.alphaOOC = v; applyDisplay() end, 0.1, 1, 0.1)

    b:header("Sichtbarkeit")
    b:cycle("Anzeigen", "Wann die Anzeige erscheint. Entsperrt ist sie immer sichtbar.",
        { "targetOrCombat", "always", "combat", "target" },
        function() return g.showWhen or "targetOrCombat" end,
        function(v) g.showWhen = v end,
        function(v)
            if v == "always" then return "immer" end
            if v == "combat" then return "nur im Kampf" end
            if v == "target" then return "nur mit Ziel" end
            return "mit Ziel oder im Kampf"
        end)
    b:checkbox("Auf dem Reittier ausblenden", "Blendet die Anzeige und die Erinnerungen aus, solange du reitest.",
        function() return g.hideMounted end,
        function(v) g.hideMounted = v end)
    b:checkbox("Im Fahrzeug ausblenden", "Blendet die Anzeige aus, solange du ein Fahrzeug steuerst.",
        function() return g.hideVehicle end,
        function(v) g.hideVehicle = v end)
    b:buttons({
        { text = "Position zurücksetzen", onClick = function() g.pos = nil; applyDisplay() end },
    })

    b = right
    b:header("Design")
    b:cycle("Icon-Form", "Runde Icons (wie bei NAG) oder klassisch eckig.", { "round", "square" },
        function() return g.shape or "round" end,
        function(v) g.shape = v; applyDisplay() end,
        function(v) return v == "square" and "eckig" or "rund" end)
    b:checkbox("Rahmen in Klassenfarbe", "Sonst schwarzer Rahmen.",
        function() return g.classBorder end,
        function(v) g.classBorder = v; applyDisplay() end)
    b:checkbox("Leuchten, wenn jetzt drücken", "Goldenes Pulsieren um das große Icon.",
        function() return g.glow end,
        function(v) g.glow = v end)
    b:checkbox("Cooldown-Spirale", "Spirale wie auf der Aktionsleiste (aus den mitgezählten Zeiten).",
        function() return g.swipe end,
        function(v) g.swipe = v end)
    b:checkbox("Zweites Icon (danach)", "Zeigt, was nach dem aktuellen Zauber kommt.",
        function() return g.showNext end,
        function(v) g.showNext = v end)
    if LibStub and LibStub("Masque", true) then
        b:checkbox("Masque-Skin verwenden", "Icons im Stil deines Masque-Skins (dann immer eckig). Einstellbar unter /masque.",
            function() return g.masque end,
            function(v) g.masque = v; applyDisplay() end)
    end

    b:header("Timeline")
    b:checkbox("Timeline anzeigen", "Die vorhergesagten nächsten Zauber laufen auf die Jetzt-Linie zu.",
        function() return g.timeline end,
        function(v) g.timeline = v; applyDisplay() end)
    b:cycle("Position", "Neben dem Icon: Zauber gleiten in das große Icon hinein.\nDarunter: eigene Leiste mit Jetzt-Linie, plus \"danach\"-Icon.",
        { "row", "below" },
        function() return g.timelinePos or "row" end,
        function(v) g.timelinePos = v; applyDisplay() end,
        function(v) return v == "below" and "darunter" or "neben dem Icon" end)
    b:cycle("Großes Icon im Leerlauf", "Was das große Icon zeigt, solange der nächste Zauber noch auf der Timeline heranläuft (nur bei Position \"neben dem Icon\").",
        { "spell", "empty", "auto" },
        function() return g.idleMode or "spell" end,
        function(v) g.idleMode = v end,
        function(v)
            if v == "empty" then return "leer + Countdown" end
            if v == "auto" then return "Autoangriff" end
            return "nächster Zauber (grau)"
        end)
    b:stepper("Vorschau (Sekunden)", "Wie weit die Timeline in die Zukunft schaut.",
        function() return g.timelineSeconds or 12 end,
        function(v) g.timelineSeconds = v; applyDisplay() end, 4, 30, 1)
end

---------------------------------------------------------------------------
-- Reiter 2: Hinweise (Aktionsleiste, Procs, Erinnerungen, Coach)
---------------------------------------------------------------------------

local function buildHintsTab(left, right, g)
    local b = left
    b:header("Aktionsleiste")
    b:checkbox("Empfehlung auf der Aktionsleiste leuchten lassen", "Rahmt den Knopf des empfohlenen Zaubers ein (Blizzard-Leisten, Bartender4, Dominos, ElvUI). Gold = jetzt drücken, blau = zu wenig Mana, rot = außer Reichweite.",
        function() return g.actionGlow end,
        function(v) g.actionGlow = v end)
    b:cycle("Leuchten ab", "Nur wenn jetzt drücken, oder schon vorher (grau), solange der Zauber noch heranläuft.",
        { "ready", "always" },
        function() return g.actionGlowMode or "ready" end,
        function(v) g.actionGlowMode = v end,
        function(v) return v == "always" and "schon vorher (grau)" or "wenn jetzt drücken" end)

    b:header("Procs")
    b:checkbox("Proc-Hinweis an der Anzeige", "Text und Aufblitzen über dem großen Icon, z. B. wenn {Seal of Command} auslöst.\nDie Schadenszahlen selbst zeichnet das Spiel, die kann kein Addon einfärben.",
        function() return g.procAlert end,
        function(v) g.procAlert = v end)
    local sounds, soundLabels = {}, {}
    for _, e in ipairs(ns:AvailableProcSounds()) do
        sounds[#sounds + 1] = e.key
        soundLabels[e.key] = e.label
    end
    b:cycle("Ton", "Wird beim Proc abgespielt (höchstens einmal pro 0,4 s).\nEigene Datei: Sounds\\proc.ogg im Addon-Ordner ablegen, dann Spiel neu starten.",
        sounds,
        function() return g.procSound or "off" end,
        function(v) g.procSound = v; ns:PlayProcSound(v) end,
        function(v) return soundLabels[v] or v end)
    b:buttons({
        { text = "Vorschau", width = 120, desc = "Zeigt den Hinweis und spielt den Ton einmal.",
          onClick = function()
              if ns.Display then
                  ns.Display:ShowProc("Command!", ns.spells["Seal of Command"] and ns.spells["Seal of Command"].icon, { 1, 0.85, 0.3 })
              end
              ns:PlayProcSound()
          end },
        { text = "Procs testen (60 s)", width = 170,
          desc = "Schreibt 60 Sekunden lang jeden eigenen Zauber und jeden erkannten Proc in den Chat. Damit lässt sich prüfen, ob Forever den Proc von {Seal of Command} meldet.",
          onClick = function() ns:StartCastLog(60) end },
    })

    b = right
    b:header("Erinnerungen vor dem Pull")
    b:cycle("Essen-Buff", "Zeigt über der Anzeige „Kein Essen-Buff“, solange du außerhalb des Kampfs bist.",
        { "off", "instance", "always" },
        function() return g.remindFood or "off" end,
        function(v) g.remindFood = v end, modeLabel)
    b:cycle("Waffenöl / Wetzstein", "Zeigt eine Erinnerung, wenn deine Haupthand-Waffe keine temporäre Verzauberung hat.",
        { "off", "instance", "always" },
        function() return g.remindWeapon or "off" end,
        function(v) g.remindWeapon = v end, modeLabel)

end

---------------------------------------------------------------------------
-- Reiter 3: Rotation (Rolle, Auswahl, Optionen der Rotation)
---------------------------------------------------------------------------

local function buildRotationTab(left, right, g)
    local b = left
    local candidates = ns:CandidatesForPlayer()
    local def = ns.rotation
    if #candidates > 0 then
        b:header("Rolle")
        b:cycle("Rolle", "Die Rolle bestimmt die Rotation, nicht die Talente.\nAutomatisch: Gruppenrolle, sonst Rollen-Buff (z. B. {Righteous Fury} = Tank), sonst Schaden.",
            ns.ROLES,
            function() return ns:RoleMode() end,
            function(v)
                ns:SetRoleMode(v)
                C_Timer.After(0, function() Config:Build() end)
            end,
            function(v)
                if v == "auto" then
                    return L["Automatisch"] .. " (" .. ns:RoleLabel((ns:DetectRole())) .. ")"
                end
                return ns:RoleLabel(v)
            end)
        local role, source = ns:DetectRole()
        b:note(string.format(L["Aktiv: %s – Rolle %s, erkannt über: %s"],
            ns:RotLabel(def), ns:RoleLabel(role), ns:SourceLabel(source)))
    end
    if #candidates > 1 then
        local ids, labels = {}, {}
        for _, c in ipairs(candidates) do
            ids[#ids + 1] = c.id
            labels[c.id] = c.label
        end
        b:cycle("Rotation", "Von Hand wählen legt auch die Rolle fest. Zurück zur Erkennung: Rolle auf Automatisch.", ids,
            function() return ns.rotation and ns.rotation.id end,
            function(id)
                ns:SelectRotation(ns.rotations[id])
                C_Timer.After(0, function() Config:Build() end)
            end,
            function(id) return labels[id] or id end)
    end
    if not def then
        b:note("Für deine Klasse gibt es noch keine Rotation.")
        return
    end
    b:buttons({
        { text = "Prioritäten bearbeiten", width = 200,
          desc = "Reihenfolge der Regeln ändern und einzelne Regeln abschalten.",
          onClick = function() ns.Priorities:Toggle() end },
    })
    b:buttons({
        { text = "Cooldowns neu lernen", width = 200, desc = "Gelernte Cooldown-Dauern löschen, sie werden außerhalb des Kampfs neu gemessen.",
          onClick = function() wipe(ns.db.learnedCD); print(ns.PREFIX .. L["Gelernte Cooldowns gelöscht."]) end },
    })

    -- Optionen der Rotation: erst links weiter, ab der Hälfte rechts
    b:header(def.label)
    local opts = sortedOptions(def)
    local half = math.ceil(#opts / 2)
    for i, entry in ipairs(opts) do
        if i == half + 1 then
            b = right
            b:header(" ")
        end
        local name, o = entry.name, entry.o
        local text = o.label or name
        local get = function() return ns:Opt(name) end
        local set = function(v) ns:SetOpt(name, v) end
        if o.values then
            b:cycle(text, o.desc, o.values, get, set,
                o.valueLabels and function(v) return o.valueLabels[v] or tostring(v) end)
        elseif type(o.default) == "boolean" then
            b:checkbox(text, o.desc, get, set)
        elseif type(o.default) == "number" then
            b:stepper(text, o.desc, get, set, o.min, o.max, o.step)
        end
    end
end

---------------------------------------------------------------------------
-- Reiter 4: Coach – Auswertung der letzten Kämpfe
---------------------------------------------------------------------------

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function text(b, str, size, r, g, bl, x)
    local fs = b.parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, size and size >= 20 and "THICKOUTLINE" or "")
    fs:SetPoint("TOPLEFT", x or LEFT, b.y)
    fs:SetText(str)
    fs:SetTextColor(r or 1, g or 1, bl or 1)
    return fs
end

local function bar(parent, x, y, width, fraction, r, g, bl)
    local bg = parent:CreateTexture(nil, "ARTWORK")
    bg:SetTexture(WHITE)
    bg:SetVertexColor(1, 1, 1, 0.08)
    bg:SetPoint("TOPLEFT", x, y)
    bg:SetSize(width, 10)
    local fg = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    fg:SetTexture(WHITE)
    fg:SetVertexColor(r, g, bl, 0.9)
    fg:SetPoint("TOPLEFT", bg, "TOPLEFT")
    fg:SetSize(math.max(1, width * math.min(1, math.max(0, fraction))), 10)
end

local function fightTitle(r)
    return string.format("%s · %d s", date("%H:%M", r.time or 0), r.duration or 0)
end

local function buildCoachTab(left, right, g)
    local Coach = ns.Coach
    local hist = Coach:History()
    Coach.selected = math.min(Coach.selected or 1, math.max(1, #hist))
    local r = hist[Coach.selected]

    -- links: ausgewählter Kampf ------------------------------------------
    local b = left
    if not r then
        b:header("Coach")
        b:note(string.format(L["Noch keine Auswertung. Kämpfe mindestens %d Sekunden, dann erscheint sie hier."], g.coachMin or 10))
    else
        b:header(Coach.selected == 1 and L["Letzter Kampf"] .. " · " .. fightTitle(r) or fightTitle(r))
        local pct = Coach:Pct(r)
        local cr, cg, cb = Coach:GradeRGB(pct)
        local big = text(b, pct .. " %", 30, cr, cg, cb)
        local sub = b.parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        sub:SetPoint("BOTTOMLEFT", big, "BOTTOMRIGHT", 10, 4)
        sub:SetText(string.format(L["nach Empfehlung (%d von %d Zaubern)"], r.match, r.casts))
        b.y = b.y - 40

        local function stat(label, value)
            text(b, T(label), 12, 0.8, 0.8, 0.8)
            text(b, value, 12, 1, 1, 1, LEFT + 220)
            b.y = b.y - 18
        end
        stat("Ø Reaktionszeit", string.format("%.1f s", r.avgDelay or 0))
        stat("Ungenutzte GCD-Zeit", string.format("%.1f s", r.idle or 0))
        local seal = r.drops and r.drops.seal
        if seal then stat("Siegel ausgelaufen", seal .. "×") end
        b.y = b.y - 6

        -- Reaktionszeit pro Zauber (Balken bis 2 s)
        local spells = {}
        for key, p in pairs(r.perSpell or {}) do spells[#spells + 1] = { key = key, n = p.n, avg = p.delay / p.n } end
        table.sort(spells, function(a, c) return a.avg > c.avg end)
        if #spells > 0 then
            b:header("Reaktion pro Zauber")
            for _, e in ipairs(spells) do
                local icon = b.parent:CreateTexture(nil, "ARTWORK")
                icon:SetSize(16, 16)
                icon:SetPoint("TOPLEFT", LEFT, b.y + 2)
                icon:SetTexture((ns.spells[e.key] and ns.spells[e.key].icon) or 134400)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local name = text(b, ns:SpellName(e.key), 12, 1, 1, 1, LEFT + 22)
                name:SetWidth(150)
                name:SetWordWrap(false)
                name:SetJustifyH("LEFT")
                local br, bg2, bb = 0.25, 1, 0.25
                if e.avg >= 1 then br, bg2, bb = 1, 0.31, 0.31 elseif e.avg >= 0.5 then br, bg2, bb = 1, 0.82, 0.25 end
                bar(b.parent, LEFT + 178, b.y - 1, 110, e.avg / 2, br, bg2, bb)
                text(b, string.format("%.1f s · %d×", e.avg, e.n), 11, 0.8, 0.8, 0.8, LEFT + 294)
                b.y = b.y - 20
            end
        end

        b:header("Tipps")
        for _, tip in ipairs(Coach:Tips(r)) do b:note("• " .. tip) end
    end

    -- rechts: Verlauf, Durchschnitt, Einstellungen -----------------------
    b = right
    if #hist > 0 then
        b:header("Verlauf")
        for i, h in ipairs(hist) do
            local row = CreateFrame("Button", nil, b.parent)
            row:SetSize(WIDTH - 2 * LEFT, 20)
            row:SetPoint("TOPLEFT", LEFT, b.y)
            local hl = row:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetTexture(WHITE)
            hl:SetVertexColor(1, 0.82, 0.25, i == Coach.selected and 0.18 or 0)
            row:SetHighlightTexture(WHITE)
            row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
            local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            t:SetPoint("LEFT", 4, 0)
            t:SetText(fightTitle(h))
            local pct = Coach:Pct(h)
            local cr, cg, cb = Coach:GradeRGB(pct)
            bar(row, 120, -5, 160, pct / 100, cr, cg, cb)
            local p = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            p:SetPoint("LEFT", 290, 0)
            p:SetText(pct .. " %")
            p:SetTextColor(cr, cg, cb)
            row:SetScript("OnClick", function()
                Coach.selected = i
                Config:Build()
            end)
            b.y = b.y - 22
        end
        local avg = Coach:Average()
        if avg and avg.fights > 1 then
            b.y = b.y - 4
            b:note(string.format(L["Ø der letzten %d Kämpfe: %d %% nach Empfehlung, Reaktion %.1f s, ungenutzte GCD-Zeit %.1f s pro Minute"],
                avg.fights, avg.pct, avg.avgDelay, avg.idlePerMin))
        end
    end

    b:header("Einstellungen")
    b:checkbox("Auswertung nach dem Kampf", "Vergleicht deine Zauber mit den Empfehlungen: Anteil nach Empfehlung, Reaktionszeit, ungenutzte GCD-Zeit, ausgelaufene Siegel.",
        function() return g.coach end,
        function(v) g.coach = v end)
    b:checkbox("Kurzinfo an der Anzeige", "Nach dem Kampf erscheint für ein paar Sekunden das Ergebnis unter der Anzeige.",
        function() return g.coachToast end,
        function(v) g.coachToast = v end)
    b:checkbox("Zusätzlich im Chat ausgeben", "Eine Zeile im Chat nach jedem Kampf.",
        function() return g.coachChat end,
        function(v) g.coachChat = v end)
    b:stepper("Kämpfe ab (Sekunden)", "Kürzere Kämpfe werden nicht ausgewertet.",
        function() return g.coachMin or 10 end,
        function(v) g.coachMin = v end, 5, 60, 5)
    b:buttons({
        { text = "Verlauf löschen", width = 160, onClick = function() Coach:Reset() end },
    })
end

---------------------------------------------------------------------------
-- Fenster mit Reitern
---------------------------------------------------------------------------

local TABS = {
    { key = "display",  label = "Anzeige",  build = buildDisplayTab },
    { key = "hints",    label = "Hinweise", build = buildHintsTab },
    { key = "rotation", label = "Rotation", build = buildRotationTab },
    { key = "coach",    label = "Coach",    build = buildCoachTab },
}

function Config:Build()
    local f = self.frame
    self.tab = self.tab or "display"

    -- Reiter-Knöpfe (einmalig)
    if not f.tabButtons then
        f.tabButtons = {}
        for i, tab in ipairs(TABS) do
            local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            btn:SetSize(120, 24)
            btn:SetPoint("TOPLEFT", 16 + (i - 1) * 126, -28)
            btn:SetScript("OnClick", function()
                Config.tab = tab.key
                Config:Build()
            end)
            f.tabButtons[tab.key] = btn
        end
    end
    for _, tab in ipairs(TABS) do
        local btn = f.tabButtons[tab.key]
        btn:SetText(T(tab.label))
        if tab.key == self.tab then btn:Disable() else btn:Enable() end  -- aktiver Reiter = gedrückt
    end

    if self.content then self.content:Hide() end
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 0, -56)
    content:SetSize(2 * WIDTH, 1)
    self.content = content

    local g = ns.db.global
    local left, right = columns(content)
    for _, tab in ipairs(TABS) do
        if tab.key == self.tab then tab.build(left, right, g) end
    end
    left:note("Änderungen gelten sofort. Befehle im Chat: /frot help")
    f:SetHeight(-math.min(left.y, right.y) + 56 + 30)
end

function Config:Toggle()
    if not self.frame then self.frame = createWindow() end
    self.frame:SetShown(not self.frame:IsShown())
end

-- Fenster direkt auf einem Reiter öffnen (z. B. "coach")
function Config:Open(tab)
    if not self.frame then self.frame = createWindow() end
    self.tab = tab or self.tab
    if self.frame:IsShown() then self:Build() else self.frame:Show() end
end

-- Eintrag im Addon-Menü an der Minimap (siehe AddonCompartmentFunc in der .toc)
function ForeverRotation_OnCompartmentClick()
    Config:Toggle()
end

---------------------------------------------------------------------------
-- Symbol an der Minimap (ohne Bibliothek): am Rand entlang ziehbar.
-- Linksklick = Einstellungen, Rechtsklick = Anzeige sperren/entsperren.
---------------------------------------------------------------------------

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local function placeButton(btn)
    local angle = math.rad(ns.db.global.minimapAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 10
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function dragUpdate(btn)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.db.global.minimapAngle = math.floor(math.deg(math.atan2(cy - my, cx - mx)) + 0.5)
    placeButton(btn)
end

function MinimapButton:Create()
    local b = CreateFrame("Button", "ForeverRotationMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_HolyBolt")
    icon:SetPoint("TOPLEFT", 7, -6)
    -- rund zuschneiden wie die übrigen Minimap-Knöpfe
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local g = ns.db.global
            g.locked = not g.locked
            if ns.Display then ns.Display:ApplySettings() end
            print(ns.PREFIX .. (g.locked and L["Anzeige fixiert."] or L["Anzeige entsperrt: mit der Maus verschieben."]))
        elseif IsShiftKeyDown() then
            Config:Open("coach")
        else
            Config:Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", dragUpdate)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("ForeverRotation", 1, 0.82, 0)
        if ns.rotation then
            local role, source = ns:DetectRole()
            GameTooltip:AddLine(ns:RotLabel(ns.rotation), 1, 1, 1)
            GameTooltip:AddLine(L["Rolle: "] .. ns:RoleLabel(role) .. " (" .. ns:SourceLabel(source) .. ")", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine(L["Keine Rotation für deine Klasse"], 0.8, 0.8, 0.8)
        end
        local last = ns.db.coach and ns.db.coach.history[1]
        if last and ns.Coach then
            local pct = ns.Coach:Pct(last)
            local cr, cg, cb = ns.Coach:GradeRGB(pct)
            GameTooltip:AddLine(string.format(L["Coach: %d %% nach Empfehlung"], pct), cr, cg, cb)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Linksklick: Einstellungen"], 0.6, 0.9, 1)
        GameTooltip:AddLine(L["Shift-Klick: Coach"], 0.6, 0.9, 1)
        GameTooltip:AddLine(L["Rechtsklick: Anzeige sperren/entsperren"], 0.6, 0.9, 1)
        GameTooltip:AddLine(L["Ziehen: am Minimap-Rand verschieben"], 0.6, 0.9, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = b
end

-- Anzeigen/Verstecken und Position nach den Einstellungen.
function MinimapButton:Apply()
    if not Minimap or not ns.db then return end
    if ns.db.global.minimap then
        if not self.button then self:Create() end
        placeButton(self.button)
        self.button:Show()
    elseif self.button then
        self.button:Hide()
    end
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function() MinimapButton:Apply() end)

---------------------------------------------------------------------------
-- Prioritäten-Fenster: Regeln der aktiven Rotation sortieren und abschalten.
-- Oben = wichtiger. Gespeichert pro Rotation; "Standard" setzt zurück.
---------------------------------------------------------------------------

local Priorities = {}
ns.Priorities = Priorities

local ROW_H = 28
local PRIO_W = 440

local function arrowButton(parent, dir)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    btn:SetNormalTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Up")
    btn:SetPushedTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Down")
    btn:SetDisabledTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Disabled")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return btn
end

local function entryIcon(entry)
    for _, name in ipairs(entry.spells) do
        local sp = ns.spells[name]
        if sp and sp.known and sp.icon then return sp.icon end
    end
    local sp = ns.spells[entry.spells[1]]
    return (sp and sp.icon) or 134400 -- Fragezeichen
end

local function entryKnown(entry)
    for _, name in ipairs(entry.spells) do
        if ns:Known(name) then return true end
    end
    return false
end

function Priorities:Create()
    local ok, f = pcall(CreateFrame, "Frame", "ForeverRotationPriorities", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
        f = CreateFrame("Frame", "ForeverRotationPriorities", UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    f:SetSize(PRIO_W, 300)
    if Config.frame and Config.frame:IsShown() then
        f:SetPoint("TOPLEFT", Config.frame, "TOPRIGHT", 6, 0)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -12)
    end
    f.title = title
    table.insert(UISpecialFrames, "ForeverRotationPriorities")
    f:SetScript("OnShow", function() Priorities:Build() end)
    self.frame = f
end

function Priorities:Build()
    local f = self.frame
    if not f then return end
    if self.content then self.content:Hide() end
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 0, -28)
    content:SetSize(PRIO_W, 1)
    self.content = content

    local def = ns.rotation
    f.title:SetText(L["Prioritäten – "] .. ns:RotLabel(def))
    if not def then
        f:SetHeight(80)
        return
    end

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -2)
    hint:SetWidth(PRIO_W - 32)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Oben = wichtiger. Es wird die erste Regel empfohlen, deren Bedingung passt und die (fast) bereit ist. Grau = noch nicht gelernt."])
    local y = -(hint:GetStringHeight() + 10)

    local list = ns:OrderedEntries(def)
    for i, entry in ipairs(list) do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(PRIO_W - 24, ROW_H)
        row:SetPoint("TOPLEFT", 12, y)
        if i % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(1, 1, 1, 0.04)
        end

        local enabled = ns:EntryEnabled(entry.key)
        local known = entryKnown(entry)

        local rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rank:SetPoint("LEFT", 2, 0)
        rank:SetWidth(22)
        rank:SetJustifyH("RIGHT")
        rank:SetText(tostring(i))

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", rank, "RIGHT", 4, 0)
        cb:SetChecked(enabled)
        cb:SetScript("OnClick", function(btn)
            ns:SetEntryEnabled(entry.key, btn:GetChecked() and true or false)
            Priorities:Build()
        end)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        icon:SetTexture(entryIcon(entry))
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDesaturated(not (enabled and known))

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(ns:EntryLabel(entry))
        if not enabled then
            label:SetTextColor(0.5, 0.5, 0.5)
        elseif not known then
            label:SetTextColor(0.65, 0.65, 0.65)
        end

        local down = arrowButton(row, "Down")
        down:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        down:SetScript("OnClick", function() ns:MoveEntry(entry.key, 1); Priorities:Build() end)
        if i == #list then down:Disable() end
        local up = arrowButton(row, "Up")
        up:SetPoint("RIGHT", down, "LEFT", -2, 0)
        up:SetScript("OnClick", function() ns:MoveEntry(entry.key, -1); Priorities:Build() end)
        if i == 1 then up:Disable() end

        -- Tooltip: welche Zauber gehören zu diesem Eintrag
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(r)
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetText(ns:EntryLabel(entry), 1, 1, 1)
            for _, rule in ipairs(entry.rules) do
                local k = ns:Known(rule.spell)
                GameTooltip:AddDoubleLine(ns:SpellName(rule.spell), ns:T(rule.reason, rule.spell) or "", k and 1 or 0.5, k and 1 or 0.5, k and 1 or 0.5, 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        y = y - ROW_H
    end

    local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    reset:SetSize(180, 24)
    reset:SetPoint("TOPLEFT", 16, y - 10)
    reset:SetText(L["Standard wiederherstellen"])
    reset:SetScript("OnClick", function() ns:ResetPriorities(); Priorities:Build() end)

    f:SetHeight(-y + 28 + 50)
end

function Priorities:Toggle()
    if not self.frame then self:Create() end
    self.frame:SetShown(not self.frame:IsShown())
end
