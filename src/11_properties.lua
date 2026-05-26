-- Composer property change handlers.
-- Each property value is parsed and applied to the corresponding runtime state.

local function ParseControlRooms(value)
	CONTROL_ROOMS = {}
	CONTROL_ROOM_SET = {}
	for roomIdText in string.gmatch(tostring(value or ''), '(%d+)') do
		local roomId = tonumber(roomIdText)
		if (roomId and not CONTROL_ROOM_SET[roomId]) then
			table.insert(CONTROL_ROOMS, roomId)
			CONTROL_ROOM_SET[roomId] = true
		end
	end
	ROOM_CACHE = nil
end

local function ParseAllowedClientIps(value)
	ALLOWED_CLIENT_IPS = {}
	for tokenText in string.gmatch(tostring(value or ''), '([^,]+)') do
		local token = Trim(tokenText)
		if (token ~= '') then
			ALLOWED_CLIENT_IPS[token] = true
		end
	end
end

-- ── Composer per-room slot properties ──────────────────────────────────────
-- Each of the 8 static room slots in driver.xml has:
--   "Room N Name"     STRING readonly  — shows which C4 room occupies the slot
--   "Room N Preset P" DEVICE_SELECTOR  — integrator picks source device directly
-- When Control Rooms changes, rooms are (re)assigned to slots 1-8 in sorted
-- order.  Removed rooms have their preset data cleared.  Empty slots are hidden.

local function SetComposerPropertyHidden(name, hidden)
        if (C4 and C4.SetPropertyAttribs) then
                SafeCall(function()
                        C4:SetPropertyAttribs(name, hidden and 1 or 0)
                end)
        end
end

local function SlotNameProp(slot)
        return 'Room ' .. tostring(slot) .. ' Name'
end

local function SlotPresetProp(slot, presetIndex)
        return 'Room ' .. tostring(slot) .. ' Preset ' .. tostring(presetIndex)
end

local function ShowRoomSlot(slot, show)
        SetComposerPropertyHidden(SlotNameProp(slot), not show)
        for p = 1, MAX_PRESETS_PER_ROOM do
                SetComposerPropertyHidden(SlotPresetProp(slot, p), not show)
        end
end

local function RefreshRoomSlots()
        -- Assign rooms to slots in ascending room-ID order.
        local sortedRooms = {}
        for _, roomId in ipairs(CONTROL_ROOMS) do
                table.insert(sortedRooms, roomId)
        end
        table.sort(sortedRooms)

        ROOM_SLOT_ASSIGN = {}
        for slot = 1, MAX_ROOM_SLOTS do
                local roomId = sortedRooms[slot]
                ROOM_SLOT_ASSIGN[slot] = roomId
                if (roomId) then
                        UpdateDriverProperty(SlotNameProp(slot),
                                GetRoomName(roomId) .. '  (ID: ' .. tostring(roomId) .. ')')
                        ShowRoomSlot(slot, true)
                else
                        UpdateDriverProperty(SlotNameProp(slot), '')
                        ShowRoomSlot(slot, false)
                end
        end
end

local function CleanupRoomPresetProperties()
        ROOM_SLOT_ASSIGN = {}
        for slot = 1, MAX_ROOM_SLOTS do
                UpdateDriverProperty(SlotNameProp(slot), '')
                ShowRoomSlot(slot, false)
        end
end

local function HandleRoomPresetPropertyChange(slotIndex, presetIndex, rawValue)
        local roomId = ROOM_SLOT_ASSIGN[slotIndex]
        if (not roomId) then
                return
        end

        -- The DEVICE_SELECTOR property value is the selected device's numeric ID.
        -- Mirror the reference driver: just store the raw ID; resolve source type
        -- dynamically at execution time (avoids stale type from config-time lookup).
        local deviceId = tonumber(rawValue) or 0
        local key = RoomPresetKey(roomId)
        ROOM_PRESETS[key] = ROOM_PRESETS[key] or {}

        if (deviceId == 0) then
                ROOM_PRESETS[key][presetIndex] = nil
        else
                local sourceName = SafeCall(function()
                        return C4:ListGetDeviceName(deviceId)
                end) or ('Device ' .. tostring(deviceId))
                ROOM_PRESETS[key][presetIndex] = {
                        name = 'Preset ' .. tostring(presetIndex),
                        source = deviceId,
                        source_name = sourceName,
                }
        end

        PersistData.SourcePresets = ROOM_PRESETS
end

-- ── Property apply dispatcher ───────────────────────────────────────────────

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
	elseif (name == 'Control Rooms') then
		local oldRoomSet = CONTROL_ROOM_SET
		ParseControlRooms(value)
		-- oldRoomSet may be nil on same-instance LuaJIT reload (destroyed then re-inited)
		for roomId, _ in pairs(oldRoomSet or {}) do
			if (not CONTROL_ROOM_SET[roomId]) then
				ROOM_PRESETS[RoomPresetKey(roomId)] = nil
			end
		end
		PersistData = PersistData or {}
		PersistData.SourcePresets = ROOM_PRESETS
		if (LATE_INIT_DONE) then
			RefreshRoomSlots()
		end
	elseif (name == 'Allow Unselected Rooms') then
		ALLOW_UNSELECTED_ROOMS = (value == 'On')
	elseif (name == 'Allow Raw Room Commands') then
		ALLOW_RAW_ROOM_COMMANDS = (value == 'On')
	elseif (name == 'Allowed Client IPs') then
		ParseAllowedClientIps(value)
	elseif (name == 'Password') then
		-- Read on each request; no restart required.
	else
		-- "Room N Preset P" DEVICE_SELECTOR changed.
		local slot, preset = string.match(name, '^Room (%d+) Preset (%d+)$')
		if (slot) then
			HandleRoomPresetPropertyChange(tonumber(slot), tonumber(preset), value)
		end
	end
end
