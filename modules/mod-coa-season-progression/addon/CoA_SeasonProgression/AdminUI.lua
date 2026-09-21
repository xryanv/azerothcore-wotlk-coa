local A = CoASeason
local UI = {tab="Season", widgets={}, seasons={}, history={}, offset=0}
local labels = {
    {"quest","Quest Season Points"},{"level","Level Season Points"},{"elite","Elite Season Points"},
    {"rare","Rare Season Points"},{"rare_elite","Rare elite Season Points"},
    {"dungeon","Dungeon boss Season Points"},{"heroic","Heroic boss Season Points"},
    {"raid","Raid boss Season Points"},{"world","World boss Season Points"},
    {"level_tokens","Bazaar Tokens per level"},{"dungeon_min","Dungeon tokens minimum"},
    {"dungeon_max","Dungeon tokens maximum"},{"dungeon_chance","Dungeon token chance (%)"},
    {"heroic_min","Heroic tokens minimum"},{"heroic_max","Heroic tokens maximum"},
    {"heroic_chance","Heroic token chance (%)"},{"raid_min","Raid tokens minimum"},
    {"raid_max","Raid tokens maximum"},{"raid_chance","Raid token chance (%)"},
    {"world_min","World tokens minimum"},{"world_max","World tokens maximum"},
    {"world_chance","World token chance (%)"},{"lockout_enabled","Elite / rare lockout (0 or 1)"},
    {"lockout_seconds","Lockout duration (seconds)"}
}

local function text(key,x,y,value,width)
    local w = UI.widgets[key]
    if not w then w=UI.content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); UI.widgets[key]=w end
    w:ClearAllPoints(); w:SetPoint("TOPLEFT",x,-y); w:SetWidth(width or 470)
    w:SetJustifyH("LEFT"); w:SetText(value); w:Show(); return w
end
local function button(key,x,y,width,title,action)
    local w = UI.widgets[key]
    if not w then w=CreateFrame("Button",nil,UI.content,"UIPanelButtonTemplate"); UI.widgets[key]=w end
    w:ClearAllPoints(); w:SetPoint("TOPLEFT",x,-y); w:SetSize(width,23)
    w:SetText(title); w:SetScript("OnClick",action); w:Enable(); w:Show(); return w
end
local function edit(key,x,y,width,value)
    local w = UI.widgets[key]
    if not w then
        w=CreateFrame("EditBox",nil,UI.content,"InputBoxTemplate")
        w:SetAutoFocus(false); w:SetMaxLetters(80)
        w:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
        w:SetScript("OnEnterPressed",function(self)self:ClearFocus()end)
        UI.widgets[key]=w
    end
    w:ClearAllPoints(); w:SetPoint("TOPLEFT",x,-y); w:SetSize(width,22)
    w:SetText(tostring(value or "")); w:Show(); return w
end
local function number(field,label,maximum)
    local n=A.Number(field:GetText())
    if not n or (maximum and n>maximum) then A.Notify("error",label.." must be a valid whole number."); return end
    return n
end
local function admin(operation,...)
    if not A.state or not A.state.admin then return end
    return A.Request("ADMIN",operation,...)
end
local function mutate(operation,...)
    local s=A.state
    if s then return admin(operation,s.season,s.revision,...) end
end
local function refreshList() UI.seasons={}; admin("LIST") end
local function clear()
    for _,w in pairs(UI.widgets) do w:Hide() end
    UI.content:SetHeight(1000)
end
local render

