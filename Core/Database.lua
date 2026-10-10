local _, SF = ...

local function NewDefaultList()
    return {
        id = 1,
        name = "Shopping List",
        note = "",
        assignedCharacters = {},
        items = {},
    }
end

local function NewDatabase()
    return {
        schemaVersion = SF.schemaVersion,
        nextListID = 2,
        nextItemID = 1,
        selectedListID = 1,
        selectedListByCharacter = {},
        nextHistoryID = 1,
        history = {},
        lists = { NewDefaultList() },
        characters = {},
        vendorCatalog = {},
        settings = {
            autoOpenAuctionHouse = true,
            autoOpenMerchant = true,
            autoOpenProfession = true,
            filterMode = "all",
            sortMode = "added",
            window = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
                width = 680,
                height = 520,
            },
        },
    }
end

local function NormalizeItem(item, fallbackID)
    if type(item) ~= "table" then return nil end

    local itemID = tonumber(item.itemID)
    if not itemID or itemID < 1 then return nil end

    item.id = SF.util.ClampWholeNumber(item.id, 1, nil, fallbackID)
    item.itemID = math.floor(itemID)
    item.name = SF.util.Trim(tostring(item.name or ""))
    if item.name == "" then item.name = "Item #" .. item.itemID end
    item.itemLink = type(item.itemLink) == "string" and item.itemLink or nil
    item.icon = tonumber(item.icon)
    item.desired = SF.util.ClampWholeNumber(item.desired, 1, SF.Model.MAX_QUANTITY, 1)
    item.acquired = SF.util.ClampWholeNumber(item.acquired, 0, SF.Model.MAX_QUANTITY, 0)
    item.targetMode = SF.Model:NormalizeTargetMode(item.targetMode)
    item.preferredSource = SF.Model:NormalizeSourceMode(item.preferredSource)
    item.manualCompleted = item.manualCompleted == true
    item.addedAt = tonumber(item.addedAt) or 0
    item.crafting = type(item.crafting) == "table" and item.crafting or {}
    item.vendors = type(item.vendors) == "table" and item.vendors or {}
    return item
end

