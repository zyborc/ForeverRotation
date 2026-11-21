-- ForeverRotation – Echo-Anzeige (Unsealed Wrath) über Blizzards native Aura-Anzeige.
--
-- Die Stapel der Siegel-Kopien sind im Kampf für Addons geheim. Blizzards AuraContainer
-- zeichnet sie aber selbst: Pro Kopie-Aura (Echo of Command, Echo of Righteousness …) gibt es
-- einen Slot; das Spiel setzt den Wert einer Stapelleiste auf die echte Stapelzahl und blendet
-- eine zweite Leiste nur ab 3 Stapeln ein. An der ersten hängt ein Ausschnitt, der die Füllung
-- (Bögen, Runen-Kanal der Klinge) freigibt, an der zweiten das Leuchten. Das Addon
-- liest dabei NICHTS – die Anzeige stimmt 1:1, die Werte bleiben geheim.
-- (Aufbau nach Blizzard_CustomAuraContainer.)

local _, ns = ...

local Echo = {}
ns.EchoDisplay = Echo

local TEX = "Interface\\AddOns\\ForeverRotation\\Textures\\"
local STRATA = "BACKGROUND"   -- unterste Ebene für Addons ("WORLD" setzt das Spiel still auf MEDIUM)
local CUSTOM = "Interface\\AddOns\\ForeverRotation\\Custom\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Stile: Texturgröße (tw, th), Anzeigegröße (w, h), Lage zum Charakter, Füllbereich in Textur-Pixeln.
--   base     Grundbild ab der 1. Kopie (tintBase = in Siegelfarbe einfärben)
--   fill     wird von unten nach oben (bzw. links nach rechts) freigegeben
--   glow     Schein bei 3 Kopien
-- Stufen-Stile (stages): je Stufe ein Slot, den das Spiel erst ab `min` Stapeln zeigt. Teile:
--   file, color ("seal" = Siegelfarbe, "target" = Zielfarbe, nil = Originalfarben), alpha, add (ADD-Mischung)
local STYLES = {
    arch = {     -- Echo-Bogen: linker Bogen / Hammer mit Flügeln / rechter Bogen
        w = 400, h = 200, x = 0, y = 90, tintable = true,
        stages = {
            { min = 1, parts = {
                { file = "echo_arch_p1", alpha = 0.25 }, { file = "echo_arch_p2", alpha = 0.25 },
                { file = "echo_arch_p3", alpha = 0.25 },
                { file = "echo_arch_g1", color = "seal", alpha = 0.18, add = true },
                { file = "echo_arch_p1" } } },
            { min = 2, parts = {
                { file = "echo_arch_g2", color = "seal", alpha = 0.18, add = true },
                { file = "echo_arch_p2" } } },
            { min = 3, parts = {
                { file = "echo_arch_g3", color = "seal", alpha = 0.18, add = true },
                { file = "echo_arch_p3" } } },
            -- Wechselsignal hinter dem Bogen, nur mit Option "Leuchten bei 3 Kopien"
            { min = 3, behind = true, optional = "echoFxFullGlow", parts = {
                { file = "echo_arch_glow", color = "target", alpha = 0.5, add = true } } },
        },
    },
    custom = {   -- eigene Grafik aus ForeverRotation/Custom/ (tools/echo_custom.py), nicht im Repo
        dir = CUSTOM, w = 400, h = 200, x = 0, y = 90, tintable = true,
        stages = {
            { min = 1, parts = {
                { file = "echo_custom_p1", alpha = 0.25 }, { file = "echo_custom_p2", alpha = 0.25 },
                { file = "echo_custom_p3", alpha = 0.25 },
                { file = "echo_custom_g1", color = "seal", alpha = 0.18, add = true },
                { file = "echo_custom_p1" } } },
            { min = 2, parts = {
                { file = "echo_custom_g2", color = "seal", alpha = 0.18, add = true },
                { file = "echo_custom_p2" } } },
            { min = 3, parts = {
                { file = "echo_custom_g3", color = "seal", alpha = 0.18, add = true },
                { file = "echo_custom_p3" } } },
            -- Wechselsignal hinter dem Bogen, nur mit Option "Leuchten bei 3 Kopien"
            { min = 3, behind = true, optional = "echoFxFullGlow", parts = {
                { file = "echo_custom_glow", color = "target", alpha = 0.5, add = true } } },
        },
    },
    arcs = {
        tw = 512, th = 256, w = 512, h = 256, x = 0, y = -10,
        base = "echo_edge", tintBase = true, fill = "echo_arcs", glow = "echo_glow",
        vertical = true, from = 218, to = 38,
    },
    blade = {
        tw = 256, th = 512, w = 120, h = 240, x = 160, y = 0,
        base = "echo_blade_base", fill = "echo_blade_fill", glow = "echo_blade_glow",
        vertical = true, from = 330, to = 70,
    },
}

