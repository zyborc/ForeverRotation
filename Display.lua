-- ForeverRotation – Anzeige.
--   * großes Icon (jetzt) + kleines Icon (danach)
--   * Timeline: die vorhergesagten nächsten Zauber laufen auf die "Jetzt"-Linie zu
--   * runde oder eckige Icons, Rahmen in Klassenfarbe, Cooldown-Spirale,
--     Leuchtring wenn "jetzt drücken", Pop-Animation, Overlays für Reichweite/Mana

local _, ns = ...

local Display = {}
ns.Display = Display
local L = ns.L

local UPDATE_INTERVAL = 0.05
local MAIN_SIZE, NEXT_SIZE, TL_ICON = 56, 38, 26
local TL_WIDTH, TL_HEIGHT = 300, 34
local TL_MAX = 8
local BORDER = 2
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function classColor()
    local _, class = UnitClass("player")
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c then return c.r, c.g, c.b end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

---------------------------------------------------------------------------
-- Form (rund/eckig) über Maskentexturen
---------------------------------------------------------------------------

local function setMasked(owner, tex, round)
    if not tex then return end
    if round then
        if not tex.roundMask then
            local m = owner:CreateMaskTexture()
            m:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(tex)
            tex.roundMask = m
        end
        if not tex.isMasked then
            tex:AddMaskTexture(tex.roundMask)
            tex.isMasked = true
        end
    elseif tex.isMasked then
        tex:RemoveMaskTexture(tex.roundMask)
        tex.isMasked = false
    end
end

local function applyShape(b, round)
    for _, tex in ipairs({ b.shadow, b.glowTex, b.border, b.icon, b.tint }) do
        setMasked(b, tex, round)
    end
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- Tastenplakette: bei runden Icons unten innen (die Ecken sind abgeschnitten),
    -- bei eckigen oben rechts, bei Timeline-Icons darunter.
    b.key:ClearAllPoints()
    if b.keyBelow then
        b.key:SetPoint("TOP", b, "BOTTOM", 0, -2)
    elseif round then
        b.key:SetPoint("BOTTOM", b, "BOTTOM", 0, math.max(2, math.floor(b.size * 0.06)))
    else
        b.key:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
    end
    if round then
        b.cd:SetSwipeTexture(ROUND_MASK)
        if b.cd.SetUseCircularEdge then b.cd:SetUseCircularEdge(true) end
    else
        b.cd:SetSwipeTexture(WHITE)
        if b.cd.SetUseCircularEdge then b.cd:SetUseCircularEdge(false) end
    end
    b.cd:SetSwipeColor(0, 0, 0, 0.65)
    b.round = round
end

---------------------------------------------------------------------------
-- Ein Icon mit allen Effekten
---------------------------------------------------------------------------

