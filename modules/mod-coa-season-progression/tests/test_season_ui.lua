local root = arg[1] or "modules/mod-coa-season-progression/addon/CoA_SeasonProgression/"
local dummy = {RegisterEvent=function() end, SetScript=function() end}
function CreateFrame() return dummy end
function GetTime() return 0 end
function UnitName() return "Tester" end
SlashCmdList = {}
dofile(root .. "Protocol.lua")
dofile(root .. "SeasonUI.lua")
local A = CoASeason

local tiers = {}
for i=1,7 do
    tiers[i] = {threshold=i*100,type="appearance",target=1000+i,preview=1000+i,count=1,
        name="Reward "..i,completed=i<=2}
end
assert(A.TierComplete(5,1) and not A.TierComplete(5,2) and A.TierComplete(5,3))
assert(A.ProgressPercent(0,tiers) == 0)
assert(math.abs(A.ProgressPercent(50,tiers) - 100/14) < 0.001)
assert(A.ProgressPercent(700,tiers) == 100)
assert(A.CanBuy == nil, "spendable Season Point purchase policy must be removed")

local source = assert(io.open(root .. "SeasonUI.lua", "r")):read("*a")
assert(not source:find('"BUY"', 1, true), "season UI must never generate BUY")
assert(not source:find("Seasonal Points", 1, true), "old spendable-currency wording must be removed")

local complete, overlayShown, overlayText
local node = {
    UnlockedBorder={SetShown=function(_,v) complete=v end},
    RewardOverlay={SetShown=function(_,v) overlayShown=v end,Text={SetText=function(_,v) overlayText=v end}},
    Selected={Hide=function() end}, MetalBorder={SetVertexColor=function() end},
    SetEnabled=function() end, Locked={Hide=function() end}
}
A.PaintTier(node, tiers[1], true)
assert(node.Complete and complete and not overlayShown and overlayText == "100", "completed tier paints cumulative threshold")
A.PaintTier(node, tiers[1], false)
assert(not node.Complete and not complete and overlayShown and overlayText == "100", "locked tier keeps threshold visible")

local values = {}
local function textSlot(key) return {SetText=function(_,v) values[key]=v end} end
local button = {Disable=function(self) self.disabled=true end, SetEnabled=function(self,v) self.enabled=v end,
    SetText=function(self,v) self.text=v end, Hide=function(self) self.hidden=true end}
local model = {
    coaEditorReward={target=999}, ClearModel=function() end, ResetValues=function() end, SetCamera=function() end,
    Title=textSlot("title"), Header=textSlot("header"), CollectButton=button, PrevButton=button, NextButton=button
}
A.ShowPreview = function(m,reward) m.previewed=reward.target; m.Title:SetText(reward.name); return true end
A.state={season=1,revision=2,name="Test",points=150,mask=1,admin=false,status="active",tiers=tiers,settings={}}
A.UpdateModel(model, 1)
assert(model.previewed == 1001 and values.title == "Reward 1", "selected tier previews assigned reward")
assert(values.header:find("Earned",1,true), "completed tier preview says earned")
assert(button.hidden or button.enabled == false or button.disabled, "player purchase control is not actionable")
A.UpdateModel(model, 3)
assert(model.previewed == 1003 and values.header:find("300",1,true), "locked tier shows required cumulative points")

local refreshes=0
A.Refresh=function() refreshes=refreshes+1 end
assert(type(A.OnSeasonFrameShow)=="function", "season frame has authoritative reopen handler")
A.OnSeasonFrameShow()
assert(refreshes==1, "reopening native season frame fetches authoritative state")
print("PASS season UI cumulative tier reward rules")
