local _, SF = ...

local MAX_BULK_TEXT_LENGTH = 8000

local function CopyTable(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[CopyTable(key, seen)] = CopyTable(child, seen) end
    return result
end

function SF:GetUniqueListName(requested, copyLabel)
    requested = self.Model:NormalizeListName(requested)
    if not requested then return nil end
    copyLabel = self.Model:NormalizeListName(copyLabel or "Copy") or "Copy"
    local used = {}
    for _, list in ipairs(self.db.lists) do used[string.lower(list.name)] = true end
    if not used[string.lower(requested)] then return requested end
    for index = 1, 999 do
        local suffix = index == 1 and (" " .. copyLabel) or (" " .. copyLabel .. " " .. index)
        local candidate = string.sub(requested, 1, self.Model.MAX_LIST_NAME_LENGTH - #suffix) .. suffix
        if not used[string.lower(candidate)] then return candidate end
    end
end

function SF:DuplicateList(listID)
    local source = self:FindList(listID)
    if not source then return false, "List not found." end
    if #self.db.lists >= self.Model.MAX_LISTS then return false, "The list limit has been reached." end
    local name = self:GetUniqueListName(source.name)
    if not name then return false, "A unique copy name could not be created." end

    local copy = {
        id = self.db.nextListID,
        name = name,
        note = source.note,
        assignedCharacters = {},
        items = {},
    }
    local nextItemID = self.db.nextItemID
    for _, item in ipairs(source.items) do
        copy.items[#copy.items + 1] = {
            id = nextItemID,
            itemID = item.itemID,
            itemLink = item.itemLink,
            name = item.name,
            icon = item.icon,
            desired = item.desired,
            acquired = 0,
            targetMode = item.targetMode,
            preferredSource = item.preferredSource,
            manualCompleted = false,
            addedAt = time and time() or 0,
            crafting = CopyTable(item.crafting or {}),
            vendors = CopyTable(item.vendors or {}),
        }
        nextItemID = nextItemID + 1
    end
    self.db.nextListID = self.db.nextListID + 1
    self.db.nextItemID = nextItemID
    self.db.lists[#self.db.lists + 1] = copy
    self:SelectList(copy.id)
    self:NotifyChanged("listDuplicated", { sourceListID = source.id, listID = copy.id })
    return true, copy
end

function SF:ParseBulkItems(text)
    if type(text) ~= "string" or SF.util.IsSecret(text) then return nil, "Enter items to add." end
    if #text > MAX_BULK_TEXT_LENGTH then return nil, "Bulk input can be at most 8,000 characters." end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local entries, lineNumber = {}, 0
    for rawLine in string.gmatch(text .. "\n", "(.-)\n") do
        lineNumber = lineNumber + 1
        local line = SF.util.Trim(rawLine)
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            local itemInfo, quantityText = line:match("^(.-)%s+[xX](%d+)%s*$")
            if not itemInfo then itemInfo, quantityText = line:match("^(.-)%s+(%d+)%s*$") end
            itemInfo = SF.util.Trim(itemInfo or line)
            local quantity, quantityError = self.Model:NormalizeQuantity(tonumber(quantityText) or 1)
            if not quantity then return nil, "Line " .. lineNumber .. ": " .. quantityError end
            local resolved, itemError = self.Model:ResolveItem(itemInfo)
            if not resolved then return nil, "Line " .. lineNumber .. ": " .. itemError end
            entries[#entries + 1] = {
                line = lineNumber,
                itemID = resolved.itemID,
                itemInfo = resolved.itemLink or resolved.itemID,
                name = resolved.name,
                quantity = quantity,
            }
        end
    end
    if #entries == 0 then return nil, "Enter at least one item." end
    return entries
end

function SF:BulkAddItems(text, targetMode)
    local list = self:GetCurrentList()
    if not list then return false, "No list is selected." end
    targetMode = self.Model:NormalizeTargetMode(targetMode)
    local parsed, errorMessage = self:ParseBulkItems(text)
    if not parsed then return false, errorMessage end

    local existing = {}
    for _, item in ipairs(list.items) do
        existing[tostring(item.itemID) .. ":" .. item.targetMode] = item
    end
    local grouped, order = {}, {}
    for _, entry in ipairs(parsed) do
        local key = tostring(entry.itemID) .. ":" .. targetMode
        if not grouped[key] then
            grouped[key] = {
                itemID = entry.itemID,
                itemInfo = entry.itemInfo,
                name = entry.name,
                quantity = 0,
            }
            order[#order + 1] = key
        end
        grouped[key].quantity = grouped[key].quantity + entry.quantity
        if grouped[key].quantity > self.Model.MAX_QUANTITY then
            return false, entry.name .. " exceeds the per-entry quantity limit."
        end
    end

    local newEntries = 0
    for _, key in ipairs(order) do
        local entry, current = grouped[key], existing[key]
        if current then
            if current.desired + entry.quantity > self.Model.MAX_QUANTITY then
                return false, entry.name .. " would exceed the per-entry quantity limit."
            end
        else
            newEntries = newEntries + 1
        end
    end
    if #list.items + newEntries > self.Model.MAX_ITEMS_PER_LIST then
        return false, "There is not enough room on this list for every bulk item."
    end

    local originalItems, originalDesired = {}, {}
    for index, item in ipairs(list.items) do
        originalItems[index] = item
        originalDesired[item.id] = item.desired
    end
    local originalNextItemID = self.db.nextItemID
    local totalQuantity = 0
    for _, key in ipairs(order) do
        local entry = grouped[key]
        local ok, result = self:AddItem(entry.itemInfo, entry.quantity, targetMode)
        if not ok then
            list.items = originalItems
            self.db.nextItemID = originalNextItemID
            for _, item in ipairs(list.items) do item.desired = originalDesired[item.id] end
            self:NotifyChanged("bulkAddRolledBack", { listID = list.id })
            return false, result
        end
        totalQuantity = totalQuantity + entry.quantity
    end
    return true, #order, totalQuantity
end

function SF:ClearCompletedItems(listID)
    local list = self:FindList(listID)
    if not list then return false, "List not found." end
    local removed, kept = {}, {}
    for index, item in ipairs(list.items) do
        local _, _, completed = self:GetItemProgress(item)
        if completed then removed[#removed + 1] = { index = index, item = item }
        else kept[#kept + 1] = item end
    end
    if #removed == 0 then return false, "This list has no completed items." end
    list.items = kept
    self.db.lastCleanup = {
        listID = list.id,
        removed = removed,
        createdAt = time and time() or 0,
    }
    self:NotifyChanged("completedItemsCleared", { listID = list.id, count = #removed })
    return true, #removed
end

function SF:UndoLastCleanup()
    local cleanup = self.db.lastCleanup
    if type(cleanup) ~= "table" then return false, "There is no list cleanup to undo." end
    local list = self:FindList(cleanup.listID)
    if not list then return false, "The cleaned list no longer exists." end
    if type(cleanup.removed) ~= "table" or #cleanup.removed == 0 then
        self.db.lastCleanup = nil
        return false, "The saved list cleanup is invalid."
    end
    if #list.items + #cleanup.removed > self.Model.MAX_ITEMS_PER_LIST then
        return false, "The cleaned items no longer fit on their original list."
    end
    local existingTargets = {}
    for _, item in ipairs(list.items) do
        existingTargets[tostring(item.itemID) .. ":" .. item.targetMode] = true
    end
    for _, removed in ipairs(cleanup.removed) do
        if type(removed) ~= "table" or type(removed.item) ~= "table"
            or type(removed.index) ~= "number"
        then
            self.db.lastCleanup = nil
            return false, "The saved list cleanup is invalid."
        end
        local key = tostring(removed.item.itemID) .. ":" .. removed.item.targetMode
        if existingTargets[key] then
            return false, "A cleaned item was added again; remove it before undoing the cleanup."
        end
        existingTargets[key] = true
    end
    table.sort(cleanup.removed, function(left, right) return left.index < right.index end)
    for _, removed in ipairs(cleanup.removed) do
        table.insert(list.items, math.min(removed.index, #list.items + 1), removed.item)
    end
    local count = #cleanup.removed
    self.db.lastCleanup = nil
    self:SelectList(list.id)
    self:NotifyChanged("listCleanupUndone", { listID = list.id, count = count })
    return true, count, list
end

function SF:ResetListProgress(listID)
    local list = self:FindList(listID)
    if not list then return false, "List not found." end
    local changed = 0
    for _, item in ipairs(list.items) do
        if item.acquired ~= 0 or item.manualCompleted then
            item.acquired = 0
            item.manualCompleted = false
            changed = changed + 1
        end
    end
    if changed == 0 then return false, "This list has no tracked progress to reset." end
    self:NotifyChanged("listProgressReset", { listID = list.id, count = changed })
    return true, changed
end