local function createIcon(parent, size, opts)
    opts = opts or {}
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    b.size = size
    b.keyBelow = opts.keyBelow

    b.shadow = b:CreateTexture(nil, "BACKGROUND", nil, -3)
    b.shadow:SetPoint("TOPLEFT", -BORDER - 3, BORDER + 3)
    b.shadow:SetPoint("BOTTOMRIGHT", BORDER + 3, -BORDER - 3)
    b.shadow:SetColorTexture(0, 0, 0, 0.4)

    if opts.glow then
        local pad = math.floor(size * 0.16)
        b.glowTex = b:CreateTexture(nil, "BACKGROUND", nil, -2)
        b.glowTex:SetPoint("TOPLEFT", -pad, pad)
        b.glowTex:SetPoint("BOTTOMRIGHT", pad, -pad)
        b.glowTex:SetColorTexture(1, 0.78, 0.25, 1)
        b.glowTex:SetBlendMode("ADD")
        b.glowTex:SetAlpha(0)

        b.glowAnim = b.glowTex:CreateAnimationGroup()
        b.glowAnim:SetLooping("BOUNCE")
        local a = b.glowAnim:CreateAnimation("Alpha")
        a:SetFromAlpha(0.15)
        a:SetToAlpha(0.85)
        a:SetDuration(0.5)
        a:SetSmoothing("IN_OUT")
    end

    b.border = b:CreateTexture(nil, "BACKGROUND", nil, 0)
    b.border:SetPoint("TOPLEFT", -BORDER, BORDER)
    b.border:SetPoint("BOTTOMRIGHT", BORDER, -BORDER)
    b.border:SetColorTexture(0, 0, 0, 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()

    b.tint = b:CreateTexture(nil, "ARTWORK", nil, 2)
    b.tint:SetAllPoints()
    b.tint:Hide()

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetDrawEdge(false)
    b.cd:SetDrawBling(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end

    b.textLayer = CreateFrame("Frame", nil, b)
    b.textLayer:SetAllPoints()
    b.textLayer:SetFrameLevel(b.cd:GetFrameLevel() + 2)

    b.timer = b.textLayer:CreateFontString(nil, "OVERLAY")
    b.timer:SetFont(FONT, math.max(10, math.floor(size * 0.36)), "THICKOUTLINE")
    b.timer:SetPoint("CENTER", 0, 0)

    b.key = b.textLayer:CreateFontString(nil, "OVERLAY")
    b.key:SetFont(FONT, math.max(8, math.floor(size * 0.22)), "OUTLINE")
    b.key:SetTextColor(1, 1, 1)
    -- dunkle Plakette hinter der Taste, damit sie auf hellen Icons lesbar bleibt
    b.keyBg = b.textLayer:CreateTexture(nil, "ARTWORK")
    b.keyBg:SetColorTexture(0, 0, 0, 0.55)
    b.keyBg:SetPoint("TOPLEFT", b.key, "TOPLEFT", -3, 1)
    b.keyBg:SetPoint("BOTTOMRIGHT", b.key, "BOTTOMRIGHT", 3, -1)
    b.keyBg:Hide()

    b.pop = b:CreateAnimationGroup()
    local scale = b.pop:CreateAnimation("Scale")
    if scale.SetScaleFrom then
        scale:SetScaleFrom(1.18, 1.18)
        scale:SetScaleTo(1, 1)
    else
        scale:SetScale(0.85, 0.85)
    end
    scale:SetDuration(0.14)
    scale:SetSmoothing("OUT")
    local fade = b.pop:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.4)
    fade:SetToAlpha(1)
    fade:SetDuration(0.14)

    applyShape(b, true)
    return b
end

-- Taste setzen; Plakette nur mit Text zeigen
local function setKey(b, text)
    b.key:SetText(text or "")
    b.keyBg:SetShown(text ~= nil and text ~= "")
end

---------------------------------------------------------------------------
-- Timeline
---------------------------------------------------------------------------

local function createTimeline(parent)
    local tl = CreateFrame("Frame", nil, parent)
    tl:SetSize(TL_WIDTH, TL_HEIGHT)

    tl.bg = tl:CreateTexture(nil, "BACKGROUND")
    tl.bg:SetAllPoints()
    tl.bg:SetColorTexture(0, 0, 0, 0.45)

    tl.edgeTop = tl:CreateTexture(nil, "BORDER")
    tl.edgeTop:SetPoint("TOPLEFT"); tl.edgeTop:SetPoint("TOPRIGHT"); tl.edgeTop:SetHeight(1)
    tl.edgeTop:SetColorTexture(1, 1, 1, 0.08)
    tl.edgeBottom = tl:CreateTexture(nil, "BORDER")
    tl.edgeBottom:SetPoint("BOTTOMLEFT"); tl.edgeBottom:SetPoint("BOTTOMRIGHT"); tl.edgeBottom:SetHeight(1)
    tl.edgeBottom:SetColorTexture(1, 1, 1, 0.08)

    -- weicher Übergang am linken Rand: in der Zeile gleiten die Zauber ins große Icon
    tl.fade = tl:CreateTexture(nil, "BORDER")
    tl.fade:SetPoint("TOPLEFT")
    tl.fade:SetPoint("BOTTOMLEFT")
    tl.fade:SetWidth(TL_ICON)
    tl.fade:SetTexture(WHITE)
    local okGrad = CreateColor and pcall(tl.fade.SetGradient, tl.fade, "HORIZONTAL",
        CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
    if not okGrad and tl.fade.SetGradientAlpha then
        okGrad = pcall(tl.fade.SetGradientAlpha, tl.fade, "HORIZONTAL", 0, 0, 0, 0.55, 0, 0, 0, 0)
    end
    if not okGrad then tl.fade:Hide() end

    -- "Jetzt"-Linie links (Klassenfarbe)
    tl.nowLine = tl:CreateTexture(nil, "OVERLAY")
    tl.nowLine:SetPoint("TOPLEFT", TL_ICON / 2 - 1, 3)
    tl.nowLine:SetPoint("BOTTOMLEFT", TL_ICON / 2 - 1, -3)
    tl.nowLine:SetWidth(2)

    -- Sekunden-Striche
    tl.ticks = {}
    for i = 1, 12 do
        local t = tl:CreateTexture(nil, "BORDER")
        t:SetWidth(1)
        t:SetColorTexture(1, 1, 1, 0.15)
        tl.ticks[i] = t
        local label = tl:CreateFontString(nil, "OVERLAY")
        label:SetFont(FONT, 8, "OUTLINE")
        label:SetTextColor(1, 1, 1, 0.35)
        t.label = label
    end

    tl.icons = {}
    for i = 1, TL_MAX do
        local b = createIcon(tl, TL_ICON, { keyBelow = false })
        b:Hide()
        tl.icons[i] = b
    end
    return tl
end

local function layoutTicks(tl, horizon)
    local usable = TL_WIDTH - TL_ICON
    -- bis 10 s jede Sekunde ein Strich, darüber alle 2 s, über 20 s alle 5 s
    local step = horizon > 20 and 5 or (horizon > 10 and 2 or 1)
    for i, t in ipairs(tl.ticks) do
        local sec = i * step
        if sec < horizon then
            local x = TL_ICON / 2 + usable * (sec / horizon)
            t:ClearAllPoints()
            t:SetPoint("TOP", tl, "TOPLEFT", x, -4)
            t:SetPoint("BOTTOM", tl, "BOTTOMLEFT", x, 4)
            t.label:ClearAllPoints()
            t.label:SetPoint("BOTTOM", tl, "BOTTOMLEFT", x, 1)
            t.label:SetText(sec)
            t:Show(); t.label:Show()
        else
            t:Hide(); t.label:Hide()
        end
    end
    tl.horizon = horizon
end

---------------------------------------------------------------------------
-- Rahmenfenster
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Proc-Hinweis: Text schwebt über dem großen Icon nach oben, Icon blitzt auf.
-- (Die Schadenszahlen selbst zeichnet das Spiel – die kann kein Addon einfärben.)
---------------------------------------------------------------------------

local function createProcAlert(f)
    local a = CreateFrame("Frame", nil, f)
    a:SetSize(220, 34)
    a:SetPoint("BOTTOM", f.main, "TOP", 0, 10)
    a:SetFrameLevel(f.main:GetFrameLevel() + 20)
    a.text = a:CreateFontString(nil, "OVERLAY")
    a.text:SetFont(FONT, 20, "THICKOUTLINE")
    a.text:SetPoint("CENTER", 14, 0)
    a.icon = a:CreateTexture(nil, "ARTWORK")
    a.icon:SetSize(26, 26)
    a.icon:SetPoint("RIGHT", a.text, "LEFT", -6, 0)
    setMasked(a, a.icon, true)
    a:Hide()

    local ag = a:CreateAnimationGroup()
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.08); fadeIn:SetOrder(1)
    local grow = ag:CreateAnimation("Scale")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(1.6, 1.6); grow:SetScaleTo(1, 1)
    else
        grow:SetScale(0.625, 0.625)
    end
    grow:SetDuration(0.16); grow:SetOrder(1)
    local rise = ag:CreateAnimation("Translation")
    rise:SetOffset(0, 26); rise:SetDuration(1.2); rise:SetOrder(2)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetStartDelay(0.55); fadeOut:SetDuration(0.65); fadeOut:SetOrder(2)
    ag:SetScript("OnFinished", function() a:Hide() end)
    a.anim = ag

    -- Aufblitzen des großen Icons
    local flash = f.main.textLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints(f.main.icon)
    flash:SetTexture(WHITE)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    local fg = flash:CreateAnimationGroup()
    local fa = fg:CreateAnimation("Alpha")
    fa:SetFromAlpha(0.85); fa:SetToAlpha(0); fa:SetDuration(0.4)
    fg:SetScript("OnFinished", function() flash:SetAlpha(0) end)
    flash.anim = fg
    a.flash = flash

    a.count, a.last = 0, 0
    return a
end

-- Kurzinfo unter der Anzeige: unter der Timeline, wenn die darunter liegt, sonst unter dem Icon.
local function anchorToast(f)
    local t = f.toast
    if not t then return end
    t:ClearAllPoints()
    if ns.db.global.timeline and ns.db.global.timelinePos == "below" then
        t:SetPoint("TOPLEFT", f.timeline, "BOTTOMLEFT", 0, -6)
    else
        t:SetPoint("TOPLEFT", f.main, "BOTTOMLEFT", -BORDER, -24)
    end
end

-- Kurzinfo unter der Anzeige (z. B. Coach-Ergebnis nach dem Kampf), blendet nach 6 s aus.
function Display:ShowToast(msg, r, g, b)
    local f = self.frame
    if not f then return end
    if not f.toast then
        local t = CreateFrame("Frame", nil, f)
        t:SetSize(300, 18)
        f.toast = t
        anchorToast(f)
        t.text = t:CreateFontString(nil, "OVERLAY")
        t.text:SetFont(FONT, 13, "OUTLINE")
        t.text:SetPoint("LEFT")
        t.hint = t:CreateFontString(nil, "OVERLAY")
        t.hint:SetFont(FONT, 10, "OUTLINE")
        t.hint:SetPoint("LEFT", t.text, "RIGHT", 8, 0)
        t.hint:SetTextColor(0.7, 0.7, 0.7)
        local ag = t:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.3); fadeIn:SetOrder(1)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetStartDelay(5.5); fadeOut:SetDuration(0.8); fadeOut:SetOrder(2)
        ag:SetScript("OnFinished", function() t:Hide() end)
        t.anim = ag
    end
    local t = f.toast
    t.text:SetText(msg)
    t.text:SetTextColor(r or 1, g or 1, b or 1)
    t.hint:SetText(L["Details: Minimap-Symbol mit Shift-Klick"])
    t.anim:Stop()
    t:Show()
    t.anim:Play()
