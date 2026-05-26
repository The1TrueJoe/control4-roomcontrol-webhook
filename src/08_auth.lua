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

local function PresetValue(preset, names)
	for _, name in ipairs(names) do
		if (preset[name] ~= nil and preset[name] ~= '') then
			return preset[name]
		end
	end
	return nil
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

local function RoomSourceMap(roomId)
	local byIdAndType = {}
	local byId = {}
	for _, source in ipairs(RoomSources(roomId)) do
		byIdAndType[tostring(source.id) .. ':' .. source.type] = source
		byId[source.id] = byId[source.id] or source
	end
	return byIdAndType, byId
end

local function NormalizeSourcePreset(preset, index, roomId)
	if (type(preset) ~= 'table') then
		return nil, 'Preset must be an object'
	end

	local name = Trim(preset.name or preset.label or preset.title or '')
	local source = tonumber(PresetValue(preset, {'source', 'source_id', 'sourceId', 'device', 'deviceid', 'device_id', 'deviceId'}))
	local sourceType = SourceTypeLabel(PresetValue(preset, {'source_type', 'sourceType', 'type', 'mode'}))
	local media = tonumber(PresetValue(preset, {'media', 'media_id', 'mediaId', 'mediaid'}))

	if (name == '') then
		name = 'Preset ' .. tostring(index)
	end
	if (not source) then
		return nil, 'Source device ID is required'
	end

	local byIdAndType, byId = RoomSourceMap(roomId)
	local matched = byIdAndType[tostring(source) .. ':' .. sourceType] or byId[source]
	if (matched) then
		sourceType = matched.type
	end

	return {
		name = name,
		source = source,
		source_type = sourceType,
		source_name = (matched and matched.name) or GetRoomName(source),
		media = media,
	}, nil
end

local function SaveRoomSourcePresets(roomId, presets)
	roomId = tonumber(roomId)
	if (not roomId) then
		return false, 'Room ID is required'
	end
	if (not IsRoomAllowed(roomId)) then
		return false, 'Room is not enabled for webhook control: ' .. tostring(roomId)
	end
	if (type(presets) ~= 'table') then
		return false, 'Presets must be an array'
	end

	local clean = {}
	for index, preset in ipairs(presets) do
		if (index > MAX_PRESETS_PER_ROOM) then
			break
		end
		local normalized, err = NormalizeSourcePreset(preset, index, roomId)
		if (not normalized) then
			return false, 'Preset ' .. tostring(index) .. ': ' .. tostring(err)
		end
		table.insert(clean, normalized)
	end

	ROOM_PRESETS[RoomPresetKey(roomId)] = clean
	PersistData = PersistData or {}
	PersistData.SourcePresets = ROOM_PRESETS
	return true, nil
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
	local rooms = GetRooms(true)
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
	local roomValue = RequestAnyValue(req, {'room', 'room_id', 'roomId'})
	local body = req.bodyTable or req.form or {}
	local saved = {}

	if (roomValue ~= nil and roomValue ~= '') then
		local roomIds, roomErr = ResolveRooms(roomValue)
		if (not roomIds or #roomIds ~= 1) then
			return 400, {ok = false, error = {code = 'room_error', message = roomErr or 'Specify exactly one room when saving presets'}}
		end
		local ok, err = SaveRoomSourcePresets(roomIds[1], body.presets or {})
		if (not ok) then
			return 400, {ok = false, error = {code = 'preset_error', message = err}}
		end
		table.insert(saved, roomIds[1])
	elseif (type(body.presets) == 'table') then
		for key, presets in pairs(body.presets) do
			local roomId = tonumber(key)
			local ok, err = SaveRoomSourcePresets(roomId, presets)
			if (not ok) then
				return 400, {ok = false, error = {code = 'preset_error', message = err}}
			end
			table.insert(saved, roomId)
		end
	else
		return 400, {ok = false, error = {code = 'preset_error', message = 'Provide room and presets'}}
	end

	return 200, {
		ok = true,
		saved = saved,
		presets = PresetCatalog().presets,
	}
end

local function FindPreset(roomId, presetValue)
	local presets = PresetsForRoom(roomId)
	local index = tonumber(presetValue)
	if (index and presets[index]) then
		return presets[index], index
	end

	local normalized = NormalizeCommand(presetValue)
	for presetIndex = 1, MAX_PRESETS_PER_ROOM do
		local preset = presets[presetIndex]
		if (preset and NormalizeCommand(preset.name) == normalized) then
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
