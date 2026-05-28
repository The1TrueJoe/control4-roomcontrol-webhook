-- Per-room preset catalog and root registration.

local function PresetNameProperty(index)
	return 'Preset ' .. tostring(index) .. ' Name'
end

local function PresetSourceProperty(index)
	return 'Preset ' .. tostring(index) .. ' Source'
end

local function ResolveRootFromBinding()
	local rootId = FirstBoundId(SafeCall(function()
		return C4:GetBoundProviderDevice(0, ROOT_LINK_BINDING_ID)
	end))
	if (rootId) then
		ROOT_DEVICE_ID = rootId
		ROOT_BINDING_ID = ROOT_LINK_BINDING_ID
		UpdateDriverProperty('Root Link Status', 'Linked to root driver ' .. tostring(ROOT_DEVICE_ID))
	else
		UpdateDriverProperty('Root Link Status', 'Not linked')
	end
	return ROOT_DEVICE_ID
end

local function BuildPresets()
	PRESETS = {}
	for index = 1, MAX_PRESETS_PER_ROOM do
		local source = tonumber(Properties and Properties[PresetSourceProperty(index)] or '')
		if (source and source > 0) then
			local name = Trim(Properties and Properties[PresetNameProperty(index)] or '')
			if (name == '') then
				name = 'Preset ' .. tostring(index)
			end
			PRESETS[index] = {
				index = index,
				name = name,
				source = source,
				source_name = GetDeviceName(source),
			}
		end
	end
end

local function RegisterWithRoot(tParams)
	if (DRIVER_DESTROYING) then
		return
	end
	tParams = tParams or {}
	ROOT_DEVICE_ID = tonumber(tParams.ROOT_DEVICE_ID or tParams.Root or tParams.root or ROOT_DEVICE_ID)
	ROOT_BINDING_ID = tonumber(tParams.ROOT_BINDING_ID or tParams.RootBinding or tParams.root_binding or ROOT_BINDING_ID or ROOT_LINK_BINDING_ID)
	if (not ROOT_DEVICE_ID) then
		ResolveRootFromBinding()
	end
	if (not ROOT_DEVICE_ID) then
		UpdateDriverProperty('Root Link Status', 'Not linked')
		return
	end

	UpdateRoomContext()
	BuildPresets()
	if (not ROOM_ID) then
		UpdateDriverProperty('Last Error', 'Unable to resolve current room')
		return
	end

	local deviceId = tonumber(SafeCall(function()
		return C4:GetDeviceID()
	end))
	local payload = {
		DEVICE_ID = tostring(deviceId or ''),
		DEVICE_NAME = GetDeviceName(deviceId),
		ROOT_BINDING_ID = tostring(ROOT_BINDING_ID or ''),
		ROOM_ID = tostring(ROOM_ID),
		ROOM_NAME = ROOM_NAME,
		ENABLED = ACCEPT_CONTROL and '1' or '0',
	}

	for index = 1, MAX_PRESETS_PER_ROOM do
		local preset = PRESETS[index]
		if (preset) then
			local prefix = 'PRESET_' .. tostring(index) .. '_'
			payload[prefix .. 'NAME'] = preset.name
			payload[prefix .. 'SOURCE'] = tostring(preset.source)
			payload[prefix .. 'SOURCE_NAME'] = preset.source_name
		end
	end

	for index = 1, BUTTON_COUNT do
		local button = BUTTONS[index]
		if (button) then
			local prefix = 'BUTTON_' .. tostring(index) .. '_'
			payload[prefix .. 'NAME'] = button.name
			payload[prefix .. 'BINDING'] = tostring(button.binding_id)
		end
	end

	SafeCall(function()
		C4:SendToDevice(ROOT_DEVICE_ID, 'REGISTER_ROOM_CONTROL_CHILD', payload, true)
	end)
	UpdateDriverProperty('Root Link Status', 'Registered with root driver ' .. tostring(ROOT_DEVICE_ID))
	DebugLog('Registered room ' .. tostring(ROOM_ID) .. ' with root ' .. tostring(ROOT_DEVICE_ID))
end

local function UnregisterFromRoot()
	local deviceId = tonumber(SafeCall(function()
		return C4:GetDeviceID()
	end))
	if (ROOT_DEVICE_ID and deviceId) then
		SafeCall(function()
			C4:SendToDevice(ROOT_DEVICE_ID, 'UNREGISTER_ROOM_CONTROL_CHILD', {
				DEVICE_ID = tostring(deviceId),
			}, true)
		end)
	end
end

local function ApplyProperty(name)
	local value = (Properties and Properties[name]) or ''
	if (name == 'Driver Version') then
		UpdateDriverProperty('Driver Version', DRIVER_VERSION)
	elseif (name == 'Debug Mode') then
		DEBUGPRINT = (value == 'On')
	elseif (name == 'Accept Control') then
		ACCEPT_CONTROL = (value ~= 'Off')
		if (LATE_INIT_DONE) then
			RegisterWithRoot()
		end
	else
		local presetIndex = string.match(name, '^Preset (%d+) ')
		if (presetIndex) then
			BuildPresets()
			if (LATE_INIT_DONE) then
				RegisterWithRoot()
			end
			return
		end

		local buttonIndex = string.match(name, '^Button (%d+) Name$')
		if (buttonIndex) then
			RegisterButton(tonumber(buttonIndex), value)
			if (LATE_INIT_DONE) then
				RegisterWithRoot()
			end
		end
	end
end