end

function Display:ShowProc(label, icon, color)
    local f = self.frame
    if not f or not f:IsShown() then return end
    f.proc = f.proc or createProcAlert(f)
    local a = f.proc
    local now = GetTime()
    -- mehrere Procs kurz hintereinander (Unsealed Wrath löst bis zu 3 aus): "x2", "x3"
    a.count = (now - a.last < 0.6) and (a.count + 1) or 1
    a.last = now
    local r, g, b = 1, 0.82, 0.2
    if color then r, g, b = color[1], color[2], color[3] end
    a.text:SetText(a.count > 1 and (label .. "  x" .. a.count) or label)
    a.text:SetTextColor(r, g, b)
    a.icon:SetTexture(icon or 134400)
    a.icon:SetShown(icon ~= nil)
    a.anim:Stop()
    a:Show()
    a.anim:Play()

    local flash = a.flash
    setMasked(f.main.textLayer, flash, f.main.round)
    flash:SetVertexColor(r, g, b)
    flash.anim:Stop()
    flash:SetAlpha(0.85)
    flash.anim:Play()
end

---------------------------------------------------------------------------
-- Masque (optional): Icons im Stil des gewählten Masque-Skins. Nur wenn Masque
-- installiert ist; dann eckig, ohne eigenen Rahmen und Schatten.
---------------------------------------------------------------------------

