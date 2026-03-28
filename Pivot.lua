-- Pivot.lua
-- Left-drag: rotate, Right-drag: pan, Mouse wheel: zoom.
-- Dressing Room: Ctrl+left-click toggles background textures.

local ROTATION_SENSITIVITY = 0.8
local MOVE_INV_SENSITIVITY = 1 / 45
local ZOOM_STEP            = 0.15
local DEFAULT_FACING       = 35
local DEFAULT_FACING_RAD   = math.rad(DEFAULT_FACING)

local RESET_BUTTON_SIZE    = 20
local RESET_BUTTON_TEXTURE = "Interface\\AddOns\\Pivot\\reset\\reset"

local GetCursorPosition = GetCursorPosition
local math_rad          = math.rad
local math_max          = math.max
local IsControlKeyDown  = IsControlKeyDown

local function _hideThis() this:Hide() end

-- ── Background toggle ─────────────────────────────────────────────────────────

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
        dressBg1:Show(); dressBg2:Show(); dressBg3:Show(); dressBg4:Show()
    else
        dressBg1:Hide(); dressBg2:Hide(); dressBg3:Hide(); dressBg4:Hide()
    end
end

local function ToggleDressUpBackground()
    SetDressUpBackground(not dressUpBgVisible)
end

-- ── Model interaction (overlay-based, for frames with slot buttons) ───────────

local function SetupModelInteraction(modelFrame, unit, rightInset, bottomInset, withBgToggle, withResetBtn)
    if not modelFrame then return end

    local lastX           = 0
    local lastY           = 0
    local currentRotation = 0
    local SetRotation     = modelFrame.SetRotation

    local overlayLevel = math_max(modelFrame:GetFrameLevel(), 10) + 10

    local overlay = CreateFrame("Frame", nil, modelFrame)
    overlay:SetPoint("TOPLEFT",     modelFrame, "TOPLEFT",      0,          0)
    overlay:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", -rightInset, bottomInset)
    overlay:SetFrameLevel(overlayLevel)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)

    local function ResetModel()
        currentRotation = DEFAULT_FACING
        overlay:SetScript("OnUpdate", nil)
        if unit then modelFrame:SetUnit(unit) end
        SetRotation(modelFrame, DEFAULT_FACING_RAD)
    end

    overlay:SetScript("OnMouseWheel", function()
        local Z, X, Y = modelFrame:GetPosition()
        modelFrame:SetPosition(Z + (arg1 > 0 and ZOOM_STEP or -ZOOM_STEP), X, Y)
    end)

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

    if withBgToggle then
        overlay:SetScript("OnMouseUp", function()
            if arg1 == "LeftButton" then
                stopDrag()
                if IsControlKeyDown() then ToggleDressUpBackground() end
            elseif arg1 == "RightButton" then
                stopDrag()
            end
        end)
    else
        overlay:SetScript("OnMouseUp", function()
            if arg1 == "LeftButton" or arg1 == "RightButton" then stopDrag() end
        end)
    end

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
            if arg1 == "LeftButton" then ResetModel() end
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

-- ── Character Frame, Dressing Room & Pet Frame ────────────────────────────────

local charHook = CreateFrame("Frame")
charHook:RegisterEvent("PLAYER_ENTERING_WORLD")
charHook:SetScript("OnEvent", function()
    SetupDressUpBgCache()

    local cp, crt, crp, cx, cy = CharacterModelFrame:GetPoint()
    CharacterModelFrame:ClearAllPoints()
    CharacterModelFrame:SetHeight(CharacterModelFrame:GetHeight() - 9)
    CharacterModelFrame:SetPoint(cp, crt, crp, cx, cy)
    SetupModelInteraction(CharacterModelFrame, "player", 33, 0, nil, true)
    HideRotateButton(CharacterModelFrameRotateLeftButton)
    HideRotateButton(CharacterModelFrameRotateRightButton)

    local p, rt, rp, x, y = DressUpModel:GetPoint()
    DressUpModel:ClearAllPoints()
    DressUpModel:SetHeight(331)
    DressUpModel:SetPoint(p, rt, rp, x, y + 20)
    SetupModelInteraction(DressUpModel, nil, 0, 16, true, nil)
    DressUpFrameResetButton:SetScript("OnClick", function()
        DressUpModel:Dress()
        DressUpModel:SetRotation(DEFAULT_FACING_RAD)
    end)
    HideRotateButton(DressUpModelRotateLeftButton)
    HideRotateButton(DressUpModelRotateRightButton)

    if PetModelFrame then
        SetupModelInteraction(PetModelFrame, "pet", 33, 0, nil, true)
        HideRotateButton(PetModelFrameRotateLeftButton)
        HideRotateButton(PetModelFrameRotateRightButton)
        PetPaperDollPetInfo:SetFrameStrata("HIGH")
    end

    charHook:UnregisterEvent("PLAYER_ENTERING_WORLD")
    charHook:SetScript("OnEvent", nil)
end)

