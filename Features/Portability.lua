local _, SF = ...

local LIST_PREFIX = "SFL1:"
local BACKUP_PREFIX = "SFB1:"
local LIST_FORMAT_VERSION = 1
local BACKUP_FORMAT_VERSION = 1
local MAX_LIST_CODE_LENGTH = 100000
local MAX_BACKUP_CODE_LENGTH = 500000
local MAX_LINK_LENGTH = 2048
local MAX_SERIALIZED_ENTRIES = 100000
local MAX_SERIALIZED_DEPTH = 32
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local DECODE = {}
local TARGET_VALUE = { buy = 0, own = 1 }
local TARGET_NAME = { [0] = "buy", [1] = "own" }
local SOURCE_VALUE = { any = 0, auction = 1, vendor = 2, craft = 3 }
local SOURCE_NAME = { [0] = "any", [1] = "auction", [2] = "vendor", [3] = "craft" }

SF.Portability = {
    LIST_PREFIX = LIST_PREFIX,
    BACKUP_PREFIX = BACKUP_PREFIX,
    MAX_LIST_CODE_LENGTH = MAX_LIST_CODE_LENGTH,
    MAX_BACKUP_CODE_LENGTH = MAX_BACKUP_CODE_LENGTH,
}

for index = 1, #ALPHABET do
    DECODE[string.sub(ALPHABET, index, index)] = index - 1
end