-- Kopie-Auren von Unsealed Wrath je Siegel: Farbe der Füllung, Farbe des Leuchtens bei 3
-- (beim Twisten = Farbe des Siegels, auf das gewechselt wird)
local ORANGE, BLUE, GOLD = { 1.00, 0.17, 0.09 }, { 0.35, 0.75, 1.00 }, { 1.00, 0.85, 0.30 }   -- ORANGE: Rot-Orange (Command)
local ECHOES = {
    { id = 1311703, color = ORANGE,                  full = BLUE },   -- Echo of Command
    { id = 1311704, color = BLUE,                    full = ORANGE }, -- Echo of Righteousness
    { id = 1311705, color = { 0.70, 0.40, 1.00 },    full = GOLD },   -- Echo of Justice
    { id = 1311701, color = { 0.85, 0.10, 0.35 },    full = GOLD },   -- Echo of Fury (Karmin)
    { id = 1328198, color = { 0.45, 1.00, 0.55 },    full = GOLD },   -- Echo of Light
    { id = 1328206, color = { 0.30, 0.90, 0.90 },    full = GOLD },   -- Echo of Wisdom
}

local containers = {}   -- ["Stil|Farbe"] = { frame = AuraContainer, style = Stil, status = "...", failed = "..." }
local active             -- Schlüssel des Containers, der gerade läuft

-- Farbe der Anzeige (Option echoFxColor): "gold" = Originalfarben der Grafik + Schimmer in Siegelfarbe,
-- "seal" = alles in Siegelfarbe, "custom" = alles in eigener Farbe (echoFxCustom).
-- Wird beim Aufbau eines Containers festgelegt; ein Farbwechsel baut einen neuen Container.
local cur = { mode = "gold" }

local function colorSetting()
    local mode = ns:Opt("echoFxColor") or "gold"
    local c = ns:Opt("echoFxCustom")
    local custom = type(c) == "table" and { c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1 } or { 1, 0.85, 0.3 }
    local key = mode == "custom" and string.format("custom:%.2f,%.2f,%.2f", custom[1], custom[2], custom[3]) or mode
    if ns:Opt("echoFxFullGlow") then key = key .. "+glow" end
    return mode, custom, key
end

-- Farbe der Kopien eines Siegels
local function sealColor(e)
    return cur.mode == "custom" and cur.custom or e.color
end

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
    button:SetFrameStrata(STRATA)
    local sc = sealColor(e)
    local r, g, b = sc[1], sc[2], sc[3]
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

