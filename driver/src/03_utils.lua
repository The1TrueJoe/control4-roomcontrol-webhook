-- Root-driver HTTP utilities: service status, URL decoding, and form-body parsing.
-- Generic utilities (Trim, Normalize, SafeCall, DebugLog, UpdateDriverProperty,
-- SetDriverVariable, BoolParam, FirstBoundId) live in shared/01_utils.lua.

local function SetServiceStatus(status, err)
	UpdateDriverProperty('Service Status', status)
	SetDriverVariable('Service Status', status)
	if (err and err ~= '') then
		UpdateDriverProperty('Last Error', err)
		SetDriverVariable('Last Error', err)
	end
end

local function UrlDecode(value)
	value = tostring(value or '')
	value = string.gsub(value, '+', ' ')
	value = string.gsub(value, '%%(%x%x)', function(hex)
		return string.char(tonumber(hex, 16))
	end)
	return value
end

local function ParseKeyValueString(value)
	local params = {}
	value = tostring(value or '')
	for pair in string.gmatch(value, '([^&]+)') do
		local key, val = string.match(pair, '^([^=]*)=?(.*)$')
		key = UrlDecode(key or '')
		val = UrlDecode(val or '')
		if (key ~= '') then
			params[key] = val
		end
	end
	return params
end