local function EncodeBase64(value)
    local result = {}
    for position = 1, #value, 3 do
        local first = string.byte(value, position)
        local second = string.byte(value, position + 1)
        local third = string.byte(value, position + 2)
        local packed = (first * 65536) + ((second or 0) * 256) + (third or 0)
        local a = math.floor(packed / 262144)
        local b = math.floor(packed / 4096) % 64
        local c = math.floor(packed / 64) % 64
        local d = packed % 64
        result[#result + 1] = string.sub(ALPHABET, a + 1, a + 1)
        result[#result + 1] = string.sub(ALPHABET, b + 1, b + 1)
        if second then result[#result + 1] = string.sub(ALPHABET, c + 1, c + 1) end
        if third then result[#result + 1] = string.sub(ALPHABET, d + 1, d + 1) end
    end
    return table.concat(result)
end

local function DecodeBase64(value)
    if type(value) ~= "string" or value == "" or #value % 4 == 1 then return nil end
    local result = {}
    for position = 1, #value, 4 do
        local first = DECODE[string.sub(value, position, position)]
        local second = DECODE[string.sub(value, position + 1, position + 1)]
        local thirdCharacter = string.sub(value, position + 2, position + 2)
        local fourthCharacter = string.sub(value, position + 3, position + 3)
        local third = thirdCharacter ~= "" and DECODE[thirdCharacter] or nil
        local fourth = fourthCharacter ~= "" and DECODE[fourthCharacter] or nil
        if first == nil or second == nil or (thirdCharacter ~= "" and third == nil)
            or (fourthCharacter ~= "" and fourth == nil)
        then
            return nil
        end
        local packed = (first * 262144) + (second * 4096) + ((third or 0) * 64) + (fourth or 0)
        result[#result + 1] = string.char(math.floor(packed / 65536) % 256)
        if third ~= nil then result[#result + 1] = string.char(math.floor(packed / 256) % 256) end
        if fourth ~= nil then result[#result + 1] = string.char(packed % 256) end
    end
    return table.concat(result)
end

local function AppendU16(parts, value)
    parts[#parts + 1] = string.char(math.floor(value / 256) % 256, value % 256)
end

local function AppendU32(parts, value)
    parts[#parts + 1] = string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256
    )
end

local function AppendString(parts, value)
    AppendU16(parts, #value)
    if value ~= "" then parts[#parts + 1] = value end
end

local function Checksum(value)
    local first, second = 1, 0
    for index = 1, #value do
        first = (first + string.byte(value, index)) % 65521
        second = (second + first) % 65521
    end
    return (second * 65536) + first
end

local function AddChecksum(body)
    local result = { body }
    AppendU32(result, Checksum(body))
    return table.concat(result)
end

local function VerifyChecksum(payload)
    if type(payload) ~= "string" or #payload < 5 then return nil end
    local bodyLength = #payload - 4
    local a, b, c, d = string.byte(payload, bodyLength + 1, #payload)
    if not a or not b or not c or not d then return nil end
    local expected = (a * 16777216) + (b * 65536) + (c * 256) + d
    local body = string.sub(payload, 1, bodyLength)
    return Checksum(body) == expected and body or nil
end

local function MakeReader(payload)
    local reader = { payload = payload, position = 1 }
    function reader:Byte()
        local value = string.byte(self.payload, self.position)
        self.position = self.position + 1
        return value
    end
    function reader:U16()
        local first, second = self:Byte(), self:Byte()
        return first and second and ((first * 256) + second) or nil
    end
    function reader:U32()
        local first, second, third, fourth = self:Byte(), self:Byte(), self:Byte(), self:Byte()
        return first and second and third and fourth
            and ((first * 16777216) + (second * 65536) + (third * 256) + fourth) or nil
    end
    function reader:String(maxLength, allowEmpty)
        local length = self:U16()
        if not length or length > maxLength or (length == 0 and not allowEmpty)
            or self.position + length - 1 > #self.payload
        then
            return nil
        end
        local value = string.sub(self.payload, self.position, self.position + length - 1)
        self.position = self.position + length
        return value
    end
    function reader:IsDone()
        return self.position == #self.payload + 1
    end
    return reader
end

local function IsCleanText(value, maximum, allowEmpty)
    return type(value) == "string" and #value <= maximum and (allowEmpty or value ~= "")
        and not string.find(value, "[%z\1-\31\127]")
end

function SF:EncodeCurrentList()
    local list = self:GetCurrentList()
    if not list then return nil, "No list is selected." end
    if not IsCleanText(list.name, self.Model.MAX_LIST_NAME_LENGTH, false)
        or not IsCleanText(list.note or "", 255, true) or #list.items > self.Model.MAX_ITEMS_PER_LIST
    then
        return nil, "The selected list contains data that cannot be shared."
    end

    local parts = { string.char(LIST_FORMAT_VERSION) }
    AppendString(parts, list.name)
    AppendString(parts, list.note or "")
    AppendU16(parts, #list.items)
    for _, item in ipairs(list.items) do
        local targetValue = TARGET_VALUE[item.targetMode]
        local sourceValue = SOURCE_VALUE[item.preferredSource or "any"]
        local itemName = item.name or ("Item #" .. tostring(item.itemID))
        local itemLink = item.itemLink or ""
        if not self.Model:IsWholeNumber(item.itemID, 1, 4294967295)
            or not self.Model:IsWholeNumber(item.desired, 1, self.Model.MAX_QUANTITY)
            or targetValue == nil or sourceValue == nil
            or not IsCleanText(itemName, self.Model.MAX_ITEM_NAME_LENGTH, false)
            or #itemLink > MAX_LINK_LENGTH
        then
            return nil, "The selected list contains an invalid item."
        end
        AppendU32(parts, item.itemID)
        AppendU32(parts, item.desired)
        parts[#parts + 1] = string.char(targetValue, sourceValue)
        AppendString(parts, itemName)
        AppendString(parts, itemLink)
    end
    local code = LIST_PREFIX .. EncodeBase64(AddChecksum(table.concat(parts)))
    if #code > MAX_LIST_CODE_LENGTH then return nil, "The share code is too long." end
    return code
end

function SF:DecodeListCode(code)
    code = SF.util.Trim(code or "")
    if #code > MAX_LIST_CODE_LENGTH then return nil, "The share code is too long." end
    if string.sub(code, 1, #LIST_PREFIX) ~= LIST_PREFIX then
        return nil, "List codes must begin with " .. LIST_PREFIX
    end
    local payload = DecodeBase64(string.sub(code, #LIST_PREFIX + 1))
    local body = payload and VerifyChecksum(payload)
    if not body then return nil, "The share code is damaged or invalid." end
    local reader = MakeReader(body)
    if reader:Byte() ~= LIST_FORMAT_VERSION then return nil, "This list-code version is not supported." end
    local name = reader:String(self.Model.MAX_LIST_NAME_LENGTH, false)
    local note = reader:String(255, true)
    local itemCount = reader:U16()
    if not IsCleanText(name, self.Model.MAX_LIST_NAME_LENGTH, false)
        or not IsCleanText(note, 255, true) or not itemCount
        or itemCount > self.Model.MAX_ITEMS_PER_LIST
    then
        return nil, "The share code contains invalid list data."
    end
    local items = {}
    local seenTargets = {}
    for _ = 1, itemCount do
        local itemID, desired = reader:U32(), reader:U32()
        local targetMode, preferredSource = TARGET_NAME[reader:Byte()], SOURCE_NAME[reader:Byte()]
        local itemName = reader:String(self.Model.MAX_ITEM_NAME_LENGTH, false)
        local itemLink = reader:String(MAX_LINK_LENGTH, true)
        if not self.Model:IsWholeNumber(itemID, 1, 4294967295)
            or not self.Model:IsWholeNumber(desired, 1, self.Model.MAX_QUANTITY)
            or not targetMode or not preferredSource
            or not IsCleanText(itemName, self.Model.MAX_ITEM_NAME_LENGTH, false) or itemLink == nil
        then
            return nil, "The share code contains invalid item data."
        end
        if itemLink ~= "" and self.Model:GetItemID(itemLink) ~= itemID then itemLink = "" end
        local targetKey = tostring(itemID) .. ":" .. targetMode
        if seenTargets[targetKey] then return nil, "The share code contains duplicate item goals." end
        seenTargets[targetKey] = true
        items[#items + 1] = {
            itemID = itemID,
            desired = desired,
            targetMode = targetMode,
            preferredSource = preferredSource,
            name = itemName,
            itemLink = itemLink ~= "" and itemLink or nil,
        }
    end
    if not reader:IsDone() then return nil, "The share code contains extra data." end
    return { name = name, note = note, items = items }
end

local function UniqueListName(database, requested, maximum)
    local used = {}
    for _, list in ipairs(database.lists) do used[string.lower(list.name)] = true end
    if not used[string.lower(requested)] then return requested end
    local base = requested
    for index = 1, 999 do
        local suffix = index == 1 and " Imported" or (" Imported " .. index)
        local candidate = string.sub(base, 1, maximum - #suffix) .. suffix
        if not used[string.lower(candidate)] then return candidate end
    end
end

function SF:ImportListCode(code)
    if #self.db.lists >= self.Model.MAX_LISTS then return false, "The list limit has been reached." end
    local decoded, errorMessage = self:DecodeListCode(code)
    if not decoded then return false, errorMessage end
    local name = UniqueListName(self.db, decoded.name, self.Model.MAX_LIST_NAME_LENGTH)
    if not name then return false, "A unique imported-list name could not be created." end
    local list = {
        id = self.db.nextListID,
        name = name,
        note = decoded.note,
        assignedCharacters = {},
        items = {},
    }
    local nextItemID = self.db.nextItemID
    for _, imported in ipairs(decoded.items) do
        local resolved = self.Model:ResolveItem(imported.itemID)
        list.items[#list.items + 1] = {
            id = nextItemID,
            itemID = imported.itemID,
            itemLink = (resolved and resolved.itemLink) or imported.itemLink,
            name = (resolved and resolved.name) or imported.name,
            icon = resolved and resolved.icon or nil,
            desired = imported.desired,
            acquired = 0,
            targetMode = imported.targetMode,
            preferredSource = imported.preferredSource,
            manualCompleted = false,
            addedAt = time and time() or 0,
            crafting = {},
            vendors = {},
        }
        nextItemID = nextItemID + 1
    end
    self.db.nextListID = self.db.nextListID + 1
    self.db.nextItemID = nextItemID
    self.db.lists[#self.db.lists + 1] = list
    self:SelectList(list.id)
    self:NotifyChanged("listImported", { listID = list.id, itemCount = #list.items })
    return true, list
end

local function SortKeys(keys)
    local order = { number = 1, string = 2, boolean = 3 }
    table.sort(keys, function(left, right)
        local leftType, rightType = type(left), type(right)
        if leftType ~= rightType then return order[leftType] < order[rightType] end
        if leftType == "number" then return left < right end
        return tostring(left) < tostring(right)
    end)
end

local function Serialize(root)
    local parts = { string.char(BACKUP_FORMAT_VERSION) }
    local visited, entryCount = {}, 0
    local function Write(value, depth)
        if depth > MAX_SERIALIZED_DEPTH then return false end
        local valueType = type(value)
        if valueType == "nil" then
            parts[#parts + 1] = "N"
        elseif valueType == "boolean" then
            parts[#parts + 1] = value and "T" or "F"
        elseif valueType == "number" then
            if value ~= value or value == math.huge or value == -math.huge then return false end
            local encoded = tostring(value)
            parts[#parts + 1] = "D"
            AppendU32(parts, #encoded)
            parts[#parts + 1] = encoded
        elseif valueType == "string" then
            parts[#parts + 1] = "S"
            AppendU32(parts, #value)
            parts[#parts + 1] = value
        elseif valueType == "table" then
            if visited[value] then return false end
            visited[value] = true
            local keys = {}
            for key in pairs(value) do
                local keyType = type(key)
                if keyType ~= "number" and keyType ~= "string" and keyType ~= "boolean" then return false end
                keys[#keys + 1] = key
            end
            entryCount = entryCount + #keys
            if entryCount > MAX_SERIALIZED_ENTRIES then return false end
            SortKeys(keys)
            parts[#parts + 1] = "A"
            AppendU32(parts, #keys)
            for _, key in ipairs(keys) do
                if not Write(key, depth + 1) or not Write(value[key], depth + 1) then return false end
            end
            visited[value] = nil
        else
            return false
        end
        return true
    end
    if not Write(root, 0) then return nil end
    return AddChecksum(table.concat(parts))
end

local function Deserialize(payload)
    local body = VerifyChecksum(payload)
    if not body then return nil end
    local reader = MakeReader(body)
    if reader:Byte() ~= BACKUP_FORMAT_VERSION then return nil end
    local entryCount = 0
    local Read
    Read = function(depth)
        if depth > MAX_SERIALIZED_DEPTH then return nil, false end
        local tag = reader:Byte()
        if tag == string.byte("N") then return nil, true end
        if tag == string.byte("T") then return true, true end
        if tag == string.byte("F") then return false, true end
        if tag == string.byte("D") or tag == string.byte("S") then
            local length = reader:U32()
            if not length or length > MAX_BACKUP_CODE_LENGTH
                or reader.position + length - 1 > #reader.payload
            then
                return nil, false
            end
            local value = string.sub(reader.payload, reader.position, reader.position + length - 1)
            reader.position = reader.position + length
            if tag == string.byte("D") then
                value = tonumber(value)
                return value, value ~= nil
            end
            return value, true
        end
        if tag == string.byte("A") then
            local count = reader:U32()
            if not count then return nil, false end
            entryCount = entryCount + count
            if entryCount > MAX_SERIALIZED_ENTRIES then return nil, false end
            local result = {}
            for _ = 1, count do
                local key, keyOK = Read(depth + 1)
                local value, valueOK = Read(depth + 1)
                local keyType = type(key)
                if not keyOK or not valueOK
                    or (keyType ~= "number" and keyType ~= "string" and keyType ~= "boolean")
                then
                    return nil, false
                end
                result[key] = value
            end
            return result, true
        end
        return nil, false
    end
    local result, ok = Read(0)
    return ok and reader:IsDone() and result or nil
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[DeepCopy(key, seen)] = DeepCopy(child, seen) end
    return result
end

function SF:BuildBackupSnapshot()
    local fields = {
        "schemaVersion", "nextListID", "nextItemID", "selectedListID",
        "selectedListByCharacter", "nextHistoryID", "lists", "characters",
        "vendorCatalog", "history", "settings",
    }
    local snapshot = {}
    for _, field in ipairs(fields) do snapshot[field] = DeepCopy(self.db[field]) end
    return snapshot
end

function SF:EncodeBackup()
    local payload = Serialize(self:BuildBackupSnapshot())
    if not payload then return nil, "The current data could not be serialized." end
    local code = BACKUP_PREFIX .. EncodeBase64(payload)
    if #code > MAX_BACKUP_CODE_LENGTH then return nil, "The backup code is too long." end
    return code
end

function SF:DecodeBackupCode(code)
    code = SF.util.Trim(code or "")
    if #code > MAX_BACKUP_CODE_LENGTH then return nil, "The backup code is too long." end
    if string.sub(code, 1, #BACKUP_PREFIX) ~= BACKUP_PREFIX then
        return nil, "Backup codes must begin with " .. BACKUP_PREFIX
    end
    local payload = DecodeBase64(string.sub(code, #BACKUP_PREFIX + 1))
    local decoded = payload and Deserialize(payload)
    if type(decoded) ~= "table" then return nil, "The backup code is damaged or invalid." end
    return decoded
end

function SF:ValidateBackupSnapshot(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.lists) ~= "table"
        or #snapshot.lists < 1 or #snapshot.lists > self.Model.MAX_LISTS
        or type(snapshot.characters) ~= "table" or type(snapshot.vendorCatalog) ~= "table"
        or type(snapshot.history) ~= "table" or #snapshot.history > 200
        or type(snapshot.settings) ~= "table"
    then
        return false
    end
    local listIDs, itemEntryIDs = {}, {}
    for _, list in ipairs(snapshot.lists) do
        if type(list) ~= "table" or not self.Model:IsWholeNumber(list.id, 1)
            or listIDs[list.id] or not IsCleanText(list.name, self.Model.MAX_LIST_NAME_LENGTH, false)
            or not IsCleanText(list.note or "", 255, true)
            or type(list.items) ~= "table" or #list.items > self.Model.MAX_ITEMS_PER_LIST
        then
            return false
        end
        listIDs[list.id] = true
        for _, item in ipairs(list.items) do
            if type(item) ~= "table" or not self.Model:IsWholeNumber(item.id, 1)
                or itemEntryIDs[item.id]
                or not self.Model:IsWholeNumber(item.itemID, 1, 4294967295)
                or not self.Model:IsWholeNumber(item.desired, 1, self.Model.MAX_QUANTITY)
                or not self.Model:IsWholeNumber(item.acquired or 0, 0, self.Model.MAX_QUANTITY)
                or not self.Model.TARGET_MODES[item.targetMode]
                or not self.Model.SOURCE_MODES[item.preferredSource or "any"]
            then
                return false
            end
            itemEntryIDs[item.id] = true
        end
    end
    return listIDs[tonumber(snapshot.selectedListID)] == true
end

function SF:RestoreBackupCode(code)
    local decoded, errorMessage = self:DecodeBackupCode(code)
    if not decoded then return false, errorMessage end
    if not self:ValidateBackupSnapshot(decoded) then return false, "The backup contains invalid data." end
    local safetyCode, safetyError = self:EncodeBackup()
    if not safetyCode then return false, "Could not create a safety copy: " .. tostring(safetyError) end

    local candidate = DeepCopy(decoded)
    candidate.safetyBackups = DeepCopy(self.db.safetyBackups or {})
    candidate.safetyBackups[#candidate.safetyBackups + 1] = {
        createdAt = time and time() or 0,
        code = safetyCode,
    }
    while #candidate.safetyBackups > 3 do table.remove(candidate.safetyBackups, 1) end
    self:NormalizeDatabase(candidate)
    ShoppingForeverDB = candidate
    self.db = candidate
    self:UpdateCurrentCharacter()
    self.itemOffset = 0
    self:NotifyChanged("backupRestored")
    return true, candidate
end

function SF:RestoreLatestSafetyBackup()
    local backups = self.db and self.db.safetyBackups
    local latest = type(backups) == "table" and backups[#backups] or nil
    if not latest or type(latest.code) ~= "string" then return false, "No safety copy is available." end
    return self:RestoreBackupCode(latest.code)
end
