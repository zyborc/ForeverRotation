-- ForeverRotation – Echo-Anzeige (Unsealed Wrath) über Blizzards native Aura-Anzeige.
--
-- Die Stapel der Siegel-Kopien sind im Kampf für Addons geheim. Blizzards AuraContainer
-- zeichnet sie aber selbst: Pro Kopie-Aura (Echo of Command, Echo of Righteousness …) gibt es
-- einen Slot; das Spiel setzt den Wert einer Stapelleiste auf die echte Stapelzahl und blendet
-- eine zweite Leiste nur ab 3 Stapeln ein. An der ersten hängt ein Ausschnitt, der die Bögen von
-- unten nach oben freigibt, an der zweiten das Leuchten. Das Addon liest dabei NICHTS – die
-- Anzeige stimmt 1:1, die Werte bleiben geheim. (Aufbau nach Blizzard_CustomAuraContainer.)

local _, ns = ...

local Echo = {}
ns.EchoDisplay = Echo

local TEX = "Interface\\AddOns\\ForeverRotation\\Textures\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local W, H = 512, 256
local BAR_TOP, BAR_BOTTOM = 38, 218      -- senkrechter Bereich der Bögen in der Textur

-- Kopie-Auren von Unsealed Wrath je Siegel: Farbe der Bögen, Farbe des Leuchtens bei 3
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

local container
local built, failed = false, nil
local status = {}          -- für /frot state: Slots, die angelegt wurden / Fehler

local function interp()
    return Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
end

-- Slot "Stapel": Umriss + Bögen, die das Spiel über die Stapelleiste freigibt
local function initStacks(button, e)
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "CENTER")
    button:SetSize(W, H)
    local r, g, b = e.color[1], e.color[2], e.color[3]

    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetTexture(TEX .. "echo_edge")
    edge:SetAllPoints(button)
    edge:SetVertexColor(r, g, b, 0.8)

    -- unsichtbare Leiste: das Spiel setzt ihren Wert auf die Stapelzahl (0..3)
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetOrientation("VERTICAL")
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -BAR_TOP)
    bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, H - BAR_BOTTOM)
    bar:SetMinMaxValues(0, 3)
    bar:SetValue(0)

    -- Ausschnitt von unten bis zur Füllkante der Leiste
    local clip = CreateFrame("Frame", nil, button)
    clip:SetClipsChildren(true)
    clip:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT")
    clip:SetPoint("RIGHT", button, "RIGHT")
    clip:SetPoint("TOP", bar:GetStatusBarTexture(), "TOP")
    local arcs = clip:CreateTexture(nil, "ARTWORK")
    arcs:SetTexture(TEX .. "echo_arcs")
    arcs:SetPoint("TOPLEFT", button, "TOPLEFT")
    arcs:SetSize(W, H)
    arcs:SetBlendMode("ADD")
    arcs:SetVertexColor(r, g, b, 1)

    -- erst jetzt übergeben: danach gehört der Wert der Leiste dem Spiel (geheim)
    button:SetApplicationBar(bar, { maxApplications = 3, interpolation = interp() })
end

-- Slot "voll": Leuchten, das das Spiel nur ab 3 Stapeln einblendet
local function initFull(button, e)
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "CENTER")
    button:SetSize(W, H)
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    local glow = bar:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(TEX .. "echo_glow")
    glow:SetAllPoints(button)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(e.full[1], e.full[2], e.full[3], 0.9)
    local arcs = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    arcs:SetTexture(TEX .. "echo_arcs")
    arcs:SetAllPoints(button)
    arcs:SetBlendMode("ADD")
    arcs:SetVertexColor(e.full[1], e.full[2], e.full[3], 0.9)
    -- das Spiel zeigt die Leiste (und damit das Leuchten) nur bei Stapel >= 3
    button:SetApplicationBar(bar, { minApplications = 3, maxApplications = 3 })
end

local function addSlot(key, spellID, init, e)
    local initErr
    local ok, err = pcall(container.AddAuraSlot, container, key, "HELPFUL", {
        candidateFilters = { includeSpellIDs = { [spellID] = true } },
        initializeFrame = function(button)
            local okI, errI = pcall(init, button, e)
            if not okI then initErr = errI end
        end,
    })
    if not ok or initErr then
        status[#status + 1] = key .. ": " .. tostring(initErr or err):sub(1, 120)
        return false
    end
    pcall(container.SetAuraSlotEnabled, container, key, true)
    return true
end

local function build()
    built = true
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then
        failed = "AuraContainer: " .. tostring(c)
        return
    end
    container = c
    container:SetSize(W, H)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, -10)
    container:SetFrameStrata("BACKGROUND")
    container:EnableMouse(false)
    local okU, errU = pcall(container.SetUnit, container, "player")
    if not okU then failed = "SetUnit: " .. tostring(errU) return end
    local n = 0
    for _, e in ipairs(ECHOES) do
        if addSlot("s" .. e.id, e.id, initStacks, e) then n = n + 1 end
        if addSlot("f" .. e.id, e.id, initFull, e) then n = n + 1 end
    end
    status[#status + 1] = n .. " Slots angelegt"
end

-- Soll die Anzeige laufen? Nur Vergeltung mit Option an.
local function wanted()
    return ns.rotation and ns.rotation.id == "PALADIN_RETRIBUTION" and ns:Opt("echoFx") and true or false
end

function Echo:Refresh()
    local want = wanted()
    if want and not built then
        if InCombatLockdown() then return end   -- erst nach dem Kampf aufbauen
        build()
    end
    if container and want ~= self.shown then
        self.shown = want
        pcall(container.SetEnabled, container, want)
        container:SetShown(want)
    end
    if container and want then
        local scale = ns:Opt("echoFxScale") or 1
        if container:GetScale() ~= scale then container:SetScale(scale) end
    end
end

-- Zeile für /frot state
function Echo:StatusText()
    if failed then return "Fehler – " .. failed end
    if not built then return "nicht aufgebaut" end
    return table.concat(status, "; ")
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
