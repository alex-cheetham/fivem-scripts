-- Every chat command this script adds.
-- /police on its own lists them all in chat. Most things are also in the police menu (F7).
-- The 4th value "true" marks a staff-only command.
CommandSets = {
    {
        base = Config.Command,
        title = 'Police',
        list = {
            { 'menu', '', 'Open the police menu (also F7)' },
            { 'addstation', '<label>', 'Add a station (booking desk + evidence lab) where you stand', true },
            { 'removestation', '', 'Remove the nearest station', true },
            { 'addchore', '', 'Add a prison chore spot where you stand', true },
            { 'addcomserv', '', 'Add a community service spot where you stand', true },
            { 'addjailspawn', '', 'Add a jail spawn point where you stand', true },
            { 'setrelease', '', 'Set the prison release point where you stand', true },
            { 'clearpoints', '<chores|comserv|jailspawns>', 'Remove all points of that type', true },
            { 'clearprops', '', 'Remove every cone, barrier and spike strip on the map', true },
            { 'resetpoints', '', 'Go back to the points in config.lua', true },
        },
        others = {
            { 'cuff', '[id]', '(Police) Handcuff the nearest person (again to uncuff)' },
            { 'zip', '[id]', '(Police) Zip-tie the nearest person' },
            { 'uncuff', '[id]', '(Police) Remove cuffs / zip ties' },
            { 'escort', '[id]', '(Police) Escort / let go of a restrained person' },
            { 'seat', '[id]', '(Police) Put the person you are escorting in the nearest vehicle' },
            { 'unseat', '[id]', '(Police) Take a restrained person out of a vehicle' },
            { 'frisk', '[id]', '(Police) Pat someone down for weapons' },
            { 'search', '[id]', '(Police) Full search - needs them cuffed or their consent' },
            { 'checkid', '[id]', '(Police) Check someone\'s ID, licences and record' },
            { 'breath', '[id]', '(Police) Breathalyse someone' },
            { 'drugtest', '[id]', '(Police) Drug swab someone' },
            { 'gsr', '[id]', '(Police) Gunshot residue test' },
            { 'dna', '[id]', '(Police) Take a DNA swab' },
            { 'ticket', '[id]', '(Police) Write a citation / fine' },
            { 'arrest', '[id]', '(Police) Book someone into jail (at a station)' },
            { 'comserv', '[id]', '(Police) Give someone community service' },
            { 'unjail', '<id>', '(Police) Release someone from jail / community service' },
            { 'runplate', '[plate]', '(Police) Run a plate (the vehicle in front if no plate given)' },
            { 'vehsearch', '', '(Police) Search the nearest vehicle' },
            { 'impound', '', '(Police) Impound the nearest empty vehicle' },
            { 'radar', '', '(Police) Vehicle speed radar on / off' },
            { 'spikes', '', '(Police) Deploy / pick up a spike strip' },
            { 'evidence', '', '(Police) Evidence mode - see casings and blood nearby' },
            { 'mdt', '', '(Police) Records, warrants and the evidence locker' },
            { 'badge', '', '(Police) Show your badge' },
            { 'patrol', '', '(Police) AI patrol computer - callouts, units, stats (also F10)' },
            { 'code4', '', '(Police) Close the AI callout you are on' },
            { 'callbackup', '', '(Police) Request an AI backup unit' },
            { 'calltransport', '', '(Police) Request AI prisoner transport' },
            { 'calltow', '', '(Police) Request an AI tow truck for the vehicle next to you' },
            { 'callems', '', '(Police) Request an AI ambulance' },
            { 'callcoroner', '', '(Police) Request an AI coroner' },
            { 'callair', '', '(Police) Request an AI air unit' },
            { 'dismissunits', '', '(Police) Send your AI units away' },
            { 'aicallout', '[type]', 'Force an AI callout to test it', true },
            { 'showid', '', 'Show your ID to the person next to you' },
            { 'fines', '', 'See and pay your fines' },
            { 'rpstatus', '<drink|drug name|clear> [minutes]', 'Roleplay what you\'ve had to drink or taken (breath / drug tests pick it up)' },
            { 'washhands', '', 'Wash gunshot residue off your hands (near water)' },
            { 'jailtime', '', 'How long you have left in jail / community service' },
        },
    },
}

