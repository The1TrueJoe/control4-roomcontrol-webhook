-- Composer property change handlers for the root HTTP server driver.
-- Per-room presets and custom buttons now live on linked child drivers.

local function ParseAllowedClientIps(value)
	ALLOWED_CLIENT_IPS = {}
	for tokenText in string.gmatch(tostring(value or ''), '([^,]+)') do
		local token = Trim(tokenText)
		if (token ~= '') then
			ALLOWED_CLIENT_IPS[token] = true
		end
	end
end

local function ApplyProperty(name)
	local value = (Properties and Properties[name]) or ''

	if (name == 'Driver Version') then
		UpdateDriverProperty('Driver Version', DRIVER_VERSION)
	elseif (name == 'Debug Mode') then
		DEBUGPRINT = (value == 'On')
	elseif (name == 'Enabled') then
		SERVICE_ENABLED = (value ~= 'Off')
		ScheduleServerRestart()
	elseif (name == 'HTTP Port') then
		HTTP_PORT = tonumber(value) or DEFAULT_PORT
		ScheduleServerRestart()
	elseif (name == 'Bind Address') then
		BIND_ADDRESS = Trim(value)
		if (BIND_ADDRESS == '') then
			BIND_ADDRESS = '!all'
		end
		ScheduleServerRestart()
	elseif (name == 'Max Concurrent Clients') then
		MAX_CLIENTS = tonumber(value) or DEFAULT_MAX_CLIENTS
	elseif (name == 'Max Request Bytes') then
		MAX_REQUEST_BYTES = tonumber(value) or DEFAULT_MAX_REQUEST_BYTES
	elseif (name == 'Allow Raw Room Commands') then
		ALLOW_RAW_ROOM_COMMANDS = (value == 'On')
	elseif (name == 'Allowed Client IPs') then
		ParseAllowedClientIps(value)
	elseif (name == 'Password') then
		-- Read on each request; no restart required.
	elseif (name == 'Linked Rooms') then
		UpdateLinkedRoomsStatus()
	end
end
