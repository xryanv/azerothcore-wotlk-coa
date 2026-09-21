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

local function assignmentContextValid()
    local s = A.state
    return A.tierEditMode and s and s.admin and s.status ~= "archived" and
        s.season == A.assignmentSeason and s.revision == A.assignmentRevision
end

local function setAssignmentButton()
    local button = A.assignmentButton
    if not button then return end
    if not A.tierEditMode or not A.assignmentTier then button:Hide(); return end
    button:Show()
    local candidate = A.assignmentCandidate
    button:SetText(candidate and ("Assign to Tier " .. A.assignmentTier) or
        ("Select reward for Tier " .. A.assignmentTier))
    button:SetEnabled(candidate ~= nil and A.assignmentRequest == nil)
end

function A.ExitTierEditMode()
    A.tierEditMode = nil
    A.assignmentTier = nil
    A.assignmentCandidate = nil
    A.assignmentSeason = nil
    A.assignmentRevision = nil
    setAssignmentButton()
    if A.editTierButton then A.editTierButton:SetText("Edit Tier Rewards") end
end

function A.EnterTierEditMode()
    local s = A.state
    if not s or not s.admin or s.status == "archived" or A.assignmentRequest then
        A.Notify("error", "Tier reward editing requires an editable GM season state.")
        return false
    end
    if CoASeasonAdminFrame and CoASeasonAdminFrame:IsShown() then CoASeasonAdminFrame:Hide() end
    A.tierEditMode = true
    A.assignmentSeason = s.season
    A.assignmentRevision = s.revision
    A.assignmentTier = nil
    A.assignmentCandidate = nil
    if A.editTierButton then A.editTierButton:SetText("Exit Tier Edit") end
    if SeasonCollectionFrame then SeasonCollectionFrame:Show() end
    setAssignmentButton()
    return true
end

function A.SetAssignmentCandidate(kind, target, preview, count, name)
    if not assignmentContextValid() or not A.assignmentTier then return false end
    target, preview, count = tonumber(target), tonumber(preview) or 0, tonumber(count) or 1
    if (kind ~= "appearance" and kind ~= "vanity" and kind ~= "item") or not target or target < 1 or
        preview < 0 or count < 1 or type(name) ~= "string" or name == "" then
        return false
    end
    A.assignmentCandidate = {type=kind,target=target,preview=preview,count=count,name=name,
        season=A.assignmentSeason,revision=A.assignmentRevision}
    setAssignmentButton()
    return true
end

function A.CaptureAppearanceSelection(model)
    local id = model and tonumber(model.appearanceID)
    if not id or id < 1 then return false end
    local name = model.displayName or ("Appearance " .. id)
    return A.SetAssignmentCandidate("appearance", id, id, 1, name)
end

function A.CaptureVanitySelection(store)
    local id = store and tonumber(store.ItemInternal)
    if not id or id < 1 then return false end
    local name
    if type(GetItemInfo) == "function" then name = GetItemInfo(id) end
    if not name and C_VanityCollection and C_VanityCollection.GetItem then
        local item = C_VanityCollection.GetItem(id)
        name = item and item.name
    end
    name = name or ("Vanity " .. id)
    local preview = 0
    if C_Appearance and C_Appearance.GetItemAppearanceID then
        local ok, value = pcall(C_Appearance.GetItemAppearanceID, id)
        if ok and tonumber(value) then preview = tonumber(value) end
    end
    return A.SetAssignmentCandidate("vanity", id, preview, 1, name)
end

local function hookNativeAssignmentModels()
    local collection = AppearanceWardrobeFrame and AppearanceWardrobeFrame.Collection
    if collection and collection.Models then
        for _, model in ipairs(collection.Models) do
            if model.HookScript and not model.coaSeasonAssignmentHooked then
                model.coaSeasonAssignmentHooked = true
                model:HookScript("OnMouseUp", function(self)
                    if A.tierEditMode and A.assignmentTier then A.CaptureAppearanceSelection(self) end
                end)
            end
        end
    end
    for i=1,9 do
        local button = _G["StoreCollectionItemFrame" .. i .. ".Button"]
        if button and button.HookScript and not button.coaSeasonAssignmentHooked then
            button.coaSeasonAssignmentHooked = true
            button:HookScript("OnClick", function()
                if A.tierEditMode and A.assignmentTier then A.CaptureVanitySelection(StoreCollectionFrame) end
            end)
        end
    end
end
A.InstallAssignmentHooks = hookNativeAssignmentModels

local function ensureAssignmentButton()
    if A.assignmentButton or not Collections then return end
    local button = CreateFrame("Button", "CoASeasonAssignTierButton", Collections, "UIPanelButtonTemplate")
    button:SetSize(190, 26)
    button:SetPoint("BOTTOMRIGHT", Collections, "BOTTOMRIGHT", -48, 18)
    button:SetFrameStrata("DIALOG")
    button:SetScript("OnClick", function()
        if Collections.IsOnTab and Collections.Tabs and Collections.Tabs.Vanity and
            Collections:IsOnTab(Collections.Tabs.Vanity) then
            A.CaptureVanitySelection(StoreCollectionFrame)
        end
        A.SubmitTierAssignment()
    end)
    button:Hide()
    A.assignmentButton = button
end

function A.OpenAssignmentBrowser()
    if not assignmentContextValid() or not A.assignmentTier then return false end
    if SeasonCollectionFrame then SeasonCollectionFrame:Hide() end
    if Collections and Collections.GoToTab and Collections.Tabs and Collections.Tabs.Wardrobe then
        Collections:GoToTab(Collections.Tabs.Wardrobe)
    elseif Collections then
        ShowUIPanel(Collections)
    end
    ensureAssignmentButton()
    hookNativeAssignmentModels()
    if Timer and Timer.After then Timer.After(0, hookNativeAssignmentModels)
    elseif C_Timer and C_Timer.After then C_Timer.After(0, hookNativeAssignmentModels) end
    setAssignmentButton()
    return true
