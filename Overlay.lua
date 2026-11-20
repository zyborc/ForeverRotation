-- ForeverRotation – Effekt am Charakter (wie Blizzards Proc-Bögen, z. B. Maelstrom Weapon).
-- Eine Rotation kann `overlay = function(s, demo)` liefern; Rückgabe (oder nil = aus):
--   count, max      gesammelte Stapel / Höchstzahl (Rauten unter dem Charakter)
--   atLeast         Zahl ist nur "mindestens count" (nächste Raute flackert)
--   estimated       Stapel nur geschätzt (Rauten etwas blasser)
--   r, g, b         Farbe der gesammelten Stapel
--   ready           jetzt handeln: Bögen und Symbol leuchten in der Zielfarbe
--   spell, tr, tg, tb   Zielzauber (Symbol in der Mitte) und seine Farbe
--   scale           Größe (Option)
-- Reine Anzeige, nichts Anklickbares, keine geschützten Funktionen.

local _, ns = ...

local Overlay = {}
ns.Overlay = Overlay

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Blizzards Proc-Bögen; falls der Client sie nicht hat, zeichnen wir eigene Leuchtsäulen.
local SAO_TEXTURES = {
    "Textures\\SpellActivationOverlays\\Art_of_War",
    "Textures\\SpellActivationOverlays\\Daybreak",
    "Textures\\SpellActivationOverlays\\Maelstrom_Weapon",
    "Textures\\SpellActivationOverlays\\Generic_Arc_01",
}
local MAX_PIPS = 5

local frame

local function setSAO(tex)
    for _, path in ipairs(SAO_TEXTURES) do
        local ok, res = pcall(tex.SetTexture, tex, path)
        if ok and res == true then return path end
    end
    return nil
end

local function pulse(target, from, to, dur)
    local ag = target:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetSmoothing("IN_OUT")
    return ag
end

local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -20)
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f:Hide()

    -- Bögen links/rechts vom Charakter
    f.arcs = CreateFrame("Frame", nil, f)
    f.arcs:SetAllPoints(f)
    local left = f.arcs:CreateTexture(nil, "ARTWORK")
    local right = f.arcs:CreateTexture(nil, "ARTWORK")
    local path = setSAO(left)
    if path then
        right:SetTexture(path)
        left:SetSize(128, 256); right:SetSize(128, 256)
        left:SetPoint("RIGHT", f, "CENTER", -95, 0)
        right:SetPoint("LEFT", f, "CENTER", 95, 0)
        right:SetTexCoord(1, 0, 0, 1)               -- gespiegelt
        left:SetBlendMode("ADD"); right:SetBlendMode("ADD")
    else
        -- Ersatz: weiche Leuchtsäulen, nach außen auslaufend
        for _, t in ipairs({ left, right }) do
            t:SetTexture(WHITE)
            t:SetSize(26, 230)
            t:SetBlendMode("ADD")
        end
        left:SetPoint("RIGHT", f, "CENTER", -110, 0)
        right:SetPoint("LEFT", f, "CENTER", 110, 0)
        if CreateColor then
            left:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1))
            right:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
        end
    end
    f.left, f.right, f.saoPath = left, right, path
    f.arcPulse = pulse(f.arcs, 0.55, 1, 0.35)

    -- Rauten unter dem Charakter: eine pro Stapel
    f.pips = {}
    for i = 1, MAX_PIPS do
        local p = CreateFrame("Frame", nil, f)
        p:SetSize(22, 22)
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetTexture(WHITE); p.bg:SetSize(17, 17); p.bg:SetPoint("CENTER")
        p.bg:SetRotation(math.pi / 4)
        p.bg:SetVertexColor(0, 0, 0, 0.75)
        p.glow = p:CreateTexture(nil, "BORDER")
        p.glow:SetTexture(WHITE); p.glow:SetSize(21, 21); p.glow:SetPoint("CENTER")
        p.glow:SetRotation(math.pi / 4)
        p.glow:SetBlendMode("ADD")
        p.fill = p:CreateTexture(nil, "ARTWORK")
        p.fill:SetTexture(WHITE); p.fill:SetSize(12, 12); p.fill:SetPoint("CENTER")
        p.fill:SetRotation(math.pi / 4)
        p.shine = p:CreateTexture(nil, "OVERLAY")
        p.shine:SetTexture(WHITE); p.shine:SetSize(4, 4); p.shine:SetPoint("CENTER", -2, 2)
        p.shine:SetRotation(math.pi / 4)
        p.shine:SetVertexColor(1, 1, 1, 0.8)
        p.flicker = pulse(p, 0.25, 1, 0.3)
        f.pips[i] = p
    end

    -- Zielzauber in der Mitte, über dem Kopf
    f.icon = CreateFrame("Frame", nil, f)
    f.icon:SetSize(44, 44)
    f.icon:SetPoint("BOTTOM", f, "CENTER", 0, 105)
    f.icon.ring = f.icon:CreateTexture(nil, "BACKGROUND")
    f.icon.ring:SetTexture(WHITE); f.icon.ring:SetPoint("TOPLEFT", -4, 4); f.icon.ring:SetPoint("BOTTOMRIGHT", 4, -4)
    f.icon.ring:SetBlendMode("ADD")
    f.icon.tex = f.icon:CreateTexture(nil, "ARTWORK")
    f.icon.tex:SetAllPoints()
    f.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon.pulse = pulse(f.icon, 0.5, 1, 0.3)
    f.icon:Hide()

    frame = f
