local _, SF = ...

local function ShowHelp()
    SF:Print("/sf - open or close Shopping Forever")
    SF:Print("/sf add ITEM_LINK [QUANTITY] - add an item to the selected list")
    SF:Print("/sf new NAME - create and select a list")
    SF:Print("/sf own | buy - set the add mode")
    SF:Print("/sf history - show acquisition history for the selected list")
    SF:Print("/sf undo - undo the latest acquisition for the selected list")
    SF:Print("/sf manage - open list-wide tools")
    SF:Print("/sf bulk - paste several item goals at once")
    SF:Print("/sf duplicate - copy the selected list with fresh progress")
    SF:Print("/sf share - open list sharing and full backup tools")
end

local function HandleCommand(message)
    message = SF.util.Trim(message or "")
    local command, argument = message:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "" or command == "show" then
        SF:ToggleWindow()
    elseif command == "hide" then
        SF:HideWindow()
    elseif command == "help" then
        ShowHelp()
    elseif command == "new" then
        local ok, result = SF:AddList(argument)
        if not ok then SF:Print(result) else SF:ShowWindow() end
    elseif command == "own" or command == "buy" then
        SF.addTargetMode = command
        if SF.targetModeButton then
            SF.targetModeButton:SetText(command == "own" and "Own Total" or "Buy More")
        end
        SF:Print("New entries will use " .. (command == "own" and "Own Total." or "Buy More."))
    elseif command == "history" then
        SF:ShowWindow()
        SF:ShowHistoryWindow()
    elseif command == "undo" then
        local list = SF:GetCurrentList()
        local ok, result, quantity = SF:UndoLastAcquisition(list and list.id)
        if ok then
            SF:Print("Undid " .. quantity .. " acquired " .. (result.itemName or "item") .. ".")
        else
            SF:Print(result)
        end
    elseif command == "share" or command == "backup" then
        SF:ShowWindow()
        SF:ShowPortabilityWindow()
    elseif command == "manage" then
        SF:ShowWindow()
        SF:ShowManageWindow()
    elseif command == "bulk" then
        SF:ShowWindow()
        SF:ShowBulkAddWindow()
    elseif command == "duplicate" then
        local list = SF:GetCurrentList()
        local ok, result = SF:DuplicateList(list and list.id)
        if ok then
            SF:ShowWindow()
            SF:Print("Created " .. result.name .. " with fresh progress.")
        else
            SF:Print(result)
        end
    elseif command == "add" then
        local itemInfo, quantity = argument:match("^(.-)%s+(%d+)%s*$")
        if not itemInfo or itemInfo == "" then itemInfo, quantity = argument, 1 end
        local ok, result, merged = SF:AddItem(itemInfo, tonumber(quantity) or 1, SF.addTargetMode)
        if not ok then
            SF:Print(result)
        else
            SF:Print((merged and "Updated " or "Added ") .. result.name .. ".")
        end
    else
        ShowHelp()
    end
end

function SF:RegisterCommands()
    _G.SLASH_SHOPPINGFOREVER1 = "/sf"
    _G.SLASH_SHOPPINGFOREVER2 = "/shoppingforever"
    SlashCmdList.SHOPPINGFOREVER = HandleCommand
end
