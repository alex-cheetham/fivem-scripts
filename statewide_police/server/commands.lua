-- /police and the staff setup commands
local function T(v) return { x = math.floor(v.x * 100) / 100, y = math.floor(v.y * 100) / 100, z = math.floor(v.z * 100) / 100 } end

local function Save()
    SaveJson('data/points.json', Points)
    BroadcastPoints()
end

local function Handle(src, args)
    local sub = (args[1] or ''):lower()
    if sub == 'menu' then
        if src > 0 then TriggerClientEvent(EV .. 'openMenu', src) end
        return
    end
    if not IsAdmin(src) then return Notify(src, 'Staff only.') end
    if src == 0 and sub ~= 'resetpoints' and sub ~= 'clearprops' then return Notify(src, 'Do that in game.') end
    local p = GetPoints()
    local here = src > 0 and GetEntityCoords(GetPlayerPed(src)) or nil

    if sub == 'addstation' then
        local label = table.concat(args, ' ', 2)
        if #label < 3 then return Notify(src, 'Usage: /policeaddstation <label>') end
        local pt = T(here)
        p.stations[#p.stations + 1] = { id = 'st' .. os.time(), label = label, pos = pt }
        Points.stations = p.stations
        Save()
        return Notify(src, ('Station "%s" added - you can book people and use the lab here.'):format(label))
    elseif sub == 'removestation' then
        local best, bd = nil, 30.0
        for i, s in ipairs(p.stations) do
            local d = #(here - V3(s.pos))
            if d < bd then best, bd = i, d end
        end
        if not best then return Notify(src, 'No station within 30m.') end
        local s = table.remove(p.stations, best)
        Points.stations = p.stations
        Save()
        return Notify(src, ('Removed %s.'):format(s.label))
    elseif sub == 'addchore' or sub == 'addcomserv' or sub == 'addjailspawn' then
        local key = ({ addchore = 'chores', addcomserv = 'comserv', addjailspawn = 'spawns' })[sub]
        local pt = T(here)
        if key == 'spawns' then pt.w = math.floor(GetEntityHeading(GetPlayerPed(src))) end
        p[key][#p[key] + 1] = pt
        Points[key] = p[key]
        Save()
        return Notify(src, ('Added (%d now).'):format(#p[key]))
    elseif sub == 'setrelease' then
        local pt = T(here)
        pt.w = math.floor(GetEntityHeading(GetPlayerPed(src)))
        Points.release = pt
        Save()
        return Notify(src, 'Prison release point set.')
    elseif sub == 'clearpoints' then
        local key = ({ chores = 'chores', comserv = 'comserv', jailspawns = 'spawns' })[(args[2] or ''):lower()]
        if not key then return Notify(src, 'Usage: /policeclearpoints <chores|comserv|jailspawns>') end
        Points[key] = {}
        Save()
        return Notify(src, 'Cleared - add new ones where you stand.')
    elseif sub == 'clearprops' then
        ClearAllProps()
        return Notify(src, 'Every police cone, barrier and spike strip was removed.')
    elseif sub == 'resetpoints' then
        Points = {}
        Save()
        return Notify(src, 'Points reset to config.lua.')
    end
end

RegisterCommandSet(CommandSets[1], Handle, IsAdmin)
