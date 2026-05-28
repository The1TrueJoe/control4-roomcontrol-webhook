-- Shared utilities for both the root HTTP server driver and the room child driver.
-- Concatenated into each driver bundle by build.sh AFTER the driver's own globals file,
-- so upvalue capture of DEBUGPRINT and LOG_PREFIX works correctly.

local function Trim(value)
	value = tostring(value or '')
	return (string.gsub(value, '^%s*(.-)%s*$', '%1'))
end

-- Normalizes a string to UPPER_CASE_WITH_UNDERSCORES.
-- Used for command/value matching throughout both drivers.
local function Normalize(value)
	value = Trim(value)
	value = string.gsub(value, '[%s%-/]+', '_')
	value = string.gsub(value, '_+', '_')
	value = string.gsub(value, '^_', '')
	value = string.gsub(value, '_$', '')
	return string.upper(value)
end

local function SafeCall(fn)
	local ok, result = pcall(fn)
	if (ok) then
		return result
	end
	return nil
end

-- LOG_PREFIX and DEBUGPRINT must be declared as locals in the driver's globals
-- file, which is concatenated before this file so that upvalue capture works.
local function DebugLog(message)
	if (DEBUGPRINT) then
		print(LOG_PREFIX .. tostring(message))
	end
end

local function UpdateDriverProperty(name, value)
	if (C4 and C4.UpdateProperty) then
		SafeCall(function()
			C4:UpdateProperty(name, tostring(value or ''))
		end)
	end
end

local function SetDriverVariable(name, value)
	if (C4 and C4.SetVariable) then
		SafeCall(function()
			C4:SetVariable(name, tostring(value or ''))
		end)
	end
end

local function BoolParam(value, defaultValue)
	if (value == nil or value == '') then
		return defaultValue == true
	end
	local normalized = string.lower(Trim(value))
	return (normalized == '1' or normalized == 'true' or normalized == 'yes' or normalized == 'on' or normalized == 'enabled')
end

-- Returns the first numeric key from a table, or tonumber(value) if value is
-- not a table.  Used to extract a device ID from C4:GetBound*Device() results
-- which may return either a scalar or a {[id]=name} table.
local function FirstBoundId(value)
	if (type(value) == 'table') then
		for id, _ in pairs(value) do
			return tonumber(id)
		end
	end
	return tonumber(value)
end
