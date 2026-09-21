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

-- GM Tier Edit Mode policy and request shape.
local adminFrame={shown=true,Hide=function(self)self.shown=false end,IsShown=function(self)return self.shown end}
CoASeasonAdminFrame=adminFrame
SeasonCollectionFrame={shown=true,Show=function(self)self.shown=true end,Hide=function(self)self.shown=false end,
    IsShown=function(self)return self.shown end,RewardModel=model}
local browserOpens=0
A.OpenAssignmentBrowser=function()browserOpens=browserOpens+1;return true end
A.state.admin=false
assert(not A.EnterTierEditMode(), "non-GM cannot arm tier editing")
A.state={season=4,revision=7,name="Draft",points=0,mask=0,admin=true,status="draft",tiers=tiers,settings={}}
assert(A.EnterTierEditMode() and A.tierEditMode and not adminFrame.shown, "GM edit mode arms and hides standalone admin")
assert(not A.HandleTierClick(0) and A.assignmentTier==nil, "tier zero cannot become an assignment tier")
assert(A.HandleTierClick(4) and A.assignmentTier==4 and browserOpens==1, "edit-mode tier click opens native browser")

local captured={}
A.Request=function(...)captured={...};return "assign-1"end
assert(A.CaptureAppearanceSelection({appearanceID=4404,displayName="Appearance Four"}), "appearance model selection captured")
assert(A.assignmentCandidate.type=="appearance" and A.assignmentCandidate.preview==4404)
assert(A.SubmitTierAssignment()=="assign-1", "valid candidate submits")
assert(captured[1]=="ADMIN" and captured[2]=="ASSIGN" and captured[3]==4 and captured[4]==7 and
    captured[5]==4 and captured[6]=="appearance" and captured[7]==4404 and captured[8]==4404 and
    captured[9]==1 and A.Decode(captured[10])=="Appearance Four", "ASSIGN payload binds season revision tier and reward")

local refreshes, selected=0,0
A.Refresh=function()refreshes=refreshes+1 end
A.SelectTier=function(i)selected=i end
for _,listener in ipairs(A.listeners) do listener("saved","assign-1") end
assert(not A.tierEditMode and refreshes==1, "successful assignment exits edit mode and refreshes")
A.state={season=4,revision=8,name="Draft",points=0,mask=0,admin=true,status="draft",tiers=tiers,settings={}}
SeasonCollectionFrame.shown=false
A.Adapt=function()end
A.Paint=function()end
for _,listener in ipairs(A.listeners) do listener("state",A.state) end
assert(SeasonCollectionFrame.shown and selected==4, "refreshed assignment returns to the edited tier")

assert(A.EnterTierEditMode())
assert(A.HandleTierClick(5))
GetItemInfo=function(id)return "Vanity "..id end
C_Appearance={GetItemAppearanceID=function(id)return id+10000 end}
StoreCollectionFrame={ItemInternal=777}
assert(A.CaptureVanitySelection(StoreCollectionFrame), "native vanity selection captured")
assert(A.assignmentCandidate.type=="vanity" and A.assignmentCandidate.target==777 and A.assignmentCandidate.preview==10777)
A.state.revision=9
assert(not A.SubmitTierAssignment() and not A.tierEditMode and A.assignmentTier==nil,
    "stale season revision clears tier edit mode")

A.ExitTierEditMode()
assert(A.HandleTierClick(3) and selected==3 and browserOpens==2, "normal tier click stays normal outside edit mode")

refreshes=0
assert(type(A.OnSeasonFrameShow)=="function", "season frame has authoritative reopen handler")
A.OnSeasonFrameShow()
assert(refreshes==1, "reopening native season frame fetches authoritative state")
print("PASS season UI cumulative tier reward and GM edit-mode rules")
