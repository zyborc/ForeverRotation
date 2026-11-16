-- ForeverRotation – Einstellungsfenster, Minimap-Symbol, Prioritäten, Coach, Hilfe.
--
-- Aufbau:
--   * eigenes Fenster (dunkel, Rahmen in Klassenfarbe) mit Reitern und Scrollbereich
--   * alle Bausteine kommen aus einem Pool und werden bei jedem Neuaufbau wiederverwendet
--     (Frames lassen sich nicht löschen – ohne Pool würde jeder Aufbau Speicher fressen)
--   * Optionen der aktiven Rotation werden dynamisch aus def.options gebaut:
--       boolean -> Häkchen, Zahl (min/max/step) -> Schieberegler, values -> Auswahlliste
--   * Prioritäten als eigener Reiter: Pfeile oder Ziehen mit der Maus, Häkchen zum Abschalten,
--     die gerade empfohlene Regel ist markiert
--   * Willkommensfenster beim ersten Start, Eintrag in den Blizzard-Einstellungen

local ADDON_NAME, ns = ...

local Config = {}
ns.Config = Config
local L = ns.L
-- Alle Bausteine übersetzen ihre Texte selbst (ns:T: Sprache + {Zauber}-Platzhalter).
local function T(text) return ns:T(text) end

local WIN_W, WIN_H = 680, 600
local HEADER_H, TABS_H, FOOTER_H = 54, 32, 34
local PAD = 14          -- Abstand Fensterrand -> Inhalt
local INSET = 10        -- Einzug innerhalb einer Zeile
local CONTROL_W = 224   -- Breite der Spalte mit den Bedienelementen (rechts)
local PRIO_ROW_H = 30
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LOGO = "Interface\\Icons\\Spell_Holy_HolyBolt"

local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or ""

-- Farben
local COL_BG      = { 0.07, 0.07, 0.09, 0.96 }
local COL_TEXT    = { 0.95, 0.95, 0.95 }
local COL_MUTED   = { 0.66, 0.66, 0.70 }
local COL_DIM     = { 0.45, 0.45, 0.50 }

local function accent()
    local _, class = UnitClass("player")
    local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
    c = c or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

---------------------------------------------------------------------------
-- Zeichen-Helfer
---------------------------------------------------------------------------

local function fs(parent, size, flags, layer)
    local s = parent:CreateFontString(nil, layer or "OVERLAY")
    s:SetFont(FONT, size or 12, flags or "")
    s:SetTextColor(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3])
    s:SetJustifyH("LEFT")
    return s
end

