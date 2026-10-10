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
    local slots = type(schematic) == "table"
        and (schematic.reagentSlotSchematics or schematic.reagentSlots or schematic.reagents) or nil
    if type(slots) ~= "table" then return result end

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
            end
        end
    end
    return result
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
                        recipes[tostring(recipeID)] = {
                            recipeID = recipeID,
                            outputItemID = outputItemID,
                            outputQuantity = math.max(1, tonumber(outputInfo and outputInfo.quantity)
                                or tonumber(schematic and (schematic.quantityMin or schematic.outputQuantity)) or 1),
                            recipeName = type(recipeInfo) == "table" and recipeInfo.name or nil,
                            professionID = professionID,
                            professionName = professionName,
                            skillLineID = skillLineID,
                            reagents = ExtractReagents(schematic),
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
                        observedAt = recipe.observedAt,
                    }
                    if guid == currentGUID then result.current = result.current or source
                    else result.alts[#result.alts + 1] = source end
                end
            end
        end
    end
    table.sort(result.alts, function(left, right)
        return tostring(left.characterName) < tostring(right.characterName)
    end)
    return result
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
            if SF.db.settings.autoOpenProfession then SF:ShowWindowForSource("profession") end
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
