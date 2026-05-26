-- HTTP response construction and request parameter accessors.

local function HeaderValue(headers, name)
	return headers[string.lower(name or '')]
end

local function RequestValue(req, name)
	if (req.bodyTable and req.bodyTable[name] ~= nil) then
		return req.bodyTable[name]
	end
	if (req.form and req.form[name] ~= nil) then
		return req.form[name]
	end
	return req.query[name]
end

local function RequestAnyValue(req, names)
	for _, name in ipairs(names) do
		local value = RequestValue(req, name)
		if (value ~= nil and value ~= '') then
			return value
		end
	end
	return nil
end

local function Response(client, status, payload, extraHeaders)
	local body = ''
	local contentType = 'application/json; charset=utf-8'
	if (payload ~= nil) then
		if (type(payload) == 'table') then
			body = JsonEncode(payload)
		else
			body = tostring(payload)
		end
	end

	local lines = {
		'HTTP/1.1 ' .. tostring(status) .. ' ' .. (HTTP_REASONS[status] or 'OK'),
		'Content-Type: ' .. contentType,
		'Content-Length: ' .. tostring(string.len(body)),
		'Connection: close',
		'Cache-Control: no-store',
		'Access-Control-Allow-Origin: *',
		'Access-Control-Allow-Methods: GET, POST, OPTIONS',
		'Access-Control-Allow-Headers: Authorization, Content-Type, X-Control4-Password, X-API-Key',
	}

	for key, value in pairs(extraHeaders or {}) do
		table.insert(lines, tostring(key) .. ': ' .. tostring(value))
	end

	local data = table.concat(lines, '\r\n') .. '\r\n\r\n' .. body
	SafeCall(function()
		client:Write(data)
		client:Close(true)
	end)
end

local function ErrorResponse(client, status, code, message, details, extraHeaders)
	Response(client, status, {
		ok = false,
		error = {
			code = code,
			message = message,
			details = details,
		},
	}, extraHeaders)
end
