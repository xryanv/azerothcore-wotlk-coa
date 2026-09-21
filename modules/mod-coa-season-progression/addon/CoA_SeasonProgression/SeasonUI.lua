local A = CoASeason

function A.TierComplete(mask, tier)
    return math.floor(mask / 2 ^ (tier - 1)) % 2 == 1
end

function A.ProgressPercent(points, tiers)
    local previous = 0
    for i, tier in ipairs(tiers) do
        if points < tier.threshold then
            return ((i - 1) + math.max(0, points - previous) / (tier.threshold - previous)) / 7 * 100
        end
        previous = tier.threshold
    end
    return 100
end

function A.PaintTier(node, tier, complete)
    node.Complete = complete
    node.UnlockedBorder:SetShown(complete)
    node.RewardOverlay:SetShown(not complete)
    node.RewardOverlay.Text:SetText(tostring(tier.threshold))
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
            model.rewards = {reward.preview}
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
    model.coaEditorReward = nil
    local state = A.state
    local tiers = state and state.tiers or {}
    if #tiers ~= 7 then
        if model.cancelToken then model.cancelToken(); model.cancelToken = nil end
        model:ClearModel()
        model.Title:SetText("No tier reward available")
        model.Header:SetText("Season rewards")
        model.CollectButton:Disable()
        if model.CollectButton.Hide then model.CollectButton:Hide() end
        model.PrevButton:Disable()
        model.NextButton:Disable()
        return
    end

    index = math.max(1, math.min(7, tonumber(index) or 1))
    model.coaIndex = index
    local tier = tiers[index]
    local completed = tier.completed or A.TierComplete(state.mask or 0, index)
    if tier.type == "" or tier.target == 0 then
        model:ClearModel()
        model.Title:SetText("Tier " .. index .. " reward not assigned")
    else
        A.ShowPreview(model, tier)
    end
    if completed then
        model.Header:SetText("Tier " .. index .. " — Earned")
    else
        model.Header:SetText("Tier " .. index .. " — " .. tier.threshold .. " Season Points")
    end
    model.CollectButton:SetText(completed and "Earned" or "Automatic")
    model.CollectButton:SetEnabled(false)
    if model.CollectButton.Hide then model.CollectButton:Hide() end
    model.PrevButton:SetEnabled(index > 1)
    model.NextButton:SetEnabled(index < 7)
end

function A.SelectTier(index)
    if not A.state or index < 1 or index > 7 then return end
    if SeasonCollectionFrame and SeasonCollectionFrame.RewardModel then
        A.UpdateModel(SeasonCollectionFrame.RewardModel, index)
    end
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
    label(frame.UnlockInfo, "Season Points: " .. state.points,
        "Quests, levels, elites, rares and bosses advance this account-wide total.")
    label(frame.DraftInfo, "Automatic tier rewards",
        "Cross a tier threshold to receive its permanent reward. Bazaar Tokens buy additional items.")
    label(frame.PointsInfo, state.points .. " Season Points", "Season Points are progress and are never spent.")

    local bar = frame.ProgressBar
    bar:SetScript("OnUpdate", nil)
    bar.LastValue = A.ProgressPercent(state.points, state.tiers)
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
    A.UpdateModel(frame.RewardModel, frame.RewardModel.coaIndex or 1)
end

local function tierTooltip(node, index)
    local state = A.state
    if not state then return end
    GameTooltip:SetOwner(node, "ANCHOR_TOP")
    if index == 0 then
        GameTooltip:SetText("Gameplay-earned season")
        GameTooltip:AddLine("Season Points come only from gameplay.", 1, 1, 1, true)
    else
        local tier = state.tiers[index]
        GameTooltip:SetText("Tier " .. index)
        GameTooltip:AddLine(state.points .. " / " .. tier.threshold .. " Season Points", 1, 1, 1)
        GameTooltip:AddLine("Reward: " .. (tier.name ~= "" and tier.name or "Not assigned"), 1, 0.82, 0)
        if A.TierComplete(state.mask, index) then GameTooltip:AddLine("Earned", 0, 1, 0) end
    end
    GameTooltip:Show()
end

function A.OnSeasonFrameShow()
    A.Refresh(A.viewSeason)
    A.Paint()
end

function A.Adapt()
    local frame = SeasonCollectionFrame
    if not frame or frame.coaAdapted then return end
    frame.coaAdapted = true
    frame.OnShow = function() A.OnSeasonFrameShow() end
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
            node.GetRewardPoints = function() return 0 end
            node.GetCurrentChapter = function() return 1 end
            node:SetScript("OnClick", function(self)
                if index > 0 then A.SelectTier(index) end
                tierTooltip(self, index)
            end)
        end
    end

    local model = frame.RewardModel
    model.coaOriginalShowReward = model.ShowReward
    model.OnShow = function(self) A.UpdateModel(self, self.coaIndex or 1) end
    model.ShowReward = function(self, index) A.UpdateModel(self, index) end
    model.RefreshCurrentDisplay = function(self) A.UpdateModel(self, self.coaIndex or 1) end
    model.NextReward = function(self) A.UpdateModel(self, (self.coaIndex or 1) + 1) end
    model.PrevReward = function(self) A.UpdateModel(self, (self.coaIndex or 1) - 1) end
    model.OpenStore = function() end
    model.CollectButton:SetScript("OnClick", function() end)
    model.CollectButton:Disable()
    model.CollectButton:Hide()

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(120, 24)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 65, -30)
    button:SetText("Season Admin")
    button:Hide()
    button:SetScript("OnClick", function() if A.ShowAdmin then A.ShowAdmin() end end)
    frame.coaAdminButton = button
    A.Paint()
end

function A.Open()
    if not SeasonCollectionFrame then
        local ok, reason = LoadAddOn("Ascension_SeasonCollection")
        if not ok then A.Notify("error", "Cannot load Ascension seasonal UI: " .. tostring(reason)); return end
    end
    A.Adapt()
    if Collections then ShowUIPanel(Collections) end
    SeasonCollectionFrame:Show()
    A.Refresh(A.viewSeason)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function() A.Adapt() end)
SlashCmdList.COASEASON = function(text)
    A.Open()
    if text and text:lower() == "admin" and A.ShowAdmin then A.ShowAdmin() end
end
SLASH_COASEASON1 = "/coaseason"
A.listeners[#A.listeners+1] = function(kind, value)
    if kind == "state" then
        A.Adapt()
        A.Paint()
    elseif kind == "resync" then
        A.Refresh(A.viewSeason)
    elseif kind == "ok" or kind == "error" then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff80ff80Season:|r " .. value) end
    elseif kind == "saved" then
        A.Refresh(A.viewSeason)
    end
end
