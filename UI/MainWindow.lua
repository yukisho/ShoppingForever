local _, SF = ...

local ROW_COUNT = 10
local ROW_HEIGHT = 32
local SOURCE_ORDER = { "any", "auction", "vendor", "craft" }
local SOURCE_LABELS = {
    any = "Automatic",
    auction = "Auction House",
    vendor = "Vendor",
    craft = "Craft",
}
local FILTER_ORDER = { "all", "incomplete", "complete" }
local FILTER_LABELS = { all = "All", incomplete = "Open", complete = "Done" }
local SORT_ORDER = { "added", "name", "remaining", "source" }
local SORT_LABELS = { added = "Added", name = "Name", remaining = "Need", source = "Source" }
local HISTORY_SOURCE_LABELS = {
    auction = "Auction House",
    vendor = "Vendor",
    craft = "Craft",
    manual = "Manual",
    unknown = "Unknown",
}

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

    StaticPopupDialogs.SHOPPING_FOREVER_LIST_NOTE = {
        text = "Note for |cffffffff%s|r:",
        button1 = SAVE,
        button2 = CANCEL,
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(dialog, data)
            local editBox = PopupEditBox(dialog)
            if editBox then
                editBox:SetMaxLetters(255)
                editBox:SetText(data and data.note or "")
                editBox:HighlightText()
                editBox:SetFocus()
            end
        end,
        OnAccept = function(dialog, data)
            local editBox = PopupEditBox(dialog)
            local ok, result = SF:SetListNote(data and data.id, editBox and editBox:GetText() or "")
            if not ok then SF:Print(result) end
        end,
    }

    StaticPopupDialogs.SHOPPING_FOREVER_RESTORE_BACKUP = {
        text = "Restore this full Shopping Forever backup? Current data will be replaced after a safety copy is created.",
        button1 = "Restore",
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
        OnAccept = function(_, code) SF:RestoreBackupFromUI(code) end,
    }

    StaticPopupDialogs.SHOPPING_FOREVER_RESTORE_SAFETY = {
        text = "Restore the most recent automatic safety copy?",
        button1 = "Restore",
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
        OnAccept = function() SF:RestoreSafetyFromUI() end,
    }

    StaticPopupDialogs.SHOPPING_FOREVER_CLEAR_HISTORY = {
        text = "Clear acquisition history for |cffffffff%s|r? Progress will not be changed.",
        button1 = DELETE,
        button2 = CANCEL,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
        preferredIndex = 3,
        OnAccept = function(_, listID)
            local ok, removed = SF:ClearAcquisitionHistory(listID)
            if ok then SF.statusText:SetText("Cleared " .. removed .. " history entries.") end
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
    row.materials = MakeButton(row, "Mats", 48, 22)
    row.materials:SetPoint("LEFT", row.plus, "RIGHT", 2, 0)
    row.materials:SetScript("OnEnter", function(self)
        if not row.item then return end
        local plan = SF:GetRecipeReagentPlan(row.item)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add missing materials")
        if plan then
            GameTooltip:AddLine("Adds uncovered reagents as Buy More entries.", 1, 1, 1, true)
            if not plan.currentCharacter then
                GameTooltip:AddLine("Recipe known by " .. (plan.source.characterName or "an alternate character") .. ".",
                    0.5, 0.85, 1)
            end
        end
        GameTooltip:Show()
    end)
    row.materials:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.action = MakeButton(row, "AH", 46, 22)
    row.action:SetPoint("LEFT", row.materials, "RIGHT", 2, 0)
    row.edit = MakeButton(row, "Edit", 44, 22)
    row.edit:SetPoint("LEFT", row.action, "RIGHT", 2, 0)
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

local function NextMode(current, order)
    for index, value in ipairs(order) do
        if value == current then return order[(index % #order) + 1] end
    end
    return order[1]
end

function SF:GetDisplayItems(list)
    local filterMode = self.db.settings.filterMode
    if not FILTER_LABELS[filterMode] then filterMode = "all" end
    local sortMode = self.db.settings.sortMode
    if not SORT_LABELS[sortMode] then sortMode = "added" end

    local items = {}
    local sourceLabels = {}
    for _, item in ipairs(list.items) do
        local _, _, completed = self:GetItemProgress(item)
        if filterMode == "all" or (filterMode == "complete" and completed)
            or (filterMode == "incomplete" and not completed)
        then
            items[#items + 1] = item
            if sortMode == "source" then
                sourceLabels[item.id] = self:GetSourcePresentation(item).label
            end
        end
    end

    table.sort(items, function(left, right)
        if sortMode == "name" then
            local leftName, rightName = string.lower(left.name or ""), string.lower(right.name or "")
            if leftName ~= rightName then return leftName < rightName end
        elseif sortMode == "remaining" then
            local _, leftRemaining = self:GetItemProgress(left)
            local _, rightRemaining = self:GetItemProgress(right)
            if leftRemaining ~= rightRemaining then return leftRemaining > rightRemaining end
        elseif sortMode == "source" then
            local leftSource, rightSource = sourceLabels[left.id] or "", sourceLabels[right.id] or ""
            if leftSource ~= rightSource then return leftSource < rightSource end
        else
            local leftAdded, rightAdded = tonumber(left.addedAt) or 0, tonumber(right.addedAt) or 0
            if leftAdded ~= rightAdded then return leftAdded < rightAdded end
        end
        return (tonumber(left.id) or 0) < (tonumber(right.id) or 0)
    end)
    return items, filterMode, sortMode
end

function SF:CycleFilterMode()
    self.db.settings.filterMode = NextMode(self.db.settings.filterMode, FILTER_ORDER)
    self.itemOffset = 0
    self:NotifyChanged("filterChanged")
end

function SF:CycleSortMode()
    self.db.settings.sortMode = NextMode(self.db.settings.sortMode, SORT_ORDER)
    self.itemOffset = 0
    self:NotifyChanged("sortChanged")
end

function SF:RefreshWindow()
    if not self.window then return end
    local list = self:GetCurrentList()
    if not list then return end

    self.listNameText:SetText(list.name)
    self.listCountText:SetText(#self.db.lists .. " list" .. (#self.db.lists == 1 and "" or "s"))
    self.listAssignmentText:SetText("For: " .. self:GetListAssignmentText(list))
    self.listNoteText:SetText(list.note ~= "" and list.note or "No note")
    local assignments = list.assignedCharacters
    local isGlobal = type(assignments) ~= "table" or next(assignments) == nil
    local isAssigned = not isGlobal and self.currentCharacter
        and assignments[self.currentCharacter.guid] == true
    self.assignmentButton:SetText(isGlobal and "Everyone" or (isAssigned and "Assigned" or "Assign me"))

    local displayItems, filterMode, sortMode = self:GetDisplayItems(list)
    self.filterButton:SetText(FILTER_LABELS[filterMode])
    self.sortButton:SetText(SORT_LABELS[sortMode])
    local maxOffset = math.max(0, #displayItems - ROW_COUNT)
    self.itemOffset = math.max(0, math.min(self.itemOffset or 0, maxOffset))
    local completedCount = 0
    for _, item in ipairs(list.items) do
        local _, _, completed = self:GetItemProgress(item)
        if completed then completedCount = completedCount + 1 end
    end
    local shownText = filterMode ~= "all" and string.format(" · %d shown", #displayItems) or ""
    self.summaryText:SetText(string.format("%d of %d complete%s", completedCount, #list.items, shownText))

    for rowIndex, row in ipairs(self.itemRows) do
        local item = displayItems[self.itemOffset + rowIndex]
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
            local reagentPlan = SF:GetRecipeReagentPlan(item)
            row.materials:SetShown(reagentPlan ~= nil and reagentPlan.crafts > 0)
            row.materials:SetEnabled(reagentPlan ~= nil and reagentPlan.totalToAdd > 0)
            row.materials:SetScript("OnClick", function()
                local ok, result = SF:AddMissingRecipeReagents(item)
                if ok then
                    SF.statusText:SetText("Added " .. result .. " missing reagent" .. (result == 1 and "." or "s."))
                else
                    SF.statusText:SetText("|cffff6666" .. tostring(result) .. "|r")
                end
            end)
            row.action:SetText(source.actionText)
            row.action:SetScript("OnClick", function() SF:PerformSourceAction(item) end)
            row.edit:SetScript("OnClick", function() SF:OpenItemEditor(item) end)
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
    local displayItems = self:GetDisplayItems(list)
    self.itemOffset = math.max(0,
        math.min(math.max(0, #displayItems - ROW_COUNT), (self.itemOffset or 0) + amount))
    self:RefreshWindow()
end

function SF:CycleItemEditorTargetMode()
    if not self.itemEditor then return end
    self.itemEditor.targetMode = self.itemEditor.targetMode == "buy" and "own" or "buy"
    self.itemEditor.targetButton:SetText(self.itemEditor.targetMode == "own" and "Own Total" or "Buy More")
end

function SF:CycleItemEditorSource()
    if not self.itemEditor then return end
    local current = self.Model:NormalizeSourceMode(self.itemEditor.preferredSource)
    local nextIndex = 1
    for index, source in ipairs(SOURCE_ORDER) do
        if source == current then
            nextIndex = (index % #SOURCE_ORDER) + 1
            break
        end
    end
    self.itemEditor.preferredSource = SOURCE_ORDER[nextIndex]
    self.itemEditor.sourceButton:SetText(SOURCE_LABELS[self.itemEditor.preferredSource])
end

function SF:OpenItemEditor(item)
    if not self.itemEditor or not item then return end
    local editor = self.itemEditor
    editor.itemEntryID = item.id
    editor.targetMode = item.targetMode
    editor.preferredSource = self.Model:NormalizeSourceMode(item.preferredSource)
    editor.itemName:SetText(item.itemLink or item.name)
    editor.quantityInput:SetText(tostring(item.desired))
    editor.targetButton:SetText(editor.targetMode == "own" and "Own Total" or "Buy More")
    editor.sourceButton:SetText(SOURCE_LABELS[editor.preferredSource])
    editor.statusText:SetText("")
    editor:Show()
    editor.quantityInput:SetFocus()
    editor.quantityInput:HighlightText()
end

function SF:SaveItemEditor()
    local editor = self.itemEditor
    if not editor or not editor.itemEntryID then return end
    local ok, result = self:UpdateItem(
        editor.itemEntryID,
        tonumber(editor.quantityInput:GetText()),
        editor.targetMode,
        editor.preferredSource
    )
    if not ok then
        editor.statusText:SetText("|cffff6666" .. tostring(result) .. "|r")
        return
    end
    editor:Hide()
    self.statusText:SetText("Updated " .. result.name .. ".")
end

function SF:CreateItemEditor()
    local editor = CreateFrame("Frame", "ShoppingForeverItemEditor", UIParent, "BasicFrameTemplateWithInset")
    editor:SetSize(370, 235)
    editor:SetPoint("CENTER", self.window, "CENTER", 0, 0)
    editor:SetFrameStrata("FULLSCREEN_DIALOG")
    editor:SetClampedToScreen(true)
    editor:Hide()
    editor.TitleText:SetText("Edit shopping item")
    table.insert(UISpecialFrames, editor:GetName())
    self.itemEditor = editor

    editor.itemName = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editor.itemName:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -38)
    editor.itemName:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -18, -38)
    editor.itemName:SetJustifyH("LEFT")

    local quantityLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    quantityLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 20, -78)
    quantityLabel:SetText("Quantity")
    editor.quantityInput = MakeEditBox(editor, 100)
    editor.quantityInput:SetPoint("TOPLEFT", quantityLabel, "BOTTOMLEFT", 0, -5)
    editor.quantityInput:SetNumeric(true)
    editor.quantityInput:SetMaxLetters(7)
    editor.quantityInput:SetScript("OnEnterPressed", function() SF:SaveItemEditor() end)

    local targetLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetLabel:SetPoint("LEFT", quantityLabel, "LEFT", 115, 0)
    targetLabel:SetText("Target")
    editor.targetButton = MakeButton(editor, "Own Total", 105)
    editor.targetButton:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -5)
    editor.targetButton:SetScript("OnClick", function() SF:CycleItemEditorTargetMode() end)

    local sourceLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sourceLabel:SetPoint("LEFT", targetLabel, "LEFT", 120, 0)
    sourceLabel:SetText("Preferred source")
    editor.sourceButton = MakeButton(editor, "Automatic", 110)
    editor.sourceButton:SetPoint("TOPLEFT", sourceLabel, "BOTTOMLEFT", 0, -5)
    editor.sourceButton:SetScript("OnClick", function() SF:CycleItemEditorSource() end)

    editor.statusText = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editor.statusText:SetPoint("TOPLEFT", editor.quantityInput, "BOTTOMLEFT", 0, -12)
    editor.statusText:SetPoint("TOPRIGHT", editor.sourceButton, "BOTTOMRIGHT", 0, -12)
    editor.statusText:SetJustifyH("LEFT")

    local save = MakeButton(editor, SAVE, 80)
    save:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -96, 16)
    save:SetScript("OnClick", function() SF:SaveItemEditor() end)
    local cancel = MakeButton(editor, CANCEL, 80)
    cancel:SetPoint("LEFT", save, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function() editor:Hide() end)
end

local function FormatHistoryTime(timestamp)
    if date and tonumber(timestamp) and tonumber(timestamp) > 0 then
        return date("%m/%d %H:%M", timestamp)
    end
    return "--/-- --:--"
end

function SF:RefreshHistoryWindow()
    local historyWindow = self.historyWindow
    local list = self:GetCurrentList()
    if not historyWindow or not list then return end
    historyWindow.listName:SetText(list.name)
    local entries = self:GetAcquisitionHistory(list.id, #historyWindow.rows)
    for index, row in ipairs(historyWindow.rows) do
        local entry = entries[index]
        if entry then
            row:Show()
            row.time:SetText(FormatHistoryTime(entry.timestamp))
            row.item:SetText(entry.itemLink or entry.itemName or ("Item #" .. entry.itemID))
            row.source:SetText(HISTORY_SOURCE_LABELS[entry.source] or entry.source or "Unknown")
            row.quantity:SetText("+" .. tostring(entry.quantity))
            row.state:SetText(entry.undoneAt and "Undone" or "")
            local red, green, blue = entry.undoneAt and 0.55 or 1, entry.undoneAt and 0.55 or 1,
                entry.undoneAt and 0.55 or 1
            row.time:SetTextColor(red, green, blue)
            row.item:SetTextColor(red, green, blue)
            row.source:SetTextColor(red, green, blue)
            row.quantity:SetTextColor(entry.undoneAt and 0.55 or 0.3, entry.undoneAt and 0.55 or 1,
                entry.undoneAt and 0.55 or 0.3)
        else
            row:Hide()
        end
    end
    historyWindow.emptyText:SetShown(#entries == 0)
end

function SF:UndoLatestFromUI()
    local list = self:GetCurrentList()
    local ok, result, quantity = self:UndoLastAcquisition(list and list.id)
    if ok then
        self.statusText:SetText("Undid " .. quantity .. " acquired " .. (result.itemName or "item") .. ".")
    else
        self.statusText:SetText("|cffff6666" .. tostring(result) .. "|r")
    end
    self:RefreshHistoryWindow()
end

function SF:ShowHistoryWindow()
    if not self.historyWindow then return end
    self:RefreshHistoryWindow()
    self.historyWindow:Show()
end

function SF:CreateHistoryWindow()
    local historyWindow = CreateFrame("Frame", "ShoppingForeverHistoryFrame", UIParent,
        "BasicFrameTemplateWithInset")
    historyWindow:SetSize(540, 360)
    historyWindow:SetPoint("CENTER", self.window, "CENTER", 0, 0)
    historyWindow:SetFrameStrata("FULLSCREEN_DIALOG")
    historyWindow:SetClampedToScreen(true)
    historyWindow:Hide()
    historyWindow.TitleText:SetText("Acquisition History")
    table.insert(UISpecialFrames, historyWindow:GetName())
    self.historyWindow = historyWindow

    historyWindow.listName = historyWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    historyWindow.listName:SetPoint("TOPLEFT", historyWindow, "TOPLEFT", 18, -38)

    local headers = {
        { text = "When", x = 18, width = 86 },
        { text = "Item", x = 108, width = 225 },
        { text = "Source", x = 337, width = 95 },
        { text = "Qty", x = 436, width = 38 },
        { text = "", x = 478, width = 48 },
    }
    for _, info in ipairs(headers) do
        local header = historyWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        header:SetPoint("TOPLEFT", historyWindow, "TOPLEFT", info.x, -65)
        header:SetWidth(info.width)
        header:SetJustifyH("LEFT")
        header:SetText(info.text)
    end

    historyWindow.rows = {}
    for index = 1, 8 do
        local row = CreateFrame("Frame", nil, historyWindow)
        row:SetPoint("TOPLEFT", historyWindow, "TOPLEFT", 16, -82 - ((index - 1) * 28))
        row:SetPoint("TOPRIGHT", historyWindow, "TOPRIGHT", -16, -82 - ((index - 1) * 28))
        row:SetHeight(26)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.time:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.time:SetWidth(86)
        row.time:SetJustifyH("LEFT")
        row.item = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.item:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
        row.item:SetWidth(225)
        row.item:SetJustifyH("LEFT")
        row.item:SetWordWrap(false)
        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.source:SetPoint("LEFT", row.item, "RIGHT", 4, 0)
        row.source:SetWidth(95)
        row.source:SetJustifyH("LEFT")
        row.quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.quantity:SetPoint("LEFT", row.source, "RIGHT", 4, 0)
        row.quantity:SetWidth(38)
        row.quantity:SetJustifyH("LEFT")
        row.state = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.state:SetPoint("LEFT", row.quantity, "RIGHT", 4, 0)
        row.state:SetWidth(48)
        row.state:SetJustifyH("LEFT")
        historyWindow.rows[index] = row
    end

    historyWindow.emptyText = historyWindow:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    historyWindow.emptyText:SetPoint("CENTER", historyWindow, "CENTER", 0, 0)
    historyWindow.emptyText:SetText("No acquisitions recorded for this list.")

    local clear = MakeButton(historyWindow, "Clear", 72)
    clear:SetPoint("BOTTOMLEFT", historyWindow, "BOTTOMLEFT", 16, 16)
    clear:SetScript("OnClick", function()
        local list = SF:GetCurrentList()
        if list then StaticPopup_Show("SHOPPING_FOREVER_CLEAR_HISTORY", list.name, nil, list.id) end
    end)
    local undo = MakeButton(historyWindow, "Undo Latest", 100)
    undo:SetPoint("BOTTOMRIGHT", historyWindow, "BOTTOMRIGHT", -104, 16)
    undo:SetScript("OnClick", function() SF:UndoLatestFromUI() end)
    local close = MakeButton(historyWindow, CLOSE, 88)
    close:SetPoint("LEFT", undo, "RIGHT", 8, 0)
    close:SetScript("OnClick", function() historyWindow:Hide() end)
end

function SF:SetPortabilityStatus(message, isError)
    if not self.portabilityWindow then return end
    self.portabilityWindow.statusText:SetText((isError and "|cffff6666" or "|cff66ff99")
        .. tostring(message or "") .. "|r")
end

function SF:SetPortabilityCode(code)
    if not self.portabilityWindow then return end
    local editBox = self.portabilityWindow.codeInput
    editBox:SetText(code or "")
    editBox:SetCursorPosition(0)
end

function SF:GenerateListShareCode()
    local code, errorMessage = self:EncodeCurrentList()
    if not code then self:SetPortabilityStatus(errorMessage, true) return false end
    self:SetPortabilityCode(code)
    self:SetPortabilityStatus("List code ready · " .. #code .. " characters", false)
    return true
end

function SF:ImportListFromUI()
    local code = self.portabilityWindow and self.portabilityWindow.codeInput:GetText() or ""
    local ok, result = self:ImportListCode(code)
    if not ok then self:SetPortabilityStatus(result, true) return end
    self:SetPortabilityStatus("Imported " .. result.name .. " with " .. #result.items .. " items.", false)
end

function SF:GenerateBackupCode()
    local code, errorMessage = self:EncodeBackup()
    if not code then self:SetPortabilityStatus(errorMessage, true) return false end
    self:SetPortabilityCode(code)
    self:SetPortabilityStatus("Full backup ready · " .. #code .. " characters", false)
    return true
end

function SF:ConfirmBackupRestoreFromUI()
    local code = self.portabilityWindow and self.portabilityWindow.codeInput:GetText() or ""
    local decoded, errorMessage = self:DecodeBackupCode(code)
    if not decoded or not self:ValidateBackupSnapshot(decoded) then
        self:SetPortabilityStatus(errorMessage or "The backup contains invalid data.", true)
        return
    end
    StaticPopup_Show("SHOPPING_FOREVER_RESTORE_BACKUP", nil, nil, code)
end

function SF:RestoreBackupFromUI(code)
    local ok, result = self:RestoreBackupCode(code)
    if not ok then self:SetPortabilityStatus(result, true) return end
    self:SetPortabilityStatus("Backup restored. A safety copy of the previous data was saved.", false)
    self:SetPortabilityCode("")
end

function SF:ConfirmSafetyRestoreFromUI()
    if not self.db.safetyBackups or #self.db.safetyBackups == 0 then
        self:SetPortabilityStatus("No automatic safety copy is available.", true)
        return
    end
    StaticPopup_Show("SHOPPING_FOREVER_RESTORE_SAFETY")
end

function SF:RestoreSafetyFromUI()
    local ok, result = self:RestoreLatestSafetyBackup()
    if not ok then self:SetPortabilityStatus(result, true) return end
    self:SetPortabilityStatus("The latest safety copy was restored.", false)
    self:SetPortabilityCode("")
end

function SF:ShowPortabilityWindow()
    if not self.portabilityWindow then return end
    self.portabilityWindow:Show()
    self:GenerateListShareCode()
end

function SF:CreatePortabilityWindow()
    local window = CreateFrame("Frame", "ShoppingForeverPortabilityFrame", UIParent,
        "BasicFrameTemplateWithInset")
    window:SetSize(650, 270)
    window:SetPoint("CENTER", self.window, "CENTER", 0, 0)
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetClampedToScreen(true)
    window:Hide()
    window.TitleText:SetText("Share and Backup")
    table.insert(UISpecialFrames, window:GetName())
    self.portabilityWindow = window

    local help = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -38)
    help:SetPoint("TOPRIGHT", window, "TOPRIGHT", -18, -38)
    help:SetJustifyH("LEFT")
    help:SetText("SFL1 codes share only the selected list. SFB1 codes back up all Shopping Forever data.")

    window.codeInput = MakeEditBox(window, 600, 32)
    window.codeInput:SetPoint("TOPLEFT", window, "TOPLEFT", 20, -72)
    window.codeInput:SetMaxLetters(self.Portability.MAX_BACKUP_CODE_LENGTH)
    window.codeInput:SetScript("OnEnterPressed", function(editBox) editBox:ClearFocus() end)

    local exportList = MakeButton(window, "Export List", 92)
    exportList:SetPoint("TOPLEFT", window.codeInput, "BOTTOMLEFT", 0, -12)
    exportList:SetScript("OnClick", function() SF:GenerateListShareCode() end)
    local importList = MakeButton(window, "Import List", 92)
    importList:SetPoint("LEFT", exportList, "RIGHT", 6, 0)
    importList:SetScript("OnClick", function() SF:ImportListFromUI() end)
    local backup = MakeButton(window, "Full Backup", 96)
    backup:SetPoint("LEFT", importList, "RIGHT", 14, 0)
    backup:SetScript("OnClick", function() SF:GenerateBackupCode() end)
    local restore = MakeButton(window, "Restore", 82)
    restore:SetPoint("LEFT", backup, "RIGHT", 6, 0)
    restore:SetScript("OnClick", function() SF:ConfirmBackupRestoreFromUI() end)
    local safety = MakeButton(window, "Safety Copy", 96)
    safety:SetPoint("LEFT", restore, "RIGHT", 14, 0)
    safety:SetScript("OnClick", function() SF:ConfirmSafetyRestoreFromUI() end)

    window.statusText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.statusText:SetPoint("TOPLEFT", exportList, "BOTTOMLEFT", 0, -16)
    window.statusText:SetPoint("TOPRIGHT", window, "TOPRIGHT", -20, -16)
    window.statusText:SetJustifyH("LEFT")

    local selectAll = MakeButton(window, "Select All", 88)
    selectAll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -106, 16)
    selectAll:SetScript("OnClick", function()
        window.codeInput:SetFocus()
        window.codeInput:HighlightText()
    end)
    local close = MakeButton(window, CLOSE, 88)
    close:SetPoint("LEFT", selectAll, "RIGHT", 8, 0)
    close:SetScript("OnClick", function() window:Hide() end)
end

function SF:CreateMainWindow()
    self:InitializeDialogs()
    self.addTargetMode = "own"
    self.itemOffset = 0

    local window = CreateFrame("Frame", "ShoppingForeverFrame", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(680, 520)
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

    local noteList = MakeButton(window, "Note", 50)
    noteList:SetPoint("LEFT", deleteList, "RIGHT", 4, 0)
    noteList:SetScript("OnClick", function()
        local list = SF:GetCurrentList()
        if list then StaticPopup_Show("SHOPPING_FOREVER_LIST_NOTE", list.name, nil, list) end
    end)

    self.assignmentButton = MakeButton(window, "Everyone", 110)
    self.assignmentButton:SetPoint("LEFT", noteList, "RIGHT", 4, 0)
    self.assignmentButton:SetScript("OnClick", function()
        local list = SF:GetCurrentList()
        local ok, assigned = SF:ToggleCurrentCharacterAssignment(list and list.id)
        if ok then
            SF.statusText:SetText(assigned and "Assigned this list to this character."
                or "Removed this character assignment.")
        else
            SF.statusText:SetText("|cffff6666" .. tostring(assigned) .. "|r")
        end
    end)
    self.assignmentButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Character assignment")
        GameTooltip:AddLine("Everyone means the list can be selected automatically for every character.",
            1, 1, 1, true)
        GameTooltip:AddLine("Assigned lists are preferred automatically when that character logs in.",
            0.8, 0.8, 1, true)
        GameTooltip:Show()
    end)
    self.assignmentButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.listCountText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.listCountText:SetPoint("TOPLEFT", previousList, "BOTTOMLEFT", 0, -3)
    self.listCountText:SetWidth(65)
    self.listCountText:SetJustifyH("LEFT")

    self.listAssignmentText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.listAssignmentText:SetPoint("TOPLEFT", window, "TOPLEFT", 90, -61)
    self.listAssignmentText:SetWidth(180)
    self.listAssignmentText:SetJustifyH("LEFT")

    self.listNoteText = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.listNoteText:SetPoint("TOPLEFT", window, "TOPLEFT", 275, -61)
    self.listNoteText:SetWidth(385)
    self.listNoteText:SetJustifyH("LEFT")
    self.listNoteText:SetWordWrap(false)

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

    self.filterButton = MakeButton(window, "All", 70)
    self.filterButton:SetPoint("LEFT", addButton, "RIGHT", 7, 0)
    self.filterButton:SetScript("OnClick", function() SF:CycleFilterMode() end)
    self.filterButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Filter items")
        GameTooltip:AddLine("Cycles through all, open, and completed entries.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.filterButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.sortButton = MakeButton(window, "Added", 70)
    self.sortButton:SetPoint("LEFT", self.filterButton, "RIGHT", 5, 0)
    self.sortButton:SetScript("OnClick", function() SF:CycleSortMode() end)
    self.sortButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort items")
        GameTooltip:AddLine("Cycles through added order, name, need, and source.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.sortButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

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

    local historyButton = MakeButton(window, "History", 68, 22)
    historyButton:SetPoint("LEFT", self.pageDownButton, "RIGHT", 8, 0)
    historyButton:SetScript("OnClick", function() SF:ShowHistoryWindow() end)
    local undoButton = MakeButton(window, "Undo", 54, 22)
    undoButton:SetPoint("LEFT", historyButton, "RIGHT", 4, 0)
    undoButton:SetScript("OnClick", function() SF:UndoLatestFromUI() end)

    local shareButton = MakeButton(window, "Share", 62, 22)
    shareButton:SetPoint("LEFT", undoButton, "RIGHT", 4, 0)
    shareButton:SetScript("OnClick", function() SF:ShowPortabilityWindow() end)

    self.summaryText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.summaryText:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 330, 23)
    self.summaryText:SetWidth(130)
    self.summaryText:SetJustifyH("CENTER")

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

    self:CreateItemEditor()
    self:CreateHistoryWindow()
    self:CreatePortabilityWindow()

    self:RegisterCallback(function()
        if SF.window then SF:RefreshWindow() end
        if SF.historyWindow and SF.historyWindow:IsShown() then SF:RefreshHistoryWindow() end
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