function Display:MasqueActive()
    return ns.db.global.masque and LibStub and LibStub("Masque", true) ~= nil
end

function Display:ApplyMasque()
    local f = self.frame
    if not self:MasqueActive() then
        if self.msq and self.msq.Delete then pcall(self.msq.Delete, self.msq) end
        self.msq = nil
        return
    end
    if not self.msq then
        local Masque = LibStub("Masque", true)
        local ok, group = pcall(Masque.Group, Masque, "ForeverRotation")
        if not ok or not group then return end
        self.msq = group
    end
    local list = { f.main, f.next }
    for _, b in ipairs(f.timeline.icons) do list[#list + 1] = b end
    for _, b in ipairs(list) do
        pcall(self.msq.AddButton, self.msq, b, { Icon = b.icon, Cooldown = b.cd, Normal = false,
            Pushed = false, Highlight = false, Border = false })
    end
    if self.msq.ReSkin then pcall(self.msq.ReSkin, self.msq) end
end

function Display:Init()
    if self.frame then
        self:ApplySettings()
        return
    end
    local f = CreateFrame("Frame", "ForeverRotationFrame", UIParent)
    f:SetSize(MAIN_SIZE + NEXT_SIZE + 12, MAIN_SIZE)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        ns.db.global.pos = { point, relPoint, x, y }
    end)
    -- entsperrt: Rechtsklick sperrt die Anzeige wieder
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not ns.db.global.locked then
            ns.db.global.locked = true
            Display:ApplySettings()
            if ns.Config and ns.Config.Refresh then ns.Config:Refresh() end
            print(ns.PREFIX .. L["Anzeige fixiert."])
        end
    end)

    f.main = createIcon(f, MAIN_SIZE, { glow = true })
    f.main:SetPoint("LEFT")

    f.next = createIcon(f, NEXT_SIZE)
    f.next:SetPoint("BOTTOMLEFT", f.main, "BOTTOMRIGHT", 14, 0)

    f.arrow = f:CreateFontString(nil, "OVERLAY")
    f.arrow:SetFont(FONT, 14, "OUTLINE")
    f.arrow:SetPoint("RIGHT", f.next, "LEFT", -2, 0)
    f.arrow:SetText(">")
    f.arrow:SetTextColor(1, 1, 1, 0.7)

    f.reason = f:CreateFontString(nil, "OVERLAY")
    f.reason:SetFont(FONT, 11, "OUTLINE")
    f.reason:SetPoint("TOPLEFT", f.main, "BOTTOMLEFT", -BORDER, -7)
    -- dunkler Streifen hinter der Begründung (lesbar auch vor hellem Boden)
    f.reasonBg = f:CreateTexture(nil, "BACKGROUND", nil, -4)
    f.reasonBg:SetColorTexture(0, 0, 0, 0.45)
    f.reasonBg:SetPoint("TOPLEFT", f.reason, "TOPLEFT", -4, 2)
    f.reasonBg:SetPoint("BOTTOMRIGHT", f.reason, "BOTTOMRIGHT", 4, -2)
    f.reasonBg:Hide()

    f.timeline = createTimeline(f)

    f.handle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.handle:SetPoint("BOTTOMLEFT", f.main, "TOPLEFT", 0, 8)

    -- Erinnerungen vor dem Pull (Essen, Waffenöl) über dem großen Icon
    f.remind = f:CreateFontString(nil, "OVERLAY")
    f.remind:SetFont(FONT, 12, "OUTLINE")
    f.remind:SetPoint("BOTTOMLEFT", f.main, "TOPLEFT", -BORDER, 8)
    f.remind:SetJustifyH("LEFT")
    f.remind:SetTextColor(1, 0.85, 0.4)
    f.handle:SetText(L["ForeverRotation – ziehen · Rechtsklick sperrt"])

    f.unlockBg = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    f.unlockBg:SetColorTexture(0.1, 0.8, 0.2, 0.25)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        Display:Update()
    end)

    self.frame = f
    self:ApplySettings()
