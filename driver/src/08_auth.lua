-- Authentication and room command dispatch.

local function IsAuthorized(req)
	local password = Trim(Properties and Properties['Password'] or '')
	if (password == '') then
		return true
	end

	local candidates = {}
	local function addCandidate(value)
		if (value ~= nil) then
			table.insert(candidates, tostring(value))
		end
	end

	addCandidate(HeaderValue(req.headers, 'x-control4-password'))
	addCandidate(HeaderValue(req.headers, 'x-api-key'))
	addCandidate(req.query.password)
	addCandidate(req.query.token)

	if (req.bodyTable) then
		addCandidate(req.bodyTable.password)
		addCandidate(req.bodyTable.token)
	end
	if (req.form) then
		addCandidate(req.form.password)
		addCandidate(req.form.token)
	end

	local auth = HeaderValue(req.headers, 'authorization') or ''
	local bearer = string.match(auth, '^[Bb]earer%s+(.+)$')
	if (bearer) then
		addCandidate(Trim(bearer))
	end

	local basic = string.match(auth, '^[Bb]asic%s+(.+)$')
	if (basic and C4 and C4.Base64Decode) then
		local decoded = SafeCall(function()
			return C4:Base64Decode(Trim(basic))
		end)
		if (decoded) then
			addCandidate(decoded)
			local basicPassword = string.match(decoded, '^[^:]*:(.*)$')
			if (basicPassword) then
				addCandidate(basicPassword)
			end
		end
	end

	for _, candidate in ipairs(candidates) do
		if (candidate == password) then
			return true
		end
	end

	return false
end

local function IsClientIpAllowed(ip)
	if (next(ALLOWED_CLIENT_IPS) == nil) then
		return true
	end
	return (ALLOWED_CLIENT_IPS[tostring(ip or '')] == true)
end

local function SendRoomCommands(roomIds, sequence, params)
	local sent = {}
	params = (type(params) == 'table' and params) or {}
	for _, roomId in ipairs(roomIds) do
		local roomResult = {
			room = roomId,
			name = GetRoomName(roomId),
			commands = {},
		}
		for _, command in ipairs(sequence) do
			DebugLog('Sending ' .. command .. ' to room ' .. tostring(roomId))
			SafeCall(function()
				C4:SendToDevice(roomId, command, params)
			end)
			table.insert(roomResult.commands, command)
		end
		table.insert(sent, roomResult)
	end
	return sent
end

local function RoomPresetKey(roomId)
	return tostring(tonumber(roomId) or roomId or '')
end

local function SourceTypeLabel(sourceType)
	sourceType = string.lower(Trim(sourceType or ''))
	if (sourceType == 'listen' or sourceType == 'audio') then
		return 'listen'
	end
	return 'watch'
end

local function ParseSourceList(xml, sourceType, hidden, sources, seen)
	if (type(xml) ~= 'string' or xml == '') then
		return
	end
	sourceType = SourceTypeLabel(sourceType)
	for fragment in string.gmatch(xml, '<source>(.-)</source>') do
		local sourceId = tonumber(string.match(fragment, '<id>(.-)</id>'))
		if (sourceId) then
			local key = tostring(sourceId) .. ':' .. sourceType
			if (not seen[key]) then
				seen[key] = true
				local name = string.match(fragment, '<name>(.-)</name>') or string.match(fragment, '<displayname>(.-)</displayname>') or GetRoomName(sourceId)
				table.insert(sources, {
					id = sourceId,
					name = XmlUnescape(name or GetRoomName(sourceId)),
					type = sourceType,
					hidden = hidden == true,
				})
			end
		end
	end
end

local function RoomSources(roomId)
	roomId = tonumber(roomId)
	local sources = {}
	local seen = {}
	if (not roomId) then
		return sources
	end

	ParseSourceList(SafeCall(function()
		return C4:SendToDevice(roomId, 'GET_WATCH_DEVICES', {})
	end), 'watch', false, sources, seen)
	ParseSourceList(SafeCall(function()
		return C4:SendToDevice(roomId, 'GET_WATCH_DEVICES', {hidden = 1})
	end), 'watch', true, sources, seen)
	ParseSourceList(SafeCall(function()
		return C4:SendToDevice(roomId, 'GET_LISTEN_DEVICES', {})
	end), 'listen', false, sources, seen)
	ParseSourceList(SafeCall(function()
		return C4:SendToDevice(roomId, 'GET_LISTEN_DEVICES', {hidden = 1})
	end), 'listen', true, sources, seen)

	table.sort(sources, function(a, b)
		local typeCompare = tostring(a.type) < tostring(b.type)
		if (a.type ~= b.type) then
			return typeCompare
		end
		return string.lower(a.name) < string.lower(b.name)
	end)
	return sources
