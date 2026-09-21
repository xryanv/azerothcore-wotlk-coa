-- Runs the actual GM UI with a minimal frame API; assertions cover requests and access.
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
    local f={kind=kind,name=name,parent=parent,template=template,scripts={},shown=false,disabled=false}
    setmetatable(f,{__index=function(_,key)return methods[key] or function()end end})
    frames[#frames+1]=f
    return f
end
UIParent=CreateFrame("Frame")
function GetTime()return 0 end
function UnitName()return "Tester"end
function SendAddonMessage()end
function date()return "date"end
dofile(root.."Protocol.lua")
dofile(root.."AdminUI.lua")
local A=CoASeason
local requests={}
A.Request=function(...)requests[#requests+1]={...};return tostring(#requests)end
A.Refresh=function()end
A.Paint=function()end
A.ShowPreview=function()end
local tiers={}
for i=1,7 do tiers[i]={threshold=i*100,points=25}end
A.state={season=1,revision=3,name="Test",admin=false,status="active",settings={},tiers=tiers,rewards={}}
A.ShowAdmin()
assert(#requests==0,"ordinary account cannot open or request GM data")
A.state.admin=true
A.ShowAdmin()
assert(requests[1][1]=="ADMIN" and requests[1][2]=="LIST")
local function click(label)
    for _,f in ipairs(frames)do
        if f.text==label and f.scripts.OnClick and not f.disabled then f.scripts.OnClick(f);return end
    end
    error("button missing: "..label)
end
click("Economy")
-- Find first visible numeric edit box and Save button; changing one field must use current revision.
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
local before=#requests
field:SetText("-5")
save.scripts.OnClick(save)
assert(#requests==before,"negative economy value rejected locally")
click("Season")
before=#requests
click("Create with defaults")
assert(#requests==before+1)
click("Accounts")
click("Apply audited adjustment")
assert(#requests==before+1,"invalid account adjustment not sent")
print("PASS GM UI authorization and edit payloads")