local function solid(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- Vier dünne Linien als Rahmen
local function makeBorder(f, r, g, b, a, size, layer)
    size = size or 1
    local t = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tex = f:CreateTexture(nil, layer or "BORDER")
        tex:SetColorTexture(r, g, b, a)
        if side == "TOP" then
            tex:SetPoint("TOPLEFT"); tex:SetPoint("TOPRIGHT"); tex:SetHeight(size)
        elseif side == "BOTTOM" then
            tex:SetPoint("BOTTOMLEFT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetHeight(size)
        elseif side == "LEFT" then
            tex:SetPoint("TOPLEFT"); tex:SetPoint("BOTTOMLEFT"); tex:SetWidth(size)
        else
            tex:SetPoint("TOPRIGHT"); tex:SetPoint("BOTTOMRIGHT"); tex:SetWidth(size)
        end
        t[i] = tex
    end
    return t
end

local function colorBorder(t, r, g, b, a)
    for _, tex in ipairs(t) do tex:SetColorTexture(r, g, b, a) end
end

-- Tooltip + Zeilen-Hervorhebung: liest self.tipTitle / self.tipDesc und self.row
local function onEnter(self)
    local row = self.row or self
    if row.hover then row.hover:Show() end
    if self.tipTitle and self.tipTitle ~= "" then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle, 1, 1, 1)
        if self.tipDesc and self.tipDesc ~= "" then GameTooltip:AddLine(self.tipDesc, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end
end

local function onLeave(self)
    local row = self.row or self
    if row.hover then row.hover:Hide() end
    GameTooltip:Hide()
end

local function hoverable(widget, row)
    widget.row = row
    widget:SetScript("OnEnter", onEnter)
    widget:SetScript("OnLeave", onLeave)
end

local function setTip(widget, title, desc)
    widget.tipTitle, widget.tipDesc = title, desc
end

-- Flacher Knopf (eigener Stil)
local function createButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(140, 24)
    b.bg = solid(b, "BACKGROUND", 1, 1, 1, 0.07)
    b.bg:SetAllPoints()
    b.edges = makeBorder(b, 1, 1, 1, 0.14)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.07)
    b.label = fs(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b.SetLabel = function(self, text) self.label:SetText(text) end
    hoverable(b)
    return b
end

local function styleButton(b, accented)
    if accented then
        local r, g, bl = accent()
        b.bg:SetColorTexture(r, g, bl, 0.2)
        colorBorder(b.edges, r, g, bl, 0.6)
    else
        b.bg:SetColorTexture(1, 1, 1, 0.07)
        colorBorder(b.edges, 1, 1, 1, 0.14)
    end
end

local function setEnabled(b, on)
    if on then b:Enable(); b:SetAlpha(1) else b:Disable(); b:SetAlpha(0.4) end
end

---------------------------------------------------------------------------
-- Widget-Pool: Bausteine werden beim Neuaufbau nicht neu erzeugt, sondern
-- versteckt, abgehängt und beim nächsten Aufbau wiederverwendet.
---------------------------------------------------------------------------

local poolParent = CreateFrame("Frame", nil, UIParent)
poolParent:Hide()
local pools = {}     -- [Art] = { freie Widgets }
local used = {}      -- gerade benutzte Widgets
local creators = {}  -- [Art] = function(parent) -> Widget

local function acquire(kind, parent)
    pools[kind] = pools[kind] or {}
    local w = table.remove(pools[kind])
    if not w then
        w = creators[kind](poolParent)
        w.kind = kind
    end
    w:SetParent(parent)
    w:ClearAllPoints()
    w:SetAlpha(1)
    w:Show()
    used[#used + 1] = w
    return w
end

local function releaseAll()
    for i = #used, 1, -1 do
        local w = used[i]
        if w.reset then w:reset() end
        w:Hide()
        w:ClearAllPoints()
        w:SetParent(poolParent)
        table.insert(pools[w.kind], w)
        used[i] = nil
    end
end

-- Text (Überschrift, Hinweis, Beschriftung)
creators.text = function(parent)
    local w = CreateFrame("Frame", nil, parent)
    w.text = fs(w, 12)
    w.text:SetPoint("TOPLEFT")
    w.reset = function(self)
        self.text:SetWidth(0)
        self.text:SetWordWrap(true)
        self.text:SetJustifyH("LEFT")
    end
    return w
end

-- Text setzen und den Rahmen passend machen; width = Umbruchbreite (nil = eine Zeile)
local function setText(w, str, size, flags, r, g, b, width)
    w.text:SetFont(FONT, size or 12, flags or "")
    w.text:SetTextColor(r or COL_TEXT[1], g or COL_TEXT[2], b or COL_TEXT[3])
    if width then w.text:SetWidth(width) end
    w.text:SetText(str or "")
    local h = w.text:GetStringHeight()
    local wd = width or w.text:GetStringWidth()
    w:SetSize(math.max(1, wd), math.max(1, h))
    return h
end

-- Trennlinie
creators.line = function(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetHeight(1)
    w.tex = solid(w, "ARTWORK", 1, 1, 1, 0.1)
    w.tex:SetAllPoints()
    return w
end

-- Zeile mit Beschriftung + Beschreibung (Grundlage für Häkchen, Regler, Auswahl)
local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(34)
    row.hover = solid(row, "BACKGROUND", 1, 1, 1, 0.04)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.label = fs(row, 13)
    row.label:SetPoint("TOPLEFT", INSET, -8)
    row.desc = fs(row, 11)
    row.desc:SetTextColor(COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
    row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row:EnableMouse(true)
    hoverable(row, row)
    return row
end

-- Beschriftung/Beschreibung setzen, Höhe berechnen; liefert die Zeilenhöhe
local function fillRow(row, width, title, desc, controlH)
    row:SetWidth(width)
    local textW = width - CONTROL_W - 2 * INSET - 12
    row.label:SetWidth(textW)
    row.label:SetText(title or "")
    row.desc:SetWidth(textW)
    row.desc:SetText(desc or "")
    row.desc:SetShown(desc ~= nil and desc ~= "")
    local h = 8 + row.label:GetStringHeight() + 8
    if desc and desc ~= "" then h = h + 3 + row.desc:GetStringHeight() end
    h = math.max(h, (controlH or 24) + 10)
    row:SetHeight(h)
    setTip(row, title, desc)
    return h
end

-- Häkchen
creators.check = function(parent)
    local row = createRow(parent)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("LEFT", row, "RIGHT", -CONTROL_W - INSET, 0)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if SOUNDKIT then
            ns.safe(PlaySound, on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        if row.set then row.set(on) end
    end)
    hoverable(cb, row)
    local lbl = cb.Text or cb.text
    if lbl then lbl:SetText("") end
    row.cb = cb
    row.reset = function(self) self.set = nil; self.hover:Hide() end
    return row
end

-- Schieberegler mit -/+ und Wertanzeige
creators.slider = function(parent)
    local row = createRow(parent)
    local x0 = -CONTROL_W - INSET
    local minus = createButton(row)
    minus:SetSize(20, 20)
    minus:SetLabel("–")
    minus:SetPoint("LEFT", row, "RIGHT", x0, 0)
    local s = CreateFrame("Slider", nil, row)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(112, 18)
    s:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    s.track = solid(s, "BACKGROUND", 1, 1, 1, 0.14)
    s.track:SetPoint("LEFT", 0, 0)
    s.track:SetPoint("RIGHT", 0, 0)
    s.track:SetHeight(4)
    s.fill = solid(s, "ARTWORK", 1, 1, 1, 0.8)
    s.fill:SetPoint("LEFT", s.track, "LEFT")
    s.fill:SetHeight(4)
    s.fill:SetWidth(1)
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(10, 18)
    thumb:SetVertexColor(0.92, 0.92, 0.95)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouse(true)
    hoverable(s, row)
    local plus = createButton(row)
    plus:SetSize(20, 20)
    plus:SetLabel("+")
    plus:SetPoint("LEFT", s, "RIGHT", 6, 0)
    local value = fs(row, 12)
    value:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    value:SetWidth(46)
    value:SetJustifyH("RIGHT")
    row.slider, row.minus, row.plus, row.value = s, minus, plus, value

    local function fmt(v)
        if (row.step or 1) < 1 then return string.format("%.1f", v) end
        return tostring(math.floor(v + 0.5))
    end
    local function paint(v)
        local lo, hi = s:GetMinMaxValues()
        local frac = hi > lo and (v - lo) / (hi - lo) or 0
        s.fill:SetWidth(math.max(1, s:GetWidth() * frac))
        value:SetText(fmt(v) .. (row.unit or ""))
    end
    local function apply(v)
        local step = row.step or 1
        v = math.floor(v / step + 0.5) * step
        v = math.floor(v * 100 + 0.5) / 100
        if row.min then v = math.max(row.min, v) end
        if row.max then v = math.min(row.max, v) end
        row.updating = true
        s:SetValue(v)
        row.updating = false
        paint(v)
        if row.set then row.set(v) end
    end
    s:SetScript("OnValueChanged", function(self, v)
        if row.updating then return end
        apply(v)
    end)
    minus:SetScript("OnClick", function() apply((row.get and row.get() or s:GetValue()) - (row.step or 1)) end)
    plus:SetScript("OnClick", function() apply((row.get and row.get() or s:GetValue()) + (row.step or 1)) end)
    row.paint = paint
    row.reset = function(self) self.set = nil; self.get = nil; self.hover:Hide() end
    return row
end

-- Auswahlliste (eigenes Aufklappmenü, kein UIDropDownMenu: kein Taint, eigener Stil)
local closeMenu, openMenu

creators.dropdown = function(parent)
    local row = createRow(parent)
    local btn = createButton(row)
    btn:SetSize(CONTROL_W, 24)
    btn:SetPoint("LEFT", row, "RIGHT", -CONTROL_W - INSET, 0)
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", 8, 0)
    btn.label:SetPoint("RIGHT", -22, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)
    btn.arrow = btn:CreateTexture(nil, "OVERLAY")
    btn.arrow:SetSize(12, 12)
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    pcall(btn.arrow.SetRotation, btn.arrow, -math.pi / 2)
    btn:SetScript("OnMouseDown", nil)
    btn:SetScript("OnMouseUp", nil)
    btn:SetScript("OnClick", function(self)
        if row.values then
            openMenu(self, row.values, row.get and row.get(), row.labelFn, function(v)
                if row.set then row.set(v) end
                self:SetLabel(row.labelFn and row.labelFn(v) or tostring(v))
            end)
        end
    end)
    hoverable(btn, row)
    row.btn = btn
    row.reset = function(self) self.set = nil; self.get = nil; self.values = nil; self.labelFn = nil; self.hover:Hide() end
    return row
end

-- Freier Knopf
creators.button = function(parent)
    local b = createButton(parent)
    b.reset = function(self) self:SetScript("OnClick", nil); setEnabled(self, true); styleButton(self, false); self.tipTitle = nil end
    return b
end

-- Fläche mit Hintergrund (Karte)
creators.card = function(parent)
    local w = CreateFrame("Frame", nil, parent)
    w.bg = solid(w, "BACKGROUND", 1, 1, 1, 0.04)
    w.bg:SetAllPoints()
    w.edges = makeBorder(w, 1, 1, 1, 0.08)
    return w
end

-- Balken (Coach)
creators.bar = function(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetHeight(8)
    w.bg = solid(w, "BACKGROUND", 1, 1, 1, 0.08)
    w.bg:SetAllPoints()
    w.fg = solid(w, "ARTWORK", 1, 1, 1, 0.9)
    w.fg:SetPoint("TOPLEFT")
    w.fg:SetPoint("BOTTOMLEFT")
    w.fg:SetWidth(1)
    return w
end

local function setBar(w, width, fraction, r, g, b)
    w:SetWidth(width)
    w.fg:SetWidth(math.max(1, width * math.min(1, math.max(0, fraction))))
    w.fg:SetColorTexture(r, g, b, 0.9)
end

-- Symbol
creators.icon = function(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(20, 20)
    w.tex = w:CreateTexture(nil, "ARTWORK")
    w.tex:SetAllPoints()
    w.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return w
end

-- Verlaufszeile (Coach): anklickbar
creators.hrow = function(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.bg = solid(b, "BACKGROUND", 1, 1, 1, 0)
    b.bg:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)
    b.time = fs(b, 12)
    b.time:SetPoint("LEFT", INSET, 0)
    b.time:SetWidth(110)
    b.bar = creators.bar(b)
    b.bar:SetPoint("LEFT", INSET + 120, 0)
    b.pct = fs(b, 12)
    b.pct:SetPoint("LEFT", b.bar, "RIGHT", 10, 0)
    b.marker = solid(b, "ARTWORK", 1, 1, 1, 1)
    b.marker:SetPoint("TOPLEFT", 0, 0)
    b.marker:SetPoint("BOTTOMLEFT", 0, 0)
    b.marker:SetWidth(3)
    b:SetScript("OnClick", function(self)
        if self.index then
            ns.Coach.selected = self.index
            Config:Build()
        end
    end)
    b.reset = function(self) self.index = nil end
    return b
end

---------------------------------------------------------------------------
-- Aufklappmenü für Auswahllisten
---------------------------------------------------------------------------

local menu

function closeMenu()
    if menu and menu:IsShown() then menu:Hide() end
end

function openMenu(anchor, values, current, labelFn, onSelect)
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(20)
        menu:SetClampedToScreen(true)
        menu.bg = solid(menu, "BACKGROUND", 0.09, 0.09, 0.11, 0.98)
        menu.bg:SetAllPoints()
        menu.edges = makeBorder(menu, 1, 1, 1, 0.2)
        menu.items = {}
        -- unsichtbare Fläche darunter: Klick daneben schließt das Menü
        local catcher = CreateFrame("Frame", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(1)
        catcher:EnableMouse(true)
        catcher:SetScript("OnMouseDown", closeMenu)
        catcher:Hide()
        menu.catcher = catcher
        menu:SetScript("OnShow", function() catcher:Show() end)
        menu:SetScript("OnHide", function() catcher:Hide() end)
        menu:Hide()
    end
    if menu:IsShown() and menu.anchor == anchor then closeMenu() return end
    local maxW = anchor:GetWidth()
    for i, v in ipairs(values) do
        local it = menu.items[i]
        if not it then
            it = CreateFrame("Button", nil, menu)
            it:SetHeight(22)
            it.hl = it:CreateTexture(nil, "HIGHLIGHT")
            it.hl:SetAllPoints()
            it.hl:SetColorTexture(1, 1, 1, 0.08)
            it.text = fs(it, 12)
            it.text:SetPoint("LEFT", 12, 0)
            it.text:SetPoint("RIGHT", -8, 0)
            it.text:SetWordWrap(false)
            it.mark = solid(it, "ARTWORK", 1, 1, 1, 1)
            it.mark:SetPoint("TOPLEFT", 1, -3)
            it.mark:SetPoint("BOTTOMLEFT", 1, 3)
            it.mark:SetWidth(3)
            it:SetScript("OnClick", function(self)
                closeMenu()
                if menu.onSelect then menu.onSelect(self.value) end
            end)
            menu.items[i] = it
        end
        it.value = v
        it.text:SetText(labelFn and labelFn(v) or tostring(v))
        local r, g, b = accent()
        it.mark:SetColorTexture(r, g, b, 1)
        it.mark:SetShown(v == current)
        it.text:SetTextColor(v == current and 1 or 0.85, v == current and 1 or 0.85, v == current and 1 or 0.85)
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", 1, -(1 + (i - 1) * 22))
        it:SetPoint("RIGHT", -1, 0)
        it:Show()
        maxW = math.max(maxW, it.text:GetStringWidth() + 28)
    end
    for i = #values + 1, #menu.items do menu.items[i]:Hide() end
    menu.onSelect = onSelect
    menu.anchor = anchor
    menu:SetSize(maxW, #values * 22 + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

---------------------------------------------------------------------------
-- Builder: setzt die Bausteine von oben nach unten in den Scrollbereich
---------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

local function NewBuilder(parent, width)
    return setmetatable({ parent = parent, width = width, y = -4 }, Builder)
end

function Builder:get(kind)
    return acquire(kind, self.parent)
end

function Builder:place(w, x, dy)
    w:SetPoint("TOPLEFT", self.parent, "TOPLEFT", x or 0, self.y - (dy or 0))
end

function Builder:gap(n)
    self.y = self.y - (n or 8)
end

function Builder:header(text)
    self.y = self.y - 10
    local w = self:get("text")
    local r, g, b = accent()
    local h = setText(w, T(text), 14, "", r, g, b)
    self:place(w, INSET)
    local line = self:get("line")
    line:SetPoint("TOPLEFT", self.parent, "TOPLEFT", INSET, self.y - h - 5)
    line:SetWidth(self.width - 2 * INSET)
    self.y = self.y - h - 12
end

function Builder:note(text, r, g, b)
    local w = self:get("text")
    local h = setText(w, T(text), 11, "", r or COL_MUTED[1], g or COL_MUTED[2], b or COL_MUTED[3], self.width - 2 * INSET)
    self:place(w, INSET)
    self.y = self.y - h - 8
end

-- Fließtext in normaler Größe (Hilfe)
function Builder:para(text)
    local w = self:get("text")
    local h = setText(w, T(text), 12, "", 0.88, 0.88, 0.9, self.width - 2 * INSET)
    self:place(w, INSET)
    self.y = self.y - h - 8
end

-- Aufzählungspunkt: linke Spalte fett/hell, rechts Erklärung
function Builder:bullet(title, text)
    local w = self:get("text")
    local hT = setText(w, "•  " .. T(title), 12, "", 1, 1, 1, 180)
    self:place(w, INSET)
    local d = self:get("text")
    local h = setText(d, T(text), 12, "", 0.8, 0.8, 0.84, self.width - 2 * INSET - 190)
    d:SetPoint("TOPLEFT", self.parent, "TOPLEFT", INSET + 190, self.y)
    self.y = self.y - math.max(hT, h) - 6
end

function Builder:check(text, desc, get, set)
    local row = self:get("check")
    local title, d = T(text), T(desc)
    local h = fillRow(row, self.width, title, d, 26)
    row.cb:SetChecked(get() and true or false)
    row.set = set
    setTip(row.cb, title, d)
    self:place(row, 0)
    self.y = self.y - h
    return row
end

function Builder:slider(text, desc, get, set, min, max, step, unit)
    local row = self:get("slider")
    local title, d = T(text), T(desc)
    local h = fillRow(row, self.width, title, d, 24)
    row.min, row.max, row.step, row.unit = min or 0, max or 100, step or 1, unit
    row.get, row.set = get, set
    row.updating = true
    row.slider:SetMinMaxValues(row.min, row.max)
    row.slider:SetValueStep(row.step)
    row.slider:SetValue(get())
    row.updating = false
    row.paint(get())
    setTip(row.slider, title, d)
    setTip(row.minus, title, d)
    setTip(row.plus, title, d)
    self:place(row, 0)
    self.y = self.y - h
    return row
end

function Builder:dropdown(text, desc, values, get, set, display)
    local row = self:get("dropdown")
    local title, d = T(text), T(desc)
    local h = fillRow(row, self.width, title, d, 24)
    row.values = values
    row.get, row.set = get, set
    row.labelFn = function(v) return T(display and display(v) or tostring(v)) end
    row.btn:SetLabel(row.labelFn(get()))
    setTip(row.btn, title, d)
    self:place(row, 0)
    self.y = self.y - h
    return row
end

-- Knöpfe nebeneinander: { { text, desc, onClick, width, accent, disabled } ... }
function Builder:buttons(list)
    local x = INSET
    for _, item in ipairs(list) do
        local w = item.width or 170
        if x + w > self.width - INSET and x > INSET then
            x = INSET
            self.y = self.y - 30
        end
        local btn = self:get("button")
        btn:SetSize(w, 24)
        btn:SetLabel(T(item.text))
        btn:SetScript("OnClick", item.onClick)
        styleButton(btn, item.accent)
        setEnabled(btn, not item.disabled)
        setTip(btn, T(item.text), T(item.desc))
        self:place(btn, x)
        x = x + w + 8
    end
    self.y = self.y - 32
end

---------------------------------------------------------------------------
-- Scrollbereich mit eigener schmaler Leiste
---------------------------------------------------------------------------

local function createScroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf.child = child

    local bar = CreateFrame("Slider", nil, sf)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -1, -2)
    bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -1, 2)
    bar.track = solid(bar, "BACKGROUND", 1, 1, 1, 0.06)
    bar.track:SetAllPoints()
    bar:SetThumbTexture(WHITE)
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(6, 40)
    thumb:SetVertexColor(1, 1, 1, 0.35)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
    bar:Hide()
    sf.bar = bar

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local lo, hi = bar:GetMinMaxValues()
        if hi <= lo then return end
        bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 40)))
    end)

    function sf:Refresh(contentHeight)
        -- Sichthöhe: aus den Ankern, zur Sicherheit mit festem Ersatzwert
        local vh = self:GetHeight()
        if not vh or vh < 1 then vh = WIN_H - HEADER_H - TABS_H - FOOTER_H - 16 end
        local range = math.max(0, contentHeight - vh)
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        if range > 0 then
            thumb:SetHeight(math.max(24, vh * (vh / contentHeight)))
        end
        if bar:GetValue() > range then bar:SetValue(range) end
    end

    function sf:SetScroll(v)
        local lo, hi = bar:GetMinMaxValues()
        bar:SetValue(math.max(lo, math.min(hi, v or 0)))
        self:SetVerticalScroll(bar:GetValue())
    end
    return sf
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function savePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    ns.db.global.configPos = { point, relPoint, x, y }
end

local function restorePosition(f)
    local p = ns.db.global.configPos
    f:ClearAllPoints()
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER") end
end

local function createWindow()
    local f = CreateFrame("Frame", "ForeverRotationConfig", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
    restorePosition(f)

    f.bg = solid(f, "BACKGROUND", COL_BG[1], COL_BG[2], COL_BG[3], COL_BG[4])
    f.bg:SetAllPoints()
    f.edges = makeBorder(f, 0, 0, 0, 1)
    local r, g, b = accent()
    f.accentLine = solid(f, "BORDER", r, g, b, 0.9)
    f.accentLine:SetPoint("TOPLEFT", 1, -1)
    f.accentLine:SetPoint("TOPRIGHT", -1, -1)
    f.accentLine:SetHeight(2)

    -- Kopf: Logo, Titel, Untertitel, Schließen
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -3)
    header:SetPoint("TOPRIGHT", -1, -3)
    header:SetHeight(HEADER_H)
    header.bg = solid(header, "BACKGROUND", 1, 1, 1, 0.03)
    header.bg:SetAllPoints()
    f.header = header

    f.logo = header:CreateTexture(nil, "ARTWORK")
    f.logo:SetSize(30, 30)
    f.logo:SetPoint("LEFT", PAD, 0)
    f.logo:SetTexture(LOGO)
    f.logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local mask = header:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(f.logo)
    f.logo:AddMaskTexture(mask)
    f.logoRing = header:CreateTexture(nil, "BORDER")
    f.logoRing:SetSize(34, 34)
    f.logoRing:SetPoint("CENTER", f.logo, "CENTER")
    f.logoRing:SetColorTexture(r, g, b, 1)
    local ringMask = header:CreateMaskTexture()
    ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ringMask:SetAllPoints(f.logoRing)
    f.logoRing:AddMaskTexture(ringMask)

    f.title = fs(header, 17)
    f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 10, -1)
    f.title:SetText("ForeverRotation")
    f.subtitle = fs(header, 11)
    f.subtitle:SetTextColor(COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
    f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.subtitle:SetPoint("RIGHT", header, "RIGHT", -40, 0)
    f.subtitle:SetWordWrap(false)

    f.close = createButton(header)
    f.close:SetSize(24, 24)
    f.close:SetPoint("TOPRIGHT", -PAD + 4, -8)
    f.close:SetLabel("×")
    f.close.label:SetFont(FONT, 16, "")
    f.close:SetScript("OnClick", function() f:Hide() end)

    -- Reiterleiste
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    tabBar:SetHeight(TABS_H)
    tabBar.line = solid(tabBar, "ARTWORK", 1, 1, 1, 0.1)
    tabBar.line:SetPoint("BOTTOMLEFT")
    tabBar.line:SetPoint("BOTTOMRIGHT")
    tabBar.line:SetHeight(1)
    f.tabBar = tabBar
    f.tabButtons = {}

    -- Fußzeile: Sperrknopf, Hinweis, Version
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    footer.line = solid(footer, "ARTWORK", 1, 1, 1, 0.1)
    footer.line:SetPoint("TOPLEFT")
    footer.line:SetPoint("TOPRIGHT")
    footer.line:SetHeight(1)
    f.footer = footer
    f.lockBtn = createButton(footer)
    f.lockBtn:SetSize(170, 22)
    f.lockBtn:SetPoint("LEFT", PAD, 0)
    f.lockBtn:SetScript("OnClick", function()
        local g = ns.db.global
        g.locked = not g.locked
        if ns.Display then ns.Display:ApplySettings() end
        Config:Build()
    end)
    f.footHint = fs(footer, 11)
    f.footHint:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
    f.footHint:SetPoint("LEFT", f.lockBtn, "RIGHT", 12, 0)
    f.footHint:SetText(L["Änderungen gelten sofort · /frot help"])
    f.version = fs(footer, 11)
    f.version:SetTextColor(COL_DIM[1], COL_DIM[2], COL_DIM[3])
    f.version:SetPoint("RIGHT", -PAD, 0)
    f.version:SetText(VERSION ~= "" and ("v" .. VERSION) or "")

    -- Scrollbereich
    f.scroll = createScroll(f)
    f.scroll:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", PAD - 4, -4)
    f.scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -(PAD - 6), 4)

    -- Mit Escape schließen
    table.insert(UISpecialFrames, "ForeverRotationConfig")
    f:SetScript("OnShow", function() Config:Build() end)
    f:SetScript("OnHide", function()
        closeMenu()
        GameTooltip:Hide()
        if ns.Display then ns.Display:Update() end
    end)
    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Inhalt der Reiter
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

local MODE_LABELS = { off = "aus", instance = "nur in Dungeons", always = "immer" }
local function modeLabel(v) return MODE_LABELS[v] or v end

-- Reiter: Anzeige --------------------------------------------------------

local function buildDisplayTab(b, g)
    b:note("Solange dieser Reiter offen ist, bleibt die Anzeige sichtbar – jede Änderung ist sofort zu sehen.")
    b:header("Anzeige")
    b:check("Anzeige gesperrt", "Entsperrt lässt sich die Anzeige mit der Maus verschieben. Rechtsklick auf die Anzeige sperrt sie wieder.",
        function() return g.locked end,
        function(v) g.locked = v; applyDisplay(); Config:Build() end)
    b:check("Begründung unter dem Icon", "Zeigt, warum ein Zauber empfohlen wird.",
        function() return g.showReason end,
        function(v) g.showReason = v end)
    b:slider("Größe", "Skalierung der Anzeige.",
        function() return g.scale or 1 end,
        function(v) g.scale = v; applyDisplay() end, 0.5, 3, 0.1)
    b:slider("Größe in Dungeons (Faktor)", "Zusätzlicher Faktor in Dungeons und Schlachtzügen, z. B. 1.2 = 20 % größer.",
        function() return g.instanceScale or 1 end,
        function(v) g.instanceScale = v; applyDisplay() end, 0.5, 2, 0.1)
    b:slider("Transparenz außerhalb des Kampfs", "1 = voll sichtbar, 0.1 = fast unsichtbar.",
        function() return g.alphaOOC or 0.6 end,
        function(v) g.alphaOOC = v; applyDisplay() end, 0.1, 1, 0.1)
    b:check("Symbol an der Minimap", "Linksklick öffnet dieses Fenster, Shift-Klick den Coach, Rechtsklick sperrt/entsperrt die Anzeige. Am Rand entlang ziehbar.",
        function() return g.minimap end,
        function(v) g.minimap = v; ns.MinimapButton:Apply() end)
    b:buttons({
        { text = "Position zurücksetzen", desc = "Setzt die Anzeige zurück in die Bildschirmmitte.",
          onClick = function() g.pos = nil; applyDisplay() end },
    })

    b:header("Sichtbarkeit")
    b:dropdown("Anzeigen", "Wann die Anzeige erscheint. Entsperrt ist sie immer sichtbar.",
        { "targetOrCombat", "always", "combat", "target" },
        function() return g.showWhen or "targetOrCombat" end,
        function(v) g.showWhen = v end,
        function(v)
            if v == "always" then return "immer" end
            if v == "combat" then return "nur im Kampf" end
            if v == "target" then return "nur mit Ziel" end
            return "mit Ziel oder im Kampf"
        end)
    b:check("Auf dem Reittier ausblenden", "Blendet die Anzeige und die Erinnerungen aus, solange du reitest.",
        function() return g.hideMounted end,
        function(v) g.hideMounted = v end)
    b:check("Im Fahrzeug ausblenden", "Blendet die Anzeige aus, solange du ein Fahrzeug steuerst.",
        function() return g.hideVehicle end,
        function(v) g.hideVehicle = v end)

    b:header("Design")
    b:dropdown("Icon-Form", "Runde Icons (wie bei NAG) oder klassisch eckig.", { "round", "square" },
        function() return g.shape or "round" end,
        function(v) g.shape = v; applyDisplay() end,
        function(v) return v == "square" and "eckig" or "rund" end)
    b:check("Rahmen in Klassenfarbe", "Sonst schwarzer Rahmen.",
        function() return g.classBorder end,
        function(v) g.classBorder = v; applyDisplay() end)
    b:check("Leuchten, wenn jetzt drücken", "Goldenes Pulsieren um das große Icon.",
        function() return g.glow end,
        function(v) g.glow = v end)
    b:check("Cooldown-Spirale", "Spirale wie auf der Aktionsleiste (aus den mitgezählten Zeiten).",
        function() return g.swipe end,
        function(v) g.swipe = v end)
    b:check("Zweites Icon (danach)", "Zeigt, was nach dem aktuellen Zauber kommt (nur bei Timeline darunter oder ohne Timeline).",
        function() return g.showNext end,
        function(v) g.showNext = v end)
    if LibStub and LibStub("Masque", true) then
        b:check("Masque-Skin verwenden", "Icons im Stil deines Masque-Skins (dann immer eckig). Einstellbar unter /masque.",
            function() return g.masque end,
            function(v) g.masque = v; applyDisplay() end)
    end

    b:header("Timeline")
    b:check("Timeline anzeigen", "Die vorhergesagten nächsten Zauber laufen auf die Jetzt-Linie zu.",
        function() return g.timeline end,
        function(v) g.timeline = v; applyDisplay() end)
    b:dropdown("Position", "Neben dem Icon: Zauber gleiten in das große Icon hinein.\nDarunter: eigene Leiste mit Jetzt-Linie, plus \"danach\"-Icon.",
        { "row", "below" },
        function() return g.timelinePos or "row" end,
        function(v) g.timelinePos = v; applyDisplay() end,
        function(v) return v == "below" and "darunter" or "neben dem Icon" end)
    b:dropdown("Großes Icon im Leerlauf", "Was das große Icon zeigt, solange der nächste Zauber noch auf der Timeline heranläuft (nur bei Position \"neben dem Icon\").",
        { "spell", "empty", "auto" },
        function() return g.idleMode or "spell" end,
        function(v) g.idleMode = v end,
        function(v)
            if v == "empty" then return "leer + Countdown" end
            if v == "auto" then return "Autoangriff" end
            return "nächster Zauber (grau)"
        end)
    b:slider("Vorschau (Sekunden)", "Wie weit die Timeline in die Zukunft schaut.",
        function() return g.timelineSeconds or 12 end,
        function(v) g.timelineSeconds = v; applyDisplay() end, 4, 30, 1, " s")
end

-- Reiter: Hinweise -------------------------------------------------------

local function buildHintsTab(b, g)
    b:header("Aktionsleiste")
    b:check("Empfehlung auf der Aktionsleiste leuchten lassen", "Rahmt den Knopf des empfohlenen Zaubers ein (Blizzard-Leisten, Bartender4, Dominos, ElvUI). Gold = jetzt drücken, blau = zu wenig Mana, rot = außer Reichweite.",
        function() return g.actionGlow end,
        function(v) g.actionGlow = v end)
    b:dropdown("Leuchten ab", "Nur wenn jetzt drücken, oder schon vorher (grau), solange der Zauber noch heranläuft.",
        { "ready", "always" },
        function() return g.actionGlowMode or "ready" end,
        function(v) g.actionGlowMode = v end,
        function(v) return v == "always" and "schon vorher (grau)" or "wenn jetzt drücken" end)

    b:header("Procs")
    b:check("Proc-Hinweis an der Anzeige", "Text und Aufblitzen über dem großen Icon, z. B. wenn {Seal of Command} auslöst.\nDie Schadenszahlen selbst zeichnet das Spiel, die kann kein Addon einfärben.",
        function() return g.procAlert end,
        function(v) g.procAlert = v end)
    local sounds, soundLabels = {}, {}
    for _, e in ipairs(ns:AvailableProcSounds()) do
        sounds[#sounds + 1] = e.key
        soundLabels[e.key] = e.label
    end
    b:dropdown("Ton", "Wird beim Proc abgespielt (höchstens einmal pro 0,4 s).\nEigene Datei: Sounds\\proc.ogg im Addon-Ordner ablegen, dann Spiel neu starten.",
        sounds,
        function() return g.procSound or "off" end,
        function(v) g.procSound = v; ns:PlayProcSound(v) end,
        function(v) return soundLabels[v] or v end)
    b:buttons({
        { text = "Vorschau", width = 120, desc = "Zeigt den Hinweis und spielt den Ton einmal.",
          onClick = function()
              if ns.Display then
                  -- erster Proc der aktiven Rotation (Paladin: Seal of Command), sonst ein Platzhalter
                  local def = ns.rotation
                  local key, p = next(def and def.procs or {})
                  local icon = key and ns.spells[key] and ns.spells[key].icon
                  if not icon and def and def.rules[1] and ns.spells[def.rules[1].spell] then
                      icon = ns.spells[def.rules[1].spell].icon
                  end
                  ns.Display:ShowProc(p and p.label or "Proc!", icon, p and p.color or { 1, 0.85, 0.3 })
              end
              ns:PlayProcSound()
          end },
        { text = "Procs testen (60 s)", width = 170,
          desc = "Schreibt 60 Sekunden lang jeden eigenen Zauber und jeden erkannten Proc in den Chat. Damit lässt sich prüfen, ob Forever den Proc von {Seal of Command} meldet.",
          onClick = function() ns:StartCastLog(60) end },
    })

    b:header("Erinnerungen vor dem Pull")
    b:dropdown("Essen-Buff", "Zeigt über der Anzeige „Kein Essen-Buff“, solange du außerhalb des Kampfs bist.",
        { "off", "instance", "always" },
        function() return g.remindFood or "off" end,
        function(v) g.remindFood = v end, modeLabel)
    b:dropdown("Waffenöl / Wetzstein", "Zeigt eine Erinnerung, wenn deine Haupthand-Waffe keine temporäre Verzauberung hat.",
        { "off", "instance", "always" },
        function() return g.remindWeapon or "off" end,
        function(v) g.remindWeapon = v end, modeLabel)
end

-- Reiter: Rotation -------------------------------------------------------

local function buildRotationTab(b, g)
    local candidates = ns:CandidatesForPlayer()
    local def = ns.rotation
    if #candidates == 0 or not def then
        b:header("Rotation")
        b:note("Für deine Klasse gibt es noch keine Rotation.")
        return
    end
    b:header("Rolle")
    b:dropdown("Rolle", "Die Rolle bestimmt die Rotation, nicht die Talente.\nAutomatisch: Gruppenrolle, sonst Rollen-Buff (z. B. {Righteous Fury} = Tank), sonst Schaden.",
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
    if #candidates > 1 then
        local ids, labels = {}, {}
        for _, c in ipairs(candidates) do
            ids[#ids + 1] = c.id
            labels[c.id] = c.label
        end
        b:dropdown("Rotation", "Von Hand wählen legt auch die Rolle fest. Zurück zur Erkennung: Rolle auf Automatisch.", ids,
            function() return ns.rotation and ns.rotation.id end,
            function(id)
                ns:SelectRotation(ns.rotations[id])
                C_Timer.After(0, function() Config:Build() end)
            end,
            function(id) return labels[id] or id end)
    end
    local role, source = ns:DetectRole()
    b:note(string.format(L["Aktiv: %s – Rolle %s, erkannt über: %s"],
        ns:RotLabel(def), ns:RoleLabel(role), ns:SourceLabel(source)))
    b:buttons({
        { text = "Prioritäten bearbeiten", width = 200,
          desc = "Reihenfolge der Regeln ändern und einzelne Regeln abschalten.",
          onClick = function() Config:Open("prio") end },
        { text = "Cooldowns neu lernen", width = 200, desc = "Gelernte Cooldown-Dauern löschen, sie werden außerhalb des Kampfs neu gemessen.",
          onClick = function() wipe(ns.db.learnedCD); print(ns.PREFIX .. L["Gelernte Cooldowns gelöscht."]) end },
    })

    -- Optionen der Rotation
    b:header(def.label)
    local opts = sortedOptions(def)
    if #opts == 0 then b:note("Diese Rotation hat keine Optionen.") end
    for _, entry in ipairs(opts) do
        local name, o = entry.name, entry.o
        local text = o.label or name
        local get = function() return ns:Opt(name) end
        local set = function(v) ns:SetOpt(name, v) end
        if o.values then
            b:dropdown(text, o.desc, o.values, get, set,
                o.valueLabels and function(v) return o.valueLabels[v] or tostring(v) end)
        elseif type(o.default) == "boolean" then
            b:check(text, o.desc, get, set)
        elseif type(o.default) == "number" then
            b:slider(text, o.desc, get, set, o.min, o.max, o.step)
        end
    end
end

-- Reiter: Prioritäten ----------------------------------------------------

local prioRows = {}     -- Zeilen in aktueller Reihenfolge
local drag              -- { row, index, y0, active, target }
local ghost             -- schwebende Kopie der gezogenen Zeile
local insertLine        -- Einfügemarke

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

local function endDrag(apply)
    if ghost then ghost:Hide() end
    if insertLine then insertLine:Hide() end
    local d = drag
    drag = nil
    if apply and d and d.active and d.target and d.target ~= d.index and prioRows[d.index] then
        local key = prioRows[d.index].entry.key
        local step = d.target > d.index and 1 or -1
        for _ = 1, math.abs(d.target - d.index) do ns:MoveEntry(key, step) end
        Config:Build()
    end
end

local function ensureGhost()
    if ghost then return end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(260, PRIO_ROW_H)
    ghost.bg = solid(ghost, "BACKGROUND", 0.1, 0.1, 0.12, 0.95)
    ghost.bg:SetAllPoints()
    ghost.edges = makeBorder(ghost, 1, 1, 1, 0.3)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(20, 20)
    ghost.icon:SetPoint("LEFT", 8, 0)
    ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost.text = fs(ghost, 12)
    ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 8, 0)
    ghost.text:SetPoint("RIGHT", -8, 0)
    ghost.text:SetWordWrap(false)
    ghost:Hide()
end

creators.prow = function(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(PRIO_ROW_H)
    row.stripe = solid(row, "BACKGROUND", 1, 1, 1, 0.03, -1)
    row.stripe:SetAllPoints()
    row.active = solid(row, "BACKGROUND", 1, 1, 1, 0.15, 0)
    row.active:SetAllPoints()
    row.active:Hide()
    row.hover = solid(row, "BACKGROUND", 1, 1, 1, 0.05, 1)
    row.hover:SetAllPoints()
    row.hover:Hide()

    -- Griff (drei Striche) als Hinweis "ziehbar"
    row.grip = {}
    for i = 1, 3 do
        local t = solid(row, "ARTWORK", 1, 1, 1, 0.25)
        t:SetSize(10, 1)
        t:SetPoint("LEFT", 8, 4 - (i - 1) * 4)
        row.grip[i] = t
    end

    row.rank = fs(row, 12)
    row.rank:SetTextColor(COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
    row.rank:SetPoint("LEFT", 22, 0)
    row.rank:SetWidth(22)
    row.rank:SetJustifyH("RIGHT")

    row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.cb:SetSize(24, 24)
    row.cb:SetPoint("LEFT", row.rank, "RIGHT", 4, 0)
    local lbl = row.cb.Text or row.cb.text
    if lbl then lbl:SetText("") end
    row.cb:SetScript("OnClick", function(self)
        if row.entry then
            ns:SetEntryEnabled(row.entry.key, self:GetChecked() and true or false)
            Config:Build()
        end
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.down = arrowButton(row, "Down")
    row.down:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.down:SetScript("OnClick", function()
        if row.entry then ns:MoveEntry(row.entry.key, 1); Config:Build() end
    end)
    row.up = arrowButton(row, "Up")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetScript("OnClick", function()
        if row.entry then ns:MoveEntry(row.entry.key, -1); Config:Build() end
    end)

    -- Markierung "jetzt": diese Regel wird gerade empfohlen
    row.nowBg = solid(row, "ARTWORK", 1, 1, 1, 0.9)
    row.nowBg:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
    row.nowBg:SetSize(44, 16)
    row.nowBg:Hide()
    row.now = fs(row, 10)
    row.now:SetTextColor(0, 0, 0)
    row.now:SetPoint("CENTER", row.nowBg, "CENTER", 0, 0)
    row.now:SetJustifyH("CENTER")
    row.now:Hide()

    row.label = fs(row, 12)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", row.nowBg, "LEFT", -8, 0)
    row.label:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns:EntryLabel(self.entry), 1, 1, 1)
        for _, rule in ipairs(self.entry.rules) do
            local k = ns:Known(rule.spell)
            GameTooltip:AddDoubleLine(ns:SpellName(rule.spell), ns:T(rule.reason, rule.spell) or "",
                k and 1 or 0.5, k and 1 or 0.5, k and 1 or 0.5, 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Ziehen oder Pfeile: Reihenfolge ändern · Häkchen: Regel an/aus"], 0.6, 0.9, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide(); GameTooltip:Hide() end)
    row:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not self.entry then return end
        local _, cy = GetCursorPosition()
        drag = { row = self, index = self.index, y0 = cy / self:GetEffectiveScale(), active = false }
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and drag and drag.row == self then endDrag(true) end
    end)
    row.reset = function(self)
        self.entry, self.index = nil, nil
        self.active:Hide(); self.hover:Hide(); self.now:Hide(); self.nowBg:Hide()
    end
    return row
end

-- Läuft, solange der Prioritäten-Reiter offen ist: Markierung + Ziehen
local function prioTick(child, dt)
    child.tickAcc = (child.tickAcc or 0) + dt
    if child.tickAcc > 0.15 then
        child.tickAcc = 0
        local cur = ns.Display and ns.Display.currentRule
        local key = cur and cur.key
        for _, row in ipairs(prioRows) do
            local on = key ~= nil and row.entry and row.entry.key == key
            row.active:SetShown(on)
            row.now:SetShown(on)
            row.nowBg:SetShown(on)
        end
    end
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") then endDrag(true) return end
    local cx, cy = GetCursorPosition()
    local scale = child:GetEffectiveScale()
    local y = cy / scale
    if not drag.active and math.abs(y - drag.y0) > 6 then
        drag.active = true
        ensureGhost()
        ghost.icon:SetTexture(entryIcon(drag.row.entry))
        ghost.text:SetText(ns:EntryLabel(drag.row.entry))
        ghost:Show()
    end
    if not drag.active then return end
    local delta = math.floor((drag.y0 - y) / PRIO_ROW_H + 0.5)
    local target = math.max(1, math.min(#prioRows, drag.index + delta))
    drag.target = target
    local ref = prioRows[target]
    insertLine:ClearAllPoints()
    if target > drag.index then
        insertLine:SetPoint("TOPLEFT", ref, "BOTTOMLEFT", 0, 1)
        insertLine:SetPoint("TOPRIGHT", ref, "BOTTOMRIGHT", 0, 1)
    else
        insertLine:SetPoint("TOPLEFT", ref, "TOPLEFT", 0, 1)
        insertLine:SetPoint("TOPRIGHT", ref, "TOPRIGHT", 0, 1)
    end
    insertLine:SetShown(target ~= drag.index)
    local uiScale = UIParent:GetEffectiveScale()
    ghost:ClearAllPoints()
    ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", cx / uiScale + 16, cy / uiScale)
end

local function buildPrioTab(b, g)
    wipe(prioRows)
    local def = ns.rotation
    b:header(L["Prioritäten – "] .. ns:RotLabel(def))
    if not def then
        b:note("Für deine Klasse gibt es noch keine Rotation.")
        return
    end
    b:note("Oben = wichtiger. Es wird die erste Regel empfohlen, deren Bedingung passt und die (fast) bereit ist. Grau = noch nicht gelernt. Die gerade empfohlene Regel ist hervorgehoben.")
    b:gap(2)

    local r, g2, bl = accent()
    local list = ns:OrderedEntries(def)
    for i, entry in ipairs(list) do
        local row = b:get("prow")
        row:SetWidth(b.width - 2 * INSET)
        b:place(row, INSET)
        row.entry, row.index = entry, i
        row.stripe:SetShown(i % 2 == 0)
        local enabled = ns:EntryEnabled(entry.key)
        local known = entryKnown(entry)
        row.rank:SetText(tostring(i))
        row.cb:SetChecked(enabled)
        row.icon:SetTexture(entryIcon(entry))
        row.icon:SetDesaturated(not (enabled and known))
        row.label:SetText(ns:EntryLabel(entry))
        if not enabled then
            row.label:SetTextColor(0.5, 0.5, 0.5)
        elseif not known then
            row.label:SetTextColor(0.65, 0.65, 0.65)
        else
            row.label:SetTextColor(1, 1, 1)
        end
        row.active:SetColorTexture(r, g2, bl, 0.16)
        row.nowBg:SetColorTexture(r, g2, bl, 0.95)
        row.now:SetText(L["jetzt"])
        if i == 1 then row.up:Disable() else row.up:Enable() end
        if i == #list then row.down:Disable() else row.down:Enable() end
        prioRows[i] = row
        b.y = b.y - PRIO_ROW_H
    end
    b:gap(10)
    b:buttons({
        { text = "Standard wiederherstellen", width = 200, desc = "Setzt Reihenfolge und Häkchen dieser Rotation zurück.",
          onClick = function() ns:ResetPriorities(); Config:Build() end },
    })

    if not insertLine then
        insertLine = b.parent:CreateTexture(nil, "OVERLAY")
        insertLine:SetHeight(2)
        insertLine:Hide()
    end
    insertLine:SetColorTexture(r, g2, bl, 1)
    b.parent:SetScript("OnUpdate", prioTick)
end

-- Reiter: Coach ----------------------------------------------------------

local function fightTitle(r)
    return string.format("%s · %d s", date("%H:%M", r.time or 0), r.duration or 0)
end

local function buildCoachTab(b, g)
    local Coach = ns.Coach
    local hist = Coach:History()
    Coach.selected = math.min(Coach.selected or 1, math.max(1, #hist))
    local r = hist[Coach.selected]

    if not r then
        b:header("Coach")
        b:note(string.format(L["Noch keine Auswertung. Kämpfe mindestens %d Sekunden, dann erscheint sie hier."], g.coachMin or 10))
    else
        b:header(Coach.selected == 1 and (L["Letzter Kampf"] .. " · " .. fightTitle(r)) or fightTitle(r))
        -- Karte: große Prozentzahl links, Kennzahlen rechts
        local card = b:get("card")
        card:SetSize(b.width - 2 * INSET, 78)
        b:place(card, INSET)
        local pct = Coach:Pct(r)
        local cr, cg, cb = Coach:GradeRGB(pct)
        local big = b:get("text")
        setText(big, pct .. " %", 30, "THICKOUTLINE", cr, cg, cb)
        big:SetPoint("LEFT", card, "LEFT", 16, 6)
        local sub = b:get("text")
        setText(sub, string.format(L["nach Empfehlung (%d von %d Zaubern)"], r.match, r.casts), 11, "", COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
        sub:SetPoint("TOPLEFT", big, "BOTTOMLEFT", 2, -2)

        local statX, statY = 250, -12
        local function stat(label, value)
            local l = b:get("text")
            setText(l, T(label), 12, "", COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
            l:SetPoint("TOPLEFT", card, "TOPLEFT", statX, statY)
            local v = b:get("text")
            setText(v, value, 12, "", 1, 1, 1)
            v:SetPoint("TOPLEFT", card, "TOPLEFT", statX + 170, statY)
            statY = statY - 18
        end
        stat("Ø Reaktionszeit", string.format("%.1f s", r.avgDelay or 0))
        stat("Ungenutzte GCD-Zeit", string.format("%.1f s", r.idle or 0))
        local seal = r.drops and r.drops.seal
        if seal then stat("Siegel ausgelaufen", seal .. "×") end
        b.y = b.y - 78 - 8

        -- Reaktionszeit pro Zauber (Balken bis 2 s)
        local spells = {}
        for key, p in pairs(r.perSpell or {}) do spells[#spells + 1] = { key = key, n = p.n, avg = p.delay / p.n } end
        table.sort(spells, function(a, c) return a.avg > c.avg end)
        if #spells > 0 then
            b:header("Reaktion pro Zauber")
            for _, e in ipairs(spells) do
                local ic = b:get("icon")
                ic.tex:SetTexture((ns.spells[e.key] and ns.spells[e.key].icon) or 134400)
                ic:SetSize(18, 18)
                b:place(ic, INSET, 1)
                local name = b:get("text")
                setText(name, ns:SpellName(e.key), 12, "", 1, 1, 1, 200)
                name.text:SetWordWrap(false)
                b:place(name, INSET + 24, 3)
                local br, bg2, bb = 0.25, 1, 0.25
                if e.avg >= 1 then br, bg2, bb = 1, 0.31, 0.31 elseif e.avg >= 0.5 then br, bg2, bb = 1, 0.82, 0.25 end
                local bar = b:get("bar")
                setBar(bar, 160, e.avg / 2, br, bg2, bb)
                b:place(bar, INSET + 234, 6)
                local val = b:get("text")
                setText(val, string.format("%.1f s · %d×", e.avg, e.n), 11, "", COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
                b:place(val, INSET + 404, 4)
                b.y = b.y - 22
            end
        end

        b:header("Tipps")
        for _, tip in ipairs(Coach:Tips(r)) do b:para("•  " .. tip) end
    end

    -- Verlauf
    if #hist > 0 then
        b:header("Verlauf")
        for i, h in ipairs(hist) do
            local row = b:get("hrow")
            row:SetWidth(b.width - 2 * INSET)
            b:place(row, INSET)
            row.index = i
            row.time:SetText(fightTitle(h))
            local pct = Coach:Pct(h)
            local cr, cg, cb = Coach:GradeRGB(pct)
            setBar(row.bar, 200, pct / 100, cr, cg, cb)
            row.pct:SetText(pct .. " %")
            row.pct:SetTextColor(cr, cg, cb)
            local sel = i == Coach.selected
            row.bg:SetColorTexture(1, 1, 1, sel and 0.06 or 0)
            local ar, ag, ab = accent()
            row.marker:SetColorTexture(ar, ag, ab, 1)
            row.marker:SetShown(sel)
            b.y = b.y - 22
        end
        local avg = Coach:Average()
        if avg and avg.fights > 1 then
            b:gap(6)
            b:note(string.format(L["Ø der letzten %d Kämpfe: %d %% nach Empfehlung, Reaktion %.1f s, ungenutzte GCD-Zeit %.1f s pro Minute"],
                avg.fights, avg.pct, avg.avgDelay, avg.idlePerMin))
        end
    end

    b:header("Einstellungen")
    b:check("Auswertung nach dem Kampf", "Vergleicht deine Zauber mit den Empfehlungen: Anteil nach Empfehlung, Reaktionszeit, ungenutzte GCD-Zeit, ausgelaufene Siegel.",
        function() return g.coach end,
        function(v) g.coach = v end)
    b:check("Kurzinfo an der Anzeige", "Nach dem Kampf erscheint für ein paar Sekunden das Ergebnis unter der Anzeige.",
        function() return g.coachToast end,
        function(v) g.coachToast = v end)
    b:check("Zusätzlich im Chat ausgeben", "Eine Zeile im Chat nach jedem Kampf.",
        function() return g.coachChat end,
        function(v) g.coachChat = v end)
    b:slider("Kämpfe ab (Sekunden)", "Kürzere Kämpfe werden nicht ausgewertet.",
        function() return g.coachMin or 10 end,
        function(v) g.coachMin = v end, 5, 60, 5, " s")
    b:buttons({
        { text = "Verlauf löschen", width = 160, desc = "Löscht alle gespeicherten Kämpfe.",
          onClick = function() Coach:Reset() end },
    })
end

-- Reiter: Hilfe ----------------------------------------------------------

local function buildHelpTab(b, g)
    b:header("Erste Schritte")
    b:para("Die Anzeige erscheint, sobald du ein Ziel hast oder im Kampf bist. ForeverRotation schlägt nur vor – gedrückt wird wie gewohnt auf der Aktionsleiste.")
    b:bullet("Großes Icon", "Der Zauber, der jetzt dran ist. Leuchtet es golden, drücken. Grau mit Zahl = kommt in so vielen Sekunden.")
    b:bullet("Timeline", "Die vorhergesagten nächsten Zauber. Sie gleiten von rechts in das große Icon hinein.")
    b:bullet("Taste im Icon", "Die Taste, auf der der Zauber liegt – von deiner Aktionsleiste gelesen.")
    b:bullet("Blau eingefärbt", "Zu wenig Mana für diesen Zauber.")
    b:bullet("Rot eingefärbt", "Ziel außer Reichweite.")
    b:bullet("Text darunter", "Die Begründung: warum gerade dieser Zauber.")
    b:bullet("Aktionsleiste", "Der empfohlene Knopf wird zusätzlich eingerahmt (Reiter Hinweise).")
    b:gap(4)
    b:buttons({
        { text = "Anzeige verschieben", width = 180, desc = "Entsperrt die Anzeige: mit der Maus ziehen, Rechtsklick sperrt wieder.",
          onClick = function() g.locked = false; applyDisplay(); Config:Build() end },
        { text = "Prioritäten ansehen", width = 180, desc = "Zeigt die Regeln der aktiven Rotation.",
          onClick = function() Config:Open("prio") end },
    })

    b:header("Warum ist die Anzeige im Kampf manchmal ungenau?")
    b:para("WoW Forever versteckt im Kampf Cooldowns, Auren und Mana vor Addons. ForeverRotation zählt deine eigenen Zauber mit und rechnet daraus Cooldowns und Buffs hoch; außerhalb des Kampfs wird gegen die echten Werte abgeglichen. Restzeiten können daher im Kampf um ein paar Zehntel abweichen, und ein Siegel, das z. B. durch einen Tod verloren ging, fällt erst nach dem Kampf auf.")
    b:para("Lebens- und Manawerte liest das Addon nie – „zu wenig Mana“ und „unter 20 %“ kommen direkt aus der Nutzbarkeit des Zaubers, die das Spiel freigibt.")

    b:header("Rolle und Rotation")
    b:para("Welche Rotation gilt, entscheidet die Rolle, nicht der Talentbaum: Gruppenrolle, sonst ein Rollen-Buff (z. B. {Righteous Fury} = Tank), sonst Schaden. Im Reiter Rotation lässt sich die Rolle auch fest einstellen.")

    b:header("Befehle")
    for _, line in ipairs({
        "  /frot – Konfigurationsfenster öffnen",
        "  /frot unlock | lock – Anzeige verschieben",
        "  /frot minimap – Minimap-Symbol an/aus",
        "  /frot prio – Prioritäten bearbeiten",
        "  /frot coach [reset] – Coach-Fenster öffnen (reset = Verlauf löschen)",
        "  /frot casts [Sekunden] – eigene Zauber und Procs im Chat protokollieren (Test)",
        "  /frot scale <Zahl> – Größe, z. B. 1.2",
        "  /frot state – Schattenzustand ausgeben",
        "  /frot list – verfügbare Rotationen deiner Klasse",
        "  /frot use <Nummer> – Rotation wählen (legt die Rolle fest)",
        "  /frot role auto | tank | dps | heal – Rolle festlegen oder automatisch erkennen",
        "  /frot reason – Begründung unter dem Icon an/aus",
        "  /frot relearn – gelernte Cooldowns zurücksetzen",
    }) do
        local txt = L[line]:gsub("^%s+", "")
        local cmd, rest = txt:match("^(/frot[^–]*)–%s*(.*)$")
        if cmd then b:bullet(cmd, rest) else b:para(txt) end
    end
    b:gap(4)
    b:note(string.format(L["ForeverRotation %s · WoW Forever · Interface %s"], VERSION, tostring(select(4, GetBuildInfo()))))
end

---------------------------------------------------------------------------
-- Reiter und Aufbau
---------------------------------------------------------------------------

local TABS = {
    { key = "display",  label = "Anzeige",     build = buildDisplayTab },
    { key = "hints",    label = "Hinweise",    build = buildHintsTab },
    { key = "rotation", label = "Rotation",    build = buildRotationTab },
    { key = "prio",     label = "Prioritäten", build = buildPrioTab },
    { key = "coach",    label = "Coach",       build = buildCoachTab },
    { key = "help",     label = "Hilfe",       build = buildHelpTab },
}

local function createTabButton(f, tab)
    local btn = CreateFrame("Button", nil, f.tabBar)
    btn:SetHeight(TABS_H)
    btn.label = fs(btn, 13)
    btn.label:SetPoint("CENTER", 0, 1)
    btn.label:SetJustifyH("CENTER")
    btn.label:SetText(T(tab.label))
    btn:SetWidth(btn.label:GetStringWidth() + 26)
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetAllPoints()
    btn.hl:SetColorTexture(1, 1, 1, 0.05)
    btn.underline = solid(btn, "ARTWORK", 1, 1, 1, 1)
    btn.underline:SetPoint("BOTTOMLEFT", 6, 0)
    btn.underline:SetPoint("BOTTOMRIGHT", -6, 0)
    btn.underline:SetHeight(2)
    btn:SetScript("OnClick", function()
        Config.tab = tab.key
        Config:Build()
    end)
    return btn
end

function Config:Build()
    local f = self.frame
    if not f then return end
    closeMenu()
    endDrag(false)
    GameTooltip:Hide()
    local g = ns.db.global
    self.tab = self.tab or "display"
    local keepScroll = (self.builtTab == self.tab) and f.scroll:GetVerticalScroll() or 0
    releaseAll()
    f.scroll.child:SetScript("OnUpdate", nil)

    -- Reiter-Knöpfe
    local x = PAD - 6
    local r, gr, bl = accent()
    for _, tab in ipairs(TABS) do
        local btn = f.tabButtons[tab.key]
        if not btn then
            btn = createTabButton(f, tab)
            f.tabButtons[tab.key] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", f.tabBar, "BOTTOMLEFT", x, 0)
        x = x + btn:GetWidth() + 2
        local active = tab.key == self.tab
        btn.underline:SetColorTexture(r, gr, bl, 1)
        btn.underline:SetShown(active)
        if active then
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.label:SetTextColor(COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
        end
    end

    -- Untertitel: aktive Rotation
    local def = ns.rotation
    if def then
        local role, source = ns:DetectRole()
        f.subtitle:SetText(string.format(L["%s · Rolle %s (%s)"], ns:RotLabel(def), ns:RoleLabel(role), ns:SourceLabel(source)))
    else
        f.subtitle:SetText(L["Für deine Klasse gibt es noch keine Rotation."])
    end
    f.lockBtn:SetLabel(g.locked and L["Anzeige verschieben"] or L["Anzeige sperren"])
    styleButton(f.lockBtn, not g.locked)
    f.accentLine:SetColorTexture(r, gr, bl, 0.9)
    f.logoRing:SetColorTexture(r, gr, bl, 1)

    -- Inhalt
    local child = f.scroll.child
    local width = WIN_W - 2 * PAD - 4
    child:SetWidth(width)
    local b = NewBuilder(child, width)
    for _, tab in ipairs(TABS) do
        if tab.key == self.tab then tab.build(b, g) end
    end
    local h = -b.y + PAD
    child:SetHeight(h)
    f.scroll:Refresh(h)
    f.scroll:SetScroll(keepScroll)
    self.builtTab = self.tab
    if ns.Display then ns.Display:Update() end
end

-- Neu zeichnen, falls offen (z. B. nach Sperren per Rechtsklick)
function Config:Refresh()
    if self.frame and self.frame:IsShown() then self:Build() end
end

-- Vorschau: Reiter "Anzeige" offen -> Anzeige bleibt sichtbar
function Config:PreviewActive()
    return self.frame ~= nil and self.frame:IsShown() and self.tab == "display"
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

-- Prioritäten: früher ein eigenes Fenster, jetzt ein Reiter. Kern und Slash-Befehl
-- sprechen weiter ns.Priorities an.
local Priorities = {}
ns.Priorities = Priorities

function Priorities:Toggle()
    if Config.frame and Config.frame:IsShown() and Config.tab == "prio" then
        Config.frame:Hide()
    else
        Config:Open("prio")
    end
end

function Priorities:Build()
    if Config.tab == "prio" then Config:Refresh() end
end

---------------------------------------------------------------------------
-- Willkommensfenster beim ersten Start
---------------------------------------------------------------------------

function Config:ShowWelcome()
    local g = ns.db.global
    if self.welcome then self.welcome:Show() return end
    local f = CreateFrame("Frame", "ForeverRotationWelcome", UIParent)
    f:SetSize(440, 230)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.bg = solid(f, "BACKGROUND", COL_BG[1], COL_BG[2], COL_BG[3], COL_BG[4])
    f.bg:SetAllPoints()
    f.edges = makeBorder(f, 0, 0, 0, 1)
    local r, gr, bl = accent()
    f.accentLine = solid(f, "BORDER", r, gr, bl, 0.9)
    f.accentLine:SetPoint("TOPLEFT", 1, -1)
    f.accentLine:SetPoint("TOPRIGHT", -1, -1)
    f.accentLine:SetHeight(2)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetPoint("TOPLEFT", 18, -18)
    logo:SetTexture(LOGO)
    logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local mask = f:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(logo)
    logo:AddMaskTexture(mask)

    local title = fs(f, 16)
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
    title:SetText(L["Willkommen bei ForeverRotation!"])
    local sub = fs(f, 11)
    sub:SetTextColor(COL_MUTED[1], COL_MUTED[2], COL_MUTED[3])
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText(ns.rotation and ns:RotLabel(ns.rotation) or "")

    local body = fs(f, 12)
    body:SetPoint("TOPLEFT", 18, -70)
    body:SetWidth(440 - 36)
    body:SetTextColor(0.88, 0.88, 0.9)
    body:SetText(L["Die Anzeige erscheint, sobald du ein Ziel hast oder im Kampf bist. Das große Icon ist der Zauber, der jetzt dran ist; die Timeline zeigt, was danach kommt. Gedrückt wird wie gewohnt auf deiner Aktionsleiste.\n\nTipp: Verschiebe die Anzeige zuerst an eine gut sichtbare Stelle."])

    local function button(text, x, accented, onClick)
        local btn = createButton(f)
        btn:SetSize(130, 24)
        btn:SetPoint("BOTTOMLEFT", x, 16)
        btn:SetLabel(L[text])
        styleButton(btn, accented)
        btn:SetScript("OnClick", function() g.welcomeShown = true; f:Hide(); onClick() end)
        return btn
    end
    button("Anzeige verschieben", 18, true, function()
        g.locked = false
        applyDisplay()
    end)
    button("Einstellungen", 18 + 138, false, function() Config:Open("help") end)
    button("Später", 18 + 276, false, function() end)
    table.insert(UISpecialFrames, "ForeverRotationWelcome")
    self.welcome = f
end

---------------------------------------------------------------------------
-- Eintrag in den Blizzard-Einstellungen (Optionen > AddOns): kurze Beschreibung
-- und ein Knopf, der das eigene Fenster öffnet.
---------------------------------------------------------------------------

function Config:RegisterSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local ok = pcall(function()
        local canvas = CreateFrame("Frame")
        canvas:Hide()
        local logo = canvas:CreateTexture(nil, "ARTWORK")
        logo:SetSize(40, 40)
        logo:SetPoint("TOPLEFT", 16, -16)
        logo:SetTexture(LOGO)
        logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local title = fs(canvas, 18)
        title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
        title:SetText("ForeverRotation" .. (VERSION ~= "" and ("  |cff888888v" .. VERSION .. "|r") or ""))
        local desc = fs(canvas, 12)
        desc:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
        desc:SetWidth(520)
        desc:SetTextColor(0.85, 0.85, 0.85)
        desc:SetText(L["Rotationshelfer für WoW Forever. Zeigt den nächsten Zauber an, ohne geheime Werte zu lesen. Alle Einstellungen liegen im eigenen Fenster (/frot)."])
        local btn = createButton(canvas)
        btn:SetSize(220, 26)
        btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
        btn:SetLabel(L["Einstellungen öffnen"])
        styleButton(btn, true)
        btn:SetScript("OnClick", function()
            if SettingsPanel and SettingsPanel.Hide then pcall(SettingsPanel.Hide, SettingsPanel) end
            Config:Open()
        end)
        local category = Settings.RegisterCanvasLayoutCategory(canvas, "ForeverRotation")
        Settings.RegisterAddOnCategory(category)
        Config.settingsCategory = category
    end)
    return ok
end

---------------------------------------------------------------------------
-- Symbol an der Minimap (ohne Bibliothek): am Rand entlang ziehbar.
-- Linksklick = Einstellungen, Shift = Coach, Strg = Prioritäten,
-- Rechtsklick = Anzeige sperren/entsperren.
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
    icon:SetTexture(LOGO)
    icon:SetPoint("TOPLEFT", 7, -6)
    -- rund zuschneiden wie die übrigen Minimap-Knöpfe
    local mask = b:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
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
            Config:Refresh()
            print(ns.PREFIX .. (g.locked and L["Anzeige fixiert."] or L["Anzeige entsperrt: mit der Maus verschieben."]))
        elseif IsShiftKeyDown() then
            Config:Open("coach")
        elseif IsControlKeyDown() then
            Config:Open("prio")
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
            local cur = ns.Display and ns.Display.currentRule
            if cur then
                GameTooltip:AddLine(L["Empfehlung: "] .. ns:SpellName(cur.spell)
                    .. (cur.reason and (" – " .. ns:T(cur.reason, cur.spell)) or ""), 0.8, 0.8, 0.8)
            end
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
        GameTooltip:AddLine(L["Strg-Klick: Prioritäten"], 0.6, 0.9, 1)
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
loginFrame:SetScript("OnEvent", function()
    MinimapButton:Apply()
    Config:RegisterSettings()
    -- Erster Start: kurze Einführung, sobald die Welt geladen ist
    if ns.db and not ns.db.global.welcomeShown and ns.rotation and C_Timer then
        C_Timer.After(4, function()
            if ns.db and not ns.db.global.welcomeShown and not InCombatLockdown() then Config:ShowWelcome() end
        end)
    end
end)
