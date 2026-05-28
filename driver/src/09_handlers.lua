-- HTTP request handling: routing, body decoding, and endpoint implementations.

local function HelpPayload()
	return {
		ok = true,
		name = 'Room Control Webhook',
		version = DRIVER_VERSION,
		endpoints = {
			'GET /health',
			'GET /rooms (linked room drivers only)',
			'GET /commands',
			'GET /presets (source presets from linked room drivers)',
			'GET /buttons (custom buttons from linked room drivers)',
			'GET|POST /command?room=ROOM_ID&command=VOLUME_UP&action=tap',
			'GET|POST /preset?room=ROOM_ID&preset=PresetName',
			'GET|POST /button?room=ROOM_ID&button=ButtonName&action=tap',
		},
		auth = {
			'Authorization: Bearer <password>',
			'Authorization: Basic <base64 user:password>',
			'X-Control4-Password: <password>',
			'password=<password> query or form field',
		},
	}
end

local function HandleCommandRequest(req)
	local roomValue = RequestAnyValue(req, {'rooms', 'room', 'room_id', 'roomId'})
	local action = RequestAnyValue(req, {'action', 'type', 'event'}) or 'tap'
	local commandValue = RequestAnyValue(req, {'command', 'button', 'button_id', 'buttonId'})

	local roomIds, roomErr = ResolveRooms(roomValue)
	if (not roomIds) then
		return 400, {ok = false, error = {code = 'room_error', message = roomErr}}
	end

	local sequence, commandErr = ResolveCommand(commandValue, action)
	if (not sequence) then
		return 400, {ok = false, error = {code = 'command_error', message = commandErr}}
	end

	local params = RequestValue(req, 'params')
	if (type(params) ~= 'table') then
		params = {}
	end

	local sent = SendRoomCommands(roomIds, sequence, params)
	local lastRequest = os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. table.concat(sequence, ',') .. ' -> ' .. tostring(#roomIds) .. ' room(s)'
	UpdateDriverProperty('Last Request', lastRequest)
	SetDriverVariable('Last Request', lastRequest)

	return 200, {
		ok = true,
		sequence = sequence,
		sent = sent,
	}
end

local function DecodeRequestBody(req)
	if (req.body == nil or req.body == '') then
		return true
	end

	local contentType = string.lower(HeaderValue(req.headers, 'content-type') or '')
	if (string.find(contentType, 'application/json', 1, true)) then
		local decoded, err = JsonDecode(req.body)
		if (decoded == nil and err ~= nil) then
			return false, 'Invalid JSON body: ' .. tostring(err)
		end
		req.bodyTable = decoded
	elseif (string.find(contentType, 'application/x-www-form-urlencoded', 1, true)) then
		req.form = ParseKeyValueString(req.body)
	else
		local decoded, err = JsonDecode(req.body)
		if (decoded ~= nil) then
			req.bodyTable = decoded
		else
			req.form = ParseKeyValueString(req.body)
			if (next(req.form) == nil and err ~= nil) then
				DebugLog('Body was not JSON or form encoded: ' .. tostring(err))
			end
		end
	end

	return true
end

local function HandleRequest(client, req)
	if (req.method == 'OPTIONS') then
		Response(client, 204, '')
		return
	end

	if (req.method ~= 'GET' and req.method ~= 'POST') then
		ErrorResponse(client, 405, 'method_not_allowed', 'Use GET, POST, or OPTIONS')
		return
	end

	local bodyOk, bodyErr = DecodeRequestBody(req)
	if (not bodyOk) then
		ErrorResponse(client, 400, 'invalid_body', bodyErr)
		return
	end

	if (req.path ~= '/health' and not IsAuthorized(req)) then
		ErrorResponse(client, 401, 'unauthorized', 'Missing or invalid password', nil, {['WWW-Authenticate'] = 'Bearer'})
		return
	end

	if (req.path == '/' or req.path == '/help') then
		Response(client, 200, HelpPayload())
	elseif (req.path == '/health') then
		Response(client, 200, {
			ok = true,
			status = SERVICE_ENABLED and 'enabled' or 'disabled',
			version = DRIVER_VERSION,
			port = HTTP_PORT,
		})
	elseif (req.path == '/rooms') then
		Response(client, 200, {
			ok = true,
			rooms = LinkedRoomCatalog(),
			selected = CONTROL_ROOMS,
			link_class = ROOT_LINK_CLASS,
		})
	elseif (req.path == '/commands') then
		local catalog = CommandCatalog()
		Response(client, 200, {
			ok = true,
			commands = catalog.commands,
			raw_enabled = catalog.raw_enabled,
		})
	elseif (req.path == '/presets') then
		if (req.method == 'GET') then
			Response(client, 200, PresetCatalog())
		else
			local status, payload = HandlePresetSaveRequest(req)
			Response(client, status, payload)
		end
	elseif (req.path == '/buttons') then
		Response(client, 200, ButtonCatalog())
	elseif (req.path == '/command') then
		local status, payload = HandleCommandRequest(req)
		Response(client, status, payload)
	elseif (req.path == '/preset') then
		local status, payload = HandlePresetRunRequest(req)
		Response(client, status, payload)
	elseif (req.path == '/button') then
		local status, payload = HandleButtonRunRequest(req)
		Response(client, status, payload)
	else
		ErrorResponse(client, 404, 'not_found', 'Unknown endpoint: ' .. tostring(req.path))
	end
end

local function ParseHeaders(headerBlock)
	local firstLine = string.match(headerBlock, '([^\r\n]+)') or ''
	local method, target, version = string.match(firstLine, '^(%S+)%s+(%S+)%s+(HTTP/%d%.%d)$')
	if (not method) then
		return nil, 'Malformed request line'
	end

	local path, queryString = string.match(target, '^([^?]*)%??(.*)$')
	path = UrlDecode(path or '/')
	if (path == '') then
		path = '/'
	end

	local headers = {}
	for line in string.gmatch(headerBlock, '([^\r\n]+)') do
		local key, value = string.match(line, '^([^:]+):%s*(.*)$')
		if (key and value) then
			headers[string.lower(Trim(key))] = Trim(value)
		end
	end

	return {
		method = string.upper(method),
		target = target,
		path = path,
		query = ParseKeyValueString(queryString or ''),
		version = version,
		headers = headers,
		body = '',
	}, nil
end
