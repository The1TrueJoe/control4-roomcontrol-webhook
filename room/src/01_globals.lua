-- Room Control Webhook Room child driver globals.

local DRIVER_VERSION = '2.0.0'
local LOG_PREFIX = '[Room Control Webhook Room] '
local ROOT_LINK_CLASS = 'ROOM_CONTROL_WEBHOOK'
local ROOT_LINK_BINDING_ID = 101
local BUTTON_LINK_CLASS = 'BUTTON_LINK'
local BUTTON_ID_BASE = 200
local BUTTON_COUNT = 20
local MAX_PRESETS_PER_ROOM = 5

local LATE_INIT_DONE = false
local DRIVER_DESTROYING = false
local DEBUGPRINT = false
local ACCEPT_CONTROL = true

local ROOT_DEVICE_ID = nil
local ROOT_BINDING_ID = nil
local ROOM_ID = nil
local ROOM_NAME = ''

local BUTTONS = {}
local PRESETS = {}
