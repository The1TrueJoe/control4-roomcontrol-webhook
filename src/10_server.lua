-- TCP server lifecycle: accept, read, and connection management.

local function RemoveClient(client)
	if (CLIENTS[client] ~= nil) then
		CLIENTS[client] = nil
		CLIENT_COUNT = CLIENT_COUNT - 1
		if (CLIENT_COUNT < 0) then
			CLIENT_COUNT = 0
		end
	end
end

local function OnClientRead(client, data)
	if (DRIVER_DESTROYING) then
		SafeCall(function()
			client:Close()
		end)
		RemoveClient(client)
		return
	end

	local state = CLIENTS[client]
	if (not state) then
		return
	end

	if (state.readingBody) then
		state.request.body = (state.request.body or '') .. (data or '')
		local remaining = state.contentLength - string.len(state.request.body)
		if (remaining > 0) then
			client:ReadUpTo(remaining)
		else
			HandleRequest(client, state.request)
		end
		return
	end

	local headerBlock = data or ''
	local req, err = ParseHeaders(headerBlock)
	if (not req) then
		ErrorResponse(client, 400, 'bad_request', err)
		return
	end

	req.client_ip = state.client_ip
	req.client_port = state.client_port

	local contentLength = tonumber(HeaderValue(req.headers, 'content-length') or '0') or 0
	if (contentLength > MAX_REQUEST_BYTES) then
		ErrorResponse(client, 413, 'payload_too_large', 'Request body exceeds Max Request Bytes')
		return
	end

	if (contentLength > 0) then
		state.readingBody = true
		state.request = req
		state.contentLength = contentLength
		client:ReadUpTo(contentLength)
	else
		HandleRequest(client, req)
	end
end

local function OnAccept(server, client)
	if (DRIVER_DESTROYING) then
		SafeCall(function()
			client:Close()
		end)
		return
	end

	local remote = SafeCall(function()
		return client:GetRemoteAddress()
	end) or {}

	if (not IsClientIpAllowed(remote.ip)) then
		Response(client, 403, {ok = false, error = {code = 'forbidden_ip', message = 'Client IP is not allowed'}})
		return
	end

	if (CLIENT_COUNT >= MAX_CLIENTS) then
		Response(client, 429, {ok = false, error = {code = 'too_many_clients', message = 'Too many concurrent clients'}})
		return
	end

	CLIENTS[client] = {
		client_ip = remote.ip or '',
		client_port = remote.port or 0,
	}
	CLIENT_COUNT = CLIENT_COUNT + 1

	SafeCall(function()
		client:Option('nodelay', true)
	end)

	client
		:OnRead(function(cli, data)
			OnClientRead(cli, data)
		end)
		:OnDisconnect(function(cli, errCode, errMsg)
			DebugLog('Client disconnected: ' .. tostring(errCode) .. ' ' .. tostring(errMsg))
			RemoveClient(cli)
		end)
		:OnError(function(cli, code, msg, op)
			DebugLog('Client error: ' .. tostring(code) .. ' ' .. tostring(msg) .. ' op=' .. tostring(op))
		end)
		:ReadUntil('\r\n\r\n')
end

local function StopServer()
	if (RESTART_TIMER) then
		SafeCall(function()
			RESTART_TIMER:Cancel()
		end)
		RESTART_TIMER = nil
	end

	-- Snapshot and clear CLIENTS before issuing Close() so that OnDisconnect
	-- callbacks fired by Close() find an empty table and cannot retain refs.
	local snapshot = CLIENTS
	CLIENTS = {}
	CLIENT_COUNT = 0
	for client, _ in pairs(snapshot) do
		SafeCall(function()
			client:Close()
		end)
	end

	-- Nil SERVER before closing so in-flight OnAccept/OnError callbacks
	-- see nil and bail out, preventing closure reference retention.
	if (SERVER) then
		local s = SERVER
		SERVER = nil
		SafeCall(function()
			s:Close()
		end)
	end

	-- Skip UI updates during teardown: Director is either removing the driver
	-- or reloading it; Composer will reflect the new state from LateInit anyway.
	if (not DRIVER_DESTROYING) then
		UpdateDriverProperty('Endpoint', '')
		SetServiceStatus('Stopped')
	end
end

local function StartServer()
	StopServer()

	if (DRIVER_DESTROYING) then
		SetServiceStatus('Stopped')
		return
	end

	if (not SERVICE_ENABLED) then
		SetServiceStatus('Disabled')
		return
	end

	if (not C4 or not C4.CreateTCPServer) then
		SetServiceStatus('Failed', 'C4:CreateTCPServer is unavailable')
		return
	end

	SERVER = C4:CreateTCPServer()
	SERVER
		:OnListen(function(server, endpoint)
			local addr = SafeCall(function()
				return server:GetLocalAddress()
			end) or endpoint or {}
			local ip = SafeCall(function()
				return C4:GetControllerNetworkAddress()
			end) or addr.ip or ''
			local url = 'http://' .. tostring(ip) .. ':' .. tostring(addr.port or HTTP_PORT) .. '/rooms'
			UpdateDriverProperty('Endpoint', url)
			UpdateDriverProperty('Service Status', 'Listening on ' .. tostring(addr.port or HTTP_PORT))
			SetDriverVariable('Listening Port', tostring(addr.port or HTTP_PORT))
			SetDriverVariable('Service Status', 'Listening')
			DebugLog('Listening on ' .. tostring(addr.ip) .. ':' .. tostring(addr.port))
		end)
		:OnError(function(server, code, msg, op)
			local err = 'Server error ' .. tostring(code) .. ': ' .. tostring(msg) .. ' op=' .. tostring(op)
			SetServiceStatus('Failed', err)
		end)
		:OnAccept(function(server, client)
			OnAccept(server, client)
		end)

	SafeCall(function()
		SERVER:Option('reuseaddr', true)
	end)

	local listening = SafeCall(function()
		return SERVER:Listen(BIND_ADDRESS, HTTP_PORT, 16)
	end)
	if (not listening) then
		SetServiceStatus('Failed', 'Listen failed on ' .. tostring(BIND_ADDRESS) .. ':' .. tostring(HTTP_PORT))
		SERVER = nil
	end
end

local function ScheduleServerRestart()
	if (not LATE_INIT_DONE or DRIVER_DESTROYING) then
		return
	end
	if (RESTART_TIMER) then
		SafeCall(function()
			RESTART_TIMER:Cancel()
		end)
	end
	RESTART_TIMER = C4:SetTimer(100, function(timer)
		RESTART_TIMER = nil
		StartServer()
	end)
end
