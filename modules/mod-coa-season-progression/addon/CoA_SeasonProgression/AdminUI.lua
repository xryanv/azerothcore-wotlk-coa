local A=CoASeason
local UI={tab="Season",widgets={},seasons={},browse={},history={},reward=nil,offset=0}
local labels={
    {"quest","Quest progress"},{"level","Level progress"},{"elite","Elite progress"},{"rare","Rare progress"},
    {"rare_elite","Rare elite progress"},{"dungeon","Dungeon boss progress"},{"heroic","Heroic boss progress"},
    {"raid","Raid boss progress"},{"world","World boss progress"},{"level_tokens","Tokens per level"},
    {"dungeon_min","Dungeon tokens minimum"},{"dungeon_max","Dungeon tokens maximum"},{"dungeon_chance","Dungeon drop chance (%)"},
    {"heroic_min","Heroic tokens minimum"},{"heroic_max","Heroic tokens maximum"},{"heroic_chance","Heroic drop chance (%)"},
    {"raid_min","Raid tokens minimum"},{"raid_max","Raid tokens maximum"},{"raid_chance","Raid drop chance (%)"},
    {"world_min","World tokens minimum"},{"world_max","World tokens maximum"},{"world_chance","World drop chance (%)"},
    {"lockout_enabled","Elite / rare lockout (0 or 1)"},{"lockout_seconds","Lockout duration (seconds)"}}
local function text(key,x,y,value,width)
    local w=UI.widgets[key]
    if not w then
        w=UI.content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        UI.widgets[key]=w
    end
    w:ClearAllPoints(); w:SetPoint("TOPLEFT",x,-y); w:SetWidth(width or 470)
    w:SetJustifyH("LEFT"); w:SetText(value); w:Show()
    return w
end
local function button(key,x,y,width,title,action)
    local w=UI.widgets[key]
    if not w then
        w=CreateFrame("Button",nil,UI.content,"UIPanelButtonTemplate")
        UI.widgets[key]=w
    end
    w:ClearAllPoints(); w:SetPoint("TOPLEFT",x,-y); w:SetSize(width,23)
    w:SetText(title); w:SetScript("OnClick",action); w:Enable(); w:Show()
    return w
end
local function edit(key,x,y,width,value)
    local w=UI.widgets[key]
    if not w then
        w=CreateFrame("EditBox",nil,UI.content,"InputBoxTemplate")
        w:SetAutoFocus(false); w:SetMaxLetters(80)
        w:SetScript("OnEscapePressed",function(self)self:ClearFocus()end)
        w:SetScript("OnEnterPressed",function(self)self:ClearFocus()end)
        UI.widgets[key]=w
    end
    w:ClearAllPoints(); w:SetPoint("TOPLEFT",x,-y); w:SetSize(width,22)
    w:SetText(tostring(value or "")); w:Show()
    return w
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
local function refreshList()
    UI.seasons={}
    admin("LIST")
end
local function clear()
    for _,w in pairs(UI.widgets)do w:Hide()end
    UI.content:SetHeight(1000)
end
local render
local function rewardForState(reward, state)
    local copy={}
    for k,v in pairs(reward)do copy[k]=v end
    copy._season=state.season
    copy._revision=state.revision
    return copy
end
local function clearPreview()
    local model=SeasonCollectionFrame and SeasonCollectionFrame.RewardModel
    if model then model.coaEditorReward=nil end
    if A.Paint then A.Paint() end
end
local function showPreview(reward)
    if not SeasonCollectionFrame then A.Open() end
    local model=SeasonCollectionFrame and SeasonCollectionFrame.RewardModel
    if not model then return end
    model.coaEditorReward=reward
    model.coaReward=nil
    model.Header:SetText("GM reward preview")
    model.CollectButton:SetText("Preview only")
    model.CollectButton:Disable()
    model.PrevButton:Disable(); model.NextButton:Disable()
    A.ShowPreview(model,reward)