end

function Display:ApplySettings()
    local f = self.frame
    if not f then return end
    local g = ns.db.global
    f:ClearAllPoints()
    if g.pos then
        f:SetPoint(g.pos[1], UIParent, g.pos[2], g.pos[3], g.pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
    self.inInstance = ns:InInstance()
    f:SetScale((g.scale or 1) * (self.inInstance and (g.instanceScale or 1) or 1))
    f:EnableMouse(not g.locked)
    f.handle:SetShown(not g.locked)

    -- Timeline: in der Zeile rechts neben dem großen Icon (Zauber gleiten hinein)
    -- oder darunter (dann mit Jetzt-Linie und zusätzlichem "danach"-Icon).
    local inRow = g.timeline and g.timelinePos ~= "below"
    f.timeline:ClearAllPoints()
    if inRow then
        f.timeline:SetPoint("LEFT", f.main, "RIGHT", BORDER + 4, 0)
        f:SetSize(MAIN_SIZE + BORDER + 4 + TL_WIDTH, MAIN_SIZE)
    else
        f.timeline:SetPoint("TOPLEFT", f.main, "BOTTOMLEFT", -BORDER, -24)
        f:SetSize(MAIN_SIZE + NEXT_SIZE + 14, MAIN_SIZE)
    end
    f.timeline.nowLine:SetShown(not inRow)
    f.timeline.fade:SetShown(inRow)
    self.inRow = inRow
    anchorToast(f)

    -- grüner Greifbereich deckt Icons und (falls an) Timeline ab
    f.unlockBg:ClearAllPoints()
    f.unlockBg:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 26)
    if g.timeline and not inRow then
        f.unlockBg:SetPoint("BOTTOMRIGHT", f.timeline, "BOTTOMRIGHT", 10, -8)
    else
        f.unlockBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 10, -24)
    end
    f.unlockBg:SetShown(not g.locked)

    local masque = self:MasqueActive()
    local round = g.shape ~= "square" and not masque
    applyShape(f.main, round)
    applyShape(f.next, round)
    for _, b in ipairs(f.timeline.icons) do applyShape(b, round) end
    for _, b in ipairs({ f.main, f.next, unpack(f.timeline.icons) }) do
        b.border:SetShown(not masque)
        b.shadow:SetShown(not masque)
    end
    self:ApplyMasque()

    local r, gr, bl = 0, 0, 0
    if g.classBorder then r, gr, bl = classColor() end
    f.main.border:SetColorTexture(r, gr, bl, 1)
    f.next.border:SetColorTexture(r * 0.7, gr * 0.7, bl * 0.7, 1)
    for _, b in ipairs(f.timeline.icons) do b.border:SetColorTexture(r * 0.6, gr * 0.6, bl * 0.6, 1) end
    f.reason:SetTextColor(g.classBorder and r or 1, g.classBorder and gr or 1, g.classBorder and bl or 1)

    local cr, cg, cb = classColor()
    f.timeline.nowLine:SetColorTexture(cr, cg, cb, 0.9)
    layoutTicks(f.timeline, g.timelineSeconds or 6)

    self:Update()
