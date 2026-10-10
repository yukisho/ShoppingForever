local _, SF = ...

local ROW_COUNT = 10
local ROW_HEIGHT = 32

local function MakeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 24)
    button:SetText(text)
    return button
end

local function MakeEditBox(parent, width, height)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width, height or 24)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(6, 6, 0, 0)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return editBox
end

local function PopupEditBox(dialog)
    if dialog.GetEditBox then
        local ok, editBox = pcall(dialog.GetEditBox, dialog)
        if ok and editBox then return editBox end
    end
    return dialog.EditBox or dialog.editBox
end

function SF:InitializeDialogs()
    StaticPopupDialogs.SHOPPING_FOREVER_NEW_LIST = {
        text = "New shopping list name:",
        button1 = CREATE,
        button2 = CANCEL,
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(dialog)
            local editBox = PopupEditBox(dialog)
            if editBox then editBox:SetText(""); editBox:SetFocus() end
        end,
        OnAccept = function(dialog)
            local editBox = PopupEditBox(dialog)
            local ok, result = SF:AddList(editBox and editBox:GetText() or "")
            if not ok then SF:Print(result) end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local dialog = editBox:GetParent()
            local ok, result = SF:AddList(editBox:GetText())
            if not ok then SF:Print(result) end
            dialog:Hide()
        end,
    }

    StaticPopupDialogs.SHOPPING_FOREVER_RENAME_LIST = {
        text = "Rename shopping list:",
        button1 = SAVE,
        button2 = CANCEL,
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(dialog, data)
            local editBox = PopupEditBox(dialog)
            if editBox then editBox:SetText(data and data.name or ""); editBox:HighlightText(); editBox:SetFocus() end
        end,
        OnAccept = function(dialog, data)
            local editBox = PopupEditBox(dialog)
            local ok, result = SF:RenameList(data and data.id, editBox and editBox:GetText() or "")
            if not ok then SF:Print(result) end
        end,
    }

    StaticPopupDialogs.SHOPPING_FOREVER_DELETE_LIST = {
        text = "Delete |cffffffff%s|r?",
        button1 = DELETE,
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
        OnAccept = function(_, data)
            local ok, result = SF:DeleteList(data and data.id)
            if not ok then SF:Print(result) end
        end,
    }
end

function SF:SaveWindowPosition()
    if not self.window or not self.db then return end
    local point, _, relativePoint, x, y = self.window:GetPoint(1)
    local settings = self.db.settings.window
    settings.point = point or "CENTER"
    settings.relativePoint = relativePoint or "CENTER"
    settings.x = x or 0
    settings.y = y or 0
    settings.width = self.window:GetWidth()
    settings.height = self.window:GetHeight()
end

function SF:RestoreWindowPosition()
    local settings = self.db.settings.window
    self.window:ClearAllPoints()
    self.window:SetPoint(
        settings.point or "CENTER",
        UIParent,
        settings.relativePoint or "CENTER",
        tonumber(settings.x) or 0,
        tonumber(settings.y) or 0
    )
end

function SF:CycleList(direction)
    local lists = self:GetLists()
    if #lists < 2 then return end
    local current = self:GetCurrentList()
    local currentIndex = 1
    for index, list in ipairs(lists) do
        if list.id == current.id then currentIndex = index break end
    end
    currentIndex = currentIndex + direction
    if currentIndex < 1 then currentIndex = #lists end
    if currentIndex > #lists then currentIndex = 1 end
    self:SelectList(lists[currentIndex].id)
end

function SF:ToggleAddTargetMode()
    self.addTargetMode = self.addTargetMode == "buy" and "own" or "buy"
    self.targetModeButton:SetText(self.addTargetMode == "own" and "Own Total" or "Buy More")
end

function SF:AddItemFromControls()
    local itemInfo = self.itemInput:GetText()
    local quantity = tonumber(self.quantityInput:GetText())
    local ok, result, merged = self:AddItem(itemInfo, quantity, self.addTargetMode)
    if not ok then
        self.statusText:SetText("|cffff6666" .. tostring(result) .. "|r")
        return
    end
    self.itemInput:SetText("")
    self.quantityInput:SetText("1")
    self.statusText:SetText(merged and "Updated existing entry." or "Added " .. result.name .. ".")
end

function SF:SetItemInput(itemInfo)
    if not self.itemInput then return end
    self.itemInput:SetText(itemInfo or "")
    self.itemInput:SetCursorPosition(0)
end

