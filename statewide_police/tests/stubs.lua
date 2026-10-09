-- Plain-Lua stubs for FiveM natives so the server scripts can be loaded outside the game (used by tests/server_test.lua)
-- FiveM stubs for loading the resource in plain Lua 5.4
local vmeta = {}
vmeta.__index = vmeta
vmeta.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
vmeta.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vmeta.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return vector3(a.x * b, a.y * b, a.z * b) end
vmeta.__div = function(a, b) return vector3(a.x / b, a.y / b, a.z / b) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
function vector4(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, vmeta) end
json = { encode = function() return '{}' end, decode = function() return nil end }
Threads, Callbacks, NetEvents, Handlers, Commands = {}, {}, {}, {}, {}
function CreateThread(fn) Threads[#Threads + 1] = fn end
Citizen = { CreateThread = CreateThread, Wait = function() end }
function Wait() end
function SetTimeout(ms, fn) Threads[#Threads + 1] = fn end
function RegisterNetEvent(name, fn) NetEvents[name] = fn end
function AddEventHandler(name, fn) Handlers[name] = Handlers[name] or {} table.insert(Handlers[name], fn) end
function RegisterCommand(name, fn) Commands[name] = fn end
function GetCurrentResourceName() return 'statewide_police' end
function LoadResourceFile() return nil end
function SaveResourceFile() end
STARTED = {}
function GetResourceState(r) return STARTED[r] and 'started' or 'missing' end
function IsDuplicityVersion() return true end
PLAYERS = { 1 }
function GetPlayers() local o = {} for _, p in ipairs(PLAYERS) do o[#o + 1] = tostring(p) end return o end
function GetPlayerName(src) for _, p in ipairs(PLAYERS) do if tonumber(src) == p then return 'Officer' .. p end end return nil end
function GetPlayerPed(src) return 100 + tonumber(src) end
PLAYER_POS = vector3(1850.0, 3700.0, 33.0)
function GetEntityCoords(e) return ENT_POS and ENT_POS[e] or PLAYER_POS end
function GetPlayerIdentifiers(src) return { 'license:abc' .. tostring(src) } end
function GetPlayerIdentifierByType(src) return 'license:abc' .. tostring(src) end
function IsPlayerAceAllowed() return true end
function GetVehiclePedIsIn() return 0 end
function GetVehicleNumberPlateText() return '' end
SENT = {}
EXPORT_CALLS = {}
ENT_POS = {}
function TriggerClientEvent(name, src, ...) table.insert(SENT, { name = name, src = src, args = { ... } }) end
function TriggerEvent() end
function Entity() return { state = { set = function() end } } end
exports = setmetatable({}, { __index = function(_, res) return setmetatable({}, { __index = function(_, fn)
    return function(_, ...) table.insert(EXPORT_CALLS, { res = res, fn = fn, args = { ... } }) end end }) end })
-- anything else: a harmless function (natives we don't care about here)
setmetatable(_G, { __index = function(_, k)
    if type(k) == 'string' and k:match('^%u') then
        local m = rawget(_G, 'MISSING') or {}
        rawset(_G, 'MISSING', m)
        m[k] = true
        return function() return nil end
    end
end })
function GetHashKey(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end return h end
GlobalState = {}
LocalPlayer = { state = {} }
