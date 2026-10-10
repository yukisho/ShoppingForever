local _, SF = ...

local MAX_PLAN_DEPTH = 8

local function ResolveItem(itemID)
    local resolved = SF.Model:ResolveItem(itemID)
    return {
        itemID = itemID,
        name = resolved and resolved.name or ("Item #" .. tostring(itemID)),
        itemLink = resolved and resolved.itemLink or nil,
        icon = resolved and resolved.icon or nil,
    }
end

local function FindCharacterRecipe(character, itemID)
    local selected
    if type(character) ~= "table" or type(character.recipes) ~= "table" then return nil end
    for _, recipe in pairs(character.recipes) do
        if type(recipe) == "table" and tonumber(recipe.outputItemID) == tonumber(itemID)
            and recipe.fixedReagentsComplete ~= false
            and type(recipe.reagents) == "table" and #recipe.reagents > 0
        then
            if not selected or (tonumber(recipe.recipeID) or math.huge)
                < (tonumber(selected.recipeID) or math.huge)
            then
                selected = recipe
            end
        end
    end
    return selected
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

function SF:GetExpandedRecipePlan(item)
    if type(item) ~= "table" then return nil end
    local sources = self:GetCraftingSources(item.itemID)
    local rootSource = sources.current or sources.alts[1]
    if not rootSource then return nil end
    local character = self.db.characters[rootSource.characterGUID]
    local rootRecipe = FindCharacterRecipe(character, item.itemID)
    if not rootRecipe then return nil end

    local _, remaining, completed = self:GetItemProgress(item)
    if completed then remaining = 0 end
    local available, steps, materialByID, active = {}, {}, {}, {}

    local function TakeOwned(itemID, quantity)
        if available[itemID] == nil then available[itemID] = self:GetOwnedCount(itemID) end
        local used = math.min(available[itemID], quantity)
        available[itemID] = available[itemID] - used
        return used
    end

    local function AddMaterial(itemID, required, owned, reason)
        local material = materialByID[itemID]
        if not material then
            material = ResolveItem(itemID)
            material.required = 0
            material.owned = 0
            material.missing = 0
            material.reasons = {}
            materialByID[itemID] = material
        end
        material.required = material.required + required
        material.owned = material.owned + owned
        material.missing = material.missing + math.max(0, required - owned)
        material.reasons[reason or "noRecipe"] = true
    end

    local function ExpandRecipe(recipe, needed, depth, ownedUsed)
        local outputItemID = tonumber(recipe.outputItemID)
        local outputQuantity = math.max(1, tonumber(recipe.outputQuantity) or 1)
        local crafts = math.floor((needed + outputQuantity - 1) / outputQuantity)
        local resolved = ResolveItem(outputItemID)
        steps[#steps + 1] = {
            itemID = outputItemID,
            name = resolved.name,
            itemLink = resolved.itemLink,
            recipeID = recipe.recipeID,
            professionName = recipe.professionName,
            skillLineID = recipe.skillLineID,
            needed = needed,
            crafts = crafts,
            outputQuantity = outputQuantity,
            ownedUsed = ownedUsed or 0,
            depth = depth,
        }

        local surplus = (crafts * outputQuantity) - needed
        if surplus > 0 then
            if available[outputItemID] == nil then available[outputItemID] = 0 end
            available[outputItemID] = available[outputItemID] + surplus
        end

        active[outputItemID] = true
        for _, reagent in ipairs(recipe.reagents) do
            local reagentID = tonumber(reagent.itemID)
            local perCraft = math.max(0, tonumber(reagent.quantity) or 0)
            local required = perCraft * crafts
            if reagentID and required > 0 then
                local owned = TakeOwned(reagentID, required)
                local missing = required - owned
                local childRecipe = missing > 0 and FindCharacterRecipe(character, reagentID) or nil
                if missing <= 0 then
                    AddMaterial(reagentID, required, owned, "owned")
                elseif active[reagentID] then
                    AddMaterial(reagentID, required, owned, "cycle")
                elseif depth >= MAX_PLAN_DEPTH then
                    AddMaterial(reagentID, required, owned, "depth")
                elseif childRecipe then
                    if owned > 0 then AddMaterial(reagentID, owned, owned, "ownedIntermediate") end
                    ExpandRecipe(childRecipe, missing, depth + 1, owned)
                else
                    AddMaterial(reagentID, required, owned, "noRecipe")
                end
            end
        end
        active[outputItemID] = nil
    end

    if remaining > 0 then ExpandRecipe(rootRecipe, remaining, 0, 0) end

    local materials, totalMissing, totalToAdd = {}, 0, 0
    for _, material in pairs(materialByID) do
        material.alreadyListed = GetOutstandingListQuantity(material.itemID)
        material.toAdd = math.max(0, material.missing - material.alreadyListed)
        material.crafting = self:GetCraftingSources(material.itemID)
        material.vendors = self.GetVendorSources and self:GetVendorSources(material.itemID)
            or { current = nil, known = {} }
        totalMissing = totalMissing + material.missing
        totalToAdd = totalToAdd + material.toAdd
        materials[#materials + 1] = material
    end
    table.sort(materials, function(left, right) return tostring(left.name) < tostring(right.name) end)

    return {
        source = rootSource,
        currentCharacter = sources.current ~= nil,
        character = character,
        remaining = remaining,
        steps = steps,
        materials = materials,
        totalMissing = totalMissing,
        totalToAdd = totalToAdd,
        maxDepth = MAX_PLAN_DEPTH,
    }
end

function SF:AddExpandedRecipeMaterials(item)
    local plan = self:GetExpandedRecipePlan(item)
    if not plan then return false, "No known recipe with fixed reagents is available." end
    if plan.remaining <= 0 then return false, "This item is already complete." end
    if plan.totalToAdd <= 0 then return false, "The required materials are already owned or listed." end

    local lines = {}
    for _, material in ipairs(plan.materials) do
        if material.toAdd > 0 then
            lines[#lines + 1] = tostring(material.itemID) .. " " .. tostring(material.toAdd)
        end
    end
    local ok, entries, quantity = self:BulkAddItems(table.concat(lines, "\n"), "buy")
    if not ok then return false, entries end
    return true, quantity, entries, plan
end