end

local function RefreshLinkedRoomIndex()
	CONTROL_ROOMS = {}
	CONTROL_ROOM_SET = {}
	ROOM_CHILDREN_BY_ROOM = {}
	ROOM_PRESETS = {}

	for childId, child in pairs(ROOM_CHILDREN or {}) do
		local roomId = tonumber(child and child.room_id)
		if (roomId) then
			child.device_id = tonumber(child.device_id) or tonumber(childId)
			ROOM_CHILDREN_BY_ROOM[roomId] = child
			if (child.enabled) then
				CONTROL_ROOM_SET[roomId] = true
				table.insert(CONTROL_ROOMS, roomId)
				ROOM_PRESETS[RoomPresetKey(roomId)] = child.presets or {}
			end
		end
	end

	table.sort(CONTROL_ROOMS)
	ROOM_CACHE = nil
end

local function SortedLinkedRooms()
	local rooms = {}
	for childId, child in pairs(ROOM_CHILDREN or {}) do
		local roomId = tonumber(child and child.room_id)
		if (roomId) then
			table.insert(rooms, {
				id = roomId,
				name = child.room_name or GetRoomName(roomId),
				enabled = child.enabled == true,
				child_device = tonumber(child.device_id) or tonumber(childId),
				child_name = child.child_name or ('Room Control Room ' .. tostring(childId)),
				binding_id = tonumber(child.binding_id),
				presets = child.presets or {},
				buttons = child.buttons or {},
			})
		end
	end
	table.sort(rooms, function(a, b)
		return string.lower(tostring(a.name)) < string.lower(tostring(b.name))
	end)
	return rooms
end

