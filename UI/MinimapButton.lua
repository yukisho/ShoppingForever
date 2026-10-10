local _, SF = ...

local ICON_TEXTURE = "Interface\\AddOns\\ShoppingForever\\Media\\ShoppingForeverIcon"
local FALLBACK_MINIMAP_RADIUS = 80

local function GetMinimapRadius()
    local width = tonumber(Minimap:GetWidth()) or 0
    local height = tonumber(Minimap:GetHeight()) or 0
    if width <= 0 or height <= 0 then return FALLBACK_MINIMAP_RADIUS end
    return math.min(width, height) / 2
end

local function CursorAngleFromMinimap()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local centerX, centerY = Minimap:GetCenter()
    if not cursorX or not cursorY or not scale or scale == 0 or not centerX or not centerY then
        return nil
    end

    local offsetX = (cursorX / scale) - centerX
    local offsetY = (cursorY / scale) - centerY
    if offsetX == 0 then return offsetY >= 0 and 90 or 270 end

    local angle = math.deg(math.atan(offsetY / offsetX))
    if offsetX < 0 then
        angle = angle + 180
    elseif angle < 0 then
        angle = angle + 360
    end
    return angle
end

function SF:PositionMinimapButton()
    local button = self.minimapButton
    if not button or not Minimap then return end
    local radians = math.rad(self:GetMinimapAngle())
    local radius = GetMinimapRadius()
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(radians) * radius, math.sin(radians) * radius)
end

function SF:RefreshMinimapButton()
    local button = self.minimapButton
    if not button then return end
    self:PositionMinimapButton()
    button:SetShown(self:IsMinimapButtonShown())
end

function SF:CreateMinimapButton()
    if self.minimapButton or not Minimap then return end

    local button = CreateFrame("Button", "ShoppingForeverMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    self.minimapButton = button

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_TEXTURE)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            SF:ShowWindow()
            SF:ShowManageWindow()
        else
            SF:ToggleWindow()
        end
    end)
    button:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
        GameTooltip:SetText("Shopping Forever")
        GameTooltip:AddLine("Left-click to open or close your shopping list.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click to open Manage and Settings.", 1, 1, 1, true)
        GameTooltip:AddLine("Drag to move this button around the minimap.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(frame)
        frame:SetScript("OnUpdate", function()
            local angle = CursorAngleFromMinimap()
            if angle then SF:SetMinimapAngle(angle, true) end
        end)
    end)
    button:SetScript("OnDragStop", function(frame)
        frame:SetScript("OnUpdate", nil)
        local angle = CursorAngleFromMinimap()
        if angle then SF:SetMinimapAngle(angle) end
    end)

    if Minimap.HookScript then
        pcall(Minimap.HookScript, Minimap, "OnSizeChanged", function()
            SF:PositionMinimapButton()
        end)
    end

    self:RefreshMinimapButton()
end