local function seasonPanel()
    local s=A.state
    text("season_help",8,8,"Create/copy a draft, assign its seven tier rewards in the native Ascension browser, then activate it.",470)
    button("season_refresh",8,48,145,"Refresh season list",refreshList)
    button("season_active",165,48,140,"View active season",function()A.viewSeason=nil;UI.force=true;A.Refresh()end)
    button("season_rewards",315,48,155,"Edit Tier Rewards",function()
        if A.EnterTierEditMode then A.EnterTierEditMode() end
    end)
    local y=82
    for i,season in ipairs(UI.seasons) do
        if i>25 then break end
        local row=season
        button("season_row"..i,8,y,462,row.id..": "..row.name.." ("..row.status..")",function()
            A.viewSeason=row.id;UI.force=true;A.Refresh(row.id)
        end)
        y=y+27
    end
    y=y+10
    text("draft_label",8,y,"New draft name"); y=y+23
    local name=edit("draft_name",12,y,275,"")
    button("draft_new",300,y,170,"Create with defaults",function()
        admin("CREATE",0,A.Encode(name:GetText())); UI.refreshList=true
    end)
    y=y+30
    button("draft_copy",8,y,275,"Copy selected season to draft",function()
        admin("CREATE",s.season,A.Encode(name:GetText())); UI.refreshList=true
    end)
    y=y+42
    text("item_fallback_help",8,y,"Physical item fallback — use only when the reward is not represented in Ascension's native browser.",470)
    y=y+24
    text("item_tier_label",8,y+4,"Tier",35)
    local itemTier=edit("item_tier",45,y,45,"")
    text("item_id_label",100,y+4,"Item ID",55)
    local itemId=edit("item_id",160,y,80,"")
    text("item_count_label",250,y+4,"Count",45)
    local itemCount=edit("item_count",300,y,45,"1")
    local itemName=edit("item_name",355,y,115,"")
    y=y+28
    button("item_assign",300,y,170,"Assign item ID",function()
        local tier=number(itemTier,"Tier",7)
        local item=number(itemId,"Item ID")
        local count=number(itemCount,"Item count")
        local displayName=itemName:GetText()
        if not tier or tier<1 or not item or item<1 or not count or count<1 then return end
        if displayName=="" or #displayName>48 then A.Notify("error","Enter an item reward name up to 48 characters."); return end
        mutate("ASSIGN",tier,"item",item,0,count,A.Encode(displayName))
    end)
    y=y+45
    text("reset_help",8,y,"Activation resets Season Points/tier state for the incoming season. Permanent rewards and Bazaar Tokens remain. All seven tier rewards must be assigned. Type RESET SEASON.",470)
    y=y+64
    local confirmation=edit("reset_confirmation",12,y,255,"")
    local activate=button("draft_activate",280,y,190,"Start selected season",function()
        if confirmation:GetText()~="RESET SEASON" then A.Notify("error","Type RESET SEASON exactly."); return end
        admin("ACTIVATE",s.season,s.revision,A.Encode(confirmation:GetText()))
        UI.force=true; UI.refreshList=true
    end)
    if s.status~="draft" then activate:Disable() end
    UI.content:SetHeight(y+55)
end

local function economyPanel()
    local s=A.state
    text("economy_help",8,8,"Season Point awards, Bazaar Token ranges and tier thresholds. Lowering an active threshold may grant newly reached tier rewards immediately.",470)
    button("economy_discard",8,58,145,"Discard local edits",function()render()end)
    button("economy_defaults",165,58,160,"Reset to defaults",function()UI.force=true;mutate("RESET")end)
    local y=95
    for i,row in ipairs(labels) do
        local key,label=row[1],row[2]
        text("setting_label"..i,8,y+5,label,275)
        local field=edit("setting_value"..i,295,y,88,s.settings[key] or 0)
        button("setting_save"..i,393,y,75,"Save",function()
            local n=number(field,label)
            if n then mutate("SETTING",key,n) end
        end)
        y=y+29
    end
    y=y+12
    text("tier_head",8,y,"Tier                 Required cumulative Season Points",460); y=y+26
    for i=1,7 do
        local index=i
        local tier=s.tiers[i]
        text("tier_label"..i,8,y+5,tostring(i),55)
        local threshold=edit("tier_threshold"..i,210,y,125,tier.threshold)
        button("tier_save"..i,393,y,75,"Save",function()
            local required=number(threshold,"Season Point threshold")
            if required then mutate("TIER",index,required) end
        end)
        y=y+29
    end
    UI.content:SetHeight(y+30)
end

local function completedCount(mask)
    local n=0
    for i=1,7 do if A.TierComplete and A.TierComplete(mask or 0,i) then n=n+1 end end
    return n
end
local function accountsPanel()
    text("account_help",8,8,"Inspect cumulative Season Points/completed tiers or make an audited test adjustment. Reducing points never revokes completed rewards.",470)
    text("account_id_label",8,58,"Account ID",180)
    local id=edit("account_id",205,53,125,UI.account and UI.account.id or "")
    button("account_load",350,53,118,"Inspect",function()
        local n=number(id,"Account ID"); if n then admin("ACCOUNT",n) end
    end)
    local value=UI.account
    if value then
        text("account_value",8,94,"Season "..value.season.." | Season Points "..value.points.." | Completed tiers "..completedCount(value.mask),460)
    end
    text("account_delta_label",8,142,"Season Point adjustment (+/-)",190)
    local delta=edit("account_delta",205,137,125,"0")
    text("account_reason_label",8,179,"Reason",180)
    local reason=edit("account_reason",205,174,260,"")
    button("account_apply",205,209,260,"Apply audited adjustment",function()
        local account=number(id,"Account ID")
        local raw=delta:GetText(); local magnitude=raw:gsub("^[+-]",""); local n=A.Number(magnitude)
        if not account or not n or n>2147483647 or not raw:match("^[+-]?%d+$") then
            A.Notify("error","Invalid signed Season Point adjustment."); return
        end
        if reason:GetText()=="" then A.Notify("error","Enter an adjustment reason."); return end
        mutate("ADJUST",account,raw:gsub("^+",""),A.Encode(reason:GetText()))
    end)
    UI.content:SetHeight(285)