-- ── Inspect Frame ─────────────────────────────────────────────────────────────

local inspectHooked = false

local function HookInspectFrame()
    if inspectHooked or not InspectModelFrame then return end
    inspectHooked = true
    SetupModelInteraction(InspectModelFrame, "target", 0, 0, nil, true)
    HideRotateButton(InspectModelRotateLeftButton)
    HideRotateButton(InspectModelRotateRightButton)
end

-- ── Auction House Dressing Room ───────────────────────────────────────────────

local auctionDressUpHooked = false

local function HookAuctionDressUpFrame()
    if auctionDressUpHooked or not AuctionDressUpModel then return end
    auctionDressUpHooked = true

    local m = AuctionDressUpModel
    local p, rt, rp = m:GetPoint()
    m:SetHeight(370)
    m:SetPoint(p, rt, rp, 0, 10)
    m:SetScript("OnUpdate", nil)

    local lastX, lastY = 0, 0
    local currentRotation = 0

    local function OnUpdateRotate()
        local curX = GetCursorPosition()
        local delta = curX - lastX
        if delta ~= 0 then
            currentRotation = currentRotation + delta * ROTATION_SENSITIVITY
            m:SetRotation(math_rad(currentRotation))
            lastX = curX
        end
    end

    local function OnUpdateMove()
        local curX, curY = GetCursorPosition()
        local dX = curX - lastX
        local dY = curY - lastY
        if dX ~= 0 or dY ~= 0 then
            local Z, X, Y = m:GetPosition()
            m:SetPosition(Z, X + dX * MOVE_INV_SENSITIVITY,
                             Y + dY * MOVE_INV_SENSITIVITY)
            lastX = curX
            lastY = curY
        end
    end

    local dragCatcher = CreateFrame("Frame", nil, UIParent)
    dragCatcher:SetAllPoints(UIParent)
    dragCatcher:SetFrameStrata("TOOLTIP")
    dragCatcher:EnableMouse(true)
    dragCatcher:Hide()

    local function stopDrag()
        m:SetScript("OnUpdate", nil)
        dragCatcher:Hide()
    end
    dragCatcher:SetScript("OnMouseUp", stopDrag)

    m:EnableMouse(true)
    m:EnableMouseWheel(true)

    m:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            lastX = GetCursorPosition()
            m:SetScript("OnUpdate", OnUpdateRotate)
            dragCatcher:Show()
        elseif arg1 == "RightButton" then
            lastX, lastY = GetCursorPosition()
            m:SetScript("OnUpdate", OnUpdateMove)
            dragCatcher:Show()
        end
    end)

    m:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" or arg1 == "RightButton" then stopDrag() end
    end)

    m:SetScript("OnMouseWheel", function()
        local Z, X, Y = m:GetPosition()
        m:SetPosition(Z + (arg1 > 0 and ZOOM_STEP or -ZOOM_STEP), X, Y)
    end)

    AuctionDressUpFrameResetButton:SetScript("OnClick", function()
        currentRotation = DEFAULT_FACING
        m:SetScript("OnUpdate", nil)
        m:Dress()
        m:SetRotation(DEFAULT_FACING_RAD)
        PlaySound("gsTitleOptionOK")
    end)

    HideRotateButton(AuctionDressUpModelRotateLeftButton)
    HideRotateButton(AuctionDressUpModelRotateRightButton)
end

-- ── Demand-loaded addons ──────────────────────────────────────────────────────

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
    if arg1 == "Blizzard_InspectUI" then HookInspectFrame()       end
    if arg1 == "Blizzard_AuctionUI" then HookAuctionDressUpFrame() end
end)
if InspectModelFrame   then HookInspectFrame()       end
if AuctionDressUpModel then HookAuctionDressUpFrame() end