end
local function seasonPanel()
    local s=A.state
    text("season_help",8,8,"Select an existing season or create a draft. The active season remains available to players.",470)
    button("season_refresh",8,50,150,"Refresh season list",refreshList)
    button("season_active",170,50,140,"View active season",function()A.viewSeason=nil;UI.force=true;A.Refresh()end)
    local y=85
    for i,season in ipairs(UI.seasons) do
        if i>25 then break end
        local row=season
        button("season_row"..i,8,y,460,row.id..": "..row.name.." ("..row.status..")",function()
            A.viewSeason=row.id;UI.force=true;A.Refresh(row.id)
        end)
        y=y+27
    end
    y=y+12
    text("draft_label",8,y,"New draft name");y=y+23
    local name=edit("draft_name",12,y,275,"")
    button("draft_new",300,y,170,"Create with defaults",function()
        admin("CREATE",0,A.Encode(name:GetText()));UI.refreshList=true
    end)
    y=y+30
    button("draft_copy",8,y,270,"Copy selected season into a new draft",function()
        admin("CREATE",s.season,A.Encode(name:GetText()));UI.refreshList=true
    end)
    y=y+45
    text("reset_help",8,y,"Starting this draft resets EVERY account's progress and Seasonal Points. Earned cosmetics, items and Bazaar Tokens remain. Type RESET SEASON.",470)
    y=y+55
    local confirmation=edit("reset_confirmation",12,y,255,"")
    local activate=button("draft_activate",280,y,190,"Start selected season",function()
        if confirmation:GetText()~="RESET SEASON" then A.Notify("error","Type RESET SEASON exactly.");return end
        admin("ACTIVATE",s.season,s.revision,A.Encode(confirmation:GetText()))
        UI.force=true;UI.refreshList=true
    end)
    if s.status~="draft" then activate:Disable() end
    UI.content:SetHeight(y+55)
end
local function economyPanel()
    local s=A.state
    text("economy_help",8,8,"Each Save applies that row live. Rates affect future events; lowering a tier may award points immediately. Increase a range maximum before raising its minimum.",470)
    button("economy_discard",8,62,145,"Discard local edits",function()render()end)
    button("economy_defaults",165,62,160,"Reset to defaults",function()UI.force=true;mutate("RESET")end)
    local y=100
    for i,row in ipairs(labels) do
        local key,label=row[1],row[2]
        text("setting_label"..i,8,y+5,label,265)
        local field=edit("setting_value"..i,285,y,95,s.settings[key] or 0)
        button("setting_save"..i,393,y,75,"Save",function()
            local n=number(field,label)
            if n then mutate("SETTING",key,n) end
        end)
        y=y+29
    end
    y=y+12
    text("tier_head",8,y,"Tier             Required progress             Points awarded",460)
    y=y+26
    for i=1,7 do
        local index=i
        local tier=s.tiers[i]
        text("tier_label"..i,8,y+5,tostring(i),40)
        local threshold=edit("tier_threshold"..i,90,y,115,tier.threshold)
        local points=edit("tier_points"..i,250,y,100,tier.points)
        button("tier_save"..i,393,y,75,"Save",function()
            local required=number(threshold,"Progress threshold")
            local payout=number(points,"Tier points")
            if required and payout then mutate("TIER",index,required,payout) end
        end)
        y=y+29
    end
    UI.content:SetHeight(y+30)
