local _, SF = ...

local Model = {}
SF.Model = Model

Model.MAX_LISTS = 100
Model.MAX_ITEMS_PER_LIST = 500
Model.MAX_LIST_NAME_LENGTH = 80
Model.MAX_ITEM_NAME_LENGTH = 255
Model.MAX_QUANTITY = 1000000
Model.TARGET_MODES = { buy = true, own = true }
Model.SOURCE_MODES = { any = true, auction = true, vendor = true, craft = true }

function Model:IsWholeNumber(value, minimum, maximum)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value == math.floor(value)
        and (minimum == nil or value >= minimum)
        and (maximum == nil or value <= maximum)
end

function Model:NormalizeTargetMode(value)
    return self.TARGET_MODES[value] and value or "own"
end

function Model:NormalizeSourceMode(value)
    return self.SOURCE_MODES[value] and value or "any"
end

function Model:NormalizeListName(value)
    value = SF.util.Trim(tostring(value or ""))
    if value == "" then
        return nil, "Enter a list name."
    end
    if #value > self.MAX_LIST_NAME_LENGTH then
        return nil, "List names can be at most " .. self.MAX_LIST_NAME_LENGTH .. " characters."
    end
    return value
end

function Model:NormalizeQuantity(value)
    value = tonumber(value)
    if not self:IsWholeNumber(value, 1, self.MAX_QUANTITY) then
        return nil, "Quantity must be a whole number from 1 to " .. self.MAX_QUANTITY .. "."
    end
    return value
end

function Model:GetItemID(itemInfo)
    if type(itemInfo) == "number" then
        return itemInfo > 0 and math.floor(itemInfo) or nil
    end
    if type(itemInfo) ~= "string" or SF.util.IsSecret(itemInfo) then
        return nil
    end

    local directID = itemInfo:match("^%s*(%d+)%s*$")
    if directID then
        return tonumber(directID)
    end

    local linkedID = itemInfo:match("item:(%d+)")
    if linkedID then
        return tonumber(linkedID)
    end

    if C_Item and C_Item.GetItemInfoInstant then
        local ok, itemID = pcall(C_Item.GetItemInfoInstant, itemInfo)
        if ok and itemID then return itemID end
    end

    if SF.itemDatabase and SF.itemDatabase.GetID then
        local ok, itemID = pcall(SF.itemDatabase.GetID, SF.itemDatabase, SF.util.Trim(itemInfo))
        if ok and itemID then return itemID end
    end
end

function Model:ResolveItem(itemInfo)
    local itemID = self:GetItemID(itemInfo)
    if not itemID or itemID < 1 then
        return nil, "Enter an item name, item link, or item ID."
    end

    local name, link, icon
    if C_Item then
        if C_Item.GetItemInfo then
            local ok, resolvedName, resolvedLink, _, _, _, _, _, _, _, resolvedIcon =
                pcall(C_Item.GetItemInfo, itemInfo)
            if ok then
                name, link, icon = resolvedName, resolvedLink, resolvedIcon
            end
        end
        if not icon and C_Item.GetItemIconByID then
            local ok, resolvedIcon = pcall(C_Item.GetItemIconByID, itemID)
            if ok then icon = resolvedIcon end
        end
        if not name and C_Item.GetItemNameByID then
            local ok, resolvedName = pcall(C_Item.GetItemNameByID, itemID)
            if ok then name = resolvedName end
        end
    end


    if type(itemInfo) == "string" and itemInfo:find("|Hitem:", 1, true) then
        link = link or itemInfo
    end

    if SF.itemDatabase then
        if not name and SF.itemDatabase.GetName then
            local ok, resolvedName = pcall(SF.itemDatabase.GetName, SF.itemDatabase, itemID)
            if ok then name = resolvedName end
        end
        if not link and SF.itemDatabase.GetLink then
            local ok, resolvedLink = pcall(SF.itemDatabase.GetLink, SF.itemDatabase, itemID)
            if ok then link = resolvedLink end
        end
    end

    if not name or name == "" then
        name = "Item #" .. itemID
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
    end

    return {
        itemID = itemID,
        itemLink = link,
        name = name,
        icon = icon,
    }
end

function Model:RefreshItemInfo(item)
    if type(item) ~= "table" or not item.itemID or not C_Item then return false end

    local name, link, icon
    if C_Item.GetItemInfo then
        local ok, resolvedName, resolvedLink, _, _, _, _, _, _, _, resolvedIcon =
            pcall(C_Item.GetItemInfo, item.itemLink or item.itemID)
        if ok then
            name, link, icon = resolvedName, resolvedLink, resolvedIcon
        end
    end
    if not name then return false end

    local changed = item.name ~= name or item.itemLink ~= link or item.icon ~= icon
    item.name = name
    item.itemLink = link or item.itemLink
    item.icon = icon or item.icon
    return changed
end
