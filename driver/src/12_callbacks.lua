-- DriverWorks callbacks invoked by Control4 Director.

function OnDriverInit(driverInitType)
	DRIVER_DESTROYING = false
	LATE_INIT_DONE = false
	-- Re-initialize tables that OnDriverDestroyed nils, so LateInit's property
	-- loop never indexes a nil table (critical path on same-instance LuaJIT updates).
	CONTROL_ROOMS = {}
	CONTROL_ROOM_SET = {}
	ROOM_CHILDREN = {}
	ROOM_CHILDREN_BY_ROOM = {}
	LINKED_CHILDREN = {}
	PersistData = PersistData or {}
	ROOM_PRESETS = {}

	BuildCommandIndex()

	if (C4 and C4.AddVariable) then
		SafeCall(function() C4:AddVariable('Service Status', 'Stopped', 'STRING', true, false) end)
		SafeCall(function() C4:AddVariable('Listening Port', tostring(DEFAULT_PORT), 'NUMBER', true, false) end)
		SafeCall(function() C4:AddVariable('Last Request', '', 'STRING', true, false) end)
		SafeCall(function() C4:AddVariable('Last Error', '', 'STRING', true, false) end)
	end

	UpdateDriverProperty('Driver Version', DRIVER_VERSION)
	UpdateDriverProperty('Linked Rooms', '0 enabled / 0 linked')
end

function OnDriverLateInit(driverInitType)
	for name, _ in pairs(Properties or {}) do
		ApplyProperty(name)
	end
	LATE_INIT_DONE = true
	RefreshRoomCache()
	RefreshLinkedRoomDrivers()
	ScheduleServerRestart()
end

function OnDriverDestroyed(driverInitType)
	DRIVER_DESTROYING = true
	LATE_INIT_DONE = false
	SERVICE_ENABLED = false
	StopServer()
	-- Release all cached state so the Lua GC can collect it.
	-- Skip CleanupRoomPresetProperties(): those Composer API calls are useless
	-- during teardown; LateInit rebuilds the slot UI on next load anyway.
	ROOM_CACHE = nil
	ROOM_PRESETS = nil
	CLIENTS = {}
	CLIENT_COUNT = 0
	CONTROL_ROOMS = nil
	CONTROL_ROOM_SET = nil
	ROOM_CHILDREN = nil
	ROOM_CHILDREN_BY_ROOM = nil
	LINKED_CHILDREN = nil
end

function OnPropertyChanged(name)
	if (DRIVER_DESTROYING) then
		return
	end
	ApplyProperty(name)
end

function ExecuteCommand(strCommand, tParams)
	if (DRIVER_DESTROYING) then
		return
	end

	tParams = tParams or {}
	local command = Normalize(strCommand)
	if (command == 'LUA_ACTION') then
		command = Normalize(tParams.ACTION or tParams.action or '')
	end

	if (command == 'RESTART_SERVER') then
		ScheduleServerRestart()
	elseif (command == 'STOP_SERVER') then
		StopServer()
	elseif (command == 'REFRESH_LINKED_ROOMS') then
		RefreshLinkedRoomDrivers()
	elseif (command == 'REGISTER_ROOM_CONTROL_CHILD') then
		local ok, err = RegisterLinkedRoom(tParams)
		if (not ok) then
			UpdateDriverProperty('Last Error', err)
			SetDriverVariable('Last Error', err)
		end
	elseif (command == 'UNREGISTER_ROOM_CONTROL_CHILD') then
		UnregisterLinkedRoom(tParams.DEVICE_ID or tParams.device_id or tParams.CHILD_ID)
	elseif (command == 'SEND_ROOM_COMMAND') then
		local roomValue = tParams.Room or tParams.room or tParams['Room(s)'] or tParams['Room']
		local commandValue = tParams.Command or tParams.command
		local action = tParams.Action or tParams.action or 'tap'
		local roomIds, roomErr = ResolveRooms(roomValue)
		if (not roomIds) then
			UpdateDriverProperty('Last Error', roomErr)
			return
		end
		local sequence, commandErr = ResolveCommand(commandValue, action)
		if (not sequence) then
			UpdateDriverProperty('Last Error', commandErr)
			return
		end
		SendRoomCommands(roomIds, sequence, {})
	else
		DebugLog('Unhandled ExecuteCommand: ' .. tostring(strCommand))
	end
end

function OnBindingChanged(idBinding, strClass, bIsBound, otherDeviceID, otherBindingID)
	if (DRIVER_DESTROYING) then
		return
	end
	if (strClass ~= ROOT_LINK_CLASS) then
		return
	end

	local isBound = (bIsBound == true or string.lower(tostring(bIsBound)) == 'true' or tostring(bIsBound) == '1')
	if (isBound) then
		LINKED_CHILDREN[tonumber(otherDeviceID)] = {binding_id = tonumber(idBinding), other_binding_id = tonumber(otherBindingID)}
		RequestLinkedRoomRegistration(otherDeviceID, idBinding)
	else
		UnregisterLinkedRoom(otherDeviceID)
	end
end

function GetCommandList(currentValue, callbackWhenDone, search, filter)
	local list = {}
	local seen = {}

	local function addItem(value, text)
		if (not seen[value]) then
			seen[value] = true
			table.insert(list, {value = value, text = text or value})
		end
	end

	for command, _ in pairs(COMMAND_INDEX) do
		addItem(command, command)
	end

	table.sort(list, function(a, b)
		return a.text < b.text
	end)

	return list
end
