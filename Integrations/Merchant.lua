local _, SF = ...

local function GetMerchantIdentity()
    local guid = UnitGUID and UnitGUID("npc") or nil
    local name = UnitName and UnitName("npc") or nil
    return guid or name or "unknown", name or "Unknown merchant"
end

function SF:ScanMerchant()
    self.currentMerchantItems = {}
    self.currentMerchantSlots = {}
    if not GetMerchantNumItems or not C_MerchantFrame or not C_MerchantFrame.GetItemInfo then return end

    local vendorKey, vendorName = GetMerchantIdentity()
    for slot = 1, (GetMerchantNumItems() or 0) do
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, slot)
        local link = GetMerchantItemLink and GetMerchantItemLink(slot) or nil
        local itemID = self.Model:GetItemID(link)
        if ok and info and itemID then
            local observation = {
                vendorKey = vendorKey,
                vendorName = vendorName,
                slot = slot,
                itemID = itemID,
                itemLink = link,
                price = tonumber(info.price) or 0,
                stackCount = math.max(1, tonumber(info.stackCount) or 1),
                numAvailable = tonumber(info.numAvailable),
                hasExtendedCost = info.hasExtendedCost == true,
                seenAt = time and time() or 0,
            }
            self.currentMerchantItems[itemID] = observation
            self.currentMerchantSlots[slot] = observation

            local key = tostring(itemID)
            local catalog = self.db.vendorCatalog[key]
            if type(catalog) ~= "table" then catalog = {}; self.db.vendorCatalog[key] = catalog end
            catalog[vendorKey] = observation
        end
    end
    self:NotifyChanged("merchantScanned")
end

function SF:GetVendorSources(itemID)
    itemID = tonumber(itemID)
    local current = self.currentMerchantItems and self.currentMerchantItems[itemID] or nil
    local known = {}
    local catalog = self.db and self.db.vendorCatalog and self.db.vendorCatalog[tostring(itemID)]
    if type(catalog) == "table" then
        for _, observation in pairs(catalog) do known[#known + 1] = observation end
        table.sort(known, function(left, right)
            return (left.seenAt or 0) > (right.seenAt or 0)
        end)
    end
    return { current = current, known = known }
end

function SF:CaptureMerchantPurchase(slot, quantity)
    local observation = self.currentMerchantSlots and self.currentMerchantSlots[tonumber(slot) or -1]
    if not observation then
        local link = GetMerchantItemLink and GetMerchantItemLink(slot) or nil
        local itemID = self.Model:GetItemID(link)
        observation = itemID and { itemID = itemID, stackCount = 1, slot = slot } or nil
    end
    if not observation then return end

    self.pendingMerchantPurchases = self.pendingMerchantPurchases or {}
    local existing = self.pendingMerchantPurchases[observation.itemID]
    if not existing then
        self.pendingMerchantPurchases[observation.itemID] = {
            itemID = observation.itemID,
            beforeCount = self:GetOwnedCount(observation.itemID),
            requested = math.max(1, tonumber(quantity) or observation.stackCount or 1),
            capturedAt = GetTime and GetTime() or 0,
        }
    end
end

function SF:ResolveMerchantPurchases()
    if not self.pendingMerchantPurchases then return end
    for itemID, pending in pairs(self.pendingMerchantPurchases) do
        local current = self:GetOwnedCount(pending.itemID)
        local gained = current - pending.beforeCount
        if gained > 0 then
            self.pendingMerchantPurchases[itemID] = nil
            self:RecordAcquisition(pending.itemID, gained, "vendor")
        end
    end
end

function SF:InitializeMerchantIntegration()
    local frame = CreateFrame("Frame")
    self.merchantEventFrame = frame
    for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            SF:ScanMerchant()
            if SF.db.settings.autoOpenMerchant then SF:ShowWindowForSource("merchant") end
        elseif event == "MERCHANT_UPDATE" then
            SF:ScanMerchant()
        elseif event == "MERCHANT_CLOSED" then
            SF.currentMerchantItems = nil
            SF.currentMerchantSlots = nil
            SF.pendingMerchantPurchases = nil
            SF:HideWindowForSource("merchant")
            SF:NotifyChanged("merchantClosed")
        elseif event == "BAG_UPDATE_DELAYED" then
            SF:ResolveMerchantPurchases()
        end
    end)

    if hooksecurefunc and BuyMerchantItem then
        hooksecurefunc("BuyMerchantItem", function(slot, quantity)
            SF:CaptureMerchantPurchase(slot, quantity)
        end)
    end
end
