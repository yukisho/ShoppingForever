local _, SF = ...

local function SafeCall(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
end

local function GetOutputItemID(outputInfo)
    if type(outputInfo) ~= "table" then return nil end
    return tonumber(outputInfo.itemID)
        or SF.Model:GetItemID(outputInfo.hyperlink)
        or SF.Model:GetItemID(outputInfo.itemLink)
end

local function ExtractReagents(schematic)
    local result = {}
    local complete = true
    local slots = type(schematic) == "table"
        and (schematic.reagentSlotSchematics or schematic.reagentSlots or schematic.reagents) or nil
    if type(slots) ~= "table" then return result, false end

    for _, slot in ipairs(slots) do
        local candidates = type(slot) == "table" and slot.reagents or nil
        if type(candidates) == "table" and #candidates == 1 then
            local reagent = candidates[1]
            local itemID = tonumber(reagent.itemID)
                or SF.Model:GetItemID(reagent.itemLink)
                or SF.Model:GetItemID(reagent.hyperlink)
            local quantity = tonumber(slot.quantityRequired or slot.requiredQuantity
                or reagent.quantityRequired or reagent.quantity) or 0
            if itemID and quantity > 0 then
                result[#result + 1] = { itemID = itemID, quantity = math.floor(quantity) }
            else
                complete = false
            end
        else
            complete = false
        end
    end
    return result, complete
end

local function GetProfessionName(info, skillLineID)
    if type(info) == "table" then
        local name = info.professionName or info.name or info.parentProfessionName
        if type(name) == "string" and name ~= "" then return name end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        return SafeCall(C_TradeSkillUI.GetTradeSkillDisplayName, skillLineID)
    end
    return "Profession"
end

function SF:ScanCurrentCharacterRecipes()
    if not self.currentCharacter or not C_TradeSkillUI then return false end
    if not C_TradeSkillUI.GetAllProfessionTradeSkillLines
        or not C_TradeSkillUI.GetProfessionInfoBySkillLineID
        or not C_TradeSkillUI.GetProfessionSpells
    then
        return false
    end

    local skillLines = SafeCall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if type(skillLines) ~= "table" then return false end

    local recipes = {}
    local professions = {}
    local observedProfession = false
    for _, skillLineID in ipairs(skillLines) do
        local info = SafeCall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        local professionID = type(info) == "table" and (info.professionID or info.profession) or nil
        local knownSpells = professionID and SafeCall(C_TradeSkillUI.GetProfessionSpells, professionID, skillLineID) or nil
        if type(knownSpells) == "table" then
            observedProfession = true
            local professionName = GetProfessionName(info, skillLineID)
            professions[tostring(skillLineID)] = {
                skillLineID = skillLineID,
                professionID = professionID,
                name = professionName,
                skillLevel = type(info) == "table" and (info.skillLevel or info.currentSkillLevel) or nil,
            }

            for _, recipeID in ipairs(knownSpells) do
                local recipeInfo = SafeCall(C_TradeSkillUI.GetRecipeInfo, recipeID)
                if recipeInfo == nil or recipeInfo.learned ~= false then
                    local outputInfo = SafeCall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
                    local outputItemID = GetOutputItemID(outputInfo)
                    if outputItemID then
                        local schematic = SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
                        local reagents, fixedReagentsComplete = ExtractReagents(schematic)
                        recipes[tostring(recipeID)] = {
                            recipeID = recipeID,
                            outputItemID = outputItemID,
                            outputQuantity = math.max(1, tonumber(outputInfo and outputInfo.quantity)
                                or tonumber(schematic and (schematic.quantityMin or schematic.outputQuantity)) or 1),
                            recipeName = type(recipeInfo) == "table" and recipeInfo.name or nil,
                            professionID = professionID,
                            professionName = professionName,
                            skillLineID = skillLineID,
                            reagents = reagents,
                            fixedReagentsComplete = fixedReagentsComplete,
                            observedAt = time and time() or 0,
                        }
                    end
                end
            end
        end
    end

    -- Some clients return the profession list before recipe data is ready. Keep
    -- the last good cache instead of briefly erasing every known recipe.
    if not observedProfession then return false end

    self.currentCharacter.professions = professions
    self.currentCharacter.recipes = recipes
    self.currentCharacter.professionsObservedAt = time and time() or 0
    self:NotifyChanged("professionsScanned")
    return true
end

function SF:GetCraftingSources(itemID)
    itemID = tonumber(itemID)
    local result = { current = nil, alts = {} }
    if not self.db or not itemID then return result end

    local currentGUID = self.currentCharacter and self.currentCharacter.guid
    local altByGUID = {}
    local function Prefer(candidate, existing)
        if not existing then return true end
        if candidate.fixedReagentsComplete ~= existing.fixedReagentsComplete then
            return candidate.fixedReagentsComplete
        end
        return (tonumber(candidate.recipeID) or math.huge)
            < (tonumber(existing.recipeID) or math.huge)
    end
    for guid, character in pairs(self.db.characters) do
        if type(character) == "table" and type(character.recipes) == "table" then
            for _, recipe in pairs(character.recipes) do
                if type(recipe) == "table" and recipe.outputItemID == itemID then
                    local source = {
                        characterGUID = guid,
                        characterName = character.name or "Unknown",
                        realm = character.realm,
                        recipeID = recipe.recipeID,
                        outputQuantity = recipe.outputQuantity or 1,
                        professionName = recipe.professionName,
                        skillLineID = recipe.skillLineID,
                        reagents = recipe.reagents or {},
                        fixedReagentsComplete = recipe.fixedReagentsComplete ~= false,
                        observedAt = recipe.observedAt,
                    }
                    if guid == currentGUID then
                        if Prefer(source, result.current) then result.current = source end
                    elseif Prefer(source, altByGUID[guid]) then
                        altByGUID[guid] = source
                    end
                end
            end
        end
    end
    for _, source in pairs(altByGUID) do result.alts[#result.alts + 1] = source end
    table.sort(result.alts, function(left, right)
        local leftName, rightName = tostring(left.characterName), tostring(right.characterName)
        if leftName ~= rightName then return leftName < rightName end
        return tostring(left.characterGUID) < tostring(right.characterGUID)
    end)
    return result
end

local function GetOutstandingListQuantity(itemID)
    local list = SF:GetCurrentList()
    local outstanding = 0
    if not list then return outstanding end
    for _, entry in ipairs(list.items) do
        if entry.itemID == itemID then
            local _, remaining, completed = SF:GetItemProgress(entry)
            if not completed then outstanding = math.max(outstanding, remaining) end
        end
    end
    return outstanding
end

function SF:GetRecipeReagentPlan(item)
    if type(item) ~= "table" then return nil end
    local sources = self:GetCraftingSources(item.itemID)
    local source = sources.current or sources.alts[1]
    if not source or source.fixedReagentsComplete == false
        or type(source.reagents) ~= "table" or #source.reagents == 0
    then
        return nil
    end

    local _, remaining, completed = self:GetItemProgress(item)
    if completed then remaining = 0 end
    local outputQuantity = math.max(1, tonumber(source.outputQuantity) or 1)
    local crafts = math.floor((remaining + outputQuantity - 1) / outputQuantity)
    local combined = {}
    for _, reagent in ipairs(source.reagents) do
        local reagentID = tonumber(reagent.itemID)
        local perCraft = math.max(0, tonumber(reagent.quantity) or 0)
        if reagentID and perCraft > 0 then
            local key = tostring(reagentID)
            local entry = combined[key] or { itemID = reagentID, perCraft = 0 }
            entry.perCraft = entry.perCraft + perCraft
            combined[key] = entry
        end
    end

    local reagents = {}
    local totalToAdd = 0
    for _, reagent in pairs(combined) do
        reagent.required = reagent.perCraft * crafts
        reagent.owned = self:GetOwnedCount(reagent.itemID)
        reagent.missing = math.max(0, reagent.required - reagent.owned)
        reagent.alreadyListed = GetOutstandingListQuantity(reagent.itemID)
        reagent.toAdd = math.max(0, reagent.missing - reagent.alreadyListed)
        local resolved = self.Model:ResolveItem(reagent.itemID)
        reagent.name = resolved and resolved.name or ("Item #" .. reagent.itemID)
        reagent.itemLink = resolved and resolved.itemLink or nil
        reagent.icon = resolved and resolved.icon or nil
        totalToAdd = totalToAdd + reagent.toAdd
        reagents[#reagents + 1] = reagent
    end
    table.sort(reagents, function(left, right)
        return tostring(left.name) < tostring(right.name)
    end)

    return {
        source = source,
        currentCharacter = sources.current ~= nil,
        crafts = crafts,
        outputQuantity = outputQuantity,
        reagents = reagents,
        totalToAdd = totalToAdd,
    }
end

function SF:AddMissingRecipeReagents(item)
    local plan = self:GetRecipeReagentPlan(item)
    if not plan then return false, "No known recipe with fixed reagents is available." end
    if plan.crafts <= 0 then return false, "This item is already complete." end
    if plan.totalToAdd <= 0 then return false, "The missing reagents are already owned or listed." end

    local list = self:GetCurrentList()
    if not list then return false, "No list is selected." end
    local newEntries = 0
    for _, reagent in ipairs(plan.reagents) do
        if reagent.toAdd > 0 then
            if reagent.toAdd > self.Model.MAX_QUANTITY then
                return false, reagent.name .. " exceeds the per-entry quantity limit."
            end
            local existing
            for _, entry in ipairs(list.items) do
                if entry.itemID == reagent.itemID and entry.targetMode == "buy" then
                    existing = entry
                    break
                end
            end
            if existing then
                if existing.desired + reagent.toAdd > self.Model.MAX_QUANTITY then
                    return false, reagent.name .. " would exceed the per-entry quantity limit."
                end
            else
                newEntries = newEntries + 1
            end
        end
    end
    if #list.items + newEntries > self.Model.MAX_ITEMS_PER_LIST then
        return false, "There is not enough room on this list for every missing reagent."
    end

    local added = 0
    for _, reagent in ipairs(plan.reagents) do
        if reagent.toAdd > 0 then
            local ok, result = self:AddItem(reagent.itemID, reagent.toAdd, "buy")
            if not ok then return false, result end
            added = added + reagent.toAdd
        end
    end
    return true, added, plan
end

function SF:OpenCraftingRecipe(source)
    if not source or not C_TradeSkillUI then return false end
    if C_TradeSkillUI.OpenTradeSkill and source.skillLineID then
        pcall(C_TradeSkillUI.OpenTradeSkill, source.skillLineID)
    end
    local function OpenRecipe()
        if C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, source.recipeID) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, OpenRecipe) else OpenRecipe() end
    return true
end

function SF:HandleCraftResult(data)
    if type(data) ~= "table" then return end
    if data.itemID or data.hyperlink or data.itemLink then
        local itemID = tonumber(data.itemID) or self.Model:GetItemID(data.hyperlink or data.itemLink)
        if itemID then self:RecordAcquisition(itemID, tonumber(data.quantity) or 1, "craft") end
        return
    end
    for _, result in ipairs(data) do self:HandleCraftResult(result) end
end

function SF:InitializeCraftingIntegration()
    local frame = CreateFrame("Frame")
    self.craftingEventFrame = frame
    for _, event in ipairs({
        "TRADE_SKILL_SHOW",
        "TRADE_SKILL_LIST_UPDATE",
        "TRADE_SKILL_CLOSE",
        "SKILL_LINES_CHANGED",
        "TRADE_SKILL_ITEM_CRAFTED_RESULT",
    }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "TRADE_SKILL_SHOW" then
            SF.tradeSkillOpen = true
            SF:ScanCurrentCharacterRecipes()
            if SF:IsAutoOpenEnabled("profession") then SF:ShowWindowForSource("profession") end
        elseif event == "TRADE_SKILL_LIST_UPDATE" then
            SF:ScanCurrentCharacterRecipes()
        elseif event == "SKILL_LINES_CHANGED" and SF.tradeSkillOpen then
            SF:ScanCurrentCharacterRecipes()
        elseif event == "TRADE_SKILL_CLOSE" then
            SF.tradeSkillOpen = false
            SF:HideWindowForSource("profession")
        elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
            SF:HandleCraftResult(...)
        end
    end)
end
