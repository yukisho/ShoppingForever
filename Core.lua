local ADDON_NAME, SF = ...

SF.name = ADDON_NAME
SF.displayName = "Shopping Forever"
SF.version = "0.8.0"
SF.schemaVersion = 5
SF.callbacks = {}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Trim(value)
    if type(value) ~= "string" or IsSecret(value) then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ClampWholeNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    value = math.floor(value)
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

SF.util = {
    IsSecret = IsSecret,
    Trim = Trim,
    ClampWholeNumber = ClampWholeNumber,
}

function SF:Print(message)
    print("|cffd9a441" .. self.displayName .. ":|r " .. tostring(message))
end

function SF:RegisterCallback(callback)
    if type(callback) == "function" then
        self.callbacks[callback] = true
    end
end

function SF:UnregisterCallback(callback)
    self.callbacks[callback] = nil
end

function SF:NotifyChanged(reason, details)
    for callback in pairs(self.callbacks) do
        local ok, errorMessage = pcall(callback, reason, details or {})
        if not ok then
            self:Print("A refresh callback failed: " .. tostring(errorMessage))
        end
    end
end
