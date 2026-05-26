-- Runtime state and configuration defaults
-- All shared module-level variables are declared here so every subsequent
-- source file can reference them after concatenation.

local DRIVER_VERSION = '1.0.0'
local DEFAULT_PORT = 5080
local DEFAULT_MAX_CLIENTS = 8
local DEFAULT_MAX_REQUEST_BYTES = 8192

local SERVER = nil
local RESTART_TIMER = nil
local LATE_INIT_DONE = false
local DRIVER_DESTROYING = false

local CLIENTS = {}
local CLIENT_COUNT = 0

local CONTROL_ROOMS = {}
local CONTROL_ROOM_SET = {}
local ROOM_CACHE = nil

local DEBUGPRINT = false
local SERVICE_ENABLED = true
local HTTP_PORT = DEFAULT_PORT
local BIND_ADDRESS = '!all'
local MAX_CLIENTS = DEFAULT_MAX_CLIENTS
local MAX_REQUEST_BYTES = DEFAULT_MAX_REQUEST_BYTES
local ALLOW_UNSELECTED_ROOMS = false
local ALLOW_RAW_ROOM_COMMANDS = false
local ALLOWED_CLIENT_IPS = {}

local MAX_PRESETS_PER_ROOM = 5
local MAX_ROOM_SLOTS = 8
local ROOM_PRESETS = {}

-- ROOM_SLOT_ASSIGN[slotIndex] = roomId or nil, set by RefreshRoomSlots().
-- Lets OnPropertyChanged for "Room N Preset P" look up which room owns slot N.
local ROOM_SLOT_ASSIGN = {}

-- Populated by BuildCommandIndex() at driver init time.
local COMMAND_INDEX = {}

local HTTP_REASONS = {
	[200] = 'OK',
	[204] = 'No Content',
	[400] = 'Bad Request',
	[401] = 'Unauthorized',
	[403] = 'Forbidden',
	[404] = 'Not Found',
	[405] = 'Method Not Allowed',
	[413] = 'Payload Too Large',
	[429] = 'Too Many Requests',
	[500] = 'Internal Server Error',
	[503] = 'Service Unavailable',
}