end

local function hide()
    if frame and frame:IsShown() then
        frame.arcPulse:Stop()
        frame.icon.pulse:Stop()
        for _, p in ipairs(frame.pips) do p.flicker:Stop() end
        frame:Hide()
    end
end

function Overlay:Hide() hide() end

-- Name der genutzten Bogen-Grafik (für /frot state), nil = eigene Leuchtsäulen
function Overlay:Style()
    return frame and (frame.saoPath or "eigene") or nil
end

-- Aus der Anzeige (20x pro Sekunde). preview = Einstellungen offen: Vorführung zeigen.
function Overlay:Update(s, preview)
    local def = ns.rotation
    local d = s and def and def.overlay and def.overlay(s, preview)
    if not d then hide() return end
    if not frame then build() end
    local f = frame
    f:SetScale(d.scale or 1)

    -- Rauten
    local max = math.min(d.max or 3, MAX_PIPS)
    local width = max * 26
    local baseA = d.estimated and 0.6 or 1
    for i, p in ipairs(f.pips) do
        if i > max then
            p:Hide()
        else
            p:ClearAllPoints()
            p:SetPoint("CENTER", f, "CENTER", -width / 2 + 13 + (i - 1) * 26, -112)
            p:Show()
            local lit = i <= (d.count or 0)
            local maybe = d.atLeast and i == (d.count or 0) + 1
            local r, g, b = d.r or 1, d.g or 0.8, d.b or 0.2
            if d.ready then r, g, b = d.tr or r, d.tg or g, d.tb or b end
            if lit or maybe then
                p.fill:SetVertexColor(r, g, b, baseA)
                p.glow:SetVertexColor(r, g, b, (lit and 0.45 or 0.25) * baseA)
                p.shine:Show()
            else
                p.fill:SetVertexColor(0.15, 0.15, 0.15, 0.8)
                p.glow:SetVertexColor(0, 0, 0, 0)
                p.shine:Hide()
            end
            if maybe then
                if not p.flicker:IsPlaying() then p.flicker:Play() end
            else
                p.flicker:Stop()
                p:SetAlpha(1)
            end
        end
    end

    -- Bögen: werden mit jedem Stapel kräftiger, bei "jetzt" volle Farbe und pulsierend
    local fillPct = (d.count or 0) / math.max(1, max)
    local r, g, b = d.r or 1, d.g or 0.8, d.b or 0.2
    local a
    if d.ready then
        r, g, b, a = d.tr or r, d.tg or g, d.tb or b, 1
        if not f.arcPulse:IsPlaying() then f.arcPulse:Play() end
    else
        a = fillPct > 0 and (0.12 + 0.38 * fillPct) or 0
        f.arcPulse:Stop()
        f.arcs:SetAlpha(1)
    end
    f.left:SetVertexColor(r, g, b, a)
    f.right:SetVertexColor(r, g, b, a)

    -- Symbol des Zielzaubers
    if d.ready and d.spell then
        local sp = ns.spells and ns.spells[d.spell]
        local id = (sp and sp.id) or ns.SPELL_IDS[d.spell]
        local tex = (sp and sp.icon) or (id and ns.safe(C_Spell.GetSpellTexture, id))
        f.icon.tex:SetTexture(tex or 134400)
        f.icon.ring:SetVertexColor(d.tr or 1, d.tg or 1, d.tb or 1, 0.9)
        if not f.icon:IsShown() then f.icon:Show(); f.icon.pulse:Play() end
    elseif f.icon:IsShown() then
        f.icon.pulse:Stop()
        f.icon:Hide()
    end
    f:Show()
end
