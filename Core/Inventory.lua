local _, SF = ...

function SF:GetOwnedCount(itemID)
    itemID = tonumber(itemID)
    if not itemID or not C_Item or not C_Item.GetItemCount then return 0 end

    local ok, count = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
    if not ok then
        ok, count = pcall(C_Item.GetItemCount, itemID, true, false, true)
    end
    if not ok then
        ok, count = pcall(C_Item.GetItemCount, itemID, true)
    end
    return ok and math.max(0, tonumber(count) or 0) or 0
end

function SF:GetItemProgress(item)
    if type(item) ~= "table" then return 0, 0, false end
    local desired = math.max(1, tonumber(item.desired) or 1)
    local current
    if item.targetMode == "own" then
        current = self:GetOwnedCount(item.itemID)
    else
        current = math.max(0, tonumber(item.acquired) or 0)
    end
    local completed = item.manualCompleted == true or current >= desired
    return current, math.max(0, desired - current), completed
end

function SF:QueueInventoryRefresh()
    self.inventoryRefreshSerial = (self.inventoryRefreshSerial or 0) + 1
    local serial = self.inventoryRefreshSerial
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
            if serial == SF.inventoryRefreshSerial then
                SF:NotifyChanged("inventoryChanged")
            end
        end)
    else
        self:NotifyChanged("inventoryChanged")
    end
end