end

---------------------------------------------------------------------------
-- Aktualisierung
---------------------------------------------------------------------------

local function setGlow(b, on)
    if not b.glowAnim then return end
    if on then
        if not b.glowAnim:IsPlaying() then b.glowAnim:Play() end
    else
        b.glowAnim:Stop()
        b.glowTex:SetAlpha(0)
    end
end

local function setSwipe(b, name)
    if not ns.db.global.swipe or not name then
        b.cd:Clear()
        b.swipeKey = nil
        return
    end
    local start, duration = ns:SwipeInfo(name)
    local key = start and (start .. ":" .. duration) or nil
    if key ~= b.swipeKey then
        b.swipeKey = key
        if start then b.cd:SetCooldown(start, duration) else b.cd:Clear() end
    end
end

local function setTint(b, noMana, inRange)
    if noMana then
        b.tint:SetColorTexture(0.2, 0.35, 1, 0.45)
        b.tint:Show()
    elseif inRange == false then
        b.tint:SetColorTexture(1, 0.1, 0.1, 0.45)
        b.tint:Show()
    else
        b.tint:Hide()
    end
end

local function setSpell(b, name)
    if b.spell ~= name then
        b.spell = name
        local sp = ns.spells[name]
        b.icon:SetTexture(sp and sp.icon or 134400)
        if b:IsShown() then b.pop:Play() end
    end
end

local function setIcon(b, rule, ready, noMana, s, isMain)
    if not rule then
        b:Hide()
        b.spell = nil
        setGlow(b, false)
        return
    end
    local name = rule.spell
    setSpell(b, name)
    setKey(b, ns:KeyFor(name))

    local waiting = ready and ready > 0.1
    b.timer:SetText(waiting and string.format(ready < 10 and "%.1f" or "%d", ready) or "")
    b.timer:SetTextColor(1, 1, 1)
    b.icon:SetDesaturated(waiting and true or false)
    setSwipe(b, name)

    local inRange = s.inRange(name)
    setTint(b, noMana, inRange)
    setGlow(b, isMain and ns.db.global.glow and not waiting and not noMana and inRange ~= false)
    b:Show()
end

-- Leerlauf im großen Icon: nichts ist jetzt dran, Autoangriff läuft.
local AUTO_ATTACK = 6603
local function showIdle(b)
    if b.spell ~= "__idle" then
        b.spell = "__idle"
        local tex = ns.safe(C_Spell.GetSpellTexture, AUTO_ATTACK)
        b.icon:SetTexture(tex or 135274)
    end
    b.icon:SetDesaturated(true)
    b.tint:Hide()
    setSwipe(b, nil)
    b.timer:SetText("")
    setKey(b, nil)
    setGlow(b, false)
    b:Show()
end

