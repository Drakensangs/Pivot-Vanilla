-- Pivot.lua
-- Rotates, pans, and zooms character models in the Character, Inspect, and
-- Dressing Room frames.
--
--   Left-drag   – rotate the model
--   Right-drag  – pan the model (X/Y position)
--   Mouse wheel – zoom in/out (Z position)
--
-- A transparent overlay sits above the equipment slot buttons (which would
-- otherwise swallow clicks) and is inset away from any surrounding UI
-- elements that need their own mouse events (resistance icons, stat rows).
--
-- Character and Inspect frames get a reset button that restores the model to
-- its default rotation, zoom, and pan.  The Dressing Room already has its own
-- built-in reset button, so none is added there.
--
-- Dressing Room extra: Ctrl+click the model to toggle the background textures.

local ROTATION_SENSITIVITY = 0.8
local MOVE_INV_SENSITIVITY = 1 / 45  -- reciprocal: multiply instead of divide each frame
local ZOOM_STEP            = 0.75       -- Z units per scroll tick

local DEFAULT_FACING     = 35
local DEFAULT_FACING_RAD = math.rad(DEFAULT_FACING)

-- Reset button: texture lives at <AddonFolder>/reset/reset.blp
local RESET_BUTTON_SIZE    = 20
local RESET_BUTTON_TEXTURE = "Interface\\AddOns\\Pivot\\reset\\reset"

-- Localize globals used in hot paths (OnUpdate fires every frame while dragging).
local GetCursorPosition = GetCursorPosition
local math_rad          = math.rad

local function _hideThis() this:Hide() end

-- ── Dressing Room background toggle ──────────────────────────────────────────
-- Four panel frames are cached once so the toggle never touches _G.

local dressUpBgVisible = true
local dressUpBgFrames  = {}

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