local function UpdateLinkedRoomsStatus()
	local rooms = SortedLinkedRooms()
	local enabledCount = 0
	local labels = {}
	for _, room in ipairs(rooms) do
		if (room.enabled) then
			enabledCount = enabledCount + 1
		end
		table.insert(labels, room.name .. (room.enabled and '' or ' (disabled)'))
	end

	local status = tostring(enabledCount) .. ' enabled / ' .. tostring(#rooms) .. ' linked'
	if (#labels > 0) then
		status = status .. ': ' .. table.concat(labels, ', ')
	end
	UpdateDriverProperty('Linked Rooms', status)
end

local function RegisterLinkedRoom(params)
	params = params or {}
	local childId = tonumber(params.DEVICE_ID or params.device_id or params.ChildDeviceID or params.child_device or params.CHILD_ID or params.idDevice or params.ID_DEVICE)
	local roomId = tonumber(params.ROOM_ID or params.room_id or params.RoomID or params.room)
	if (not childId) then
		return false, 'Missing child device ID'
	end
	if (not roomId) then
		return false, 'Missing room ID from child ' .. tostring(childId)
	end

	local presets = {}
	for index = 1, MAX_PRESETS_PER_ROOM do
		local prefix = 'PRESET_' .. tostring(index) .. '_'
		local source = tonumber(params[prefix .. 'SOURCE'] or params[prefix .. 'SOURCE_ID'] or params['Preset ' .. tostring(index) .. ' Source'])
		if (source and source > 0) then
			presets[index] = {
				name = Trim(params[prefix .. 'NAME'] or params['Preset ' .. tostring(index) .. ' Name'] or ('Preset ' .. tostring(index))),
				source = source,
				source_name = Trim(params[prefix .. 'SOURCE_NAME'] or '') ~= '' and Trim(params[prefix .. 'SOURCE_NAME']) or GetRoomName(source),
			}
		end
	end

	local buttons = {}
	for index = 1, MAX_CUSTOM_BUTTONS do
		local prefix = 'BUTTON_' .. tostring(index) .. '_'
		local name = Trim(params[prefix .. 'NAME'] or params['Button ' .. tostring(index) .. ' Name'] or '')
		if (name ~= '') then
			table.insert(buttons, {
				index = index,
				name = name,
				binding_id = tonumber(params[prefix .. 'BINDING'] or params[prefix .. 'BINDING_ID']),
			})
		end
	end

	local roomName = Trim(params.ROOM_NAME or params.room_name or '')
	if (roomName == '') then
		roomName = GetRoomName(roomId)
	end

	ROOM_CHILDREN[childId] = {
		device_id = childId,
		child_name = Trim(params.DEVICE_NAME or params.device_name or params.CHILD_NAME or '') ~= '' and Trim(params.DEVICE_NAME or params.device_name or params.CHILD_NAME) or ('Room Control Room ' .. tostring(childId)),
		binding_id = tonumber(params.ROOT_BINDING_ID or params.root_binding_id or params.BindingID),
		room_id = roomId,
		room_name = roomName,
		enabled = BoolParam(params.ENABLED or params.enabled, true),
		presets = presets,
		buttons = buttons,
		updated_at = os.time(),
	}

	RefreshLinkedRoomIndex()
	UpdateLinkedRoomsStatus()
	DebugLog('Registered linked room child ' .. tostring(childId) .. ' for room ' .. tostring(roomId))
	return true, nil
end

local function UnregisterLinkedRoom(childId)
	childId = tonumber(childId)
	if (not childId) then
		return
	end
	ROOM_CHILDREN[childId] = nil
	LINKED_CHILDREN[childId] = nil
	RefreshLinkedRoomIndex()
	UpdateLinkedRoomsStatus()
	DebugLog('Unregistered linked room child ' .. tostring(childId))
end

local function RequestLinkedRoomRegistration(childId, bindingId)
	childId = tonumber(childId)
	if (not childId or DRIVER_DESTROYING) then
		return
	end
	local rootId = SafeCall(function()
		return C4:GetDeviceID()
	end)
	SafeCall(function()
		C4:SendToDevice(childId, 'REGISTER_WITH_ROOT', {
			ROOT_DEVICE_ID = tostring(rootId or ''),
			ROOT_BINDING_ID = tostring(bindingId or ''),
		})
	end)
end

local function RefreshLinkedRoomDrivers()
	if (not C4 or not C4.GetBoundConsumerDevices) then
		UpdateLinkedRoomsStatus()
		return
	end

	local seen = {}
	for bindingId = ROOT_LINK_BINDING_START, ROOT_LINK_BINDING_END do
		local consumers = SafeCall(function()
			return C4:GetBoundConsumerDevices(0, bindingId)
		end)
		if (type(consumers) == 'table') then
			for childId, childName in pairs(consumers) do
				local numericChildId = tonumber(childId)
				if (numericChildId) then
					seen[numericChildId] = true
					LINKED_CHILDREN[numericChildId] = {binding_id = bindingId, name = childName}
					RequestLinkedRoomRegistration(numericChildId, bindingId)
				end
			end
		else
			local childId = FirstBoundId(consumers)
			if (childId) then
				seen[childId] = true
				LINKED_CHILDREN[childId] = {binding_id = bindingId}
				RequestLinkedRoomRegistration(childId, bindingId)
			end
		end
	end

	for childId, _ in pairs(ROOM_CHILDREN or {}) do
		if (not seen[tonumber(childId)]) then
			UnregisterLinkedRoom(childId)
		end
	end

	UpdateLinkedRoomsStatus()
end

local function LinkedRoomCatalog()
	return SortedLinkedRooms()
end

local function ButtonCatalog()
	local rooms = SortedLinkedRooms()
	local buttons = {}
	for _, room in ipairs(rooms) do
		buttons[RoomPresetKey(room.id)] = room.buttons or {}
	end
	return {
		ok = true,
		rooms = rooms,
		buttons = buttons,
		max_buttons_per_room = MAX_CUSTOM_BUTTONS,
	}
end

local function FindButtonForRoom(roomId, buttonValue)
	local child = ROOM_CHILDREN_BY_ROOM[tonumber(roomId)]
	if (not child) then
		return nil, nil, 'No linked room driver for room ' .. tostring(roomId)
	end
	if (not child.enabled) then
		return nil, child, 'Linked room driver is disabled for room ' .. tostring(roomId)
	end

	local index = tonumber(buttonValue)
	if (index) then
		for _, button in ipairs(child.buttons or {}) do
			if (button.index == index) then
				return button, child, nil
			end
		end
	end

	local normalized = Normalize(buttonValue)
	for _, button in ipairs(child.buttons or {}) do
		if (Normalize(button.name) == normalized) then
			return button, child, nil
		end
	end
	return nil, child, 'Button not found for room ' .. tostring(roomId)
end

local function TriggerLinkedButton(roomId, buttonValue, action)
	local button, child, err = FindButtonForRoom(roomId, buttonValue)
	if (not button) then
		return false, err
	end
	SafeCall(function()
		C4:SendToDevice(child.device_id, 'TRIGGER_CUSTOM_BUTTON', {
			Button = button.name,
			ButtonIndex = tostring(button.index),
			Action = action or 'tap',
		}, true)
	end)
	return true, {
		room = tonumber(roomId),
		name = child.room_name or GetRoomName(roomId),
		child_device = child.device_id,
		button = button.name,
		index = button.index,
		action = action or 'tap',
	}
end

local function PresetsForRoom(roomId)
	return ROOM_PRESETS[RoomPresetKey(roomId)] or {}
end

local function PresetCatalogForRoom(roomId)
	local catalog = {}
	local presets = PresetsForRoom(roomId)
	for index = 1, MAX_PRESETS_PER_ROOM do
		local preset = presets[index]
		if (preset and preset.source) then
			local item = {
				index = index,
				name = preset.name,
				source = preset.source,
				source_type = preset.source_type,
				source_name = preset.source_name,
				media = preset.media,
			}
			table.insert(catalog, item)
		end
	end
	return catalog
end

local function PresetCatalog()
	local rooms = LinkedRoomCatalog()
	local presets = {}
	local sources = {}
	for _, room in ipairs(rooms) do
		if (IsRoomAllowed(room.id)) then
			presets[RoomPresetKey(room.id)] = PresetCatalogForRoom(room.id)
			sources[RoomPresetKey(room.id)] = RoomSources(room.id)
		end
	end
	return {
		ok = true,
		rooms = rooms,
		sources = sources,
		presets = presets,
		max_presets_per_room = MAX_PRESETS_PER_ROOM,
	}
end

local function HandlePresetSaveRequest(req)
	return 405, {
		ok = false,
		error = {
			code = 'not_supported',
			message = 'Preset configuration now lives on each linked Room Control Webhook Room driver.',
		},
	}
end

local function FindPreset(roomId, presetValue)
	local presets = PresetsForRoom(roomId)
	local index = tonumber(presetValue)
	if (index and presets[index]) then
		return presets[index], index
	end

	local normalized = Normalize(presetValue)
	for presetIndex = 1, MAX_PRESETS_PER_ROOM do
		local preset = presets[presetIndex]
		if (preset and Normalize(preset.name) == normalized) then
			return preset, presetIndex
		end
	end
	return nil, nil
end

local function ParseDeviceIdSet(xml)
	local ids = {}
	if (type(xml) == 'string') then
		for fragment in string.gmatch(xml, '<source>(.-)</source>') do
			local id = tonumber(string.match(fragment, '<id>(.-)</id>'))
			if (id) then
				ids[id] = true
			end
		end
	end
	return ids
end

local function SelectSourcePreset(roomId, preset)
	roomId = tonumber(roomId)
	local source = tonumber(preset and preset.source)
	if (not roomId or not source) then
		return false, 'Room and source are required'
	end

	local media = tonumber(preset.media)
	if (media) then
		DebugLog('Selecting media ' .. tostring(media) .. ' in room ' .. tostring(roomId))
		SafeCall(function()
			C4:SendToDevice(roomId, 'SELECT_AUDIO_MEDIA', {
				deselect = '0',
				type = 'BROADCAST_AUDIO',
				mediaid = media,
			})
		end)
		return true, {command = 'SELECT_AUDIO_MEDIA', params = {mediaid = media}}
	end

	-- Dynamically determine source type by querying the room's device lists,
	-- exactly as the reference Room Control driver does. This avoids relying on
	-- a source type that may have been stored incorrectly at config time.
	local watchIds   = ParseDeviceIdSet(SafeCall(function() return C4:SendToDevice(roomId, 'GET_WATCH_DEVICES',  {})           end))
	local watchHIds  = ParseDeviceIdSet(SafeCall(function() return C4:SendToDevice(roomId, 'GET_WATCH_DEVICES',  {hidden = 1}) end))
	local listenIds  = ParseDeviceIdSet(SafeCall(function() return C4:SendToDevice(roomId, 'GET_LISTEN_DEVICES', {})           end))
	local listenHIds = ParseDeviceIdSet(SafeCall(function() return C4:SendToDevice(roomId, 'GET_LISTEN_DEVICES', {hidden = 1}) end))

	local isWatch  = watchIds[source]  or watchHIds[source]
	local isListen = listenIds[source] or listenHIds[source]

	local command
	if (isWatch) then
		command = 'SELECT_VIDEO_DEVICE'
	elseif (isListen) then
		command = 'SELECT_AUDIO_DEVICE'
	else
		-- Device not found in room lists — fall back to stored type or SELECT_VIDEO_DEVICE.
		command = (SourceTypeLabel(preset.source_type) == 'listen') and 'SELECT_AUDIO_DEVICE' or 'SELECT_VIDEO_DEVICE'
	end

	DebugLog('Selecting source ' .. tostring(source) .. ' (' .. command .. ') in room ' .. tostring(roomId))

	if (command == 'SELECT_AUDIO_DEVICE') then
		local isDigitalAudio = string.lower(tostring(SafeCall(function()
			return C4:GetDeviceData(source, 'digital_audio_support')
		end) or '')) == 'true'
		if (isDigitalAudio) then
			SafeCall(function()
				C4:SendToDevice(source, 'DEVICE_SELECTED', {idRoom = roomId})
			end)
			return true, {command = 'DEVICE_SELECTED', device = source, params = {idRoom = roomId}}
		end
	end

	SafeCall(function()
		C4:SendToDevice(roomId, command, {deviceid = source})
	end)
	return true, {command = command, params = {deviceid = source}}
end

local function HandlePresetRunRequest(req)
	local roomValue = RequestAnyValue(req, {'room', 'room_id', 'roomId'})
	local presetValue = RequestAnyValue(req, {'preset', 'preset_id', 'presetId', 'name'})
	if (Trim(presetValue or '') == '') then
		return 400, {ok = false, error = {code = 'preset_error', message = 'Specify preset by index or name'}}
	end

	local roomIds, roomErr = ResolveRooms(roomValue)
	if (not roomIds) then
		return 400, {ok = false, error = {code = 'room_error', message = roomErr}}
	end

	local results = {}
	for _, roomId in ipairs(roomIds) do
		local preset, presetIndex = FindPreset(roomId, presetValue)
		if (not preset) then
			return 404, {ok = false, error = {code = 'preset_not_found', message = 'Preset not found for room ' .. tostring(roomId)}}
		end
		local ok, sentOrErr = SelectSourcePreset(roomId, preset)
		if (not ok) then
			return 400, {ok = false, error = {code = 'source_preset_error', message = sentOrErr}}
		end
		table.insert(results, {room = roomId, preset = preset.name, index = presetIndex, source = preset.source, source_name = preset.source_name, sent = sentOrErr})
	end

	return 200, {
		ok = true,
		results = results,
	}
end

local function HandleButtonRunRequest(req)
	local roomValue = RequestAnyValue(req, {'rooms', 'room', 'room_id', 'roomId'})
	local buttonValue = RequestAnyValue(req, {'button', 'button_id', 'buttonId', 'name'})
	local action = RequestAnyValue(req, {'action', 'type', 'event'}) or 'tap'

	if (Trim(buttonValue or '') == '') then
		return 400, {ok = false, error = {code = 'button_error', message = 'Specify button by index or name'}}
	end

	local roomIds, roomErr = ResolveRooms(roomValue)
	if (not roomIds) then
		return 400, {ok = false, error = {code = 'room_error', message = roomErr}}
	end

	local results = {}
	for _, roomId in ipairs(roomIds) do
		local ok, sentOrErr = TriggerLinkedButton(roomId, buttonValue, action)
		if (not ok) then
			return 404, {ok = false, error = {code = 'button_not_found', message = sentOrErr}}
		end
		table.insert(results, sentOrErr)
	end

	local lastRequest = os.date('%Y-%m-%d %H:%M:%S') .. ' button ' .. tostring(buttonValue) .. ' -> ' .. tostring(#roomIds) .. ' room(s)'
	UpdateDriverProperty('Last Request', lastRequest)
	SetDriverVariable('Last Request', lastRequest)

	return 200, {
		ok = true,
		results = results,
	}
end
