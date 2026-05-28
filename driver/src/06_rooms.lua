-- Room discovery and caching.
-- Queries the project hierarchy and/or project items to build a list of rooms,
-- then caches the result in ROOM_CACHE until invalidated.

local function XmlUnescape(value)
	value = tostring(value or '')
	value = string.gsub(value, '&lt;', '<')
	value = string.gsub(value, '&gt;', '>')
	value = string.gsub(value, '&quot;', '"')
	value = string.gsub(value, '&apos;', "'")
	value = string.gsub(value, '&amp;', '&')
	return value
end

local function GetRoomName(roomId)
	local name = SafeCall(function()
		return C4:ListGetDeviceName(roomId)
	end)
	if (name == nil or name == '') then
		name = 'Room ' .. tostring(roomId)
	end
	return tostring(name)
end

local function AddRoom(roomsById, roomId, roomName)
	roomId = tonumber(roomId)
	if (roomId and roomId > 0 and roomsById[roomId] == nil) then
		roomsById[roomId] = {
			id = roomId,
			name = tostring(roomName or GetRoomName(roomId)),
			enabled = (CONTROL_ROOM_SET[roomId] == true),
		}
	end
end

local function CollectRoomsFromHierarchyNode(node, nodeId, roomsById, visited)
	if (type(node) ~= 'table') then
		return
	end
	if (visited[node]) then
		return
	end
	visited[node] = true

	local roomId = tonumber(node.id or node.ID or node.locationId or node.locationID or nodeId)
	local roomName = node.name or node.Name or node.locationName or node.location_name
	local nodeType = string.lower(tostring(node.type or node.Type or node.locationType or node.location_type or ''))

	if (nodeType == 'room' and roomId) then
		AddRoom(roomsById, roomId, roomName)
	end

	for key, child in pairs(node) do
		if (type(child) == 'table' and key ~= 'parent' and key ~= 'Parent') then
			CollectRoomsFromHierarchyNode(child, key, roomsById, visited)
		end
	end
end

local function CollectRoomsFromProjectItems(roomsById)
	local xml = SafeCall(function()
		return C4:GetProjectItems('LOCATIONS', 'LIMIT_DEVICE_DATA', 'NO_ROOT_TAGS')
	end)
	if (type(xml) ~= 'string' or xml == '') then
		return
	end

	local function parseLocation(fragment, firstTagPattern)
		local attrs = string.match(fragment, firstTagPattern) or ''
		local roomId = string.match(attrs, 'id="(%d+)"') or string.match(attrs, 'idDevice="(%d+)"') or string.match(fragment, '<id>(%d+)</id>') or string.match(fragment, '<iddevice>(%d+)</iddevice>')
		local nodeType = string.match(attrs, 'type="([^"]+)"') or string.match(fragment, '<type>(.-)</type>') or ''
		local roomName = string.match(attrs, 'name="([^"]+)"') or string.match(fragment, '<name>(.-)</name>') or string.match(fragment, '<displayname>(.-)</displayname>')
		if (string.lower(nodeType) == 'room' and roomId) then
			AddRoom(roomsById, roomId, XmlUnescape(roomName or ''))
		end
	end

	for fragment in string.gmatch(xml, '<location[^>]*>.-</location>') do
		parseLocation(fragment, '<location([^>]*)>')
	end
	for fragment in string.gmatch(xml, '<room[^>]*>.-</room>') do
		local attrs = string.match(fragment, '<room([^>]*)>') or ''
		local roomId = string.match(attrs, 'id="(%d+)"') or string.match(fragment, '<id>(%d+)</id>')
		local roomName = string.match(attrs, 'name="([^"]+)"') or string.match(fragment, '<name>(.-)</name>')
		AddRoom(roomsById, roomId, XmlUnescape(roomName or ''))
	end
end

local function RefreshRoomCache()
	local roomsById = {}

	local hierarchy = SafeCall(function()
		return C4:GetProjectHierarchy()
	end)
	if (type(hierarchy) == 'table') then
		CollectRoomsFromHierarchyNode(hierarchy, nil, roomsById, {})
	end

	if (next(roomsById) == nil) then
		CollectRoomsFromProjectItems(roomsById)
	end

	for _, roomId in ipairs(CONTROL_ROOMS) do
		AddRoom(roomsById, roomId, GetRoomName(roomId))
	end

	local rooms = {}
	for _, room in pairs(roomsById) do
		room.enabled = (CONTROL_ROOM_SET[room.id] == true)
		table.insert(rooms, room)
	end

	table.sort(rooms, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)

	ROOM_CACHE = rooms
	return rooms
end

local function GetRooms(refresh)
	if (refresh or ROOM_CACHE == nil) then
		return RefreshRoomCache()
	end
	return ROOM_CACHE
end