-- ── Model interaction setup ───────────────────────────────────────────────────
-- modelFrame:   the PlayerModel widget to interact with.
-- unit:         passed to SetUnit() on reset ("player", "target", nil = skip).
--               SetUnit re-seats the model at its natural camera position.
-- rightInset:   pixels to trim from the overlay's right edge.
-- bottomInset:  pixels to trim from the overlay's bottom edge.
-- withBgToggle: wire up Ctrl+click bg-toggle (Dressing Room only).
-- withResetBtn: create a reset button in the top-right corner of the frame.
local function SetupModelInteraction(modelFrame, unit, rightInset, bottomInset, withBgToggle, withResetBtn)
    if not modelFrame then return end

    local lastX           = 0
    local lastY           = 0
    local currentRotation = 0
    local SetRotation     = modelFrame.SetRotation  -- cached: avoids a table index per call

    -- ── Overlay ───────────────────────────────────────────────────────────────
    -- Frame level is resolved once; math.max is not localised because it is
    -- only called during this setup, never in a hot path.
    local overlayLevel = math.max(modelFrame:GetFrameLevel(), 10) + 10

    local overlay = CreateFrame("Frame", nil, modelFrame)
    overlay:SetPoint("TOPLEFT",     modelFrame, "TOPLEFT",      0,           0)
    overlay:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", -rightInset,  bottomInset)
    overlay:SetFrameLevel(overlayLevel)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)

    -- Restores the model to its default unit framing and rotation, and stops
    -- any in-progress drag.  Defined after overlay exists so it can nil OnUpdate.
    local function ResetModel()
        currentRotation = DEFAULT_FACING
        overlay:SetScript("OnUpdate", nil)
        if unit then modelFrame:SetUnit(unit) end
        SetRotation(modelFrame, DEFAULT_FACING_RAD)
    end

    -- Zoom: mouse wheel adjusts the Z (depth) component of the model position.
    -- Not a sustained hot path, so no special treatment needed.
    overlay:SetScript("OnMouseWheel", function()
        local Z, X, Y = modelFrame:GetPosition()
        modelFrame:SetPosition(Z + (arg1 > 0 and ZOOM_STEP or -ZOOM_STEP), X, Y)
    end)

    -- OnUpdate handlers are defined as named upvalues and installed/removed
    -- dynamically so that OnUpdate fires ONLY while a drag is in progress.
    -- With a persistent OnUpdate, all three overlays would fire every frame
    -- (~60/s) even when none of these frames are open.

    local function OnUpdateRotate()
        local curX = GetCursorPosition()
        local delta = curX - lastX
        if delta ~= 0 then
            currentRotation = currentRotation + delta * ROTATION_SENSITIVITY
            SetRotation(modelFrame, math_rad(currentRotation))
            lastX = curX
        end
    end

    local function OnUpdateMove()
        local curX, curY = GetCursorPosition()
        local dX = curX - lastX
        local dY = curY - lastY
        if dX ~= 0 or dY ~= 0 then
            local Z, X, Y = modelFrame:GetPosition()
            -- Multiply by reciprocal instead of dividing each frame.
            modelFrame:SetPosition(Z, X + dX * MOVE_INV_SENSITIVITY,
                                      Y + dY * MOVE_INV_SENSITIVITY)
            lastX = curX
            lastY = curY
        end
    end

    -- dragCatcher is a private full-screen frame used solely as a catch-all
    -- for mouse-up events that the overlay misses when the cursor leaves it
    -- before the button is released.  It is shown only during a drag and sits
    -- below the overlay in frame level so it never steals normal clicks.
    -- Using a dedicated frame avoids clobbering any OnMouseUp that another
    -- addon may have registered on WorldFrame.
    local dragCatcher = CreateFrame("Frame", nil, UIParent)
    dragCatcher:SetAllPoints(UIParent)
    dragCatcher:SetFrameStrata("TOOLTIP")
    dragCatcher:EnableMouse(true)
    dragCatcher:Hide()

    local function stopDrag()
        overlay:SetScript("OnUpdate", nil)
        dragCatcher:Hide()
    end
    dragCatcher:SetScript("OnMouseUp", stopDrag)

    overlay:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            lastX = GetCursorPosition()
            overlay:SetScript("OnUpdate", OnUpdateRotate)
            dragCatcher:Show()
        elseif arg1 == "RightButton" then
            lastX, lastY = GetCursorPosition()
            overlay:SetScript("OnUpdate", OnUpdateMove)
            dragCatcher:Show()
        end
    end)

    -- OnMouseUp on the overlay handles the normal case (cursor stayed inside).
    -- stopDrag is called directly so the catcher is also hidden in both paths.
    -- Dressing Room variant additionally handles Ctrl+click bg-toggle.
    if withBgToggle then
        overlay:SetScript("OnMouseUp", function()
            if arg1 == "LeftButton" then
                stopDrag()
                if IsControlKeyDown() then
                    ToggleDressUpBackground()
                end
            elseif arg1 == "RightButton" then
                stopDrag()
            end
        end)
    else
        overlay:SetScript("OnMouseUp", function()
            if arg1 == "LeftButton" or arg1 == "RightButton" then
                stopDrag()
            end
        end)
    end

    -- ── Reset button ──────────────────────────────────────────────────────────
    -- Sits one level above the overlay so it receives clicks before drag logic.
    if withResetBtn then
        local btn = CreateFrame("Button", nil, modelFrame)
        btn:SetWidth(RESET_BUTTON_SIZE)
        btn:SetHeight(RESET_BUTTON_SIZE)
        btn:SetPoint("TOPLEFT", modelFrame, "TOPLEFT", 4, -4)
        btn:SetFrameLevel(overlayLevel + 1)
        btn:EnableMouse(true)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(btn)
        tex:SetTexture(RESET_BUTTON_TEXTURE)

        btn:SetScript("OnClick", function()
            if arg1 == "LeftButton" then
                ResetModel()
            end
        end)

        btn:SetScript("OnEnter", function()
            tex:SetVertexColor(1, 1, 0)
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText("Reset model", 1, 1, 1)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            tex:SetVertexColor(1, 1, 1)
            GameTooltip:Hide()
        end)
    end

    -- ── OnShow ────────────────────────────────────────────────────────────────
    -- Always resets the model.  Dressing Room variant also resets the background.
    -- origShow is captured once; the guard prevents a call when it is nil.
    local origShow = modelFrame:GetScript("OnShow")
    if withBgToggle then
        modelFrame:SetScript("OnShow", function()
            ResetModel()
            SetDressUpBackground(true)
            if origShow then origShow() end
        end)
    else
        modelFrame:SetScript("OnShow", function()
            ResetModel()
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
-- CharacterModelFrame: right=33 (resistance icons), bottom=12 (stat rows)
-- DressUpModel:        right=0,  bottom=16 (Reset/Close buttons)

local charHook = CreateFrame("Frame")
charHook:RegisterEvent("PLAYER_ENTERING_WORLD")
charHook:SetScript("OnEvent", function()
    SetupDressUpBgCache()
    SetupModelInteraction(CharacterModelFrame, "player", 33, 12,  nil,  true)
    HideRotateButton(CharacterModelFrameRotateLeftButton)
    HideRotateButton(CharacterModelFrameRotateRightButton)
    SetupModelInteraction(DressUpModel,         nil,      0,  16,  true, nil)
    HideRotateButton(DressUpModelRotateLeftButton)
    HideRotateButton(DressUpModelRotateRightButton)
    -- Unregister the event and release the closure and its upvalues.
    charHook:UnregisterEvent("PLAYER_ENTERING_WORLD")
    charHook:SetScript("OnEvent", nil)
end)

-- ── Inspect Frame ─────────────────────────────────────────────────────────────
-- InspectFrame is demand-loaded; InspectModelFrame doesn't exist until the
-- player first opens Inspect.  A lightweight OnUpdate poller detects when
-- InspectFrame appears, installs an OnShow hook, then removes itself.

local inspectHooked = false

local function HookInspectFrame()
    if inspectHooked or not InspectModelFrame then return end
    inspectHooked = true
    SetupModelInteraction(InspectModelFrame, "target", 0, 0, nil, true)
    HideRotateButton(InspectModelRotateLeftButton)
    HideRotateButton(InspectModelRotateRightButton)
end

local inspectWatcher = CreateFrame("Frame")
inspectWatcher:SetScript("OnUpdate", function()
    if InspectFrame then
        local origShow = InspectFrame:GetScript("OnShow")
        InspectFrame:SetScript("OnShow", function()
            if origShow then origShow() end
            HookInspectFrame()
        end)
        if InspectFrame:IsShown() then
            HookInspectFrame()
        end
        -- Nil the script to release the closure and stop the per-frame poll.
        inspectWatcher:SetScript("OnUpdate", nil)
    end
end)
