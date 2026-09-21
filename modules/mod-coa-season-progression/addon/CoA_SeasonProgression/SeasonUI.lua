local A = CoASeason
function A.TierComplete(mask, tier)
    return math.floor(mask / 2 ^ (tier - 1)) % 2 == 1
end
function A.ProgressPercent(progress, tiers)
    local previous = 0
    for i, tier in ipairs(tiers) do
        if progress < tier.threshold then
            return ((i - 1) + math.max(0, progress - previous) / (tier.threshold - previous)) / 7 * 100
        end
        previous = tier.threshold
    end
    return 100
end
function A.CanBuy(reward, state)
    return reward and state and state.status == "active" and reward.enabled and not reward.owned
        and state.points >= reward.cost
        and (reward.minTier == 0 or A.TierComplete(state.mask, reward.minTier))
end
function A.PaintTier(node, tier, complete)
    node.Complete = complete
    node.UnlockedBorder:SetShown(complete)
    node.RewardOverlay:SetShown(not complete)
    node.RewardOverlay.Text:SetText("+" .. tier.points)
    node.Selected:Hide()
    node.MetalBorder:SetVertexColor(1, 1, 1)
    node:SetEnabled(true)
    node.Locked:Hide()
end
local function label(info, title, description)
    if info.cancelToken then info.cancelToken(); info.cancelToken = nil end
    info.Title:SetText(title)
    info.Description:SetText(description)
end
function A.ShowPreview(model, reward)
    if model.cancelToken then model.cancelToken(); model.cancelToken = nil end
    model.appearanceID = reward.preview
    if reward.preview > 0 and C_Appearance and C_Appearance.GetAppearanceDisplayInfo then
        local displayType = C_Appearance.GetAppearanceDisplayInfo(reward.preview)
        if displayType then
            model.rewards = { reward.preview }
            model.page = 1
            model.coaOriginalShowReward(model, 1)
            model.Title:SetText(reward.name)
            return true
        end
    end
    model:ResetValues()
    model:ClearModel()
    model:SetCamera(2)
    model.Title:SetText(reward.name)
    if reward.type == "item" or reward.type == "vanity" then
        model.displayID = reward.target
        model.displayType = "APPEARANCE_DISPLAY_TYPE_ITEM"
        model:DisplayItem()
        return true
    end
    model.Header:SetText("Preview unavailable in this client")
    return false
