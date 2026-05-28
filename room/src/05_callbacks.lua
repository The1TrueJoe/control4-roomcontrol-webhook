-- DriverWorks callbacks for the linked room child driver.

function OnDriverInit(driverInitType)
	DRIVER_DESTROYING = false
	LATE_INIT_DONE = false
	ROOT_DEVICE_ID = nil
	ROOT_BINDING_ID = nil
	ROOM_ID = nil
	ROOM_NAME = ''
	BUTTONS = {}
	PRESETS = {}

	PersistData = PersistData or {}
	PersistData.Buttons = PersistData.Buttons or {}

	for index, name in pairs(PersistData.Buttons) do
		RegisterButton(tonumber(index), name)
	end

	if (C4 and C4.AddVariable) then
		SafeCall(function() C4:AddVariable('Current Room', '', 'STRING', true, false) end)
		SafeCall(function() C4:AddVariable('Last Triggered Button', '', 'STRING', true, false) end)
		SafeCall(function() C4:AddVariable('Root Link Status', 'Not linked', 'STRING', true, false) end)
	end

	UpdateDriverProperty('Driver Version', DRIVER_VERSION)
end

function OnDriverLateInit(driverInitType)
	for name, _ in pairs(Properties or {}) do
		ApplyProperty(name)
	end
	UpdateRoomContext()
	BuildPresets()
	ReloadButtons()
	ResolveRootFromBinding()
	LATE_INIT_DONE = true
	RegisterWithRoot()
end

function OnDriverDestroyed(driverInitType)
	DRIVER_DESTROYING = true
	LATE_INIT_DONE = false
	UnregisterFromRoot()
	BUTTONS = {}
	PRESETS = {}
	ROOT_DEVICE_ID = nil
	ROOT_BINDING_ID = nil
	ROOM_ID = nil
	ROOM_NAME = ''
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

	if (command == 'REGISTER_WITH_ROOT') then
		RegisterWithRoot(tParams)
	elseif (command == 'RELOAD_BUTTONS') then
		ReloadButtons()
		RegisterWithRoot()
	elseif (command == 'TRIGGER_BUTTON' or command == 'TRIGGER_CUSTOM_BUTTON') then
		if (not ACCEPT_CONTROL) then
			UpdateDriverProperty('Last Error', 'Room control disabled')
			return
		end
		local buttonValue = tParams.Button or tParams.ButtonIndex or tParams['Button Name'] or tParams.button or tParams.name
		local action = tParams.Action or tParams.action or 'tap'
		local button = FindButton(buttonValue)
		if (not button) then
			UpdateDriverProperty('Last Error', 'Button not found: ' .. tostring(buttonValue))
			return
		end
		local ok, err = FireButton(button, action)
		if (not ok) then
			UpdateDriverProperty('Last Error', err)
		end
	else
		DebugLog('Unhandled ExecuteCommand: ' .. tostring(strCommand))
	end
end

function OnBindingChanged(idBinding, strClass, bIsBound, otherDeviceID, otherBindingID)
	if (DRIVER_DESTROYING) then
		return
	end
	if (tonumber(idBinding) ~= ROOT_LINK_BINDING_ID or strClass ~= ROOT_LINK_CLASS) then
		return
	end

	local isBound = (bIsBound == true or string.lower(tostring(bIsBound)) == 'true' or tostring(bIsBound) == '1')
	if (isBound) then
		ROOT_DEVICE_ID = tonumber(otherDeviceID)
		ROOT_BINDING_ID = tonumber(otherBindingID) or ROOT_LINK_BINDING_ID
		UpdateDriverProperty('Root Link Status', 'Linked to root driver ' .. tostring(ROOT_DEVICE_ID))
		RegisterWithRoot()
	else
		UnregisterFromRoot()
		ROOT_DEVICE_ID = nil
		ROOT_BINDING_ID = nil
		UpdateDriverProperty('Root Link Status', 'Not linked')
	end
end

function ReceivedFromProxy(idBinding, strCommand, tParams)
	if (strCommand == 'REQUEST_BUTTON_COLORS') then
		SafeCall(function()
			C4:SendToProxy(idBinding, 'BUTTON_COLORS', {ON_COLOR = '0000ff', OFF_COLOR = '000000'}, 'NOTIFY')
			C4:SendToProxy(idBinding, 'MATCH_LED_STATE', {STATE = false}, 'NOTIFY')
		end)
	end
end
