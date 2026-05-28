-- Room child driver utilities: device name lookup and room context refresh.
-- Generic utilities (Trim, Normalize, SafeCall, DebugLog, UpdateDriverProperty,
-- SetDriverVariable, BoolParam, FirstBoundId) live in shared/01_utils.lua.

local function GetDeviceName(deviceId)
	local name = SafeCall(function()
		return C4:ListGetDeviceName(deviceId)
	end)
	if (name == nil or name == '') then
		name = 'Device ' .. tostring(deviceId)
	end
	return tostring(name)
end

local function UpdateRoomContext()
	ROOM_ID = tonumber(SafeCall(function()
		return C4:RoomGetId()
	end))
	if (ROOM_ID) then
		ROOM_NAME = GetDeviceName(ROOM_ID)
		UpdateDriverProperty('Current Room', ROOM_NAME .. '  (ID: ' .. tostring(ROOM_ID) .. ')')
		SafeCall(function()
			C4:RenameDevice(C4:GetDeviceID(), ROOM_NAME)
		end)
	else
		ROOM_NAME = ''
		UpdateDriverProperty('Current Room', 'Unknown room')
	end
end
