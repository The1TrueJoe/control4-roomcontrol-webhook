-- DriverWorks callbacks invoked by Control4 Director.

function OnDriverInit(driverInitType)
	DRIVER_DESTROYING = false
	LATE_INIT_DONE = false
	-- Re-initialize tables that OnDriverDestroyed nils, so LateInit's property
	-- loop never indexes a nil table (critical path on same-instance LuaJIT updates).
	CONTROL_ROOMS = {}
	CONTROL_ROOM_SET = {}
	ROOM_SLOT_ASSIGN = {}
	PersistData = PersistData or {}
	PersistData.SourcePresets = PersistData.SourcePresets or PersistData.RoomPresets or {}
	ROOM_PRESETS = PersistData.SourcePresets

	BuildCommandIndex()

	if (C4 and C4.AddVariable) then
		SafeCall(function() C4:AddVariable('Service Status', 'Stopped', 'STRING', true, false) end)
		SafeCall(function() C4:AddVariable('Listening Port', tostring(DEFAULT_PORT), 'NUMBER', true, false) end)
		SafeCall(function() C4:AddVariable('Last Request', '', 'STRING', true, false) end)
		SafeCall(function() C4:AddVariable('Last Error', '', 'STRING', true, false) end)
	end

	UpdateDriverProperty('Driver Version', DRIVER_VERSION)
end

function OnDriverLateInit(driverInitType)
	for name, _ in pairs(Properties or {}) do
		ApplyProperty(name)
	end
	LATE_INIT_DONE = true
	RefreshRoomCache()
	RefreshRoomSlots()
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
	ROOM_SLOT_ASSIGN = nil
	CLIENTS = {}
	CLIENT_COUNT = 0
	CONTROL_ROOMS = nil
	CONTROL_ROOM_SET = nil
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
	local command = NormalizeCommand(strCommand)
	if (command == 'LUA_ACTION') then
		command = NormalizeCommand(tParams.ACTION or tParams.action or '')
	end

	if (command == 'RESTART_SERVER') then
		ScheduleServerRestart()
	elseif (command == 'STOP_SERVER') then
		StopServer()
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
