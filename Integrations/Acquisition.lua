local _, SF = ...

local MAX_HISTORY_ENTRIES = 200

function SF:AddAcquisitionHistory(list, item, quantity, source, allocations)
    if not self.db or not list or not item then return end
    local entry = {
        id = self.db.nextHistoryID,
        listID = list.id,
        itemID = item.itemID,
        itemName = item.name or ("Item #" .. tostring(item.itemID)),
        itemLink = item.itemLink,
        quantity = quantity,
        source = source or "unknown",
        timestamp = time and time() or 0,
        allocations = allocations or {},
    }
    self.db.nextHistoryID = self.db.nextHistoryID + 1
    self.db.history[#self.db.history + 1] = entry
    while #self.db.history > MAX_HISTORY_ENTRIES do table.remove(self.db.history, 1) end
    return entry
end

function SF:GetAcquisitionHistory(listID, limit)
    local result = {}
    listID = tonumber(listID)
    limit = math.max(1, tonumber(limit) or MAX_HISTORY_ENTRIES)
    for index = #self.db.history, 1, -1 do
        local entry = self.db.history[index]
        if not listID or entry.listID == listID then
            result[#result + 1] = entry
            if #result >= limit then break end
        end
    end
    return result
end

function SF:UndoAcquisition(historyID)
    historyID = tonumber(historyID)
    local historyEntry
    for _, entry in ipairs(self.db.history) do
        if entry.id == historyID then historyEntry = entry break end
    end
    if not historyEntry then return false, "History entry not found." end
    if historyEntry.undoneAt then return false, "That acquisition has already been undone." end

    local reversed = 0
    for _, allocation in ipairs(historyEntry.allocations or {}) do
        local item, list = self:FindItem(allocation.itemEntryID)
        if item and list.id == historyEntry.listID and item.itemID == historyEntry.itemID
            and item.targetMode == "buy"
        then
            local amount = math.min(item.acquired or 0, tonumber(allocation.quantity) or 0)
            if amount > 0 then
                item.acquired = item.acquired - amount
                item.manualCompleted = false
                reversed = reversed + amount
            end
        end
    end
    if reversed <= 0 then return false, "That acquisition can no longer be undone." end

    historyEntry.undoneAt = time and time() or 0
    historyEntry.undoneQuantity = reversed
    self:NotifyChanged("acquisitionUndone", {
        listID = historyEntry.listID,
        itemID = historyEntry.itemID,
        quantity = reversed,
        historyID = historyEntry.id,
    })
    return true, historyEntry, reversed
end

function SF:UndoLastAcquisition(listID)
    listID = tonumber(listID) or (self:GetCurrentList() and self:GetCurrentList().id)
    for index = #self.db.history, 1, -1 do
        local entry = self.db.history[index]
        if entry.listID == listID and not entry.undoneAt then
            local ok, result, quantity = self:UndoAcquisition(entry.id)
            if ok then return true, result, quantity end
        end
    end
    return false, "There is no reversible acquisition for this list."
end

function SF:RecordAcquisition(itemID, quantity, source)
    itemID = tonumber(itemID)
    quantity = SF.util.ClampWholeNumber(quantity, 1, SF.Model.MAX_QUANTITY, 1)
    if not itemID then return 0, quantity end

    local list = self:GetCurrentList()
    if not list then return 0, quantity end

    local remaining = quantity
    local applied = 0
    local allocations = {}
    local historyItem
    for _, item in ipairs(list.items) do
        if remaining <= 0 then break end
        if item.itemID == itemID and item.targetMode == "buy" and not item.manualCompleted then
            local needed = math.max(0, item.desired - (item.acquired or 0))
            local amount = math.min(needed, remaining)
            if amount > 0 then
                item.acquired = (item.acquired or 0) + amount
                item.lastSource = source or "unknown"
                item.lastAcquiredAt = time and time() or 0
                remaining = remaining - amount
                applied = applied + amount
                historyItem = historyItem or item
                allocations[#allocations + 1] = { itemEntryID = item.id, quantity = amount }
            end
        end
    end

    if applied > 0 then
        self:AddAcquisitionHistory(list, historyItem, applied, source, allocations)
        self:NotifyChanged("acquisitionRecorded", {
            listID = list.id,
            itemID = itemID,
            quantity = applied,
            source = source,
        })
    else
        self:QueueInventoryRefresh()
    end
    return applied, remaining
end

function SF:GetSourcePresentation(item)
    local crafting = self.GetCraftingSources and self:GetCraftingSources(item.itemID) or nil
    local vendors = self.GetVendorSources and self:GetVendorSources(item.itemID) or nil
    local labels = {}
    local action = "auction"
    local actionText = "AH"

    if crafting and crafting.current then
        labels[#labels + 1] = "Craft"
    elseif crafting and crafting.alts and #crafting.alts > 0 then
        labels[#labels + 1] = "Alt craft"
    end

    if vendors and vendors.current then
        labels[#labels + 1] = "Vendor"
    elseif vendors and #vendors.known > 0 then
        labels[#labels + 1] = "Vendor"
    end

    labels[#labels + 1] = "AH"

    local preferred = self.Model:NormalizeSourceMode(item.preferredSource)
    if preferred == "craft" then
        if crafting and crafting.current then action, actionText = "craft", "Craft" end
    elseif preferred == "vendor" then
        if vendors and vendors.current then action, actionText = "vendor", "Here" end
    elseif preferred == "auction" then
        action, actionText = "auction", "AH"
    elseif crafting and crafting.current then
        action, actionText = "craft", "Craft"
    elseif vendors and vendors.current then
        action, actionText = "vendor", "Here"
    end

    return {
        label = table.concat(labels, " + "),
        action = action,
        actionText = actionText,
        crafting = crafting,
        vendors = vendors,
        preferred = preferred,
    }
end

function SF:PerformSourceAction(item)
    local presentation = self:GetSourcePresentation(item)
    if presentation.action == "craft" and presentation.crafting.current then
        return self:OpenCraftingRecipe(presentation.crafting.current)
    elseif presentation.action == "vendor" and presentation.vendors.current then
        local vendor = presentation.vendors.current
        self:Print(item.name .. " is available from " .. (vendor.vendorName or "this vendor")
            .. " in slot " .. tostring(vendor.slot) .. ".")
        return true
    end
    return self:SearchAuctionHouse(item)
end

function SF:AddSourceTooltipLines(tooltip, item)
    local presentation = self:GetSourcePresentation(item)
    local crafting = presentation.crafting
    local vendors = presentation.vendors

    tooltip:AddLine(" ")
    tooltip:AddLine("Shopping Forever sources", 1, 0.82, 0)
    local preferredLabels = { any = "Automatic", auction = "Auction House", vendor = "Vendor", craft = "Craft" }
    tooltip:AddLine("Preferred: " .. (preferredLabels[presentation.preferred] or "Automatic"), 0.8, 0.8, 1)
    if crafting and crafting.current then
        tooltip:AddLine("Craft: " .. (crafting.current.professionName or "known profession")
            .. " on this character", 0.3, 1, 0.3)
    elseif crafting and crafting.alts and #crafting.alts > 0 then
        local names = {}
        for _, source in ipairs(crafting.alts) do names[#names + 1] = source.characterName end
        tooltip:AddLine("Craft on: " .. table.concat(names, ", "), 0.5, 0.85, 1)
    else
        tooltip:AddLine("Craft: no known character recipe", 0.65, 0.65, 0.65)
    end

    if vendors and vendors.current then
        tooltip:AddLine("Vendor: available here from " .. (vendors.current.vendorName or "current merchant"), 0.3, 1, 0.3)
    elseif vendors and #vendors.known > 0 then
        tooltip:AddLine("Known vendor: " .. (vendors.known[1].vendorName or "previously visited merchant"), 0.8, 0.8, 1)
    else
        tooltip:AddLine("Vendor: no source observed yet", 0.65, 0.65, 0.65)
    end
    tooltip:AddLine("Auction House: search when the Auction House is open", 0.8, 0.8, 1)

    local plan = self.GetRecipeReagentPlan and self:GetRecipeReagentPlan(item) or nil
    if plan and plan.crafts > 0 then
        local crafter = plan.currentCharacter and "this character"
            or (plan.source.characterName or "an alternate character")
        tooltip:AddLine(" ")
        tooltip:AddLine("Materials for " .. plan.crafts .. " craft" .. (plan.crafts == 1 and "" or "s")
            .. " on " .. crafter, 1, 0.82, 0)
        for _, reagent in ipairs(plan.reagents) do
            local label = reagent.itemLink or reagent.name
            local detail = tostring(reagent.owned) .. "/" .. tostring(reagent.required)
            if reagent.missing > 0 then detail = detail .. " (missing " .. reagent.missing .. ")" end
            if reagent.alreadyListed > 0 then detail = detail .. ", " .. reagent.alreadyListed .. " listed" end
            tooltip:AddDoubleLine(label, detail, 1, 1, 1,
                reagent.missing > 0 and 1 or 0.3, reagent.missing > 0 and 0.65 or 1, 0.3)
        end
    end
end