local function NormalizeDatabase(database)
    database.schemaVersion = SF.schemaVersion
    database.lists = type(database.lists) == "table" and database.lists or {}
    database.characters = type(database.characters) == "table" and database.characters or {}
    database.selectedListByCharacter = type(database.selectedListByCharacter) == "table"
        and database.selectedListByCharacter or {}
    database.history = type(database.history) == "table" and database.history or {}
    database.vendorCatalog = type(database.vendorCatalog) == "table" and database.vendorCatalog or {}
    database.settings = type(database.settings) == "table" and database.settings or {}
    database.settings.window = type(database.settings.window) == "table" and database.settings.window or {}

    local highestListID, highestItemID, highestHistoryID = 0, 0, 0
    local normalizedLists = {}
    for _, list in ipairs(database.lists) do
        if type(list) == "table" then
            local id = SF.util.ClampWholeNumber(list.id, 1, nil, highestListID + 1)
            local name = SF.Model:NormalizeListName(list.name)
            if name then
                list.id = id
                list.name = name
                list.note = type(list.note) == "string" and list.note or ""
                list.assignedCharacters = type(list.assignedCharacters) == "table" and list.assignedCharacters or {}
                list.items = type(list.items) == "table" and list.items or {}

                local items = {}
                for _, item in ipairs(list.items) do
                    item = NormalizeItem(item, highestItemID + 1)
                    if item then
                        highestItemID = math.max(highestItemID, item.id)
                        items[#items + 1] = item
                    end
                end
                list.items = items
                normalizedLists[#normalizedLists + 1] = list
                highestListID = math.max(highestListID, id)
            end
        end
    end

    if #normalizedLists == 0 then
        normalizedLists[1] = NewDefaultList()
        highestListID = 1
    end
    database.lists = normalizedLists
    database.nextListID = math.max(highestListID + 1, tonumber(database.nextListID) or 1)
    database.nextItemID = math.max(highestItemID + 1, tonumber(database.nextItemID) or 1)

    local normalizedHistory = {}
    for _, entry in ipairs(database.history) do
        if type(entry) == "table" and tonumber(entry.listID) and tonumber(entry.itemID)
            and tonumber(entry.quantity)
        then
            entry.id = SF.util.ClampWholeNumber(entry.id, 1, nil, highestHistoryID + 1)
            entry.listID = math.floor(tonumber(entry.listID))
            entry.itemID = math.floor(tonumber(entry.itemID))
            entry.quantity = SF.util.ClampWholeNumber(entry.quantity, 1, SF.Model.MAX_QUANTITY, 1)
            entry.source = type(entry.source) == "string" and entry.source or "unknown"
            entry.itemName = type(entry.itemName) == "string" and entry.itemName
                or ("Item #" .. entry.itemID)
            entry.itemLink = type(entry.itemLink) == "string" and entry.itemLink or nil
            entry.timestamp = tonumber(entry.timestamp) or 0
            entry.allocations = type(entry.allocations) == "table" and entry.allocations or {}
            entry.undoneAt = tonumber(entry.undoneAt)
            entry.undoneQuantity = tonumber(entry.undoneQuantity)
            normalizedHistory[#normalizedHistory + 1] = entry
            highestHistoryID = math.max(highestHistoryID, entry.id)
        end
    end
    database.history = normalizedHistory
    database.nextHistoryID = math.max(highestHistoryID + 1, tonumber(database.nextHistoryID) or 1)

    local selectedExists = false
    for _, list in ipairs(database.lists) do
        if list.id == database.selectedListID then selectedExists = true break end
    end
    if not selectedExists then database.selectedListID = database.lists[1].id end

    local defaults = NewDatabase().settings
    for key, value in pairs(defaults) do
        if database.settings[key] == nil then database.settings[key] = value end
    end
    local windowDefaults = defaults.window
    for key, value in pairs(windowDefaults) do
        if database.settings.window[key] == nil then database.settings.window[key] = value end
    end
end

function SF:EnsureDatabase()
    local database = ShoppingForeverDB
    if type(database) ~= "table" then
        database = NewDatabase()
        ShoppingForeverDB = database
    end
    NormalizeDatabase(database)
    self.db = database
end

function SF:GetLists()
    return self.db and self.db.lists or {}
end

function SF:GetCurrentList()
    if not self.db then return nil end
    for _, list in ipairs(self.db.lists) do
        if list.id == self.db.selectedListID then return list end
    end
    return self.db.lists[1]
end

function SF:FindList(listID)
    listID = tonumber(listID)
    for _, list in ipairs(self:GetLists()) do
        if list.id == listID then return list end
    end
end

function SF:FindItem(itemEntryID)
    itemEntryID = tonumber(itemEntryID)
    for _, list in ipairs(self:GetLists()) do
        for index, item in ipairs(list.items) do
            if item.id == itemEntryID then return item, list, index end
        end
    end
end

function SF:SelectList(listID)
    local list = self:FindList(listID)
    if not list then return false, "List not found." end
    self.db.selectedListID = list.id
    if self.currentCharacter and self.currentCharacter.guid then
        self.db.selectedListByCharacter[self.currentCharacter.guid] = list.id
    end
    self:NotifyChanged("listSelected", { listID = list.id })
    return true, list
end

function SF:SetListNote(listID, note)
    local list = self:FindList(listID)
    if not list then return false, "List not found." end
    note = SF.util.Trim(tostring(note or ""))
    if #note > 255 then return false, "List notes can be at most 255 characters." end
    list.note = note
    self:NotifyChanged("listNoteChanged", { listID = list.id })
    return true, list
end

function SF:IsListRelevantToCurrentCharacter(list)
    if type(list) ~= "table" then return false end
    local assignments = list.assignedCharacters
    if type(assignments) ~= "table" or next(assignments) == nil then return true end
    local guid = self.currentCharacter and self.currentCharacter.guid
    return guid ~= nil and assignments[guid] == true
end

function SF:ToggleCurrentCharacterAssignment(listID)
    local list = self:FindList(listID)
    local guid = self.currentCharacter and self.currentCharacter.guid
    if not list then return false, "List not found." end
    if not guid then return false, "The current character is not available yet." end

    list.assignedCharacters = type(list.assignedCharacters) == "table" and list.assignedCharacters or {}
    if next(list.assignedCharacters) == nil then
        list.assignedCharacters[guid] = true
    elseif list.assignedCharacters[guid] then
        list.assignedCharacters[guid] = nil
    else
        list.assignedCharacters[guid] = true
    end
    self:NotifyChanged("listAssignmentChanged", { listID = list.id, characterGUID = guid })
    return true, list.assignedCharacters[guid] == true
end

function SF:GetListAssignmentText(list)
    if type(list) ~= "table" or type(list.assignedCharacters) ~= "table"
        or next(list.assignedCharacters) == nil
    then
        return "All characters"
    end
    local names = {}
    for guid, assigned in pairs(list.assignedCharacters) do
        if assigned then
            local character = self.db.characters[guid]
            names[#names + 1] = character and character.name or "Unknown"
        end
    end
    table.sort(names)
    return #names > 0 and table.concat(names, ", ") or "All characters"
end

function SF:SelectBestListForCurrentCharacter()
    if not self.db or not self.currentCharacter then return end
    local guid = self.currentCharacter.guid
    local remembered = self.db.selectedListByCharacter[guid]
    local rememberedList = remembered and self:FindList(remembered) or nil
    if rememberedList and self:IsListRelevantToCurrentCharacter(rememberedList) then
        self.db.selectedListID = rememberedList.id
        return rememberedList
    end

    local globalList
    for _, list in ipairs(self.db.lists) do
        if list.assignedCharacters[guid] then
            self.db.selectedListID = list.id
            self.db.selectedListByCharacter[guid] = list.id
            return list
        elseif not globalList and next(list.assignedCharacters) == nil then
            globalList = list
        end
    end
    local selected = self:FindList(self.db.selectedListID)
    if selected and self:IsListRelevantToCurrentCharacter(selected) then
        self.db.selectedListByCharacter[guid] = selected.id
        return selected
    end
    local fallback = globalList or self.db.lists[1]
    if fallback then
        self.db.selectedListID = fallback.id
        self.db.selectedListByCharacter[guid] = fallback.id
    end
    return fallback
end

function SF:AddList(name)
    if #self.db.lists >= self.Model.MAX_LISTS then
        return false, "The list limit has been reached."
    end
    local normalizedName, nameError = self.Model:NormalizeListName(name)
    if not normalizedName then return false, nameError end
    name = normalizedName
    for _, existing in ipairs(self.db.lists) do
        if string.lower(existing.name) == string.lower(name) then
            return false, "A list with that name already exists."
        end
    end

    local list = {
        id = self.db.nextListID,
        name = name,
        note = "",
        assignedCharacters = {},
        items = {},
    }
    self.db.nextListID = self.db.nextListID + 1
    self.db.lists[#self.db.lists + 1] = list
    self.db.selectedListID = list.id
    if self.currentCharacter and self.currentCharacter.guid then
        self.db.selectedListByCharacter[self.currentCharacter.guid] = list.id
    end
    self:NotifyChanged("listAdded", { listID = list.id })
    return true, list
end

function SF:RenameList(listID, name)
    local list = self:FindList(listID)
    if not list then return false, "List not found." end
    local normalized, errorMessage = self.Model:NormalizeListName(name)
    if not normalized then return false, errorMessage end
    for _, existing in ipairs(self.db.lists) do
        if existing.id ~= list.id and string.lower(existing.name) == string.lower(normalized) then
            return false, "A list with that name already exists."
        end
    end
    list.name = normalized
    self:NotifyChanged("listRenamed", { listID = list.id })
    return true, list
end

function SF:DeleteList(listID)
    if #self.db.lists <= 1 then
        return false, "Shopping Forever must keep at least one list."
    end
    for index, list in ipairs(self.db.lists) do
        if list.id == tonumber(listID) then
            table.remove(self.db.lists, index)
            self.db.selectedListID = self.db.lists[math.min(index, #self.db.lists)].id
            for guid, selectedListID in pairs(self.db.selectedListByCharacter) do
                if selectedListID == list.id then
                    self.db.selectedListByCharacter[guid] = nil
                end
            end
            if self.currentCharacter and self.currentCharacter.guid then
                self.db.selectedListByCharacter[self.currentCharacter.guid] = self.db.selectedListID
            end
            self:NotifyChanged("listDeleted", { listID = list.id })
            return true
        end
    end
    return false, "List not found."
end

function SF:AddItem(itemInfo, quantity, targetMode)
    local list = self:GetCurrentList()
    if not list then return false, "No list is selected." end

    local normalizedQuantity, quantityError = self.Model:NormalizeQuantity(quantity)
    if not normalizedQuantity then return false, quantityError end
    local resolved, itemError = self.Model:ResolveItem(itemInfo)
    if not resolved then return false, itemError end
    targetMode = self.Model:NormalizeTargetMode(targetMode)

    for _, existing in ipairs(list.items) do
        if existing.itemID == resolved.itemID and existing.targetMode == targetMode then
            if existing.desired + normalizedQuantity > self.Model.MAX_QUANTITY then
                return false, "The combined quantity would exceed " .. self.Model.MAX_QUANTITY .. "."
            end
            existing.desired = existing.desired + normalizedQuantity
            self:NotifyChanged("itemMerged", { listID = list.id, itemID = existing.id })
            return true, existing, true
        end
    end

    if #list.items >= self.Model.MAX_ITEMS_PER_LIST then
        return false, "This list has reached its item limit."
    end

    local item = {
        id = self.db.nextItemID,
        itemID = resolved.itemID,
        itemLink = resolved.itemLink,
        name = resolved.name,
        icon = resolved.icon,
        desired = normalizedQuantity,
        acquired = 0,
        targetMode = targetMode,
        preferredSource = "any",
        manualCompleted = false,
        addedAt = time and time() or 0,
        crafting = {},
        vendors = {},
    }
    self.db.nextItemID = self.db.nextItemID + 1
    list.items[#list.items + 1] = item
    self:NotifyChanged("itemAdded", { listID = list.id, itemID = item.id })
    return true, item, false
end

function SF:RemoveItem(itemEntryID)
    local item, list, index = self:FindItem(itemEntryID)
    if not item then return false, "Item not found." end
    table.remove(list.items, index)
    self:NotifyChanged("itemRemoved", { listID = list.id, itemID = item.id })
    return true
end

function SF:SetManualCompleted(itemEntryID, completed)
    local item, list = self:FindItem(itemEntryID)
    if not item then return false, "Item not found." end
    item.manualCompleted = completed == true
    self:NotifyChanged("itemCompletionChanged", { listID = list.id, itemID = item.id })
    return true
end

function SF:AdjustAcquired(itemEntryID, amount)
    local item, list = self:FindItem(itemEntryID)
    if not item then return false, "Item not found." end
    if item.targetMode ~= "buy" then return false, "Only Buy More entries track acquisitions." end
    amount = SF.util.ClampWholeNumber(amount, -self.Model.MAX_QUANTITY, self.Model.MAX_QUANTITY, 0)
    local previous = item.acquired
    item.acquired = math.max(0, math.min(self.Model.MAX_QUANTITY, item.acquired + amount))
    local applied = item.acquired - previous
    if item.acquired < item.desired then item.manualCompleted = false end
    if applied > 0 and self.AddAcquisitionHistory then
        self:AddAcquisitionHistory(list, item, applied, "manual", {
            { itemEntryID = item.id, quantity = applied },
        })
    end
    self:NotifyChanged("itemAcquiredChanged", { listID = list.id, itemID = item.id })
    return true
end

function SF:UpdateItem(itemEntryID, desired, targetMode, preferredSource)
    local item, list = self:FindItem(itemEntryID)
    if not item then return false, "Item not found." end
    local normalizedQuantity, quantityError = self.Model:NormalizeQuantity(desired)
    if not normalizedQuantity then return false, quantityError end
    targetMode = self.Model:NormalizeTargetMode(targetMode)
    preferredSource = self.Model:NormalizeSourceMode(preferredSource)

    if targetMode ~= item.targetMode then
        for _, existing in ipairs(list.items) do
            if existing.id ~= item.id and existing.itemID == item.itemID
                and existing.targetMode == targetMode
            then
                return false, "That item already has a "
                    .. (targetMode == "own" and "Own Total" or "Buy More") .. " entry."
            end
        end
        item.targetMode = targetMode
        item.acquired = 0
        item.manualCompleted = false
    end

    item.desired = normalizedQuantity
    item.preferredSource = preferredSource
    if item.acquired > item.desired then item.acquired = item.desired end
    self:NotifyChanged("itemUpdated", { listID = list.id, itemID = item.id })
    return true, item
end

function SF:RefreshItemInformation(itemID)
    local changed = false
    for _, list in ipairs(self:GetLists()) do
        for _, item in ipairs(list.items) do
            if not itemID or item.itemID == itemID then
                changed = self.Model:RefreshItemInfo(item) or changed
            end
        end
    end
    if changed then self:NotifyChanged("itemInformationUpdated", { itemID = itemID }) end
end

function SF:UpdateCurrentCharacter()
    if not self.db or not UnitGUID then return end
    local guid = UnitGUID("player")
    if not guid then return end
    local name, realm = UnitName("player")
    realm = realm or (GetRealmName and GetRealmName()) or ""
    local character = self.db.characters[guid] or { professions = {}, recipes = {} }
    character.guid = guid
    character.name = name or "Unknown"
    character.realm = realm
    character.lastSeen = time and time() or 0
    character.professions = type(character.professions) == "table" and character.professions or {}
    character.recipes = type(character.recipes) == "table" and character.recipes or {}
    self.db.characters[guid] = character
    self.currentCharacter = character
    self:SelectBestListForCurrentCharacter()
end