end
function A.UpdateModel(model, index)
    local state = A.state
    local rewards = state and state.rewards or {}
    if #rewards == 0 then
        if model.cancelToken then model.cancelToken(); model.cancelToken = nil end
        model:ClearModel()
        model.Title:SetText("No rewards published")
        model.Header:SetText("Season rewards")
        model.CollectButton:Disable()
        model.PrevButton:Disable()
        model.NextButton:Disable()
        model.coaReward = nil
        return
    end
    index = ((index or 1) - 1) % #rewards + 1
    model.coaIndex = index
    local reward = rewards[index]
    model.coaReward = reward
    model.Header:SetText(reward.cost .. " Seasonal Points")
    A.ShowPreview(model, reward)
    model.CollectButton:SetText(reward.owned and "Owned" or "Unlock")
    model.CollectButton:SetEnabled(not A.buyPending and A.CanBuy(reward, state))
    model.PrevButton:SetEnabled(#rewards > 1)
    model.NextButton:SetEnabled(#rewards > 1)
end
function A.Paint()
    local frame, state = SeasonCollectionFrame, A.state
    if not frame or not frame.coaAdapted then return end
    if not state then
        frame.TitleText:SetText("Season — waiting for server")
        frame.RewardModel.CollectButton:Disable()
        return
    end
    frame.TitleText:SetText(state.name .. (state.status == "active" and "" or " — " .. state.status))
    label(frame.UnlockInfo, "Season Progress: " .. state.progress, "Quests, levels, elites, rares and bosses earn progress.")
    label(frame.DraftInfo, "Account-wide rewards", "Earn tier points, then choose permanent rewards. Owned rewards survive new seasons.")
    label(frame.PointsInfo, state.points .. " Seasonal Points", "Bazaar Tokens are separate and stay in your inventory.")
    local bar = frame.ProgressBar
    bar:SetScript("OnUpdate", nil)
    bar.LastValue = A.ProgressPercent(state.progress, state.tiers)
    bar.TargetValue = bar.LastValue
    bar:SetValue(bar.LastValue)
    if bar.Tier0 then
        bar.Tier0:SetEnabled(true)
        bar.Tier0.Selected:Hide()
        bar.Tier0.Locked:Hide()
    end
    for i=1,7 do
        local node = bar["Tier" .. i] or (bar.Tiers and bar.Tiers[i])
        if node then A.PaintTier(node, state.tiers[i], A.TierComplete(state.mask, i)) end
    end
    if frame.coaAdminButton then frame.coaAdminButton:SetShown(state.admin) end
    A.UpdateModel(frame.RewardModel, frame.RewardModel.coaIndex)
end
local function tierTooltip(node, index)
    local state = A.state
    if not state then return end
    GameTooltip:SetOwner(node, "ANCHOR_TOP")
    if index == 0 then
        GameTooltip:SetText("Gameplay-earned season")
        GameTooltip:AddLine("No season pass purchase is required.", 1, 1, 1, true)
    else
        local tier = state.tiers[index]
        GameTooltip:SetText("Tier " .. index)
        GameTooltip:AddLine(state.progress .. " / " .. tier.threshold .. " Season Progress", 1,1,1)
        GameTooltip:AddLine("Reward: " .. tier.points .. " Seasonal Points", 1,0.82,0)
        if A.TierComplete(state.mask,index) then GameTooltip:AddLine("Completed", 0,1,0) end
    end
    GameTooltip:Show()
end
function A.Adapt()
    local frame = SeasonCollectionFrame
    if not frame or frame.coaAdapted then return end
    frame.coaAdapted = true
    frame.OnShow = function() A.Paint() end
    frame.UnlockInfo.UnlockButton:Hide()
    frame.UnlockInfo.UnlockButton:SetScript("OnShow", function(self) self:Hide() end)
    local bar = frame.ProgressBar
    bar.OnShow = function() A.Paint() end
    bar.UpdateProgress = function() A.Paint() end
    bar.CheckCompleteTiers = function() end
    for i=0,7 do
        local index = i
        local node = bar["Tier" .. i] or (bar.Tiers and bar.Tiers[i])
        if node then
            node.OnShow = function() A.Paint() end
            node.OnEnter = function(self) tierTooltip(self, index) end
            node.GetRewardPoints = function() return A.state and index > 0 and A.state.tiers[index].points or 0 end
            node.GetCurrentChapter = function() return 1 end
            node:SetScript("OnClick", function(self) tierTooltip(self,index) end)
        end
    end
    local model = frame.RewardModel
    model.coaOriginalShowReward = model.ShowReward
    model.OnShow = function(self) A.UpdateModel(self, self.coaIndex) end
    model.ShowReward = function(self,index) A.UpdateModel(self,index) end
    model.RefreshCurrentDisplay = function(self)
        if self.coaEditorReward then A.ShowPreview(self,self.coaEditorReward)
        else A.UpdateModel(self,self.coaIndex) end
    end
    model.NextReward = function(self) self.coaEditorReward=nil; A.UpdateModel(self,(self.coaIndex or 1)+1) end
    model.PrevReward = function(self) self.coaEditorReward=nil; A.UpdateModel(self,(self.coaIndex or 1)-1) end
    model.OpenStore = function(self)
        local reward,state = self.coaReward,A.state
        if A.buyPending or not A.CanBuy(reward,state) then return end
        A.buyPending = A.Request("BUY", state.season, state.revision, reward.id)
        self.CollectButton:Disable()
    end
    model.CollectButton:SetScript("OnClick", function() model:OpenStore() end)
    local button=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    button:SetSize(120,24)
    button:SetPoint("TOPLEFT",frame,"TOPLEFT",65,-30)
    button:SetText("Season Admin")
    button:Hide()
    button:SetScript("OnClick",function() if A.ShowAdmin then A.ShowAdmin() end end)
    frame.coaAdminButton=button
    A.Paint()
end
function A.Open()
    if not SeasonCollectionFrame then
        local ok, reason=LoadAddOn("Ascension_SeasonCollection")
        if not ok then A.Notify("error","Cannot load Ascension seasonal UI: "..tostring(reason)); return end
    end
    A.Adapt()
    if Collections then ShowUIPanel(Collections) end
    SeasonCollectionFrame:Show()
    A.Refresh(A.viewSeason)
end
local loader=CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent",function() A.Adapt() end)
SlashCmdList.COASEASON=function(text)
    A.Open()
    if text and text:lower()=="admin" and A.ShowAdmin then A.ShowAdmin() end
end
SLASH_COASEASON1="/coaseason"
A.listeners[#A.listeners+1]=function(kind,value)
    if kind=="state" then A.Adapt(); A.Paint()
    elseif kind=="ok" or kind=="error" then
        A.buyPending=nil
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff80ff80Season:|r "..value) end
    elseif kind=="saved" then A.Refresh(A.viewSeason) end
end
