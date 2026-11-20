-- ForeverRotation – Echo-Anzeige (Unsealed Wrath) über Blizzards native Aura-Anzeige.
--
-- Die Stapel der Siegel-Kopien sind im Kampf für Addons geheim. Blizzards AuraContainer
-- zeichnet sie aber selbst: Pro Kopie-Aura (Echo of Command, Echo of Righteousness …) gibt es
-- einen Slot; das Spiel setzt den Wert einer Stapelleiste auf die echte Stapelzahl und blendet
-- eine zweite Leiste nur ab 3 Stapeln ein. An der ersten hängt ein Ausschnitt, der die Füllung
-- (Bögen, Hohlkehle des Schwerts, Edelsteine) freigibt, an der zweiten das Leuchten. Das Addon
-- liest dabei NICHTS – die Anzeige stimmt 1:1, die Werte bleiben geheim.
-- (Aufbau nach Blizzard_CustomAuraContainer.)

local _, ns = ...

local Echo = {}
ns.EchoDisplay = Echo

local TEX = "Interface\\AddOns\\ForeverRotation\\Textures\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Stile: Texturgröße (tw, th), Anzeigegröße (w, h), Lage zum Charakter, Füllbereich in Textur-Pixeln.
--   base     Grundbild ab der 1. Kopie (tintBase = in Siegelfarbe einfärben)
--   fill     wird von unten nach oben (bzw. links nach rechts) freigegeben
--   glow     Schein bei 3 Kopien
local STYLES = {
    arcs = {
        tw = 512, th = 256, w = 512, h = 256, x = 0, y = -10,
        base = "echo_edge", tintBase = true, fill = "echo_arcs", glow = "echo_glow",
        vertical = true, from = 218, to = 38,
    },
    sword = {
        tw = 128, th = 512, w = 80, h = 320, x = 150, y = 0,
        base = "echo_sword_base", fill = "echo_sword_fill", glow = "echo_sword_glow",
        vertical = true, from = 350, to = 70,
    },
    gems = {
        tw = 256, th = 64, w = 192, h = 48, x = 0, y = -125,
        base = "echo_gems_base", fill = "echo_gems_fill", glow = "echo_gems_glow",
        vertical = false, from = 20, to = 236,
    },
}

-- Kopie-Auren von Unsealed Wrath je Siegel: Farbe der Füllung, Farbe des Leuchtens bei 3
-- (beim Twisten = Farbe des Siegels, auf das gewechselt wird)
local ORANGE, BLUE, GOLD = { 1.00, 0.55, 0.10 }, { 0.35, 0.75, 1.00 }, { 1.00, 0.85, 0.30 }
local ECHOES = {
    { id = 1311703, color = ORANGE,                  full = BLUE },   -- Echo of Command
    { id = 1311704, color = BLUE,                    full = ORANGE }, -- Echo of Righteousness
    { id = 1311705, color = { 0.70, 0.40, 1.00 },    full = GOLD },   -- Echo of Justice
    { id = 1311701, color = { 1.00, 0.25, 0.20 },    full = GOLD },   -- Echo of Fury
    { id = 1328198, color = { 0.45, 1.00, 0.55 },    full = GOLD },   -- Echo of Light
    { id = 1328206, color = { 0.30, 0.90, 0.90 },    full = GOLD },   -- Echo of Wisdom
}

local containers = {}   -- [Stil] = { frame = AuraContainer, status = "...", failed = "..." }
local active             -- Stil, der gerade läuft

local function interp()
    return Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
end

local function texture(parent, layer, sub, file, button)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(TEX .. file)
    t:SetAllPoints(button)
    return t
end

-- Slot "Stapel": Grundbild + Füllung, die das Spiel über die Stapelleiste freigibt
local function initStacks(button, e, st, container)
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "CENTER")
    button:SetSize(st.w, st.h)
    local r, g, b = e.color[1], e.color[2], e.color[3]
    local fx, fy = st.w / st.tw, st.h / st.th

    local base = texture(button, "BACKGROUND", 0, st.base, button)
    if st.tintBase then base:SetVertexColor(r, g, b, 0.8) end

    -- unsichtbare Leiste über dem Füllbereich: das Spiel setzt ihren Wert auf die Stapelzahl
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetMinMaxValues(0, 3)
    bar:SetValue(0)
    local clip = CreateFrame("Frame", nil, button)
    clip:SetClipsChildren(true)
    if st.vertical then
        bar:SetOrientation("VERTICAL")
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -st.to * fy)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, (st.th - st.from) * fy)
        clip:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
        clip:SetPoint("RIGHT", button, "RIGHT")
        clip:SetPoint("TOP", bar:GetStatusBarTexture(), "TOP")
    else
        bar:SetOrientation("HORIZONTAL")
        bar:SetPoint("TOPLEFT", button, "TOPLEFT", st.from * fx, 0)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -(st.tw - st.to) * fx, 0)
        clip:SetPoint("TOPLEFT", button, "TOPLEFT")
        clip:SetPoint("BOTTOM", button, "BOTTOM")
        clip:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT")
    end
    local fill = clip:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(TEX .. st.fill)
    fill:SetPoint("TOPLEFT", button, "TOPLEFT")
    fill:SetSize(st.w, st.h)
    fill:SetBlendMode("ADD")
    fill:SetVertexColor(r, g, b, 1)

    -- erst jetzt übergeben: danach gehört der Wert der Leiste dem Spiel (geheim)
    button:SetApplicationBar(bar, { maxApplications = 3, interpolation = interp() })
