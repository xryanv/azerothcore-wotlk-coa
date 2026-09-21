local root = arg[1] or "modules/mod-coa-season-progression/addon/CoA_SeasonProgression/"
local now, sent = 0, {}
function GetTime() return now end
function UnitName() return "Tester" end
function SendAddonMessage(...) sent[#sent + 1] = {...} end
function CreateFrame() return {RegisterEvent=function() end, SetScript=function() end} end

dofile(root .. "Protocol.lua")
local A = CoASeason
local count = 0
local function check(value, message) assert(value, message); count = count + 1 end
local function settingRows(id)
    for _, key in ipairs(A.settingKeys) do A.Receive("1|" .. id .. "|SETTING|" .. key .. "|0", "Tester") end
end
local function tierRow(id, i, assigned, completed)
    local kind = assigned and "appearance" or ""
    local target = assigned and (1000 + i) or 0
    local preview = assigned and target or 0
    local name = assigned and A.Encode("Reward " .. i) or ""
    A.Receive(table.concat({"1",id,"TIER",i,i*100,kind,target,preview,1,name,completed and 1 or 0}, "|"), "Tester")
end

check(A.Decode(A.Encode("a|b% é")) == "a|b% é", "text round trip")
check(A.Decode("%GG") == nil and A.Decode("%0A") == nil, "reject malformed/control text")
check(A.Number("1e3") == nil and A.Number("-1") == nil and A.Number("4294967296") == nil, "numeric validation")
local queued = #A.queue
check(A.Request("BUY", 1, 2, 3) == nil and #A.queue == queued, "BUY is never generated")

local request = A.Refresh()
A.Receive("1|" .. request .. "|BEGIN|1|3|First|90|0|0|active", "Other")
check(A.state == nil, "foreign sender ignored")
A.Receive("1|" .. request .. "|BEGIN|1|3|First|90|0|0|active", "Tester")
tierRow(request, 1, true, false)
A.Receive("1|" .. request .. "|END|2", "Tester")
check(A.state == nil, "missing rows never publish")

request = A.Refresh()
A.Receive("1|" .. request .. "|BEGIN|1|3|First|650|7|0|active", "Tester")
for i=7,1,-1 do tierRow(request, i, true, i <= 3) end
settingRows(request)
A.Receive("1|" .. request .. "|END|" .. (7 + #A.settingKeys), "Tester")
check(A.state and A.state.season == 1 and A.state.points == 650 and A.state.mask == 7, "coherent unordered snapshot")
check(#A.state.tiers == 7 and A.state.tiers[3].name == "Reward 3" and A.state.tiers[3].completed, "tier assignment published")
check(A.state.rewards == nil and A.state.progress == nil, "obsolete catalog/progress state absent")

local prior = A.state
local bad = A.Refresh()
A.Receive("1|" .. bad .. "|BEGIN|2|1|Bad|0|0|0|active", "Tester")
settingRows(bad)
for i=1,7 do tierRow(bad, i, true, false) end
A.Receive("1|" .. bad .. "|REWARD|7|appearance|100|100|1|25|0|1|0|Hat|Cosmetic|0", "Tester")
check(A.state == prior, "legacy REWARD row invalidates staged snapshot")

request = A.Refresh()
A.Receive("1|" .. request .. "|BEGIN|2|1|Second|0|0|1|draft", "Tester")
settingRows(request)
for i=1,7 do tierRow(request, i, i ~= 7, false) end
A.Receive("1|" .. request .. "|END|" .. (7 + #A.settingKeys), "Tester")
check(A.state and A.state.season == 2 and A.state.admin and A.state.tiers[7].target == 0, "draft may contain unassigned tier")

request = A.Request("ADMIN", "SETTING", 2, 1, "quest", 5)
local saves = 0
A.listeners[#A.listeners+1] = function(kind) if kind == "saved" then saves = saves + 1 end end
A.Receive("1|" .. request .. "|OK|Saved", "Tester")
check(saves == 1, "admin mutation completion requests authoritative refresh")

local resyncs = 0
A.listeners[#A.listeners+1] = function(kind) if kind == "resync" then resyncs = resyncs + 1 end end
request = A.Request("ADMIN", "ASSIGN", 2, 1, 7, "appearance", 1007, 1007, 1, A.Encode("Reward 7"))
A.Receive("1|" .. request .. "|ERROR|Stale", "Tester")
check(resyncs == 1, "failed mutation requests authoritative refresh")
A.Receive("1|push|INVALIDATE|2|2", "Tester")
check(A.stale, "authoritative push invalidates state")

request = A.Refresh()
now = now + 20
A.Tick(20)
check(A.pending[request] == nil, "request expires")
A.Request("GET")
for i=1,16 do A.Tick(0.5) end
check(#sent > 0, "request actually sent")
for _, wire in ipairs(sent) do check(#wire[1] + #wire[2] + 1 <= 255, "wire limit") end

request = A.Refresh()
A.Receive("1|" .. request .. "|BEGIN|0|0|No active season|0|0|1|unconfigured", "Tester")
settingRows(request)
for i=1,7 do tierRow(request, i, false, false) end
A.Receive("1|" .. request .. "|END|" .. (#A.settingKeys + 7), "Tester")
check(A.state and A.state.season == 0 and A.state.admin and A.state.status == "unconfigured", "GM bootstrap accepted")

local firstSessionId = A.Request("GET")
dofile(root .. "Protocol.lua")
local secondSessionId = CoASeason.Request("GET")
check(firstSessionId ~= secondSessionId, "request ids remain unique across addon sessions")
print("PASS " .. count .. " protocol checks")