end

function A.HandleTierClick(index)
    index = tonumber(index)
    if not index or index < 1 or index > 7 or index % 1 ~= 0 then return false end
    if not A.tierEditMode then
        A.SelectTier(index)
        return true
    end
    if not assignmentContextValid() then
        A.ExitTierEditMode()
        A.Notify("error", "Season changed; reopen Tier Edit Mode.")
        return false
    end
    A.assignmentTier = index
    A.assignmentCandidate = nil
    setAssignmentButton()
    return A.OpenAssignmentBrowser()
end

function A.SubmitTierAssignment()
    if not assignmentContextValid() or not A.assignmentTier then
        A.ExitTierEditMode()
        A.Notify("error", "Season changed; tier assignment was cancelled.")
        return nil
    end
    if A.assignmentRequest then return nil end
    local c = A.assignmentCandidate
    if not c or c.season ~= A.assignmentSeason or c.revision ~= A.assignmentRevision then
        A.Notify("error", "Select a reward in the Ascension browser first.")
        return nil
    end
    local id = A.Request("ADMIN", "ASSIGN", A.assignmentSeason, A.assignmentRevision, A.assignmentTier,
        c.type, c.target, c.preview, c.count, A.Encode(c.name))
    if id then
        A.assignmentRequest = id
        A.assignmentPendingTier = A.assignmentTier
        setAssignmentButton()
    end
    return id
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
    model.Header:SetText(completed and ("Tier " .. index .. " — Earned") or
        ("Tier " .. index .. " — " .. tier.threshold .. " Season Points"))
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
        bar.Tier0:SetEnabled(true); bar.Tier0.Selected:Hide(); bar.Tier0.Locked:Hide()
    end
    for i=1,7 do
        local node = bar["Tier" .. i] or (bar.Tiers and bar.Tiers[i])
        if node then A.PaintTier(node, state.tiers[i], A.TierComplete(state.mask, i)) end
    end
    if frame.coaAdminButton then frame.coaAdminButton:SetShown(state.admin) end
    if A.editTierButton then A.editTierButton:SetShown(state.admin and state.status ~= "archived") end
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
        if A.tierEditMode then GameTooltip:AddLine("Click to choose this tier's reward.", 0.4, 0.8, 1) end
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
                if index > 0 then A.HandleTierClick(index) end
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
    model.CollectButton:Disable(); model.CollectButton:Hide()

    local admin = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    admin:SetSize(120,24); admin:SetPoint("TOPLEFT", frame, "TOPLEFT", 65, -30)
    admin:SetText("Season Admin"); admin:Hide()
    admin:SetScript("OnClick", function() if A.ShowAdmin then A.ShowAdmin() end end)
    frame.coaAdminButton = admin

    local edit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    edit:SetSize(135,24); edit:SetPoint("LEFT", admin, "RIGHT", 8, 0)
    edit:SetText("Edit Tier Rewards"); edit:Hide()
    edit:SetScript("OnClick", function()
        if A.tierEditMode then A.ExitTierEditMode() else A.EnterTierEditMode() end
    end)
    A.editTierButton = edit
    A.Paint()
end

function A.Open()
    if not SeasonCollectionFrame then
        local ok, reason = LoadAddOn("Ascension_SeasonCollection")
        if not ok then A.Notify("error", "Cannot load Ascension seasonal UI: " .. tostring(reason)); return end
    end
    A.Adapt()
    if Collections then ShowUIPanel(Collections) end
    if AppearanceWardrobeFrame then AppearanceWardrobeFrame:Hide() end
    if StoreCollectionFrame then StoreCollectionFrame:Hide() end
    SeasonCollectionFrame:Show()
    A.Refresh(A.viewSeason)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
    A.Adapt()
    if A.tierEditMode then hookNativeAssignmentModels() end
end)
SlashCmdList.COASEASON = function(text)
    A.Open()
    if text and text:lower() == "admin" and A.ShowAdmin then A.ShowAdmin() end
end
SLASH_COASEASON1 = "/coaseason"

A.listeners[#A.listeners+1] = function(kind, value)
    if kind == "state" then
        if A.tierEditMode and (value.season ~= A.assignmentSeason or value.revision ~= A.assignmentRevision) then
            A.ExitTierEditMode()
        end
        A.Adapt(); A.Paint()
        if A.assignmentReturnTier then
            local tier = A.assignmentReturnTier
            A.assignmentReturnTier = nil
            if Collections then ShowUIPanel(Collections) end
            if AppearanceWardrobeFrame then AppearanceWardrobeFrame:Hide() end
            if StoreCollectionFrame then StoreCollectionFrame:Hide() end
            if SeasonCollectionFrame then SeasonCollectionFrame:Show() end
            A.SelectTier(tier)
        end
    elseif kind == "resync" then
        if type(value) == "string" and value == A.assignmentRequest then
            A.assignmentRequest, A.assignmentPendingTier = nil, nil
        end
        A.ExitTierEditMode()
        A.Refresh(A.viewSeason)
    elseif kind == "saved" then
        if value == A.assignmentRequest then
            A.assignmentReturnTier = A.assignmentPendingTier
            A.assignmentRequest, A.assignmentPendingTier = nil, nil
            A.ExitTierEditMode()
        end
        A.Refresh(A.viewSeason)
    elseif kind == "ok" or kind == "error" then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff80ff80Season:|r " .. value) end
    end
end
