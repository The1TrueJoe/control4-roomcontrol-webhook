-- Runtime state and configuration defaults
-- All shared module-level variables are declared here so every subsequent
-- source file can reference them after concatenation.

local DRIVER_VERSION = '2.0.0'
local LOG_PREFIX = '[Room Control Webhook] '
local DEFAULT_PORT = 5080
local DEFAULT_MAX_CLIENTS = 8
local DEFAULT_MAX_REQUEST_BYTES = 8192
local ROOT_LINK_CLASS = 'ROOM_CONTROL_WEBHOOK'
local ROOT_LINK_BINDING_START = 101
local ROOT_LINK_BINDING_END = 116

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
local ROOM_PRESETS = {}
local MAX_CUSTOM_BUTTONS = 20

-- Linked child room driver registry. The root driver owns the HTTP server;
-- child drivers connected over ROOT_LINK_CLASS own per-room presets/buttons.
local ROOM_CHILDREN = {}
local ROOM_CHILDREN_BY_ROOM = {}
local LINKED_CHILDREN = {}

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
