local root = arg[1] or "modules/mod-coa-season-progression/addon/CoA_SeasonProgression/"
local now, sent = 0, {}
function GetTime() return now end
function UnitName() return "Tester" end
function SendAddonMessage(...) sent[#sent + 1] = {...} end
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function() end }
end
dofile(root .. "Protocol.lua")
local A = CoASeason
local count = 0
local function check(value, message)
    assert(value, message)
    count = count + 1
end
check(A.Decode(A.Encode("a|b% é")) == "a|b% é", "text round trip")
check(A.Decode("%GG") == nil and A.Decode("%0A") == nil, "reject malformed/control text")
check(A.Number("1e3") == nil and A.Number("-1") == nil, "reject nondecimal and signed numeric")
check(A.Number("4294967296") == nil, "reject integer overflow")
local request = A.Refresh()
A.Receive("1|" .. request .. "|BEGIN|1|3|First|90|25|0|0|active", "Other")
check(A.state == nil, "foreign sender ignored")
A.Receive("1|" .. request .. "|BEGIN|1|3|First|90|25|0|0|active", "Tester")
A.Receive("1|" .. request .. "|TIER|1|100|25", "Tester")
A.Receive("1|" .. request .. "|END|2", "Tester")
check(A.state == nil, "missing rows never publish")
request = A.Refresh()
A.Receive("1|" .. request .. "|BEGIN|1|3|First|90|25|0|0|active", "Tester")
for i = 7, 1, -1 do
    A.Receive("1|" .. request .. "|TIER|" .. i .. "|" .. (i * 100) .. "|25", "Tester")
end
A.Receive("1|" .. request .. "|REWARD|7|appearance|100|100|1|25|0|1|0|Hat|Cosmetic|0", "Tester")
A.Receive("1|" .. request .. "|END|8", "Tester")
check(A.state and A.state.season == 1 and #A.state.rewards == 1, "coherent unordered snapshot")
local old = request
request = A.Refresh()
A.Receive("1|" .. old .. "|BEGIN|9|9|Old|9|9|9|1|active", "Tester")
check(A.state.season == 1, "late request ignored")
A.Receive("1|" .. request .. "|BEGIN|2|1|Second|0|0|0|1|active", "Tester")
for i = 1, 7 do
    A.Receive("1|" .. request .. "|TIER|" .. i .. "|" .. (i * 100) .. "|25", "Tester")
end
A.Receive("1|" .. request .. "|END|7", "Tester")
check(A.state.season == 2 and A.state.points == 0 and A.state.mask == 0, "rollover replaces state")
check(#A.state.rewards == 0, "empty catalog clears old rewards")
check(A.Request("BUY", string.rep("a", 250)) == nil, "oversized outgoing request rejected")
A.Request("GET")
for i=1,16 do A.Tick(0.5) end
check(#sent > 0, "request actually sent")
for _, wire in ipairs(sent) do
    check(#wire[1] + #wire[2] + 1 <= 255, "wire limit")
end
request = A.Refresh()
now = now + 20
A.Tick(20)
check(A.pending[request] == nil, "request expires")
local saves = 0
A.listeners[#A.listeners + 1] = function(kind) if kind == "saved" then saves = saves + 1 end end
request = A.Request("ADMIN", "LIST")
A.Receive("1|" .. request .. "|OK|Listed", "Tester")
check(saves == 0, "read completion does not trigger mutation refresh")
request = A.Request("ADMIN", "SETTING", 2, 1, "quest", 5)
A.Receive("1|" .. request .. "|OK|Saved", "Tester")
check(saves == 1, "mutation completion requests authoritative refresh")
print("PASS " .. count .. " protocol checks")
