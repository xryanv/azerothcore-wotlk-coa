local root=arg[1] or "modules/mod-coa-season-progression/addon/CoA_SeasonProgression/"
local frames={}
local methods={}
function methods:SetScript(kind,callback)self.scripts[kind]=callback end
function methods:GetText()return self.text or ""end
function methods:SetText(value)self.text=tostring(value)end
function methods:Show()self.shown=true end
function methods:Hide()self.shown=false end
function methods:IsShown()return self.shown end
function methods:Enable()self.disabled=false end
function methods:Disable()self.disabled=true end
function methods:CreateFontString()return CreateFrame("FontString")end
function methods:SetEnabled(enabled)self.disabled=not enabled end
function methods:SetShown(show)self.shown=show end
function CreateFrame(kind,name,parent,template)
    local f={kind=kind,name=name,parent=parent,template=template,scripts={},shown=true,disabled=false}
    setmetatable(f,{__index=function(_,key)return methods[key] or function()end end})
    if name then _G[name]=f end
    frames[#frames+1]=f
    return f
end
UIParent=CreateFrame("Frame")
function GetTime()return 0 end
function UnitName()return "Tester"end
function SendAddonMessage()end
function date()return "date"end
SeasonCollectionFrame={shown=true,Hide=function(self)self.shown=false end,Show=function(self)self.shown=true end,IsShown=function(self)return self.shown end}
dofile(root.."Protocol.lua")
dofile(root.."AdminUI.lua")
local A=CoASeason
local requests={}
A.Request=function(...)requests[#requests+1]={...};return tostring(#requests)end
A.Refresh=function()end
A.Paint=function()end
local editModeCalls=0
A.EnterTierEditMode=function()editModeCalls=editModeCalls+1;return true end
local tiers={}
for i=1,7 do tiers[i]={threshold=i*100,type="appearance",target=1000+i,preview=1000+i,count=1,name="R"..i,completed=false}end
A.state={season=1,revision=3,name="Test",admin=false,status="active",settings={},tiers=tiers,points=0,mask=0}
A.ShowAdmin()
assert(#requests==0,"ordinary account cannot open or request GM data")
A.state.admin=true
A.ShowAdmin()
assert(not SeasonCollectionFrame.shown,"opening standalone admin hides native season frame")
assert(requests[1][1]=="ADMIN" and requests[1][2]=="LIST")

local labels={}
for _,f in ipairs(frames)do if f.text then labels[f.text]=true end end
assert(labels.Season and labels.Economy and labels.Accounts and labels.History,"four admin tabs exist")
assert(not labels.Rewards,"custom Rewards tab is removed")
assert(labels["Edit Tier Rewards"],"native tier reward editor entry exists")
assert(labels["Assign item ID"],"physical-item fallback is a single validated-ID action")
local source=assert(io.open(root.."AdminUI.lua","r")):read("*a")
assert(not source:find('"BROWSE"',1,true) and not source:find("Save reward",1,true),"custom reward catalog/editor removed")

local function click(label)
    for _,f in ipairs(frames)do
        if f.text==label and f.scripts.OnClick and not f.disabled and f.shown then f.scripts.OnClick(f);return end
    end
    error("button missing: "..label)
end
click("Edit Tier Rewards")
assert(editModeCalls==1,"admin hands reward editing to native tier mode")
click("Economy")
local field,save
for _,f in ipairs(frames)do
    if f.kind=="EditBox" and f.shown and not field then field=f end
    if f.text=="Save" and f.shown and not save then save=f end
end
field:SetText("5")
A.state.revision=9
save.scripts.OnClick(save)
local r=requests[#requests]
assert(r[1]=="ADMIN" and r[2]=="SETTING" and r[3]==1 and r[4]==9 and r[5]=="quest" and r[6]==5)
print("PASS GM UI native tier-editor handoff and mutual exclusion")