end
local function rewardsPanel()
    local s=A.state
    text("reward_help",8,8,"Search the server's known cosmetics and vanity rewards. Select a result to preview it in Ascension's model. Normal loot is never imported automatically.",470)
    local query=edit("reward_query",12,58,275,UI.query or "")
    button("reward_search",300,58,80,"Search",function()
        UI.query=query:GetText();UI.browse={};UI.browseOffset=0
        admin("BROWSE",A.Encode(UI.query),0)
    end)
    button("reward_more",388,58,80,"Next",function()
        UI.browse={};UI.browseOffset=(UI.browseOffset or 0)+25
        admin("BROWSE",A.Encode(UI.query or ""),UI.browseOffset)
    end)
    local y=90
    for i,reward in ipairs(UI.browse)do
        if i>25 then break end
        local row=reward
        button("browse_row"..i,8,y,460,row.name.." ("..row.type..":"..row.target..")",function()
            UI.reward=rewardForState({id=0,type=row.type,target=row.target,preview=row.preview,count=1,cost=25,
                minTier=0,enabled=true,order=0,name=row.name,category="Cosmetic"},s)
            render();showPreview(UI.reward)
        end)
        y=y+26
    end
    text("catalog_head",8,y+8,"Selected season catalog — select to edit",460);y=y+35
    for i,reward in ipairs(s.rewards)do
        local row=reward
        button("catalog_row"..i,8,y,460,row.id..": "..row.name.." — "..row.cost.." points"..(row.enabled and "" or " (disabled)"),function()
            UI.reward=rewardForState(row,s)
            render();showPreview(UI.reward)
        end)
        y=y+26
    end
    button("reward_blank",8,y+6,190,"New reward by ID",function()
        UI.reward=rewardForState({id=0,type="appearance",target=0,preview=0,count=1,cost=25,minTier=0,
            enabled=true,order=0,name="",category="Cosmetic"},s);render()
    end);y=y+44
    local r=UI.reward
    if r then
        local fields={}
        local rows={{"id","Reward ID (0 = new)"},{"type","Type: appearance / vanity / item"},
            {"target","Permanent grant target ID"},{"preview","Client appearance preview ID"},
            {"count","Item quantity"},{"cost","Seasonal Point cost"},{"minTier","Required tier (0–7)"},
            {"order","Display order"},{"name","Display name"},{"category","Category"}}
        for i,row in ipairs(rows)do
            text("edit_label"..i,8,y+5,row[2],250)
            fields[row[1]]=edit("edit_value"..i,275,y,188,r[row[1]])
            y=y+29
        end
        local enabled=r.enabled
        local toggle
        toggle=button("reward_enabled",8,y,150,enabled and "Enabled" or "Disabled",function()
            enabled=not enabled;toggle:SetText(enabled and "Enabled" or "Disabled")
        end)
        local function collect()
            local value={}
            for _,key in ipairs({"id","target","preview","count","cost","minTier","order"})do
                value[key]=number(fields[key],key,key=="minTier" and 7 or nil)
                if value[key]==nil then return end
            end
            value.type=fields.type:GetText()
            if value.type~="appearance" and value.type~="vanity" and value.type~="item" then
                A.Notify("error","Choose appearance, vanity or item.");return
            end
            value.name=fields.name:GetText();value.category=fields.category:GetText()
            value.enabled=enabled
            return value
        end
        button("reward_preview",170,y,140,"Preview changes",function()
            local value=collect();if value then showPreview(value)end
        end)
        button("reward_save",328,y,140,"Save reward",function()
            if r._season~=A.state.season or r._revision~=A.state.revision then
                A.Notify("error","Season changed; reselect this reward before saving.");return
            end
            local value=collect()
            if not value then return end
            UI.force=true
            mutate("REWARD",value.id,value.type,value.target,value.preview,value.count,value.cost,
                value.minTier,value.enabled and 1 or 0,value.order,A.Encode(value.name),A.Encode(value.category))
        end)
        y=y+32
        button("reward_discard",8,y,150,"Discard changes",function()UI.reward=nil;render();clearPreview()end)
        if r.id>0 then button("reward_disable",170,y,150,"Disable reward",function()
            UI.force=true;mutate("DISABLE",r.id)
        end) end
        y=y+35
    end
    UI.content:SetHeight(y+30)
end
local function accountsPanel()
    text("account_help",8,8,"Inspect an account and adjust Seasonal Points with an audit reason. Negative adjustments cannot take a balance below zero.",470)
    text("account_id_label",8,60,"Account ID",180)
    local id=edit("account_id",205,55,125,UI.account and UI.account.id or "")
    button("account_load",350,55,118,"Inspect",function()
        local n=number(id,"Account ID");if n then admin("ACCOUNT",n)end
    end)
    local value=UI.account
    if value then
        text("account_value",8,95,"Season "..value.season.." | Progress "..value.progress.." | Points "..value.points,460)
    end
    text("account_delta_label",8,143,"Points adjustment (+/-)",185)
    local delta=edit("account_delta",205,138,125,"0")
    text("account_reason_label",8,180,"Reason",180)
    local reason=edit("account_reason",205,175,260,"")
    button("account_apply",205,210,260,"Apply audited adjustment",function()
        local account=number(id,"Account ID")
        local raw=delta:GetText()
        local abs=raw:gsub("^[+-]","")
        local n=A.Number(abs)
        if not account or not n or n>2147483647 or not raw:match("^[+-]?%d+$") then
            A.Notify("error","Invalid signed point adjustment.");return
        end
        if reason:GetText()=="" then A.Notify("error","Enter an adjustment reason.");return end
        mutate("ADJUST",account,raw:gsub("^+", ""),A.Encode(reason:GetText()))
    end)
    UI.content:SetHeight(290)
