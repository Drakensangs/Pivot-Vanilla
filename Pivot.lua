-- Pivot.lua
-- Rotates character models in the Character, Inspect, and Dressing Room
-- frames by holding the left mouse button and dragging.
--
-- A transparent overlay sits above the equipment slot buttons (which would
-- otherwise swallow clicks) and is inset away from any surrounding UI
-- elements that need their own mouse events (resistance icons, stat rows).
--
-- Dressing Room extra: Ctrl+click the model to toggle the background textures.

local ROTATION_SENSITIVITY = 0.8
local DEFAULT_FACING       = 35
local DEFAULT_FACING_RAD   = math.rad(DEFAULT_FACING)

local GetCursorPosition = GetCursorPosition
local math_rad          = math.rad
local math_max          = math.max

local function _hideThis() this:Hide() end

-- ── Dressing Room background toggle ──────────────────────────────────────────
-- Mirrors the IDR addon's approach: background is shown by default whenever
-- the Dressing Room opens, and Ctrl+click flips it each time.
-- Frames are cached at hookup time (PLAYER_ENTERING_WORLD) so toggle calls
-- never hit _G or do string-keyed method dispatch.

local dressUpBgVisible = true
local dressUpBgFrames  = {}     -- filled by SetupDressUpBgCache() below

local function SetupDressUpBgCache()
    dressUpBgFrames[1] = DressUpBackgroundTopLeft
    dressUpBgFrames[2] = DressUpBackgroundTopRight
    dressUpBgFrames[3] = DressUpBackgroundBotLeft
    dressUpBgFrames[4] = DressUpBackgroundBotRight
end

local function SetDressUpBackground(visible)
    dressUpBgVisible = visible
    if visible then
        dressUpBgFrames[1]:Show()
        dressUpBgFrames[2]:Show()
        dressUpBgFrames[3]:Show()
        dressUpBgFrames[4]:Show()
    else
        dressUpBgFrames[1]:Hide()
        dressUpBgFrames[2]:Hide()
        dressUpBgFrames[3]:Hide()
        dressUpBgFrames[4]:Hide()
    end
end

local function ToggleDressUpBackground()
    SetDressUpBackground(not dressUpBgVisible)
end

-- rightInset: pulls the overlay's right edge left by this many pixels.
-- bottomInset: pulls the overlay's bottom edge up by this many pixels.
-- withBgToggle: if true, this overlay gets Ctrl+click bg-toggle behaviour
--               and resets the background on OnShow.  Only the Dressing Room
--               overlay sets this; Character and Inspect get leaner closures.
local function SetupModelRotation(modelFrame, rightInset, bottomInset, withBgToggle)
    if not modelFrame then return end

    local isDragging      = false
    local lastX           = 0
    local currentRotation = 0
    local SetRotation     = modelFrame.SetRotation

    local overlay = CreateFrame("Frame", nil, modelFrame)
    overlay:SetPoint("TOPLEFT",     modelFrame, "TOPLEFT",     0,                  0)
    overlay:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", -(rightInset or 0), (bottomInset or 0))
    overlay:SetFrameLevel(math_max(modelFrame:GetFrameLevel(), 10) + 10)
    overlay:EnableMouse(true)

    overlay:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            isDragging = true
            lastX = GetCursorPosition()
        end
    end)

    -- OnMouseUp: Dressing Room overlay gets the Ctrl+click branch;
    -- other overlays get a simpler handler with no dead upvalue reference.
    if withBgToggle then
        overlay:SetScript("OnMouseUp", function()
            if arg1 == "LeftButton" then
                isDragging = false
                if IsControlKeyDown() then
                    ToggleDressUpBackground()
                end
            end
        end)
    else
        overlay:SetScript("OnMouseUp", function()
            if arg1 == "LeftButton" then
                isDragging = false
            end
        end)
    end

    overlay:SetScript("OnUpdate", function()
        if isDragging then
            local curX = GetCursorPosition()
            local delta = curX - lastX
            if delta ~= 0 then
                currentRotation = currentRotation + delta * ROTATION_SENSITIVITY
                SetRotation(modelFrame, math_rad(currentRotation))
                lastX = curX
            end
        end
    end)

    -- OnShow: Dressing Room overlay resets the background on open;
    -- other overlays get a simpler handler.
    local origShow = modelFrame:GetScript("OnShow")
    if withBgToggle then
        modelFrame:SetScript("OnShow", function()
            isDragging      = false
            currentRotation = DEFAULT_FACING
            SetRotation(modelFrame, DEFAULT_FACING_RAD)
            SetDressUpBackground(true)
            if origShow then origShow() end
        end)
    else
        modelFrame:SetScript("OnShow", function()
            isDragging      = false
            currentRotation = DEFAULT_FACING
            SetRotation(modelFrame, DEFAULT_FACING_RAD)
            if origShow then origShow() end
        end)
    end
end

local function HideRotateButton(btn)
    if btn then
        btn:Hide()
        btn:SetScript("OnShow", _hideThis)
    end
end

-- ── Character Frame & Dressing Room ──────────────────────────────────────────
-- CharacterModelFrame insets (measured in-game):
--   right:  33 — frame is 233px wide; resistance icons begin at 200px in,
--               so the overlay is trimmed 33px from the right edge.
--   bottom: 12 — CharacterAttributesFrame (stats) sits ~11px below the
--               model frame's bottom; 12px trim prevents tooltip offset.
-- DressUpModel:
--   bottom: 16 — clears the Reset/Close buttons below the model.
--   withBgToggle: true — enables Ctrl+click background toggle.

local charHook = CreateFrame("Frame")
charHook:RegisterEvent("PLAYER_ENTERING_WORLD")
charHook:SetScript("OnEvent", function()
    SetupDressUpBgCache()
    SetupModelRotation(CharacterModelFrame, 33, 12)
    HideRotateButton(CharacterModelFrameRotateLeftButton)
    HideRotateButton(CharacterModelFrameRotateRightButton)
    SetupModelRotation(DressUpModel, nil, 16, true)
    HideRotateButton(DressUpModelRotateLeftButton)
    HideRotateButton(DressUpModelRotateRightButton)
    charHook:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)

-- ── Inspect Frame ─────────────────────────────────────────────────────────────
-- Loaded on demand; hook on INSPECT_READY with a 3-second timer fallback.

local inspectHooked    = false
local inspectHookFrame = CreateFrame("Frame")
local timerFrame       = CreateFrame("Frame")

local function HookInspectFrame()
    if inspectHooked or not InspectModelFrame then return end
    inspectHooked = true
    SetupModelRotation(InspectModelFrame)
    HideRotateButton(InspectModelRotateLeftButton)
    HideRotateButton(InspectModelRotateRightButton)
    inspectHookFrame:UnregisterEvent("INSPECT_READY")
    timerFrame:SetScript("OnUpdate", nil)
end

inspectHookFrame:RegisterEvent("INSPECT_READY")
inspectHookFrame:SetScript("OnEvent", HookInspectFrame)

local timer = 0
timerFrame:SetScript("OnUpdate", function()
    timer = timer + arg1
    if timer > 3 then
        timerFrame:SetScript("OnUpdate", nil)
        HookInspectFrame()
    end
end)