end

-- Slot "voll": Leuchten und volle Füllung in Zielfarbe, nur ab 3 Stapeln (entscheidet das Spiel)
local function initFull(button, e, st, container)
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "CENTER")
    button:SetSize(st.w, st.h)
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    local glow = texture(bar, "BACKGROUND", -1, st.glow, button)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(e.full[1], e.full[2], e.full[3], 0.9)
    local fill = texture(bar, "OVERLAY", 1, st.fill, button)
    fill:SetBlendMode("ADD")
    fill:SetVertexColor(e.full[1], e.full[2], e.full[3], 0.9)
    button:SetApplicationBar(bar, { minApplications = 3, maxApplications = 3 })
end

local function build(styleKey)
    local st = STYLES[styleKey]
    local info = { status = {} }
    containers[styleKey] = info
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then
        info.failed = "AuraContainer: " .. tostring(c)
        return
    end
    info.frame = c
    c:SetSize(st.w, st.h)
    c:SetPoint("CENTER", UIParent, "CENTER", st.x, st.y)
    c:SetFrameStrata("BACKGROUND")
    c:EnableMouse(false)
    c:Hide()
    local okU, errU = pcall(c.SetUnit, c, "player")
    if not okU then info.failed = "SetUnit: " .. tostring(errU) return end
    pcall(c.SetEnabled, c, false)

    local n = 0
    local function addSlot(key, spellID, init, e)
        local initErr
        local okA, err = pcall(c.AddAuraSlot, c, key, "HELPFUL", {
            candidateFilters = { includeSpellIDs = { [spellID] = true } },
            initializeFrame = function(button)
                local okI, errI = pcall(init, button, e, st, c)
                if not okI then initErr = errI end
            end,
        })
        if not okA or initErr then
            info.status[#info.status + 1] = key .. ": " .. tostring(initErr or err):sub(1, 120)
            return
        end
        pcall(c.SetAuraSlotEnabled, c, key, true)
        n = n + 1
    end
    for _, e in ipairs(ECHOES) do
        addSlot("s" .. e.id, e.id, initStacks, e)
        addSlot("f" .. e.id, e.id, initFull, e)
    end
    table.insert(info.status, 1, n .. " Slots angelegt")
end

-- Gewünschter Stil oder nil (nur Vergeltung mit Option an)
local function wantedStyle()
    if not (ns.rotation and ns.rotation.id == "PALADIN_RETRIBUTION") then return nil end
    local style = ns:Opt("echoFx")
    if style == true then style = "arcs" end      -- alte Einstellung (an/aus)
    return STYLES[style] and style or nil
end

local function setShown(styleKey, on)
    local info = containers[styleKey]
    if info and info.frame then
        pcall(info.frame.SetEnabled, info.frame, on)
        info.frame:SetShown(on)
    end
end

function Echo:Refresh()
    local want = wantedStyle()
    if want and not containers[want] then
        if InCombatLockdown() then want = active else build(want) end   -- erst nach dem Kampf aufbauen
    end
    if want ~= active then
        if active then setShown(active, false) end
        active = want
        if active then setShown(active, true) end
    end
    local info = active and containers[active]
    if info and info.frame then
        local scale = ns:Opt("echoFxScale") or 1
        if info.frame:GetScale() ~= scale then info.frame:SetScale(scale) end
    end
end

-- Zeile für /frot state
function Echo:StatusText()
    local style = wantedStyle()
    if not style then return "aus" end
    local info = containers[style]
    if not info then return style .. ": noch nicht aufgebaut" end
    if info.failed then return style .. ": Fehler – " .. info.failed end
    return style .. ": " .. table.concat(info.status, "; ")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    if ns.db then Echo:Refresh() end
end)
-- Optionen/Rotation können sich jederzeit ändern: selten nachsehen reicht
C_Timer.NewTicker(1, function()
    if ns.db then Echo:Refresh() end
end)
