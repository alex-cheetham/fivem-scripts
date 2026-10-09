-- Statewide PD: units, uniforms, divisions, AI partners and real-officer backup requests.
local AI = Config.AI
local X = AIX

---------------------------------------------------------------------------
-- Uniforms (staff save them in game; every officer's AI units then wear them)
---------------------------------------------------------------------------
local UNIFORM_SLOTS = { default = true, backup = true, swat = true, k9 = true, transport = true, roadblock = true, spikes = true, partner = true, air = true }
local MAX_PER_SLOT = 6
local Uniforms = LoadJson('data/uniforms.json', nil)
if type(Uniforms) ~= 'table' then Uniforms = {} end
for k, v in pairs(AI.Uniforms or {}) do if Uniforms[k] == nil then Uniforms[k] = v end end

local function Publish() GlobalState.swpdUniforms = Uniforms end
Publish()

local function Int(v, lo, hi)
    v = math.floor(tonumber(v) or 0)
    if v < lo then v = lo elseif v > hi then v = hi end
    return v
end

-- Only keep numbers we expect: model name, 12 clothing slots, 8 prop slots, optional head blend.
local function CleanOutfit(o)
    if type(o) ~= 'table' then return nil end
    local model = tostring(o.model or ''):gsub('[^%w_]', ''):sub(1, 40)
    if model == '' then return nil end
    local out = { model = model, comps = {}, props = {}, label = X.CleanText(o.label or '', 30) }
    for i = 0, 11 do
        local c = type(o.comps) == 'table' and (o.comps[i] or o.comps[tostring(i)] or o.comps[i + 1])
        if type(c) == 'table' then out.comps[tostring(i)] = { Int(c[1] or c.d, 0, 512), Int(c[2] or c.t, 0, 64) } end
    end
    for i = 0, 7 do
        local p = type(o.props) == 'table' and (o.props[i] or o.props[tostring(i)] or o.props[i + 1])
        if type(p) == 'table' then out.props[tostring(i)] = { Int(p[1] or p.d, -1, 512), Int(p[2] or p.t, 0, 64) } end
    end
    if type(o.head) == 'table' then
        local h = o.head
        out.head = { Int(h[1], 0, 45), Int(h[2], 0, 45), Int(h[3], 0, 45), Int(h[4], 0, 45), Int(h[5], 0, 100), Int(h[6], 0, 100) }
    end
    if type(o.hair) == 'table' then out.hair = { Int(o.hair[1], 0, 63), Int(o.hair[2], 0, 63) } end
    return out
end

PoliceCallback('aiUniforms', function(src)
    return { ok = true, uniforms = Uniforms, admin = IsAdmin(src) }
end)

PoliceCallback('aiUniformSet', function(src, slot, outfit)
    if not IsAdmin(src) then return Fail('Staff only.') end
    if not UNIFORM_SLOTS[slot] then return Fail('Unknown unit.') end
    if X.Limited(src, 'uniform', 10) then return Fail('Slow down.') end
    local o = CleanOutfit(outfit)
    if not o then return Fail('Couldn\'t read that outfit.') end
    Uniforms[slot] = type(Uniforms[slot]) == 'table' and Uniforms[slot] or {}
    if #Uniforms[slot] >= MAX_PER_SLOT then table.remove(Uniforms[slot], 1) end
    table.insert(Uniforms[slot], o)
    SaveJson('data/uniforms.json', Uniforms)
    Publish()
    return { ok = true, uniforms = Uniforms, count = #Uniforms[slot] }
end)

PoliceCallback('aiUniformReset', function(src, slot)
    if not IsAdmin(src) then return Fail('Staff only.') end
    if slot == 'all' then Uniforms = {} elseif UNIFORM_SLOTS[slot] then Uniforms[slot] = nil else return Fail('Unknown unit.') end
    SaveJson('data/uniforms.json', Uniforms)
    Publish()
    return { ok = true, uniforms = Uniforms }
end)

---------------------------------------------------------------------------
-- Divisions
---------------------------------------------------------------------------
local DIV = {}
for _, d in ipairs(AI.Divisions or {}) do DIV[d.key] = d end

function DivisionOf(src)
    local s = X.StatsOf(src)
    local d = s and s.division
    return (d and DIV[d]) and d or 'patrol'
end

PoliceCallback('aiDivision', function(src, key)
    if not DIV[key] then return Fail('Unknown division.') end
    local s = X.StatsOf(src)
    if not s then return Fail() end
    s.division = key
    X.MarkStats()
    X.Log(src, 'Division: ' .. DIV[key].label)
    return X.PatrolState(src)
end)

---------------------------------------------------------------------------
-- AI partner: the server needs to know which ped is your partner so it can act "near" for you
---------------------------------------------------------------------------
PartnerNet = {}

PoliceCallback('aiPartner', function(src, netId)
    if not netId then PartnerNet[src] = nil return { ok = true } end
    local ent = X.EntityFromNet(netId, 'any')
    if not ent or IsPedAPlayer(ent) or not X.Near(src, ent, 60.0) then return Fail('Partner not found.') end
    -- must be a unit ped this officer spawned, never someone they've stopped
    local st = Entity(ent).state
    if st.swai or not st.swpd then return Fail('That isn\'t your partner.') end
    if NetworkGetFirstEntityOwner and NetworkGetFirstEntityOwner(ent) ~= src then return Fail('That isn\'t your partner.') end
    PartnerNet[src] = tonumber(netId)
    return { ok = true }
end)

---------------------------------------------------------------------------
-- Real-officer backup: requests go to every other on-duty officer, who can respond with Y
---------------------------------------------------------------------------
local Requests = {}     -- [id] = { src, label, street, code, at, responders = { [src] = true } }
local reqSeq = 0

local function PlayerPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

function BackupRequest(src, label, street, code)
    if not Online(src) then return end
    if X.Limited(src, 'backupReq', 3) then return end
    local pos = PlayerPos(src)
    if not pos then return end
    reqSeq = reqSeq + 1
    local id = reqSeq
    Requests[id] = { src = src, label = X.CleanText(label, 60), street = X.CleanText(street or '', 60), code = tonumber(code) or 2, at = os.time(), responders = {} }
    local r = Requests[id]
    local n = 0
    for _, pl in ipairs(GetPlayers()) do
        pl = tonumber(pl)
        if pl ~= src and IsPolice(pl) and Duty(pl) then
            n = n + 1
            TriggerClientEvent(EV .. 'aiBackupReq', pl, { id = id, from = OfficerLabel(src), label = r.label, street = r.street, code = r.code, pos = pos, seconds = 30 })
        end
    end
    return id, n
end

PoliceCallback('backupRespond', function(src, id)
    local r = Requests[tonumber(id) or 0]
    if not r or not Online(r.src) then return Fail('That request has closed.') end
    if r.src == src then return Fail() end
    if not r.responders[src] then
        r.responders[src] = true
        Notify(r.src, ('~b~%s~s~ is responding to your %s.'):format(OfficerLabel(src), r.label:lower()))
        TriggerClientEvent(EV .. 'aiRadio', r.src, OfficerLabel(src) .. ': Show me responding, en route.')
    end
    return { ok = true, pos = PlayerPos(r.src), from = OfficerLabel(r.src), label = r.label }
end)

-- Responders' route blip keeps up with the officer who asked
PoliceCallback('backupWhere', function(src, id)
    local r = Requests[tonumber(id) or 0]
    if not r or not r.responders[src] or not Online(r.src) then return { ok = false } end
    if os.time() - r.at > 900 then return { ok = false } end
    return { ok = true, pos = PlayerPos(r.src) }
end)

PoliceCallback('backupCancel', function(src)
    for id, r in pairs(Requests) do
        if r.src == src then
            for pl in pairs(r.responders) do
                if Online(pl) then TriggerClientEvent(EV .. 'aiBackupClear', pl, id) end
            end
            Requests[id] = nil
        end
    end
    return { ok = true }
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for id, r in pairs(Requests) do
            if now - r.at > 900 or not Online(r.src) then Requests[id] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    PartnerNet[source] = nil
end)
