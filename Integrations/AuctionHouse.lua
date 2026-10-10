local _, SF = ...

function SF:SearchAuctionHouse(item)
    if not item then return false end
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        self:Print("Open the Auction House to search for " .. item.name .. ".")
        return false
    end

    local ok = false
    if AuctionHouseFrame.SetSearchText then
        ok = pcall(AuctionHouseFrame.SetSearchText, AuctionHouseFrame, item.name)
    elseif AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SetSearchText then
        ok = pcall(AuctionHouseFrame.SearchBar.SetSearchText, AuctionHouseFrame.SearchBar, item.name)
    end
    if not ok then
        self:Print("The Auction House search box is unavailable on this beta build.")
        return false
    end

    if AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.StartSearch then
        pcall(AuctionHouseFrame.SearchBar.StartSearch, AuctionHouseFrame.SearchBar)
    end
    return true
end

function SF:InitializeAuctionHouseIntegration()
    local frame = CreateFrame("Frame")
    self.auctionHouseEventFrame = frame
    for _, event in ipairs({
        "AUCTION_HOUSE_SHOW",
        "AUCTION_HOUSE_CLOSED",
        "COMMODITY_PURCHASED",
        "ITEM_PURCHASED",
    }) do
        pcall(frame.RegisterEvent, frame, event)
    end

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "AUCTION_HOUSE_SHOW" then
            if SF.db.settings.autoOpenAuctionHouse then SF:ShowWindowForSource("auction") end
        elseif event == "AUCTION_HOUSE_CLOSED" then
            SF:HideWindowForSource("auction")
        elseif event == "COMMODITY_PURCHASED" then
            local itemID, quantity = ...
            SF:RecordAcquisition(itemID, quantity, "auction")
        elseif event == "ITEM_PURCHASED" then
            local itemID = ...
            SF:RecordAcquisition(itemID, 1, "auction")
        end
    end)
end