-- Leerlauf "leer": dunkler Kreis mit Countdown bis zum nächsten Zauber.
local function showEmpty(b, seconds)
    if b.spell ~= "__empty" then
        b.spell = "__empty"
        b.icon:SetColorTexture(0.04, 0.04, 0.05, 0.92)
    end
    b.icon:SetDesaturated(false)
    b.tint:Hide()
    setSwipe(b, nil)
    b.timer:SetText(seconds and string.format(seconds < 10 and "%.1f" or "%d", seconds) or "")
    b.timer:SetTextColor(0.75, 0.75, 0.75)
    setKey(b, nil)
    setGlow(b, false)
    b:Show()
end

local function showPreview(b, text)
    if b.spell ~= "__preview" then
        b.spell = "__preview"
        b.icon:SetTexture(134400) -- Fragezeichen
    end
    b.icon:SetDesaturated(false)
    b.tint:Hide()
    setSwipe(b, nil)
    b.timer:SetText("")
    setKey(b, text)
    setGlow(b, false)
    b:Show()
end

-- skipFirst: in der Zeile ist der erste vorhergesagte Zauber das große Icon selbst.
local function updateTimeline(tl, s, g, skipFirst)
    local horizon = g.timelineSeconds or 6
    if tl.horizon ~= horizon then layoutTicks(tl, horizon) end
    local preds = ns:Predict(TL_MAX + 1, horizon, s)
    local usable = TL_WIDTH - TL_ICON
    local lastX = -math.huge
    local shown = 0
    for i = skipFirst and 2 or 1, #preds do
        local p = preds[i]
        if shown >= TL_MAX then break end
        local x = math.max(0, (p.at - s.now) / horizon * usable)
        x = math.max(x, lastX + TL_ICON + 2)   -- gleichzeitige Zauber nebeneinander
        if x > usable then break end
        lastX = x
        shown = shown + 1
        local b = tl.icons[shown]
        b:ClearAllPoints()
        b:SetPoint("LEFT", tl, "LEFT", x, 0)
        setSpell(b, p.rule.spell)
        setKey(b, ns:KeyFor(p.rule.spell))
        b.timer:SetText("")
        b.icon:SetDesaturated(false)
        setTint(b, p.noMana, nil)
        -- weiter entfernte Zauber etwas blasser
        b:SetAlpha(1 - 0.4 * (x / usable))
        b:Show()
    end
    for i = shown + 1, TL_MAX do
        tl.icons[i]:Hide()
        tl.icons[i].spell = nil
    end
end

---------------------------------------------------------------------------
-- Sichtbarkeit: wann die Anzeige erscheint
---------------------------------------------------------------------------

-- Vorschau: solange das Einstellungsfenster den Reiter "Anzeige" zeigt, bleibt die
-- Anzeige sichtbar, damit jede Änderung sofort zu sehen ist.
function Display:PreviewActive()
    return ns.Config and ns.Config.PreviewActive and ns.Config:PreviewActive() or false
end

function Display:ShouldShow(s)
    local g = ns.db.global
    if not g.locked or self:PreviewActive() then return true end
    if g.hideMounted and ns.safe(IsMounted) then return false end
    if g.hideVehicle and (ns.safe(UnitHasVehicleUI, "player") or ns.safe(UnitInVehicle, "player")) then return false end
    if ns.safe(UnitIsDeadOrGhost, "player") then return false end
    local mode = g.showWhen or "targetOrCombat"
    if mode == "always" then return true end
    if mode == "combat" then return s.inCombat end
    if mode == "target" then return s.hasTarget end
    return s.hasTarget or s.inCombat
end

---------------------------------------------------------------------------
-- Erinnerungen vor dem Pull: Essen-Buff und Waffenverzauberung (Öl/Stein).
-- Nur außerhalb des Kampfs – dort sind Auren lesbar.
---------------------------------------------------------------------------

local WELL_FED_SPELL = 19705    -- "Well Fed": liefert den Namen in Client-Sprache
local FOOD_ICON = 136000        -- Symbol aller Essen-Buffs

