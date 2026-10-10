local ADDON_NAME, SF = ...

local frame = CreateFrame("Frame")

local function RegisterRuntimeEvents()
    for _, event in ipairs({
        "BAG_UPDATE_DELAYED",
        "ITEM_COUNT_CHANGED",
        "PLAYERBANKSLOTS_CHANGED",
        "BANKFRAME_OPENED",
        "BANKFRAME_CLOSED",
        "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
    }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
    pcall(frame.RegisterEvent, frame, "PLAYER_LOGIN")
end

function SF:Initialize()
    self:EnsureDatabase()
    self:UpdateCurrentCharacter()
    self:CreateMainWindow()
    self:RegisterCommands()
    self:InitializeAuctionHouseIntegration()
    self:InitializeMerchantIntegration()
    self:InitializeCraftingIntegration()
    RegisterRuntimeEvents()
    self:RefreshItemInformation()
    self.initialized = true
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= ADDON_NAME then return end
        frame:UnregisterEvent("ADDON_LOADED")
        SF:Initialize()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if success then SF:RefreshItemInformation(itemID) end
    elseif event == "PLAYER_LOGIN" then
        SF:UpdateCurrentCharacter()
    elseif event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED"
        or event == "BAG_UPDATE_DELAYED" or event == "PLAYERBANKSLOTS_CHANGED"
        or event == "ITEM_COUNT_CHANGED"
        or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED"
    then
        SF:QueueInventoryRefresh()
    end
end)

frame:RegisterEvent("ADDON_LOADED")