-- Stufen-Slot: Teile, die das Spiel erst ab `stage.min` Stapeln zeigt
local function initStage(button, e, st, container, stage)
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "CENTER")
    button:SetSize(st.w, st.h)
    button:SetFrameStrata(STRATA)
    -- Reihenfolge der Ebenen: Schein "dahinter" ganz unten, dann die Stufen der Reihe nach
    local base = container:GetFrameLevel()
    button:SetFrameLevel(stage.behind and base or base + (stage.min or 1))
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    for i, part in ipairs(stage.parts) do
        local t = bar:CreateTexture(nil, "ARTWORK", nil, math.min(7, i - 1))
        local file, c = part.file, nil
        if part.color == "seal" then
            c = sealColor(e)
        elseif part.color == "target" then
            c = e.full
        elseif cur.mode ~= "gold" and st.tintable then
            file, c = file .. "w", sealColor(e)      -- farblose Fassung, im Spiel eingefärbt
            -- Lichtkanten (hellste Stellen) in derselben Farbe addiert: Konturen leuchten kräftiger,
            -- ohne die Farbe auszuwaschen (weiße Kanten machten z. B. Rot rosa)
            local h = bar:CreateTexture(nil, "OVERLAY", nil, math.min(7, i - 1))
            h:SetTexture((st.dir or TEX) .. part.file .. "h")
            h:SetAllPoints(button)
            h:SetBlendMode("ADD")
            local w = 0.18   -- Kanten leicht aufgehellt (Abstufung "mittel")
            h:SetVertexColor(c[1] + (1 - c[1]) * w, c[2] + (1 - c[2]) * w, c[3] + (1 - c[3]) * w, 0.55 * (part.alpha or 1))
        end
        t:SetTexture((st.dir or TEX) .. file)
        t:SetAllPoints(button)
        if part.add then t:SetBlendMode("ADD") end
        if c then
            t:SetVertexColor(c[1], c[2], c[3], part.alpha or 1)
        else
            t:SetVertexColor(1, 1, 1, part.alpha or 1)
        end
    end
    button:SetApplicationBar(bar, { minApplications = stage.min, maxApplications = math.max(stage.min, 3) })
end

-- Slot "voll": Leuchten und volle Füllung in Zielfarbe, nur ab 3 Stapeln (entscheidet das Spiel)
local function initFull(button, e, st, container)
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("CENTER", container, "CENTER")
    button:SetSize(st.w, st.h)
    button:SetFrameStrata(STRATA)
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
    if st.wings then
        local wg = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        wg:SetTexture(TEX .. st.wings.file)
        wg:SetSize(st.wings.w, st.wings.h)
        wg:SetPoint("CENTER", button, "CENTER", 0, st.wings.y)
        wg:SetBlendMode("ADD")
        wg:SetVertexColor(e.full[1], e.full[2], e.full[3], 1)
    end
    button:SetApplicationBar(bar, { minApplications = 3, maxApplications = 3 })
end

