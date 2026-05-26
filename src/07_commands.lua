-- Command and button resolution.
-- Maps API request values (names, IDs, aliases) to DriverWorks command
-- sequences that can be dispatched to a room via C4:SendToDevice().

local function FindRoomByName(name)
	name = string.lower(Trim(name))
	if (name == '') then
		return nil
	end

	for _, room in ipairs(GetRooms(false)) do
		if (string.lower(room.name) == name) then
			return room.id
		end
	end

	RefreshRoomCache()
	for _, room in ipairs(GetRooms(false)) do
		if (string.lower(room.name) == name) then
			return room.id
		end
	end
	return nil
end

local function IsRoomAllowed(roomId)
	roomId = tonumber(roomId)
	if (not roomId) then
		return false
	end
	return ALLOW_UNSELECTED_ROOMS or (CONTROL_ROOM_SET[roomId] == true)
end

local function AddResolvedRoom(roomIds, roomSet, token)
	token = Trim(token)
	if (token == '') then
		return true
	end

	local roomId = tonumber(token) or FindRoomByName(token)
	if (not roomId) then
		return false, 'Unknown room: ' .. token
	end
	if (not IsRoomAllowed(roomId)) then
		return false, 'Room is not enabled for webhook control: ' .. tostring(roomId)
	end
	if (not roomSet[roomId]) then
		roomSet[roomId] = true
		table.insert(roomIds, roomId)
	end
	return true
end

local function ResolveRooms(value)
	local roomIds = {}
	local roomSet = {}

	if (type(value) == 'table') then
		for _, item in pairs(value) do
			local ok, err = AddResolvedRoom(roomIds, roomSet, item)
			if (not ok) then
				return nil, err
			end
		end
	else
		value = Trim(value or '')
		local lowerValue = string.lower(value)
		if (value == '') then
			if (#CONTROL_ROOMS == 1) then
				AddResolvedRoom(roomIds, roomSet, CONTROL_ROOMS[1])
			else
				return nil, 'Specify room, room_id, rooms, or use room=all'
			end
		elseif (lowerValue == 'all' or value == '*') then
			local sourceRooms = CONTROL_ROOMS
			if (ALLOW_UNSELECTED_ROOMS and #CONTROL_ROOMS == 0) then
				sourceRooms = {}
				for _, room in ipairs(GetRooms(true)) do
					table.insert(sourceRooms, room.id)
				end
			end
			for _, roomId in ipairs(sourceRooms) do
				local ok, err = AddResolvedRoom(roomIds, roomSet, roomId)
				if (not ok) then
					return nil, err
				end
			end
		else
			for token in string.gmatch(value, '([^,]+)') do
				local ok, err = AddResolvedRoom(roomIds, roomSet, token)
				if (not ok) then
					return nil, err
				end
			end
		end
	end

	if (#roomIds == 0) then
		return nil, 'No rooms selected or resolved'
	end
	return roomIds, nil
end

local function ButtonSequence(buttonId, action)
	buttonId = tonumber(buttonId)
	local button = BUTTONS[buttonId]
	if (not button) then
		return nil, 'Unknown button: ' .. tostring(buttonId)
	end

	action = string.lower(Trim(action or 'tap'))
	local sequence = {}

	if (action == 'press' or action == 'push' or action == 'down') then
		if (button.DO_PUSH) then
			table.insert(sequence, button.DO_PUSH)
		end
	elseif (action == 'release' or action == 'up') then
		if (button.DO_RELEASE) then
			table.insert(sequence, button.DO_RELEASE)
		else
			return nil, 'Button has no release command'
		end
	elseif (action == 'click') then
		if (button.DO_CLICK) then
			table.insert(sequence, button.DO_CLICK)
		elseif (button.DO_PUSH) then
			table.insert(sequence, button.DO_PUSH)
			if (button.DO_RELEASE) then
				table.insert(sequence, button.DO_RELEASE)
			end
		end
	elseif (action == 'tap' or action == '') then
		if (button.DO_PUSH) then
			table.insert(sequence, button.DO_PUSH)
		end
		if (button.DO_RELEASE) then
			table.insert(sequence, button.DO_RELEASE)
		end
	else
		return nil, 'Unsupported action: ' .. tostring(action)
	end

	if (#sequence == 0) then
		return nil, 'No command resolved for button action'
	end
	return sequence, nil
end

local function ButtonSupportsAction(buttonId, action)
	local sequence = ButtonSequence(buttonId, action)
	return sequence ~= nil
end

local function RegisterCommand(name, definition)
	name = NormalizeCommand(name)
	if (name == '') then
		return
	end
	if (COMMAND_INDEX[name] == nil) then
		definition.name = name
		COMMAND_INDEX[name] = definition
	end
end

local function RegisterDirectCommand(command)
	command = NormalizeCommand(command)
	if (command ~= '') then
		RegisterCommand(command, {kind = 'direct', command = command})
	end
end

local function RegisterButtonCommand(name, buttonId)
	buttonId = tonumber(buttonId)
	if (BUTTONS[buttonId]) then
		RegisterCommand(name, {kind = 'action', button = buttonId})
	end
end

local function ResolveCommand(value, action)
	local buttonId = tonumber(value)
	if (buttonId and BUTTONS[buttonId]) then
		return ButtonSequence(buttonId, action)
	end

	local normalized = NormalizeCommand(value)
	if (normalized == '') then
		return nil, 'Missing command'
	end

	local definition = COMMAND_INDEX[normalized]
	if (definition and definition.kind == 'direct') then
		return {definition.command}, nil
	elseif (definition and definition.kind == 'action') then
		return ButtonSequence(definition.button, action)
	end

	if (ALLOW_RAW_ROOM_COMMANDS and string.match(normalized, '^[A-Z0-9_]+$')) then
		return {normalized}, nil
	end

	return nil, 'Command is not in the allowlist: ' .. normalized
end

local function CommandCatalog()
	local commands = {}
	for name, definition in pairs(COMMAND_INDEX) do
		local item = {
			name = name,
			kind = definition.kind,
		}
		if (definition.kind == 'direct') then
			item.sequence = {definition.command}
		else
			item.button = definition.button
			item.actions = {}
			for _, action in ipairs({'tap', 'press', 'release', 'click'}) do
				if (ButtonSupportsAction(definition.button, action)) then
					table.insert(item.actions, action)
				end
			end
		end
		table.insert(commands, item)
	end
	table.sort(commands, function(a, b)
		return a.name < b.name
	end)
	return {
		commands = commands,
		raw_enabled = ALLOW_RAW_ROOM_COMMANDS,
	}
end

-- Builds the unified command index from button definitions, aliases, and
-- non-button room commands. Called once during OnDriverInit.
local function BuildCommandIndex()
	COMMAND_INDEX = {}
	for id, commands in pairs(BUTTONS) do
		for _, command in pairs(commands) do
			RegisterDirectCommand(command)
			RegisterButtonCommand(string.gsub(command, '^START_', ''), id)
			RegisterButtonCommand(string.gsub(command, '^STOP_', ''), id)
		end
	end
	for name, id in pairs(COMMAND_ALIASES) do
		RegisterButtonCommand(name, id)
	end
	for command, _ in pairs(EXTRA_COMMANDS) do
		RegisterDirectCommand(command)
	end
end
