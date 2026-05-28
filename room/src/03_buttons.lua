-- Per-room custom button bindings.

local function ButtonPropertyName(index)
	return 'Button ' .. tostring(index) .. ' Name'
end

local function ButtonBindingId(index)
	return BUTTON_ID_BASE + tonumber(index)
end

local function RegisterButton(index, name)
	index = tonumber(index)
	if (not index or index < 1 or index > BUTTON_COUNT) then
		return
	end

	name = Trim(name)
	local bindingId = ButtonBindingId(index)
	PersistData = PersistData or {}
	PersistData.Buttons = PersistData.Buttons or {}

	if (name == '') then
		if (LATE_INIT_DONE and C4 and C4.RemoveDynamicBinding) then
			SafeCall(function()
				C4:RemoveDynamicBinding(bindingId)
			end)
		end
		BUTTONS[index] = nil
		PersistData.Buttons[index] = nil
		return
	end

	if (LATE_INIT_DONE and BUTTONS[index] and BUTTONS[index].name ~= name and C4 and C4.RemoveDynamicBinding) then
		SafeCall(function()
			C4:RemoveDynamicBinding(bindingId)
		end)
	end

	if (C4 and C4.AddDynamicBinding) then
		SafeCall(function()
			C4:AddDynamicBinding(bindingId, 'CONTROL', false, name, BUTTON_LINK_CLASS, false, false)
		end)
	end

	BUTTONS[index] = {
		index = index,
		name = name,
		binding_id = bindingId,
	}
	PersistData.Buttons[index] = name
	DebugLog('Registered button ' .. tostring(index) .. ': ' .. name .. ' binding ' .. tostring(bindingId))
end

local function ReloadButtons()
	for index = 1, BUTTON_COUNT do
		RegisterButton(index, Properties and Properties[ButtonPropertyName(index)] or '')
	end
end

local function FindButton(buttonValue)
	local index = tonumber(buttonValue)
	if (index and BUTTONS[index]) then
		return BUTTONS[index]
	end

	local normalized = Normalize(buttonValue)
	for _, button in pairs(BUTTONS) do
		if (Normalize(button.name) == normalized) then
			return button
		end
	end
	return nil
end

local function SendButtonCommand(bindingId, command)
	SafeCall(function()
		C4:SendToProxy(bindingId, command, {}, 'COMMAND')
	end)
end

local function FireButton(button, action)
	if (type(button) ~= 'table') then
		return false, 'Button is not configured'
	end

	action = string.lower(Trim(action or 'tap'))
	if (action == 'push' or action == 'press' or action == 'down') then
		SendButtonCommand(button.binding_id, 'DO_PUSH')
	elseif (action == 'release' or action == 'up') then
		SendButtonCommand(button.binding_id, 'DO_RELEASE')
	elseif (action == 'click' or action == 'tap') then
		SendButtonCommand(button.binding_id, 'DO_PUSH')
		SendButtonCommand(button.binding_id, 'DO_RELEASE')
	else
		return false, 'Unsupported button action: ' .. tostring(action)
	end

	local last = os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. button.name .. ' (' .. action .. ')'
	UpdateDriverProperty('Last Triggered Button', last)
	SetDriverVariable('Last Triggered Button', last)
	return true, nil
end
