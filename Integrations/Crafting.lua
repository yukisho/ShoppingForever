local _, SF = ...

local function SafeCall(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, result = pcall(func, ...)
    if ok then return result end
end

local function SafeCallResults(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, first, second, third, fourth, fifth = pcall(func, ...)
    if ok then return first, second, third, fourth, fifth end
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

local function GetRecipeIDFromController(controller)
    if not controller then return nil end
    local recipeID = tonumber(controller.recipeID or controller.selectedRecipeID)
    if recipeID then return recipeID end

    local recipeInfo = controller.recipeInfo
    if type(recipeInfo) == "table" then
        recipeID = tonumber(recipeInfo.recipeID or recipeInfo.recipeIDSelected)
        if recipeID then return recipeID end
    end

    recipeID = tonumber(SafeCall(controller.GetSelectedRecipeID, controller))
    if recipeID then return recipeID end
    local info = SafeCall(controller.GetRecipeInfo, controller)
    if type(info) == "table" then return tonumber(info.recipeID) end

    local selectionBehavior = controller.selectionBehavior or controller.SelectionBehavior
        or (controller.ScrollBox and controller.ScrollBox.selectionBehavior)
    local element = selectionBehavior
        and SafeCall(selectionBehavior.GetFirstSelectedElementData, selectionBehavior)
    if type(element) == "table" then
        recipeID = tonumber(element.recipeID or element.selectedRecipeID)
        local elementInfo = element.recipeInfo or element.data
        if not recipeID and type(elementInfo) == "table" then
            recipeID = tonumber(elementInfo.recipeID or elementInfo.selectedRecipeID)
        end
        if recipeID then return recipeID end
    end
end

function SF:GetSelectedProfessionRecipeID()
    if C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
        local recipeID = tonumber(SafeCall(C_TradeSkillUI.GetSelectedRecipeID))
        if recipeID then return recipeID end
    end

    local controllers = {}
    local function AddController(controller)
        if controller then controllers[#controllers + 1] = controller end
    end
    local professionsFrame = _G.ProfessionsFrame
    local craftingPage = professionsFrame and professionsFrame.CraftingPage
    AddController(craftingPage and craftingPage.SchematicForm)
    AddController(craftingPage and craftingPage.RecipeList)
    AddController(craftingPage)
    local tradeSkillFrame = _G.TradeSkillFrame
    AddController(tradeSkillFrame and tradeSkillFrame.RecipeList)
    AddController(tradeSkillFrame and tradeSkillFrame.DetailsFrame)
    AddController(tradeSkillFrame and tradeSkillFrame.DetailsFrame
        and tradeSkillFrame.DetailsFrame.Contents)
    AddController(tradeSkillFrame)

    for _, controller in ipairs(controllers) do
        local recipeID = GetRecipeIDFromController(controller)
        if recipeID then return recipeID end
    end
    if type(_G.GetTradeSkillSelectionIndex) == "function" then
        local selectionIndex = tonumber(SafeCall(_G.GetTradeSkillSelectionIndex))
        if selectionIndex and selectionIndex > 0 then return selectionIndex end
    end
end

local function ReadCraftCount(control)
    if not control then return nil end
    for _, methodName in ipairs({ "GetNumber", "GetValue", "GetText" }) do
        local value = tonumber(SafeCall(control[methodName], control))
        if value and value >= 1 then return math.floor(value) end
    end
end

function SF:GetProfessionCraftCount()
    local controls = {}
    local function AddControl(control)
        if control then controls[#controls + 1] = control end
    end
    local professionsFrame = _G.ProfessionsFrame
    local craftingPage = professionsFrame and professionsFrame.CraftingPage
    AddControl(craftingPage and craftingPage.CreateMultipleInputBox)
    AddControl(craftingPage and craftingPage.SchematicForm
        and craftingPage.SchematicForm.CreateMultipleInputBox)
    AddControl(_G.TradeSkillInputBox)
    AddControl(_G.TradeSkillFrame and _G.TradeSkillFrame.InputBox)

    for _, control in ipairs(controls) do
        local count = ReadCraftCount(control)
        if count then return math.min(count, self.Model.MAX_QUANTITY) end
    end
    return 1
end

local function ExtractIndexedReagents(recipeKey, countFunction, infoFunction, linkFunction)
    local count = tonumber(SafeCall(countFunction, recipeKey))
    if not count or count < 1 then return nil end
    local reagents, complete = {}, true
    for index = 1, count do
        local first, _, third = SafeCallResults(infoFunction, recipeKey, index)
        local info = type(first) == "table" and first or nil
        local name = info and info.name or first
        local quantity = tonumber(info and (info.quantityRequired or info.requiredQuantity
            or info.reagentCount or info.quantity) or third) or 0
        local link = SafeCall(linkFunction, recipeKey, index)
        local itemID = tonumber(info and info.itemID)
            or SF.Model:GetItemID(info and (info.itemLink or info.hyperlink))
            or SF.Model:GetItemID(link)
            or SF.Model:GetItemID(name)
        if itemID and quantity > 0 then
            reagents[#reagents + 1] = { itemID = itemID, quantity = math.floor(quantity) }
        else
            complete = false
        end
    end
    return reagents, complete
end

function SF:GetLiveProfessionRecipe(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return nil end

    local recipeInfo = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo
        and SafeCall(C_TradeSkillUI.GetRecipeInfo, recipeID) or nil
    local recipeName = type(recipeInfo) == "table" and recipeInfo.name
        or (type(recipeInfo) == "string" and recipeInfo or nil)
    local reagents, complete

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local schematic = SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if type(schematic) == "table" then
            reagents, complete = ExtractReagents(schematic)
            if #reagents == 0 and complete == false then reagents = nil end
        end
    end
    if not reagents and C_TradeSkillUI then
        reagents, complete = ExtractIndexedReagents(recipeID,
            C_TradeSkillUI.GetRecipeNumReagents,
            C_TradeSkillUI.GetRecipeReagentInfo,
            C_TradeSkillUI.GetRecipeReagentItemLink)
    end

    if not reagents and type(_G.GetTradeSkillNumReagents) == "function" then
        reagents, complete = ExtractIndexedReagents(recipeID,
            _G.GetTradeSkillNumReagents,
            _G.GetTradeSkillReagentInfo,
            _G.GetTradeSkillReagentItemLink)
        if type(_G.GetTradeSkillInfo) == "function" then
            recipeName = SafeCall(_G.GetTradeSkillInfo, recipeID) or recipeName
        end
    end
    if not reagents then return nil end

    return {
        recipeID = recipeID,
        recipeName = recipeName,
        reagents = reagents,
        fixedReagentsComplete = complete == true,
    }
end

function SF:GetProfessionRecipeShoppingPlan(recipeID, crafts)
    recipeID = tonumber(recipeID)
    crafts = self.util.ClampWholeNumber(crafts, 1, self.Model.MAX_QUANTITY, 1)
    local recipes = self.currentCharacter and self.currentCharacter.recipes
    local recipe = self:GetLiveProfessionRecipe(recipeID)
        or (type(recipes) == "table" and recipes[tostring(recipeID)] or nil)
    if type(recipe) ~= "table" then return nil, "Select a known recipe first." end
    if recipe.fixedReagentsComplete == false or type(recipe.reagents) ~= "table"
        or #recipe.reagents == 0
    then
        return nil, "This recipe does not have a complete fixed reagent list."
    end

    local combined = {}
    for _, reagent in ipairs(recipe.reagents) do
        local itemID = tonumber(reagent.itemID)
        local quantity = math.max(0, tonumber(reagent.quantity) or 0)
        if itemID and quantity > 0 then
            combined[itemID] = (combined[itemID] or 0) + (quantity * crafts)
        end
    end

    local reagents, totalRequired, totalToAdd = {}, 0, 0
    for itemID, required in pairs(combined) do
        local resolved = self.Model:ResolveItem(itemID)
        local owned = self:GetOwnedCount(itemID)
        local missing = math.max(0, required - owned)
        local alreadyListed = GetOutstandingListQuantity(itemID)
        local toAdd = math.max(0, missing - alreadyListed)
        reagents[#reagents + 1] = {
            itemID = itemID,
            name = resolved and resolved.name or ("Item #" .. itemID),
            itemLink = resolved and resolved.itemLink or nil,
            required = required,
            owned = owned,
            missing = missing,
            alreadyListed = alreadyListed,
            toAdd = toAdd,
        }
        totalRequired = totalRequired + required
        totalToAdd = totalToAdd + toAdd
    end
    table.sort(reagents, function(left, right) return tostring(left.name) < tostring(right.name) end)
    if #reagents == 0 then return nil, "This recipe has no fixed item reagents." end

    return {
        recipe = recipe,
        recipeID = recipeID,
        crafts = crafts,
        reagents = reagents,
        totalRequired = totalRequired,
        totalToAdd = totalToAdd,
    }
end

function SF:AddProfessionRecipeReagents(recipeID, crafts)
    local plan, errorMessage = self:GetProfessionRecipeShoppingPlan(recipeID, crafts)
    if not plan then return false, errorMessage end
    if plan.totalToAdd <= 0 then
        return false, "The required reagents are already owned or listed."
    end

    local lines = {}
    for _, reagent in ipairs(plan.reagents) do
        if reagent.toAdd > 0 then
            lines[#lines + 1] = tostring(reagent.itemID) .. " " .. tostring(reagent.toAdd)
        end
    end
    local ok, entries, quantity = self:BulkAddItems(table.concat(lines, "\n"), "buy")
    if not ok then return false, entries end
    return true, quantity, entries, plan
end

function SF:RefreshProfessionShoppingButton()
    local button = self.professionShoppingButton
    if not button then return end
    local recipeID = self:GetSelectedProfessionRecipeID()
    local crafts = self:GetProfessionCraftCount()
    local plan, errorMessage = self:GetProfessionRecipeShoppingPlan(recipeID, crafts)
    button.recipeID = recipeID
    button.crafts = crafts
    button.plan = plan
    button.errorMessage = errorMessage
    if not plan then
        button:SetText("Add Reagents to List")
        button:SetEnabled(false)
    elseif plan.totalToAdd <= 0 then
        button:SetText("Reagents Covered")
        button:SetEnabled(false)
    else
        button:SetText("Add Reagents (" .. plan.totalToAdd .. ")")
        button:SetEnabled(true)
    end
end

function SF:CreateProfessionShoppingButton()
    if self.professionShoppingButton then return self.professionShoppingButton end
    local professionFrame = _G.ProfessionsFrame or _G.TradeSkillFrame
    if not professionFrame then return nil end
    local host = professionFrame.CraftingPage or professionFrame

    local button = CreateFrame("Button", "ShoppingForeverProfessionAddButton", host,
        "UIPanelButtonTemplate")
    button:SetSize(170, 24)
    local detailsFrame = host.SchematicForm or professionFrame.DetailsFrame
    local detailsContents = detailsFrame and detailsFrame.Contents
    local trackRecipe = (detailsFrame and (detailsFrame.TrackRecipeCheckBox
            or detailsFrame.TrackRecipeButton))
        or (detailsContents and (detailsContents.TrackRecipeCheckBox
            or detailsContents.TrackRecipeButton))
        or _G.TradeSkillFrameTrackRecipe
    if trackRecipe then
        button:SetPoint("RIGHT", trackRecipe, "LEFT", -12, 0)
    else
        button:SetPoint("BOTTOMRIGHT", professionFrame, "BOTTOMRIGHT", -136, 48)
    end
    self.professionShoppingButton = button

    button:SetScript("OnClick", function()
        local ok, quantity, entries = SF:AddProfessionRecipeReagents(
            SF:GetSelectedProfessionRecipeID(), SF:GetProfessionCraftCount())
        if ok then
            SF:Print("Added " .. quantity .. " reagent" .. (quantity == 1 and "" or "s")
                .. " across " .. entries .. " list " .. (entries == 1 and "entry." or "entries."))
        else
            SF:Print(quantity)
        end
        SF:RefreshProfessionShoppingButton()
    end)
    button:SetScript("OnEnter", function(frame)
        SF:RefreshProfessionShoppingButton()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add Reagents to Shopping Forever")
        local plan = frame.plan
        if not plan then
            GameTooltip:AddLine(frame.errorMessage or "Select a recipe first.", 1, 0.55, 0.4, true)
        elseif plan.totalToAdd <= 0 then
            GameTooltip:AddLine("Every required reagent is already owned or on the active list.",
                0.65, 1, 0.65, true)
        else
            GameTooltip:AddLine("Adds missing reagents for " .. plan.crafts .. " craft"
                .. (plan.crafts == 1 and "" or "s") .. " to the active list.", 1, 1, 1, true)
            for _, reagent in ipairs(plan.reagents) do
                if reagent.toAdd > 0 then
                    GameTooltip:AddDoubleLine(reagent.itemLink or reagent.name,
                        tostring(reagent.toAdd), 1, 1, 1, 0.9, 0.8, 0.35)
                end
            end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnShow", function() SF:RefreshProfessionShoppingButton() end)
    button:SetScript("OnUpdate", function(frame, elapsed)
        frame.refreshElapsed = (frame.refreshElapsed or 0) + elapsed
        if frame.refreshElapsed >= 0.25 then
            frame.refreshElapsed = 0
            SF:RefreshProfessionShoppingButton()
        end
    end)
    self:RefreshProfessionShoppingButton()
    return button
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
        "TRADE_SKILL_RECIPE_SELECTED",
        "TRADE_SKILL_DATA_SOURCE_CHANGED",
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
            SF:CreateProfessionShoppingButton()
            SF:RefreshProfessionShoppingButton()
            if SF:IsAutoOpenEnabled("profession") then SF:ShowWindowForSource("profession") end
        elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_RECIPE_SELECTED"
            or event == "TRADE_SKILL_DATA_SOURCE_CHANGED"
        then
            SF:ScanCurrentCharacterRecipes()
            SF:CreateProfessionShoppingButton()
            SF:RefreshProfessionShoppingButton()
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
