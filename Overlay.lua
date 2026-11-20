-- ForeverRotation – Effekt am Charakter ("Sturmbögen", ähnlich Maelstrom Weapon).
-- Links und rechts vom Charakter je ein Bogen aus Segmenten. Ab dem ersten Stapel erscheinen
-- die Umrisse aller Segmente; pro Stapel füllt sich ein Segment (von unten nach oben) und blitzt
-- dabei einmal auf. Ist es Zeit zu handeln, sind alle Segmente in der Zielfarbe gefüllt.
--
-- Eine Rotation liefert `overlay = function(s, demo)`; Rückgabe (oder nil = aus):
--   count           gesammelte Stapel (0–3)
--   estimated       Stapel nur geschätzt (blasser)
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

local function pair(parent, f, layer, sub, file, blend)
    local list = {}
    for side = 1, 2 do
        local t = parent:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(TEX .. file)
        if blend then t:SetBlendMode(blend) end
        placeSide(t, f, side == 2)
        t:Hide()
        list[side] = t
    end
    return list
end

local function build()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -10)
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    f:Hide()

    f.segs = {}
    for i = 1, SEGMENTS do
        local seg = {}
        seg.edge = pair(f, f, "BACKGROUND", 0, "twist_edge" .. i)
        seg.glow = pair(f, f, "ARTWORK", 0, "twist_glow" .. i, "ADD")
        seg.fill = pair(f, f, "ARTWORK", 1, "twist_seg" .. i, "ADD")
        -- einmaliges Aufblitzen, wenn das Segment gefüllt wird
        seg.flashHolder = CreateFrame("Frame", nil, f)
        seg.flashHolder:SetAllPoints(f)
        seg.flashHolder:SetAlpha(0)
        seg.flash = pair(seg.flashHolder, f, "OVERLAY", 7, "twist_glow" .. i, "ADD")
        for side = 1, 2 do seg.flash[side]:Show() end
        local ag = seg.flashHolder:CreateAnimationGroup()
        local up = ag:CreateAnimation("Alpha"); up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.08); up:SetOrder(1)
        local down = ag:CreateAnimation("Alpha"); down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.5); down:SetOrder(2)
        ag:SetScript("OnFinished", function() seg.flashHolder:SetAlpha(0) end)
        seg.flashAnim = ag
        f.segs[i] = seg
    end
    f.lastCount, f.wasReady = 0, false
    frame = f
end

local function hide()
    if frame and frame:IsShown() then
        for _, seg in ipairs(frame.segs) do seg.flashAnim:Stop(); seg.flashHolder:SetAlpha(0) end
        frame.lastCount, frame.wasReady = 0, false
        frame:Hide()
    end
end

function Overlay:Hide() hide() end

local function paint(list, r, g, b, a)
    for side = 1, 2 do
        list[side]:SetVertexColor(r, g, b, a)
        list[side]:SetShown(a > 0)
    end
end

local function flash(seg, r, g, b)
    for side = 1, 2 do seg.flash[side]:SetVertexColor(r, g, b, 1) end
    seg.flashAnim:Stop()
    seg.flashAnim:Play()
end

-- Aus der Anzeige (20x pro Sekunde). demo = Einstellungen offen: Vorführung zeigen.
function Overlay:Update(s, demo)
    local def = ns.rotation
    local d = s and def and def.overlay and def.overlay(s, demo)
    if not d then hide() return end
    if not frame then build() end
    local f = frame
    f:SetScale(d.scale or 1)

    local count = math.max(0, math.min(d.count or 0, SEGMENTS))
    local ready = d.ready and true or false
    local r, g, b = d.r or 1, d.g or 0.6, d.b or 0.1
    if ready then r, g, b = d.tr or r, d.tg or g, d.tb or b end
    local base = d.estimated and 0.55 or 1
    local shown = ready or count > 0          -- Umrisse erst ab dem ersten Stapel

    for i, seg in ipairs(f.segs) do
        local filled = ready or i <= count
        paint(seg.edge, r, g, b, shown and 0.8 * base or 0)
        paint(seg.fill, r, g, b, filled and base or 0)
        paint(seg.glow, r, g, b, filled and (ready and 0.6 or 0.35) * base or 0)
        -- genau das neu gefüllte Segment blitzt einmal; beim Umschalten auf "jetzt" alle einmal
        if (ready and not f.wasReady) or (not ready and filled and i > f.lastCount) then
            flash(seg, r, g, b)
        end
    end
    f.lastCount = ready and SEGMENTS or count
    f.wasReady = ready
    f:Show()
end
