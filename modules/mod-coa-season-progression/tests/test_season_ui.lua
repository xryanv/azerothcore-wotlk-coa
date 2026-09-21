local root = arg[1] or "modules/mod-coa-season-progression/addon/CoA_SeasonProgression/"
local dummy = {RegisterEvent=function() end, SetScript=function() end}
function CreateFrame() return dummy end
function GetTime() return 0 end
function UnitName() return "Tester" end
SlashCmdList = {}
dofile(root .. "Protocol.lua")
dofile(root .. "SeasonUI.lua")
local A = CoASeason
local tiers = {{threshold=100,points=25},{threshold=250,points=40},{threshold=500,points=60},
    {threshold=900,points=90},{threshold=1400,points=125},{threshold=2100,points=175},{threshold=3000,points=250}}
assert(A.TierComplete(5,1) and not A.TierComplete(5,2) and A.TierComplete(5,3))
assert(A.ProgressPercent(0,tiers) == 0)
assert(math.abs(A.ProgressPercent(50,tiers) - 100/14) < 0.001)
assert(A.ProgressPercent(3000,tiers) == 100)
local reward={enabled=true,owned=false,minTier=2,cost=40,type="appearance"}
assert(not A.CanBuy(reward,{status="active",mask=1,points=100}))
assert(A.CanBuy(reward,{status="active",mask=3,points=100}))
reward.owned=true
assert(not A.CanBuy(reward,{status="active",mask=3,points=100}))
reward.owned=false
assert(not A.CanBuy(reward,{status="draft",mask=127,points=100}))
local complete,hidden
local node = {UnlockedBorder={SetShown=function(_,v)complete=v end},
    RewardOverlay={SetShown=function(_,v)hidden=not v end,Text={SetText=function() end}},
    Selected={Hide=function() end},MetalBorder={SetVertexColor=function() end},
    SetEnabled=function()end,Locked={Hide=function()end}}
A.PaintTier(node, {points=25}, true)
assert(node.Complete and complete and hidden)
A.PaintTier(node, {points=25}, false)
assert(not node.Complete and not complete and not hidden, "rollover clears old Complete state")
print("PASS season UI rules and rollover visuals")
