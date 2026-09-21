-- Original CoA companion addon. Server state is authoritative.
CoASeason = { prefix = "COASEASON", pending = {}, listeners = {}, queue = {}, serial = 0 }
local A = CoASeason
local MAX = 4294967295
function A.Encode(value)
    return (tostring(value):gsub("([^%w %-%._])", function(c) return string.format("%%%02X", string.byte(c)) end))
end
function A.Decode(value)
    if not value or #value > 600 then return nil end
    local rest = value:gsub("%%[%x][%x]", "")
    if rest:find("%%") then return nil end
    local decoded = value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    if decoded:find("[%z\1-\31\127]") then return nil end
    return decoded
end
function A.Number(value)
    if type(value) ~= "string" or not value:match("^%d+$") then return nil end
    local number = tonumber(value)
    if not number or number > MAX then return nil end
    return number
end
local function split(value)
    local fields = {}
    for part in (value .. "|"):gmatch("(.-)|") do fields[#fields + 1] = part end
    return fields
end
function A.Notify(kind, value)
    for _, listener in ipairs(A.listeners) do listener(kind, value) end
end
function A.Request(operation, ...)
    if #A.queue >= 16 then A.Notify("error", "Too many requests. Please wait."); return nil end
    A.serial = A.serial + 1
    local id = "c" .. math.floor(GetTime() * 1000) .. "_" .. A.serial
    local fields = { "1", id, operation, ... }
    for i, value in ipairs(fields) do fields[i] = tostring(value) end
    local message = table.concat(fields, "|")
    if #A.prefix + #message + 1 > 255 then
        A.Notify("error", "This request is too long."); return nil
    end
    A.pending[id] = { time = GetTime(), operation = operation, action = select(1, ...) }
    A.queue[#A.queue + 1] = { id = id, message = message }
    return id
end
function A.Refresh(season)
    if A.refreshId then A.pending[A.refreshId] = nil end
    A.refreshId = season and A.Request("ADMIN", "GET", season) or A.Request("GET")
    return A.refreshId
end
local function fail(id, message)
    A.pending[id] = nil
    if A.refreshId == id then A.refreshId = nil end
    A.Notify("error", message)
end
local function numeric(fields, positions)
    for _, position in ipairs(positions) do
        fields[position] = A.Number(fields[position])
        if fields[position] == nil then return false end
    end
    return true
end
function A.Receive(message, sender)
    if sender ~= UnitName("player") or type(message) ~= "string" or #message > 245 then return end
    local f = split(message)
    if f[1] ~= "1" then return end
    local id, kind = f[2], f[3]
    local request = A.pending[id]
    if not request then return end
    if kind == "ERROR" or kind == "OK" then
        local text = A.Decode(f[4])
        if not text then return fail(id, "Invalid server response.") end
        A.pending[id] = nil
        A.Notify(kind == "ERROR" and "error" or "ok", text)
        local reads = { LIST=true, BROWSE=true, ACCOUNT=true, HISTORY=true, GET=true }
        if kind == "OK" and (request.operation == "BUY" or
            (request.operation == "ADMIN" and not reads[request.action])) then A.Notify("saved", id) end
        return
    end
    if kind == "BEGIN" then
        if id ~= A.refreshId or #f ~= 11 or not numeric(f, {4,5,7,8,9,10}) then return end
        local name = A.Decode(f[6])
        if not name or f[9] > 127 or f[10] > 1 then return fail(id, "Invalid season state.") end
        request.stage = { season=f[4], revision=f[5], name=name, progress=f[7], points=f[8],
            mask=f[9], admin=f[10] == 1, status=f[11], settings={}, tiers={}, rewards={}, keys={}, rows=0 }
        return
    end
    if kind == "ACCOUNT" then
        if #f == 7 and numeric(f, {4,5,6,7}) then
            A.Notify("account", {id=f[4],season=f[5],progress=f[6],points=f[7]})
            A.pending[id] = nil
        end
        return
    end
    if kind == "SEASON" then
        if #f == 7 and numeric(f, {4,6}) and A.Decode(f[7]) then
            A.Notify("season", {id=f[4],status=f[5],revision=f[6],name=A.Decode(f[7])})
        end
        return
    end
    if kind == "BROWSE" then
        if #f == 7 and numeric(f, {5,6}) and A.Decode(f[7]) then
            A.Notify("browse", {type=f[4],target=f[5],preview=f[6],name=A.Decode(f[7])})
        end
        return
    end
    if kind == "HISTORY" then
        if #f == 6 and numeric(f, {4,5}) and A.Decode(f[6]) then
            A.Notify("history", {time=f[4],account=f[5],action=A.Decode(f[6])})
        end
        return
    end
    local s = request.stage
    if not s then return end
    if kind == "END" then
        local rows = A.Number(f[4])
        if #f ~= 4 or rows ~= s.rows or #s.tiers ~= 7 then return fail(id, "Incomplete season data; refresh.") end
        local threshold = 0
        for i=1,7 do
            if not s.tiers[i] or s.tiers[i].threshold <= threshold then
                return fail(id, "Invalid season tiers.")
            end
            threshold = s.tiers[i].threshold
        end
        table.sort(s.rewards, function(x,y) return x.order == y.order and x.id < y.id or x.order < y.order end)
        s.keys, s.rows = nil, nil
        A.state = s
        A.pending[id], A.refreshId = nil, nil
        A.Notify("state", s)
        return
    end
    local key
    if kind == "SETTING" and #f == 5 then
        local n = A.Number(f[5])
        if not n or not f[4]:match("^[a-z_]+$") then return fail(id, "Invalid season setting.") end
        key = "s" .. f[4]
        s.settings[f[4]] = n
    elseif kind == "TIER" and #f == 6 and numeric(f, {4,5,6}) then
        if f[4] < 1 or f[4] > 7 or f[5] == 0 then return fail(id, "Invalid tier.") end
        key = "t" .. f[4]
        s.tiers[f[4]] = {threshold=f[5],points=f[6]}
    elseif kind == "REWARD" and #f == 15 and numeric(f, {4,6,7,8,9,10,11,12,15}) then
        local name, category = A.Decode(f[13]), A.Decode(f[14])
        if not name or not category or f[10] > 7 or f[11] > 1 or f[15] > 1 then return fail(id, "Invalid reward.") end
        if f[5] ~= "appearance" and f[5] ~= "vanity" and f[5] ~= "item" then return fail(id, "Unknown reward type.") end
        key = "r" .. f[4]
        s.rewards[#s.rewards+1] = {id=f[4],type=f[5],target=f[6],preview=f[7],count=f[8],cost=f[9],
            minTier=f[10],enabled=f[11] == 1,order=f[12],name=name,category=category,owned=f[15] == 1}
    else
        return fail(id, "Malformed season snapshot.")
    end
    if s.keys[key] or s.rows >= 512 then return fail(id, "Duplicate or oversized season snapshot.") end
    s.keys[key], s.rows = true, s.rows + 1
end
function A.Tick(elapsed)
    A.throttle = (A.throttle or 0) + elapsed
    if A.throttle >= 0.3 and #A.queue > 0 then
        A.throttle = 0
        local entry = table.remove(A.queue, 1)
        if A.pending[entry.id] then
            SendAddonMessage(A.prefix, entry.message, "WHISPER", UnitName("player"))
        end
    end
    local expired = {}
    for id, request in pairs(A.pending) do
        if GetTime() - request.time > 15 then expired[#expired + 1] = id end
    end
    for _, id in ipairs(expired) do fail(id, "Season request timed out. Refresh to check its result.") end
end
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
    if event == "PLAYER_LOGIN" then A.Refresh()
    elseif prefix == A.prefix then A.Receive(message, sender) end
end)
frame:SetScript("OnUpdate", function(_, elapsed) A.Tick(elapsed) end)
