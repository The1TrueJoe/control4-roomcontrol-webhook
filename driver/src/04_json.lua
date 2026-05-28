-- JSON encode and decode helpers.
-- Prefers C4's native JsonEncode/JsonDecode when available; falls back to a
-- pure-Lua implementation for environments where those APIs are absent.

local function JsonEscape(value)
	value = tostring(value or '')
	value = string.gsub(value, '\\', '\\\\')
	value = string.gsub(value, '"', '\\"')
	value = string.gsub(value, '\b', '\\b')
	value = string.gsub(value, '\f', '\\f')
	value = string.gsub(value, '\n', '\\n')
	value = string.gsub(value, '\r', '\\r')
	value = string.gsub(value, '\t', '\\t')
	return value
end

local function IsArray(value)
	if (type(value) ~= 'table') then
		return false
	end

	local count = 0
	local max = 0
	for key, _ in pairs(value) do
		if (type(key) ~= 'number' or key < 1 or key ~= math.floor(key)) then
			return false
		end
		count = count + 1
		if (key > max) then
			max = key
		end
	end

	return (max == count)
end

local function FallbackJsonEncode(value)
	local valueType = type(value)
	if (valueType == 'nil') then
		return 'null'
	elseif (valueType == 'number') then
		return tostring(value)
	elseif (valueType == 'boolean') then
		return (value and 'true') or 'false'
	elseif (valueType == 'string') then
		return '"' .. JsonEscape(value) .. '"'
	elseif (valueType == 'table') then
		local parts = {}
		if (IsArray(value)) then
			for index = 1, #value do
				table.insert(parts, FallbackJsonEncode(value[index]))
			end
			return '[' .. table.concat(parts, ',') .. ']'
		else
			for key, item in pairs(value) do
				table.insert(parts, '"' .. JsonEscape(key) .. '":' .. FallbackJsonEncode(item))
			end
			return '{' .. table.concat(parts, ',') .. '}'
		end
	end
	return 'null'
end

local function JsonEncode(value)
	if (C4 and C4.JsonEncode) then
		local ok, encoded = pcall(function()
			return C4:JsonEncode(value, false, true)
		end)
		if (ok and encoded) then
			return encoded
		end
	end
	return FallbackJsonEncode(value)
end

local function JsonDecode(value)
	if (C4 and C4.JsonDecode) then
		local ok, decoded = pcall(function()
			return C4:JsonDecode(value, true)
		end)
		if (ok) then
			return decoded, nil
		end

		ok, decoded = pcall(function()
			return C4:JsonDecode(value)
		end)
		if (ok) then
			return decoded, nil
		end
		return nil, decoded
	end
	return nil, 'JSON decode is unavailable in this runtime'
end