end
local function historyPanel()
    text("history_help",8,8,"Recent account and GM economy history for the selected season.",470)
    button("history_load",8,43,140,"Load history",function()
        UI.history={};admin("HISTORY",A.state.season,UI.offset)
    end)
    button("history_next",165,43,140,"Next page",function()
        UI.offset=UI.offset+25;UI.history={};admin("HISTORY",A.state.season,UI.offset)
    end)
    button("history_first",322,43,140,"First page",function()
        UI.offset=0;UI.history={};admin("HISTORY",A.state.season,0)
    end)
    local y=83
    for i,row in ipairs(UI.history)do
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
    elseif UI.tab=="Rewards" then rewardsPanel()
    elseif UI.tab=="Accounts" then accountsPanel()
    else historyPanel()end
end
function A.ShowAdmin()
    if not A.state or not A.state.admin then
        A.Notify("error","Season Admin requires server-confirmed GM level 3.");return
    end
    if not UI.frame then
        local frame=CreateFrame("Frame","CoASeasonAdminFrame",UIParent)
        frame:SetSize(530,630);frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",20,-90)
        frame:SetFrameStrata("DIALOG");frame:SetMovable(true);frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart",frame.StartMoving);frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
        frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,
            insets={left=8,right=8,top=8,bottom=8}})
        UI.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
        UI.title:SetPoint("TOPLEFT",18,-18)
        local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
        close:SetPoint("TOPRIGHT",-4,-4)
        close:SetScript("OnClick",function()frame:Hide();UI.reward=nil;clearPreview();A.viewSeason=nil;A.Refresh()end)
        for i,name in ipairs({"Season","Economy","Rewards","Accounts","History"})do
            local tab=name
            local b=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
            b:SetSize(96,24);b:SetPoint("TOPLEFT",17+(i-1)*99,-49);b:SetText(tab)
            b:SetScript("OnClick",function()UI.tab=tab;render();UI.scroll:SetVerticalScroll(0)end)
        end
        UI.scroll=CreateFrame("ScrollFrame","CoASeasonAdminScroll",frame,"UIPanelScrollFrameTemplate")
        UI.scroll:SetPoint("TOPLEFT",15,-85);UI.scroll:SetPoint("BOTTOMRIGHT",-35,45)
        UI.content=CreateFrame("Frame",nil,UI.scroll);UI.content:SetSize(475,1000);UI.scroll:SetScrollChild(UI.content)
        UI.status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        UI.status:SetPoint("BOTTOMLEFT",18,17);UI.status:SetWidth(480);UI.status:SetJustifyH("LEFT")
        UI.frame=frame
    end
    UI.frame:Show();render();refreshList()
end
A.listeners[#A.listeners+1]=function(kind,value)
    if kind=="state" then
        if UI.reward and (UI.reward._season~=value.season or UI.reward._revision~=value.revision) then
            UI.reward=nil
            clearPreview()
        end
        if UI.frame and not value.admin then UI.frame:Hide() end
        if UI.frame and UI.frame:IsShown() and value.admin then
            if UI.force or UI.lastSeason~=value.season then render() end
            UI.lastSeason=value.season;UI.force=nil
            UI.title:SetText("Season Admin — "..value.name.." [r"..value.revision.."]")
        end
    elseif kind=="season" then UI.seasons[#UI.seasons+1]=value
    elseif kind=="browse" then UI.browse[#UI.browse+1]=value
    elseif kind=="history" then UI.history[#UI.history+1]=value
    elseif kind=="account" then UI.account=value;if UI.tab=="Accounts" then render()end
    elseif kind=="ok" then
        if UI.tab~="Economy" then render() end
        if UI.refreshList then UI.refreshList=nil;refreshList() end
    end
    if (kind=="ok" or kind=="error") and UI.status then UI.status:SetText(value)end
end