function SF:CreateItemRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -4 - ((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -4 - ((index - 1) * ROW_HEIGHT))

    row.complete = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.complete:SetSize(22, 22)
    row.complete:SetPoint("LEFT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", row.complete, "RIGHT", 2, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(165)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.source:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.source:SetWidth(80)
    row.source:SetJustifyH("LEFT")

    row.progress = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.progress:SetPoint("LEFT", row.source, "RIGHT", 4, 0)
    row.progress:SetWidth(55)
    row.progress:SetJustifyH("CENTER")

    row.minus = MakeButton(row, "-", 24, 22)
    row.minus:SetPoint("LEFT", row.progress, "RIGHT", 2, 0)
    row.plus = MakeButton(row, "+", 24, 22)
    row.plus:SetPoint("LEFT", row.minus, "RIGHT", 2, 0)
    row.action = MakeButton(row, "AH", 46, 22)
    row.action:SetPoint("LEFT", row.plus, "RIGHT", 2, 0)
    row.delete = MakeButton(row, "X", 28, 22)
    row.delete:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row:SetScript("OnEnter", function(self)
        local item = self.item
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if item.itemLink then
            GameTooltip:SetHyperlink(item.itemLink)
        else
            GameTooltip:SetText(item.name or ("Item #" .. tostring(item.itemID)))
            GameTooltip:AddLine("Item ID: " .. tostring(item.itemID), 0.8, 0.8, 0.8)
        end
        SF:AddSourceTooltipLines(GameTooltip, item)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function SF:RefreshWindow()
    if not self.window then return end
    local list = self:GetCurrentList()
    if not list then return end

    self.listNameText:SetText(list.name)
    self.listCountText:SetText(#self.db.lists .. " list" .. (#self.db.lists == 1 and "" or "s"))

    local maxOffset = math.max(0, #list.items - ROW_COUNT)
    self.itemOffset = math.max(0, math.min(self.itemOffset or 0, maxOffset))
    local completedCount = 0
    for _, item in ipairs(list.items) do
        local _, _, completed = self:GetItemProgress(item)
        if completed then completedCount = completedCount + 1 end
    end
    self.summaryText:SetText(string.format("%d of %d complete", completedCount, #list.items))

    for rowIndex, row in ipairs(self.itemRows) do
        local item = list.items[self.itemOffset + rowIndex]
        row.item = item
        if item then
            local current, _, completed = self:GetItemProgress(item)
            row:Show()
            row.icon:SetTexture(item.icon or 134400)
            row.name:SetText(item.itemLink or item.name)
            local source = self:GetSourcePresentation(item)
            row.source:SetText(source.label)
            row.progress:SetText(current .. " / " .. item.desired)
            row.complete:SetChecked(completed)
            row.complete:SetEnabled(not completed or item.manualCompleted)
            row.complete:SetScript("OnClick", function(button)
                SF:SetManualCompleted(item.id, button:GetChecked() == true)
            end)
            local isBuy = item.targetMode == "buy"
            row.minus:SetShown(isBuy)
            row.plus:SetShown(isBuy)
            row.minus:SetScript("OnClick", function() SF:AdjustAcquired(item.id, -1) end)
            row.plus:SetScript("OnClick", function() SF:AdjustAcquired(item.id, 1) end)
            row.action:SetText(source.actionText)
            row.action:SetScript("OnClick", function() SF:PerformSourceAction(item) end)
            row.delete:SetScript("OnClick", function() SF:RemoveItem(item.id) end)
        else
            row:Hide()
        end
    end

    self.pageUpButton:SetEnabled(self.itemOffset > 0)
    self.pageDownButton:SetEnabled(self.itemOffset < maxOffset)
end

function SF:ScrollItems(amount)
    local list = self:GetCurrentList()
    if not list then return end
    self.itemOffset = math.max(0, math.min(math.max(0, #list.items - ROW_COUNT), (self.itemOffset or 0) + amount))
    self:RefreshWindow()
end

function SF:CreateMainWindow()
    self:InitializeDialogs()
    self.addTargetMode = "own"
    self.itemOffset = 0

    local window = CreateFrame("Frame", "ShoppingForeverFrame", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(560, 520)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SF:SaveWindowPosition() end)
    window:SetScript("OnMouseWheel", function(_, delta) SF:ScrollItems(delta > 0 and -1 or 1) end)
    window:EnableMouseWheel(true)
    window:SetScript("OnShow", function() SF:RefreshWindow() end)
    window:Hide()
    self.window = window
    table.insert(UISpecialFrames, window:GetName())

    window.TitleText:SetText(self.displayName)
    self:RestoreWindowPosition()

    local previousList = MakeButton(window, "<", 26)
    previousList:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -32)
    previousList:SetScript("OnClick", function() SF:CycleList(-1) end)

    self.listNameText = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.listNameText:SetPoint("LEFT", previousList, "RIGHT", 7, 0)
    self.listNameText:SetWidth(190)
    self.listNameText:SetJustifyH("LEFT")

    local nextList = MakeButton(window, ">", 26)
    nextList:SetPoint("LEFT", self.listNameText, "RIGHT", 2, 0)
    nextList:SetScript("OnClick", function() SF:CycleList(1) end)

    local newList = MakeButton(window, "New", 58)
    newList:SetPoint("LEFT", nextList, "RIGHT", 8, 0)
    newList:SetScript("OnClick", function() StaticPopup_Show("SHOPPING_FOREVER_NEW_LIST") end)

    local renameList = MakeButton(window, "Rename", 68)
    renameList:SetPoint("LEFT", newList, "RIGHT", 4, 0)
    renameList:SetScript("OnClick", function()
        local list = SF:GetCurrentList()
        if list then StaticPopup_Show("SHOPPING_FOREVER_RENAME_LIST", nil, nil, list) end
    end)

    local deleteList = MakeButton(window, "Delete", 62)
    deleteList:SetPoint("LEFT", renameList, "RIGHT", 4, 0)
    deleteList:SetScript("OnClick", function()
        local list = SF:GetCurrentList()
        if list then StaticPopup_Show("SHOPPING_FOREVER_DELETE_LIST", list.name, nil, list) end
    end)

    self.listCountText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.listCountText:SetPoint("TOPLEFT", previousList, "BOTTOMLEFT", 0, -3)

    self.itemInput = MakeEditBox(window, 280)
    self.itemInput:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -78)
    self.itemInput:SetText("")
    self.itemInput:SetScript("OnEnterPressed", function(editBox) SF:AddItemFromControls(); editBox:ClearFocus() end)
    self.itemInput:SetScript("OnReceiveDrag", function()
        local cursorType, itemID, itemLink = GetCursorInfo()
        if cursorType == "item" then SF:SetItemInput(itemLink or itemID); ClearCursor() end
    end)

    self.quantityInput = MakeEditBox(window, 52)
    self.quantityInput:SetPoint("LEFT", self.itemInput, "RIGHT", 7, 0)
    self.quantityInput:SetNumeric(true)
    self.quantityInput:SetMaxLetters(7)
    self.quantityInput:SetText("1")

    self.targetModeButton = MakeButton(window, "Own Total", 90)
    self.targetModeButton:SetPoint("LEFT", self.quantityInput, "RIGHT", 7, 0)
    self.targetModeButton:SetScript("OnClick", function() SF:ToggleAddTargetMode() end)

    local addButton = MakeButton(window, "Add", 58)
    addButton:SetPoint("LEFT", self.targetModeButton, "RIGHT", 7, 0)
    addButton:SetScript("OnClick", function() SF:AddItemFromControls() end)

    local inputHint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    inputHint:SetPoint("TOPLEFT", self.itemInput, "BOTTOMLEFT", 3, -2)
    inputHint:SetText("Paste or drag an item link, then choose quantity and target mode.")

    local listPanel = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    listPanel:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -126)
    listPanel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 48)
    self.listPanel = listPanel
    self.itemRows = {}
    for index = 1, ROW_COUNT do
        self.itemRows[index] = self:CreateItemRow(listPanel, index)
    end

    self.pageUpButton = MakeButton(window, "Up", 46, 22)
    self.pageUpButton:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14, 17)
    self.pageUpButton:SetScript("OnClick", function() SF:ScrollItems(-ROW_COUNT) end)
    self.pageDownButton = MakeButton(window, "Down", 52, 22)
    self.pageDownButton:SetPoint("LEFT", self.pageUpButton, "RIGHT", 4, 0)
    self.pageDownButton:SetScript("OnClick", function() SF:ScrollItems(ROW_COUNT) end)

    self.summaryText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.summaryText:SetPoint("BOTTOM", window, "BOTTOM", 0, 23)

    self.statusText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.statusText:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, 23)
    self.statusText:SetWidth(200)
    self.statusText:SetJustifyH("RIGHT")

    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if SF.itemInput and SF.itemInput:HasFocus() and type(link) == "string" then
                SF:SetItemInput(link)
            end
        end)
    end

    self:RegisterCallback(function()
        if SF.window then SF:RefreshWindow() end
    end)
end

function SF:ShowWindow()
    if self.window then self.window:Show() end
end

function SF:ShowWindowForSource(source)
    if not self.window then return end
    if not self.window:IsShown() then
        self.windowOpenedFor = source
        self.window:Show()
    end
end

function SF:HideWindowForSource(source)
    if self.window and self.windowOpenedFor == source then
        self.windowOpenedFor = nil
        self.window:Hide()
    end
end

function SF:HideWindow()
    if self.window then self.window:Hide() end
end

function SF:ToggleWindow()
    if not self.window then return end
    self.windowOpenedFor = nil
    if self.window:IsShown() then self.window:Hide() else self.window:Show() end
end
