local _, SF = ...

local DEFAULT_RESULT_LIMIT = 8

local function NormalizeSearchText(value)
    value = SF.util.Trim(value)
    return (value:lower():gsub("[',:%-]", ""):gsub("%s+", " "))
end

local function AppendResults(target, source, limit)
    for _, entry in ipairs(source) do
        if #target >= limit then return end
        target[#target + 1] = entry
    end
end

function SF:InitializeItemDatabase()
    local itemDatabase = LibStub and LibStub("LibItemDB-1.0", true)
    if not itemDatabase then
        return false, "LibItemDB-1.0 is unavailable. Install and enable ItemDB."
    end
    if type(itemDatabase.IsReady) ~= "function" or not itemDatabase:IsReady() then
        return false, "ItemDB has not finished loading its item data."
    end

    self.itemDatabase = itemDatabase
    return true
end

function SF:BuildItemSearchIndex()
    if self.itemSearchIndex then return true end

    local ready, errorMessage = true
    if not self.itemDatabase then
        ready, errorMessage = self:InitializeItemDatabase()
    end
    if not ready then return false, errorMessage end

    local index = {}
    for itemID, name, quality in self.itemDatabase:Iterate() do
        if type(itemID) == "number" and type(name) == "string" and name ~= "" then
            index[#index + 1] = {
                itemID = itemID,
                name = name,
                quality = quality,
                searchName = NormalizeSearchText(name),
            }
        end
    end

    table.sort(index, function(a, b)
        if a.searchName == b.searchName then return a.itemID < b.itemID end
        return a.searchName < b.searchName
    end)

    self.itemSearchIndex = index
    self.itemSearchCache = nil
    return true
end

function SF:SearchItemNames(query, limit)
    query = NormalizeSearchText(query)
    limit = self.util.ClampWholeNumber(limit, 1, 20, DEFAULT_RESULT_LIMIT)
    if #query < 2 then return {} end

    if self.itemSearchCache and self.itemSearchCache.query == query
        and self.itemSearchCache.limit == limit
    then
        return self.itemSearchCache.results
    end

    local ready = self:BuildItemSearchIndex()
    if not ready then return {} end

    local exact, prefix, contains = {}, {}, {}
    for _, entry in ipairs(self.itemSearchIndex) do
        local matchAt = entry.searchName:find(query, 1, true)
        if matchAt then
            if entry.searchName == query then
                if #exact < limit then exact[#exact + 1] = entry end
            elseif matchAt == 1 then
                if #prefix < limit then prefix[#prefix + 1] = entry end
            elseif #contains < limit then
                contains[#contains + 1] = entry
            end
        end
    end

    local ranked = {}
    AppendResults(ranked, exact, limit)
    AppendResults(ranked, prefix, limit)
    AppendResults(ranked, contains, limit)

    local results = {}
    for _, entry in ipairs(ranked) do
        results[#results + 1] = {
            itemID = entry.itemID,
            name = entry.name,
            quality = entry.quality,
            link = self.itemDatabase:GetLink(entry.itemID),
        }
    end

    self.itemSearchCache = { query = query, limit = limit, results = results }
    return results
end
