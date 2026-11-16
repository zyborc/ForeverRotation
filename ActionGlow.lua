-- ForeverRotation – Aktionsleisten-Leuchten.
-- Der empfohlene Zauber leuchtet zusätzlich auf deiner Aktionsleiste (Blizzard-Leisten,
-- Bartender4, Dominos, ElvUI). Reine Optik: ein eigener Rahmen wird über den Knopf gelegt,
-- der Knopf selbst wird nicht verändert (keine Taint-Probleme, auch im Kampf).

local _, ns = ...

local ActionGlow = {}
ns.ActionGlow = ActionGlow

local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGE = 3

local buttons = {}      -- alle gefundenen Aktionsknöpfe
local bySpell = {}      -- [Zaubername in Client-Sprache] = { Knopf, ... }
local glows = {}        -- [Knopf] = Leucht-Rahmen
local lit = {}          -- [Knopf] = true, gerade leuchtend
local dirty = true      -- Zuordnung Knopf -> Zauber neu aufbauen
local lastScan = 0

---------------------------------------------------------------------------
-- Knöpfe finden
---------------------------------------------------------------------------

local BLIZZARD_BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local function collectButtons()
    wipe(buttons)
    local seen = {}
    local function add(b)
        if b and not seen[b] and b.GetObjectType then
            seen[b] = true
            buttons[#buttons + 1] = b
        end
    end
    for _, prefix in ipairs(BLIZZARD_BARS) do
        for i = 1, 12 do add(_G[prefix .. i]) end
    end
    for i = 1, 180 do
        add(_G["BT4Button" .. i])            -- Bartender4
        add(_G["DominosActionButton" .. i])  -- Dominos
    end
    for bar = 1, 15 do                       -- ElvUI
        for i = 1, 12 do add(_G["ElvUI_Bar" .. bar .. "Button" .. i]) end
    end
end

-- Aktionsplatz eines Knopfs (Blizzard: .action, LibActionButton: _state_action)
local function slotOf(b)
    local slot = b.action or b._state_action
    if type(slot) ~= "number" and b.GetAttribute then
        local ok, v = pcall(b.GetAttribute, b, "action")
        if ok then slot = v end
    end
    return type(slot) == "number" and slot or nil
end

-- Welcher Zauber liegt auf dem Platz? Auch Makros mit Zauber.
local function spellNameOfSlot(slot)
    local actionType, id = ns.safe(GetActionInfo, slot)
    local spellID
    if actionType == "spell" then
        spellID = id
    elseif actionType == "macro" and id then
        spellID = ns.safe(GetMacroSpell, id)
    end
    return spellID and ns.safe(C_Spell.GetSpellName, spellID)
end

local function rebuildMap()
    wipe(bySpell)
    for _, b in ipairs(buttons) do
        local slot = slotOf(b)
        local name = slot and spellNameOfSlot(slot)
        if name then
            bySpell[name] = bySpell[name] or {}
            table.insert(bySpell[name], b)
        end
    end
    dirty = false
    lastScan = GetTime()
end

---------------------------------------------------------------------------
-- Leucht-Rahmen
---------------------------------------------------------------------------

local function createGlow(btn)
    local gl = CreateFrame("Frame", nil, UIParent)
    gl:SetPoint("TOPLEFT", btn, "TOPLEFT", -EDGE, EDGE)
    gl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", EDGE, -EDGE)
    gl:EnableMouse(false)

    local function edge()
        local t = gl:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(WHITE)
        return t
    end
    gl.top, gl.bottom, gl.left, gl.right = edge(), edge(), edge(), edge()
    gl.top:SetPoint("TOPLEFT"); gl.top:SetPoint("TOPRIGHT"); gl.top:SetHeight(EDGE)
    gl.bottom:SetPoint("BOTTOMLEFT"); gl.bottom:SetPoint("BOTTOMRIGHT"); gl.bottom:SetHeight(EDGE)
    gl.left:SetPoint("TOPLEFT"); gl.left:SetPoint("BOTTOMLEFT"); gl.left:SetWidth(EDGE)
    gl.right:SetPoint("TOPRIGHT"); gl.right:SetPoint("BOTTOMRIGHT"); gl.right:SetWidth(EDGE)

    gl.fill = gl:CreateTexture(nil, "OVERLAY", nil, 6)
    gl.fill:SetPoint("TOPLEFT", EDGE, -EDGE)
    gl.fill:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    gl.fill:SetTexture(WHITE)
    gl.fill:SetBlendMode("ADD")

    local ag = gl:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35)
    a:SetToAlpha(1)
    a:SetDuration(0.45)
    a:SetSmoothing("IN_OUT")
    gl.anim = ag
    gl:Hide()
    return gl
end

local function setColor(gl, r, g, b)
    for _, t in ipairs({ gl.top, gl.bottom, gl.left, gl.right }) do t:SetVertexColor(r, g, b, 1) end
    gl.fill:SetVertexColor(r, g, b, 0.22)
end

local function showGlow(btn, r, g, b)
    local gl = glows[btn]
    if not gl then
        gl = createGlow(btn)
        glows[btn] = gl
    end
    gl:SetFrameStrata(btn:GetFrameStrata())
    gl:SetFrameLevel(btn:GetFrameLevel() + 10)
    setColor(gl, r, g, b)
    if not gl:IsShown() then
        gl:Show()
        gl.anim:Play()
    end
    lit[btn] = true
end

local function hideGlow(btn)
    local gl = glows[btn]
    if gl then
        gl.anim:Stop()
        gl:Hide()
    end
    lit[btn] = nil
end

function ActionGlow:Clear()
    for btn in pairs(lit) do hideGlow(btn) end
end

---------------------------------------------------------------------------
-- Aufruf aus der Anzeige (20x pro Sekunde)
---------------------------------------------------------------------------

-- rule: aktuelle Empfehlung, readyNow: jetzt drücken; noMana/outOfRange: gedämpfte Farbe
function ActionGlow:Update(rule, readyNow, noMana, outOfRange)
    local g = ns.db.global
    if not g.actionGlow or not rule or (not readyNow and g.actionGlowMode ~= "always") then
        self:Clear()
        return
    end
    if #buttons == 0 then collectButtons() end
    if dirty or GetTime() - lastScan > 2 then rebuildMap() end

    local list = bySpell[ns:SpellName(rule.spell)]
    local r, gr, b = 1, 0.8, 0.2                     -- gold: jetzt drücken
    if noMana then r, gr, b = 0.3, 0.5, 1            -- blau: zu wenig Mana
    elseif outOfRange then r, gr, b = 1, 0.25, 0.2   -- rot: außer Reichweite
    elseif not readyNow then r, gr, b = 0.6, 0.6, 0.6 end -- grau: kommt gleich
    local want = {}
    if list then
        for _, btn in ipairs(list) do
            if btn:IsVisible() then
                want[btn] = true
                showGlow(btn, r, gr, b)
            end
        end
    end
    for btn in pairs(lit) do
        if not want[btn] then hideGlow(btn) end
    end
end

---------------------------------------------------------------------------
-- Ereignisse: Leisten umgebaut / Seite gewechselt
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "SPELLS_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Leisten-Addons bauen ihre Knöpfe teils später: kurz danach noch einmal suchen
        collectButtons()
        if C_Timer then C_Timer.After(3, function() collectButtons(); dirty = true end) end
    end
    dirty = true
end)