local function build(key, styleKey, mode, custom)
    local st = STYLES[styleKey]
    local info = { status = {}, style = styleKey }
    containers[key] = info
    cur.mode, cur.custom = mode, custom
    -- In der Welt-Ebene (wie die Namensplaketten) und dort ganz unten: Lebensleisten über Gegnern
    -- liegen dann ÜBER der Anzeige statt von ihr verdeckt zu werden.
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, WorldFrame, "CustomAuraContainerTemplate")
    if not ok or not c then
        info.failed = "AuraContainer: " .. tostring(c)
        return
    end
    info.frame = c
    c:SetSize(st.w, st.h)
    c:SetPoint("CENTER", WorldFrame, "CENTER", st.x, st.y)
    -- unterste erlaubte Ebene, Stufen so niedrig wie möglich (Namensplaketten sollen darüber liegen)
    c:SetFrameStrata(STRATA)
    c:SetFrameLevel(0)
    c:EnableMouse(false)
    c:Hide()
    local okU, errU = pcall(c.SetUnit, c, "player")
    if not okU then info.failed = "SetUnit: " .. tostring(errU) return end
    pcall(c.SetEnabled, c, false)

    local n = 0
    local function addSlot(key, spellID, init, e, extra)
        local initErr
        local okA, err = pcall(c.AddAuraSlot, c, key, "HELPFUL", {
            candidateFilters = { includeSpellIDs = { [spellID] = true } },
            initializeFrame = function(button)
                local okI, errI = pcall(init, button, e, st, c, extra)
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
        if st.stages then
            for i, stage in ipairs(st.stages) do
                if not stage.optional or ns:Opt(stage.optional) then
                    addSlot("t" .. i .. "_" .. e.id, e.id, initStage, e, stage)
                end
            end
        else
            addSlot("s" .. e.id, e.id, initStacks, e)
            addSlot("f" .. e.id, e.id, initFull, e)
        end
    end
    table.insert(info.status, 1, n .. " Slots angelegt")
end

-- Gewünschter Stil oder nil (nur Vergeltung mit Option an); dazu der Container-Schlüssel (Stil|Farbe)
local function wantedStyle()
    if not (ns.rotation and ns.rotation.id == "PALADIN_RETRIBUTION") then return nil end
    local style = ns:Opt("echoFx")
    if style == true then style = "arcs" end      -- alte Einstellung (an/aus)
    if style == "sword" then style = "blade" end  -- alte Stile
    if style == "halo" or style == "runes" or style == "gems" then style = "arch" end
    if not STYLES[style] then return nil end
    local mode, custom, colorKey = colorSetting()
    return style, style .. "|" .. colorKey, mode, custom
end

local function setShown(styleKey, on)
    local info = containers[styleKey]
    if info and info.frame then
        pcall(info.frame.SetEnabled, info.frame, on)
        info.frame:SetShown(on)
    end
end

function Echo:Refresh()
    local style, want, mode, custom = wantedStyle()
    if want and not containers[want] then
        if InCombatLockdown() then want = active else build(want, style, mode, custom) end   -- erst nach dem Kampf
    end
    if want ~= active then
        if active then setShown(active, false) end
        active = want
        if active then setShown(active, true) end
    end
    local info = active and containers[active]
    if info and info.frame then
        -- Größe wie auf der Oberfläche: WorldFrame hat keine UI-Skalierung, also ausgleichen
        local scale = ns:Opt("echoFxScale") or 1
        local uiFactor = UIParent:GetEffectiveScale() / math.max(0.01, WorldFrame:GetEffectiveScale())
        local total = scale * uiFactor
        if math.abs(info.frame:GetScale() - total) > 0.001 then info.frame:SetScale(total) end
        local alpha = ns:Opt("echoFxAlpha") or 1
        if math.abs(info.frame:GetAlpha() - alpha) > 0.001 then info.frame:SetAlpha(alpha) end
        local st = STYLES[info.style]
        local y = (st.y + (ns:Opt("echoFxY") or 0)) / scale
        if info.y ~= y then
            info.y = y
            info.frame:ClearAllPoints()
            info.frame:SetPoint("CENTER", WorldFrame, "CENTER", st.x / scale, y)
        end
    end
end

-- Ebenen-Diagnose (für /frot state): wo liegt die Anzeige, wo die Namensplakette des Ziels?
local function frameInfo(f)
    if not f then return "-" end
    local okP, parent = pcall(f.GetParent, f)
    local pname = okP and parent and (parent.GetName and parent:GetName() or "?") or "nil"
    local okS, strata = pcall(f.GetFrameStrata, f)
    local okL, level = pcall(f.GetFrameLevel, f)
    return string.format("%s|%s|%s", tostring(pname), okS and tostring(strata) or "?", okL and tostring(level) or "?")
end

function Echo:LayerText()
    local info = active and containers[active]
    local mine = info and info.frame and frameInfo(info.frame) or "-"
    local slot = info and info.frame and info.frame.GetAuraSlotFrame and info.frame:GetAuraSlotFrame("t1_1311703")
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and ns.safe(C_NamePlate.GetNamePlateForUnit, "target")
    local uf = plate and (plate.UnitFrame or plate)
    local hb = uf and (uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar))
    local text = string.format("Anzeige %s\n  Slot %s\n  Plakette %s\n  UnitFrame %s\n  Leiste %s",
        mine, slot and frameInfo(slot) or "-", plate and frameInfo(plate) or "keine", uf and frameInfo(uf) or "-",
        hb and frameInfo(hb) or "-")
    -- auch in die gespeicherten Daten (nach /reload in der Datei lesbar)
    if ns.db then ns.db.global.layerDebug = date("%Y-%m-%d %H:%M:%S") .. " " .. text end
    return text
end

-- Zeile für /frot state
function Echo:StatusText()
    local style, key = wantedStyle()
    if not style then return "aus" end
    local info = containers[key]
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