local function hasFoodBuff()
    local name = ns.safe(C_Spell.GetSpellName, WELL_FED_SPELL)
    if name and ns.safe(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL") then return true end
    for i = 1, 40 do
        local aura = ns.safe(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not aura then break end
        if ns.getField(aura, "icon") == FOOD_ICON then return true end
    end
    return false
end

local function wantReminder(mode)
    if mode == "always" then return true end
    if mode == "instance" then return ns:InInstance() end
    return false
end

function Display:UpdateReminders(s)
    local f, g = self.frame, ns.db.global
    local now = GetTime()
    if f.remindNext and now < f.remindNext then return end
    f.remindNext = now + 1
    local lines = {}
    if not s.inCombat and g.locked and not (g.hideMounted and ns.safe(IsMounted)) then
        if wantReminder(g.remindFood) and not hasFoodBuff() then
            lines[#lines + 1] = "|T133943:14|t " .. L["Kein Essen-Buff"]
        end
        if wantReminder(g.remindWeapon) and not ns.safe(GetWeaponEnchantInfo) then
            local tex = ns.safe(GetInventoryItemTexture, "player", 16) or 135225
            lines[#lines + 1] = "|T" .. tex .. ":14|t " .. L["Keine Waffenverzauberung (Öl/Stein)"]
        end
    end
    f.remind:SetText(table.concat(lines, "\n"))
end

function Display:Update()
    local f = self.frame
    if not f or not ns.rotation then return end
    local g = ns.db.global

    -- Dungeon betreten/verlassen: Größe anpassen
    if ns:InInstance() ~= self.inInstance then self:ApplySettings() return end

    local s = ns:Snapshot()
    self:UpdateReminders(s)
    local preview = self:PreviewActive()
    if not self:ShouldShow(s) then
        setIcon(f.main, nil); setIcon(f.next, nil)
        f.arrow:Hide()
        f.reason:SetText("")
        f.reasonBg:Hide()
        f.timeline:Hide()
        self.currentRule, self.currentReady = nil, false
        if ns.ActionGlow then ns.ActionGlow:Update(nil) end
        return
    end
    f:SetAlpha((s.inCombat or not g.locked or preview) and 1 or (g.alphaOOC or 0.6))

    local rule, ready, noMana = ns:Recommend(s)

    -- Zeilen-Timeline: Ein Zauber kommt erst ins große Icon, wenn er jetzt
    -- (oder direkt nach dem GCD) dran ist. Vorher läuft er auf der Timeline heran.
    -- Leerlauf-Modus (nächster Zauber hat noch Cooldown):
    --   "spell" = großes Icon zeigt ihn schon grau mit Countdown, Timeline zeigt ihn heranlaufen
    --   "empty" = dunkler Kreis + Countdown, "auto" = Autoangriff
    local idleMode = g.idleMode or "spell"
    local readyNow = rule and ready <= s.gcdRemain + 0.3
    self.currentRule, self.currentReady = rule, readyNow   -- für den Prioritäten-Reiter
    if ns.ActionGlow then
        ns.ActionGlow:Update(rule, readyNow, noMana, rule and s.inRange(rule.spell) == false)
    end
    if ns.Coach then ns.Coach:OnRecommend(rule, readyNow, s) end
    local mainWaiting = self.inRow and rule and not readyNow
    if mainWaiting and idleMode == "auto" then
        showIdle(f.main)
    elseif mainWaiting and idleMode == "empty" then
        showEmpty(f.main, ready)
    else
        setIcon(f.main, rule, ready, noMana, s, true)
    end

    -- In der Zeilen-Timeline ersetzt die Timeline das "danach"-Icon.
    local wantNext = g.showNext and not self.inRow
    local nextRule, nextReady, nextNoMana
    if rule and wantNext then
        nextRule, nextReady, nextNoMana = ns:Recommend(s, rule.spell)
    end
    setIcon(f.next, nextRule, nextReady, nextNoMana, s, false)

    if not g.locked or preview then
        if not rule then showPreview(f.main, L["jetzt"]) end
        if wantNext and not nextRule then showPreview(f.next, L["dann"]) end
    end
    f.arrow:SetShown(f.next:IsShown())
    local reason
    if mainWaiting and idleMode ~= "spell" then
        reason = (g.showReason and idleMode == "auto") and L["Autoangriff"] or ""
    else
        reason = (g.showReason and rule and rule.reason and ns:T(rule.reason, rule.spell)) or ""
        if reason == "" and g.showReason and not rule and (not g.locked or preview) then
            reason = L["Begründung erscheint hier"]
        end
    end
    f.reason:SetText(reason)
    f.reasonBg:SetShown(reason ~= "")

    if g.timeline then
        f.timeline:Show()
        -- Nur wenn das große Icon den ersten Zauber zeigt, ihn auf der Timeline weglassen.
        updateTimeline(f.timeline, s, g, self.inRow and not mainWaiting)
    else
        f.timeline:Hide()
    end
end