end

local function historyPanel()
    text("history_help",8,8,"Recent season configuration, tier assignment/grant and account adjustment history.",470)
    button("history_load",8,43,140,"Load history",function()UI.history={};admin("HISTORY",A.state.season,UI.offset)end)
    button("history_next",165,43,140,"Next page",function()UI.offset=UI.offset+25;UI.history={};admin("HISTORY",A.state.season,UI.offset)end)
    button("history_first",322,43,140,"First page",function()UI.offset=0;UI.history={};admin("HISTORY",A.state.season,0)end)
    local y=83
    for i,row in ipairs(UI.history) do
        text("history_row"..i,8,y,date("%Y-%m-%d %H:%M",row.time).." | Account "..row.account.."\n"..row.action,460)
        y=y+48
    end
    UI.content:SetHeight(y+30)
end

render=function()
    if not UI.frame or not A.state or not A.state.admin then return end
    UI.title:SetText("Season Admin — "..A.state.name.." [r"..A.state.revision.."]")
    clear()
    if UI.tab=="Season" then seasonPanel()
    elseif UI.tab=="Economy" then economyPanel()
    elseif UI.tab=="Accounts" then accountsPanel()
    else historyPanel() end
end

function A.ShowAdmin()
    if not A.state or not A.state.admin then
        A.Notify("error","Season Admin requires server-confirmed GM level 3."); return
    end
    if A.ExitTierEditMode then A.ExitTierEditMode() end
    if SeasonCollectionFrame and SeasonCollectionFrame:IsShown() then SeasonCollectionFrame:Hide() end
    if not UI.frame then
        local frame=CreateFrame("Frame","CoASeasonAdminFrame",UIParent)
        frame:SetSize(530,630); frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",20,-90)
        frame:SetFrameStrata("DIALOG"); frame:SetMovable(true); frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart",frame.StartMoving); frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
        frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,
            insets={left=8,right=8,top=8,bottom=8}})
        UI.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal"); UI.title:SetPoint("TOPLEFT",18,-18)
        local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-4,-4)
        close:SetScript("OnClick",function()frame:Hide();A.viewSeason=nil;A.Refresh()end)
        for i,name in ipairs({"Season","Economy","Accounts","History"}) do
            local tab=name
            local b=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
            b:SetSize(118,24); b:SetPoint("TOPLEFT",17+(i-1)*121,-49); b:SetText(tab)
            b:SetScript("OnClick",function()UI.tab=tab;render();UI.scroll:SetVerticalScroll(0)end)
        end
        UI.scroll=CreateFrame("ScrollFrame","CoASeasonAdminScroll",frame,"UIPanelScrollFrameTemplate")
        UI.scroll:SetPoint("TOPLEFT",15,-85); UI.scroll:SetPoint("BOTTOMRIGHT",-35,45)
        UI.content=CreateFrame("Frame",nil,UI.scroll); UI.content:SetSize(475,1000); UI.scroll:SetScrollChild(UI.content)
        UI.status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        UI.status:SetPoint("BOTTOMLEFT",18,17); UI.status:SetWidth(480); UI.status:SetJustifyH("LEFT")
        UI.frame=frame
    end
    UI.frame:Show(); render(); refreshList()
end

A.listeners[#A.listeners+1]=function(kind,value)
    if kind=="state" then
        if UI.frame and not value.admin then UI.frame:Hide() end
        if UI.frame and UI.frame:IsShown() and value.admin then
            if UI.force or UI.lastSeason~=value.season then render() end
            UI.lastSeason=value.season; UI.force=nil
            UI.title:SetText("Season Admin — "..value.name.." [r"..value.revision.."]")
        end
    elseif kind=="season" then UI.seasons[#UI.seasons+1]=value
    elseif kind=="history" then UI.history[#UI.history+1]=value
    elseif kind=="account" then UI.account=value; if UI.tab=="Accounts" then render() end
    elseif kind=="ok" then
        if UI.tab~="Economy" then render() end
        if UI.refreshList then UI.refreshList=nil; refreshList() end
    end
    if (kind=="ok" or kind=="error") and UI.status then UI.status:SetText(value) end
end
