local _, SF = ...

function SF:RecordAcquisition(itemID, quantity, source)
    itemID = tonumber(itemID)
    quantity = SF.util.ClampWholeNumber(quantity, 1, SF.Model.MAX_QUANTITY, 1)
    if not itemID then return 0, quantity end

    local list = self:GetCurrentList()
    if not list then return 0, quantity end

    local remaining = quantity
    local applied = 0
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
            end
        end
    end

    if applied > 0 then
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
        action = "craft"
        actionText = "Craft"
    elseif crafting and crafting.alts and #crafting.alts > 0 then
        labels[#labels + 1] = "Alt craft"
    end

    if vendors and vendors.current then
        labels[#labels + 1] = "Vendor"
        if action ~= "craft" then
            action = "vendor"
            actionText = "Here"
        end
    elseif vendors and #vendors.known > 0 then
        labels[#labels + 1] = "Vendor"
    end

    labels[#labels + 1] = "AH"
    return {
        label = table.concat(labels, " + "),
        action = action,
        actionText = actionText,
        crafting = crafting,
        vendors = vendors,
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
end
