-- ForeverRotation – Effekt am Charakter ("Sturmbögen", ähnlich Maelstrom Weapon).
-- Links und rechts vom Charakter je ein Bogen aus Segmenten, die sich von unten nach oben
-- füllen – ein Segment pro Stapel, in der Farbe der Stapel. Ist es Zeit zu handeln, leuchten
-- alle Segmente in der Zielfarbe und pulsieren.
--
-- Eine Rotation liefert `overlay = function(s, demo)`; Rückgabe (oder nil = aus):
--   count, max      gesammelte Stapel / Segmente (max. 3)
--   atLeast         Zahl ist nur "mindestens count" (nächstes Segment flackert)
--   estimated       Stapel nur geschätzt (Segmente blasser)
--   r, g, b         Farbe der Stapel
--   ready, tr, tg, tb   jetzt handeln, in dieser Farbe
--   scale           Größe (Option)
-- Reine Anzeige: nichts Anklickbares, keine geschützten Funktionen.

local _, ns = ...

local Overlay = {}
ns.Overlay = Overlay

local TEX = "Interface\\AddOns\\ForeverRotation\\Textures\\"
local SEGMENTS = 3
local TEX_W, TEX_H = 128, 256
local CENTER_X, CENTER_Y = 200, 128   -- Kreismittelpunkt im Texturraum (= Charakter)

local frame

local function anim(region, from, to, dur, loop)
    local ag = region:CreateAnimationGroup()
    if loop then ag:SetLooping("BOUNCE") end
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetSmoothing("IN_OUT")
    return ag
end

-- Textur so setzen, dass der Kreismittelpunkt auf der Charaktermitte liegt
local function placeSide(tex, f, mirrored)
    tex:SetSize(TEX_W, TEX_H)
    if mirrored then
        tex:SetTexCoord(1, 0, 0, 1)
        tex:SetPoint("TOPLEFT", f, "CENTER", CENTER_X - TEX_W, CENTER_Y)
    else
        tex:SetPoint("TOPLEFT", f, "CENTER", -CENTER_X, CENTER_Y)
    end
end

local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -10)
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f:Hide()

    -- Ebenen: Schienen (immer schwach sichtbar) < Schein (pulsiert) < Segmente
    f.glowLayer = CreateFrame("Frame", nil, f)
    f.glowLayer:SetAllPoints(f)
    f.glowPulse = anim(f.glowLayer, 0.45, 1, 0.35, true)
    f.coreLayer = CreateFrame("Frame", nil, f)
    f.coreLayer:SetAllPoints(f)
    f.corePulse = anim(f.coreLayer, 0.75, 1, 0.35, true)

    f.segs = {}
    for i = 1, SEGMENTS do
        local seg = { track = {}, glow = {}, core = {} }
        for side = 1, 2 do
            local mirrored = side == 2
            local track = f:CreateTexture(nil, "BACKGROUND")
            track:SetTexture(TEX .. "twist_seg" .. i)
            placeSide(track, f, mirrored)
            track:SetVertexColor(1, 1, 1, 0.07)
            seg.track[side] = track

            local glow = f.glowLayer:CreateTexture(nil, "ARTWORK")
            glow:SetTexture(TEX .. "twist_glow" .. i)
            glow:SetBlendMode("ADD")
            placeSide(glow, f, mirrored)
            seg.glow[side] = glow

            local core = f.coreLayer:CreateTexture(nil, "OVERLAY")
            core:SetTexture(TEX .. "twist_seg" .. i)
            core:SetBlendMode("ADD")
            placeSide(core, f, mirrored)
            seg.core[side] = core
        end
        -- Aufblitzen, wenn das Segment neu dazukommt
        seg.flashHolder = CreateFrame("Frame", nil, f.coreLayer)
        seg.flashHolder:SetAllPoints(f)
        seg.flash = {}
        for side = 1, 2 do
            local fl = seg.flashHolder:CreateTexture(nil, "OVERLAY", nil, 7)
            fl:SetTexture(TEX .. "twist_glow" .. i)
            fl:SetBlendMode("ADD")
            placeSide(fl, f, side == 2)
            seg.flash[side] = fl
        end
        seg.flashHolder:SetAlpha(0)
        local ag = seg.flashHolder:CreateAnimationGroup()
        local up = ag:CreateAnimation("Alpha"); up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.08); up:SetOrder(1)
        local down = ag:CreateAnimation("Alpha"); down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.45); down:SetOrder(2)
        seg.flashAnim = ag
        seg.flicker = anim(seg.flashHolder, 0, 0.5, 0.3, true)
        f.segs[i] = seg
    end
    f.lastCount = 0
    frame = f
end

local function hide()
    if frame and frame:IsShown() then
        frame.glowPulse:Stop(); frame.corePulse:Stop()
        for _, seg in ipairs(frame.segs) do seg.flicker:Stop(); seg.flashAnim:Stop(); seg.flashHolder:SetAlpha(0) end
        frame.lastCount = 0
        frame:Hide()
    end
end

function Overlay:Hide() hide() end

local function setSide(list, r, g, b, a)
    for side = 1, 2 do
        list[side]:SetVertexColor(r, g, b, a)
        list[side]:SetShown(a > 0)
    end
end

-- Aus der Anzeige (20x pro Sekunde). demo = Einstellungen offen: Vorführung zeigen.
function Overlay:Update(s, demo)
    local def = ns.rotation
    local d = s and def and def.overlay and def.overlay(s, demo)
    if not d then hide() return end
    if not frame then build() end
    local f = frame
    f:SetScale(d.scale or 1)

    local count = math.min(d.count or 0, SEGMENTS)
    local ready = d.ready
    local r, g, b = d.r or 1, d.g or 0.6, d.b or 0.1
    if ready then r, g, b = d.tr or r, d.tg or g, d.tb or b end
    local base = d.estimated and 0.55 or 1

    for i, seg in ipairs(f.segs) do
        local lit = ready or i <= count
        local maybe = not ready and d.atLeast and i == count + 1
        if lit then
            setSide(seg.core, r, g, b, base)
            setSide(seg.glow, r, g, b, (ready and 0.9 or 0.35) * base)
        else
            setSide(seg.core, r, g, b, 0)
            setSide(seg.glow, r, g, b, 0)
        end
        for side = 1, 2 do seg.flash[side]:SetVertexColor(r, g, b, 1) end
        -- neues Segment: kurz aufblitzen
        if lit and not ready and i > f.lastCount and i <= count then
            seg.flicker:Stop()
            seg.flashAnim:Stop(); seg.flashAnim:Play()
        elseif maybe then
            if not seg.flicker:IsPlaying() then seg.flashAnim:Stop(); seg.flicker:Play() end
        elseif seg.flicker:IsPlaying() then
            seg.flicker:Stop(); seg.flashHolder:SetAlpha(0)
        end
    end
    -- Wechsel fällig: alles pulsiert in der Zielfarbe (beim Umschalten einmal aufblitzen)
    if ready then
        if not f.glowPulse:IsPlaying() then
            for _, seg in ipairs(f.segs) do seg.flashAnim:Stop(); seg.flashAnim:Play() end
            f.glowPulse:Play(); f.corePulse:Play()
        end
    elseif f.glowPulse:IsPlaying() then
        f.glowPulse:Stop(); f.corePulse:Stop()
        f.glowLayer:SetAlpha(1); f.coreLayer:SetAlpha(1)
    end
    f.lastCount = ready and SEGMENTS or count
    f:Show()
end
