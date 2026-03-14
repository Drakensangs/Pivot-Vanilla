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
local ZOOM_STEP            = 0.15    -- Z units per scroll tick

local DEFAULT_FACING     = 35
local DEFAULT_FACING_RAD = math.rad(DEFAULT_FACING)

-- Reset button: texture lives at <AddonFolder>/reset/reset.blp
local RESET_BUTTON_SIZE    = 20
local RESET_BUTTON_TEXTURE = "Interface\\AddOns\\Pivot\\reset\\reset"

-- Localize globals used in hot paths (OnUpdate fires every frame while dragging).
local GetCursorPosition = GetCursorPosition
local math_rad          = math.rad
local math_max          = math.max
local IsControlKeyDown  = IsControlKeyDown

local function _hideThis() this:Hide() end

-- ── Dressing Room background toggle ──────────────────────────────────────────
-- Frames are cached as direct locals once; no table allocation needed.

local dressUpBgVisible = true
local dressBg1, dressBg2, dressBg3, dressBg4

local function SetupDressUpBgCache()
    dressBg1 = DressUpBackgroundTopLeft
    dressBg2 = DressUpBackgroundTopRight
    dressBg3 = DressUpBackgroundBotLeft
    dressBg4 = DressUpBackgroundBotRight
end

local function SetDressUpBackground(visible)
    dressUpBgVisible = visible
    if visible then
        dressBg1:Show()
        dressBg2:Show()
        dressBg3:Show()
        dressBg4:Show()
    else
        dressBg1:Hide()
        dressBg2:Hide()
        dressBg3:Hide()
        dressBg4:Hide()
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
-- withResetBtn: create a reset button in the top-left corner of the frame.
local function SetupModelInteraction(modelFrame, unit, rightInset, bottomInset, withBgToggle, withResetBtn)
    if not modelFrame then return end

    local lastX           = 0
    local lastY           = 0
    local currentRotation = 0
    local SetRotation     = modelFrame.SetRotation  -- cached: avoids a table index per call

    -- ── Overlay ───────────────────────────────────────────────────────────────
    local overlayLevel = math_max(modelFrame:GetFrameLevel(), 10) + 10

    local overlay = CreateFrame("Frame", nil, modelFrame)
    overlay:SetPoint("TOPLEFT",     modelFrame, "TOPLEFT",      0,          0)
    overlay:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", -rightInset, bottomInset)
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
    -- For the Dressing Room (withBgToggle), origShow is not called because
    -- Blizzard's OnShow resets the camera position after our frame adjustments.
    if withBgToggle then
        modelFrame:SetScript("OnShow", function()
            ResetModel()
            SetDressUpBackground(true)
        end)
    else
        local origShow = modelFrame:GetScript("OnShow")
        modelFrame:SetScript("OnShow", function()
            if origShow then origShow() end
            ResetModel()
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

local charHook = CreateFrame("Frame")
charHook:RegisterEvent("PLAYER_ENTERING_WORLD")
charHook:SetScript("OnEvent", function()
    SetupDressUpBgCache()

    -- Trim CharacterModelFrame height so the model clips above the stat rows.
    local cp, crt, crp, cx, cy = CharacterModelFrame:GetPoint()
    CharacterModelFrame:ClearAllPoints()
    CharacterModelFrame:SetHeight(CharacterModelFrame:GetHeight() - 9)
    CharacterModelFrame:SetPoint(cp, crt, crp, cx, cy)
    SetupModelInteraction(CharacterModelFrame, "player", 33, 0, nil, true)
    HideRotateButton(CharacterModelFrameRotateLeftButton)
    HideRotateButton(CharacterModelFrameRotateRightButton)

    -- Resize and reposition DressUpModel so its bottom edge sits above the
    -- button bar, letting the frame boundary clip the render naturally.
    local p, rt, rp, x, y = DressUpModel:GetPoint()
    DressUpModel:ClearAllPoints()
    DressUpModel:SetHeight(331)
    DressUpModel:SetPoint(p, rt, rp, x, y + 20)
    SetupModelInteraction(DressUpModel, nil, 0, 16, true, nil)
    -- Take full ownership of the Reset button so we control the entire reset
    -- sequence: Dress() redresses without a full reload, then rotation is restored.
    DressUpFrameResetButton:SetScript("OnClick", function()
        DressUpModel:Dress()
        DressUpModel:SetRotation(DEFAULT_FACING_RAD)
    end)
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