---------------------------------------------------------------------------
-- How the commands work (you shouldn't need to touch anything below)
--   /<command> on its own lists every command in chat.
--   Each action is its own command, e.g. /parcelinvite 12, /parcelquit.
--   Staff commands only work for people with this script's admin ace.
--   "others" are separate commands this script adds that are listed too.
---------------------------------------------------------------------------
local function Usage(base, c)
    return '/' .. base .. c[1] .. (c[2] ~= '' and (' ' .. c[2]) or '')
end

if IsDuplicityVersion() then
    local HEAD = '<div style="margin:3px 0 1px;padding:5px 9px;border-radius:5px;background:rgba(241,196,15,.22);font-weight:700;">{0}</div>'
    local LINE = '<div style="padding:1px 9px;"><b style="color:#f7d774;">{0}</b> <span style="opacity:.85;">- {1}</span></div>'

    local function Chat(src, template, args)
        if src == 0 then return print(table.concat(args, '  ')) end
        TriggerClientEvent('chat:addMessage', src, { template = template, args = args })
    end

    function ShowCommands(src, set, isAdmin)
        Chat(src, HEAD, { set.title .. ' - commands' })
        local staff = false
        for _, c in ipairs(set.list) do
            if not c[4] then Chat(src, LINE, { Usage(set.base, c), c[3] })
            else staff = true end
        end
        for _, c in ipairs(set.others or {}) do
            if not c[4] then Chat(src, LINE, { Usage('', c), c[3] }) else staff = true end
        end
        if staff and isAdmin then
            Chat(src, HEAD, { set.title .. ' - staff commands' })
            for _, c in ipairs(set.list) do
                if c[4] then Chat(src, LINE, { Usage(set.base, c), c[3] }) end
            end
            for _, c in ipairs(set.others or {}) do
                if c[4] then Chat(src, LINE, { Usage('', c), c[3] }) end
            end
        end
    end

    -- handler(src, args) is the script's original command handler (args[1] = action)
    -- runBase = true: the base command still runs the handler (e.g. /licence shows your licences)
    function RegisterCommandSet(set, handler, isAdmin)
        RegisterCommand(set.base, function(src, args)
            if args[1] then return handler(src, args) end   -- the old "/parcel invite 12" style still works too
            if set.runBase then handler(src, {}) end
            ShowCommands(src, set, isAdmin(src))
        end, false)
        for _, c in ipairs(set.list) do
            local sub = c[1]
            RegisterCommand(set.base .. sub, function(src, args)
                handler(src, { sub, table.unpack(args) })
            end, false)
        end
    end
else
    local function Params(s)
        local out = {}
        for word in s:gmatch('%S+') do
            out[#out + 1] = { name = word:gsub('[<>%[%]]', ''), help = word }
        end
        return out
    end

    local function AddSuggestions()
        for _, set in ipairs(CommandSets) do
            TriggerEvent('chat:addSuggestion', '/' .. set.base, set.title .. ' - list all the commands' .. (set.baseHelp and (' (' .. set.baseHelp .. ')') or ''))
            for _, c in ipairs(set.list) do
                TriggerEvent('chat:addSuggestion', '/' .. set.base .. c[1], (c[4] and '(Staff) ' or '') .. c[3], Params(c[2]))
            end
            for _, c in ipairs(set.others or {}) do
                TriggerEvent('chat:addSuggestion', '/' .. c[1], (c[4] and '(Staff) ' or '') .. c[3], Params(c[2]))
            end
        end
    end

    CreateThread(function()
        Wait(3000)
        AddSuggestions()
    end)
    AddEventHandler('onClientResourceStart', function(res)
        if res == 'chat' then SetTimeout(1000, AddSuggestions) end
    end)
end
