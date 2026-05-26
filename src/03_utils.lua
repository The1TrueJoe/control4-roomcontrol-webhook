-- General-purpose utility helpers used throughout the driver.

local function Trim(value)
	value = tostring(value or '')
	return (string.gsub(value, '^%s*(.-)%s*$', '%1'))
end

local function NormalizeCommand(value)
	value = Trim(value)
	value = string.gsub(value, '[%s%-/]+', '_')
	value = string.gsub(value, '_+', '_')
	value = string.gsub(value, '^_', '')
	value = string.gsub(value, '_$', '')
	return string.upper(value)
end

local function DebugLog(message)
	if (DEBUGPRINT) then
		print('[Room Control Webhook] ' .. tostring(message))
	end
end

local function SafeCall(fn)
	local ok, result = pcall(fn)
	if (ok) then
		return result
	end
	return nil
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
