# CoA Season Native Tab and GM Admin Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the CoA season client so Season is a first-class Ascension Collections tab for every player, while server-confirmed GMs can explicitly toggle a session-local admin mode that exposes season administration and a dedicated reward picker without modifying the normal Wardrobe/Vanity interfaces.

**Architecture:** Preserve the already-completed cumulative Season Points backend and seven-tier automatic grant protocol. Split the remaining client responsibilities into a native-tab integration (`SeasonTab.lua`), player/GM display policy (`SeasonUI.lua` + `AdminUI.lua`), and a separate GM-only reward picker (`RewardPicker.lua`). The picker queries Ascension appearance/vanity data but never hooks the normal player collection buttons; candidate selection previews through the existing season reward renderer and assignment requires a second explicit confirmation action.

**Tech Stack:** WoW 3.3.5 Lua 5.1, Ascension `Collections`/`TabSystemMixin`, `SeasonCollectionFrame`, `C_AppearanceCollection`, `C_Appearance`, `C_VanityCollection`, existing `COASEASON` addon-message protocol, AzerothCore backend already built on the feature branch.

**Spec:** `docs/superpowers/specs/2026-09-21-coa-season-progression-design.md`

**Supersedes:** Client/UI Tasks 5-7 of `docs/superpowers/plans/2026-09-21-coa-season-tier-reward-refactor.md`. Backend/domain Tasks 1-4 remain completed and are not to be rewritten.

## Global Constraints

- Season is a normal Ascension Collections tab reached through Ascension's existing navigation, including the normal `N` entry point.
- `/coaseason` is optional convenience navigation only; it opens Ascension directly to Season and is not required for ordinary access.
- `/coaseason admin` toggles session-local GM editing mode; `/coaseason admin on` and `/coaseason admin off` set it deterministically.
- A GM sees the same player Season tab as everyone else until admin mode is enabled.
- GM-only controls require both server-confirmed `state.admin == true` and session-local `adminMode == true`.
- Every mutation remains server-authorized at GM level 3; client mode/visibility never grants privilege.
- `CoA_SeasonProgression` remains a separate addon and must not overwrite shipped Ascension addon files.
- Normal Ascension Wardrobe, Vanity, Store, Character Advancement/Trees, and other pages keep their ordinary behavior even while season admin mode is enabled.
- The dedicated GM Reward Picker may reuse Ascension data/rendering APIs but must not install click hooks into normal player collection models/buttons.
- Selecting a reward candidate only previews it; **Assign This Reward to Tier N** is a separate explicit action.
- The cumulative Season Points / one reward per tier / Bazaar-only-spendable-currency backend remains unchanged.
- Do not use focus-stealing `xdotool`/workspace automation against the live game client during acceptance. Client interaction is manual unless the user explicitly asks for automation.
- Live realm/database remain untouched until isolated acceptance passes.

## Current Branch State

The following backend/client foundations are already committed and should be preserved rather than reimplemented:

- `4667f87` cumulative Season Points domain/schema;
- `86d580a` automatic one-reward-per-tier service/protocol;
- `88bc86f` gameplay/Bazaar cumulative-point semantics;
- `caf7253` simplified player snapshot/protocol;
- `3a362e3` temporary native-browser GM edit flow (to be replaced by this plan);
- `c82cc5e` compact admin layout.

There are currently two uncommitted acceptance-fix edits in `AdminUI.lua` and `test_admin_ui.lua` that keep the player Season frame visible while the admin window is open. Preserve and fold those edits into Task 2; do not discard them.

## File Structure

- `SeasonTab.lua` — owns registration of `SeasonCollectionFrame` as `Collections.Tabs.Season`, direct navigation, and load/reload repair.
- `SeasonUI.lua` — owns player tier display, reward preview, admin-mode state, tier selection, and GM entry controls; removes normal-browser assignment hooks.
- `RewardPicker.lua` — owns GM-only reward search/browse/candidate/explicit assignment state and physical-item fallback.
- `AdminUI.lua` — owns Season/Economy/Accounts/History configuration only and obeys admin-mode gating.
- `Protocol.lua` — unchanged unless a client-only listener hook is required; wire protocol already has the needed `ADMIN|ASSIGN` mutation.
- `CoA_SeasonProgression.toc` — loads `SeasonTab.lua` before `SeasonUI.lua` and `RewardPicker.lua` before `AdminUI.lua`.
- `test_season_tab.lua`, `test_reward_picker.lua` — focused new Lua suites.
- `test_season_ui.lua`, `test_admin_ui.lua`, `test_protocol.lua` — regression suites for player/admin separation and unchanged wire behavior.

## Review Focus

1. **Collections reload/order:** Season registration must be idempotent whether `Collections` already exists, loads later, or its tab system is rebuilt; the user should never get duplicate Season tabs.
2. **Privilege loss/stale state:** logout/reload or a refreshed snapshot that no longer says GM must force admin mode off, close GM frames, and leave the normal Season tab functional.
3. **Normal browser isolation:** opening/closing the GM picker must leave Wardrobe/Vanity selected tab, filters, click behavior, and purchase actions untouched.
4. **Explicit confirmation:** selecting/searching a reward must never send `ADMIN|ASSIGN`; only the dedicated Assign button may send it, and it must bind the current season/revision/tier.
5. **Human acceptance stability:** no automated keyboard/workspace focus injection during the runtime pass; acceptance must not interfere with the user's desktop/game session.

---

### Task 1: Register Season as a native Ascension Collections tab

**Files:**
- Create: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/SeasonTab.lua`
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/CoA_SeasonProgression.toc`
- Create: `modules/mod-coa-season-progression/tests/test_season_tab.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_season_ui.lua`

**Interfaces:**
- Produces `A.RegisterSeasonTab() -> boolean, reason?`.
- Produces `A.OpenSeasonTab() -> boolean`.
- Produces `A.SeasonTabID() -> number|nil`.
- Consumes existing global `Collections`, `SeasonCollectionFrame`, and Ascension's `Collections:AddTab(label, panelName)` / `Collections:GoToTab(tabID)` APIs.

- [ ] **Step 1: Write a failing native-tab test** with a stub `Collections:AddTab` that records label/panel and returns a tab object with `GetTabID()`. Assert registration creates exactly one `Season` tab targeting `SeasonCollectionFrame`, stores it at `Collections.Tabs.Season`, and a second registration call creates no duplicate.

```lua
assert(A.RegisterSeasonTab())
assert(#addedTabs == 1)
assert(addedTabs[1].label == "Season")
assert(addedTabs[1].panel == "SeasonCollectionFrame")
assert(Collections.Tabs.Season == 6)
assert(A.RegisterSeasonTab())
assert(#addedTabs == 1, "Season registration must be idempotent")
```

- [ ] **Step 2: Run the new test and verify RED.**

```bash
lua modules/mod-coa-season-progression/tests/test_season_tab.lua modules/mod-coa-season-progression/addon/CoA_SeasonProgression/
```

Expected: FAIL because `RegisterSeasonTab`/`OpenSeasonTab` do not exist.

- [ ] **Step 3: Implement `SeasonTab.lua`** so it loads `Ascension_SeasonCollection` only when needed, waits for `Collections`, adds the tab using Ascension's native `AddTab` API, assigns an icon/tooltip, updates layout, and never modifies `Ascension_Collections` source files.

```lua
function A.RegisterSeasonTab()
    if not SeasonCollectionFrame then
        local ok = LoadAddOn("Ascension_SeasonCollection")
        if not ok then return false, "season-addon-unavailable" end
    end
    if not Collections or not Collections.AddTab then return false, "collections-not-ready" end
    Collections.Tabs = Collections.Tabs or {}
    if Collections.Tabs.Season and Collections:GetTabByID(Collections.Tabs.Season) then return true end
    local tab = Collections:AddTab("Season", "SeasonCollectionFrame")
    tab:SetIcon("Interface\\Icons\\inv_treasurechest_felfirecitadel")
    tab:SetTooltip("Season", "Gameplay-earned seasonal progression and rewards")
    Collections.Tabs.Season = tab:GetTabID()
    Collections:UpdateTabLayout()
    return true
end
```

- [ ] **Step 4: Implement direct navigation** via `A.OpenSeasonTab()` using the normal Ascension shell, not manual child-frame show/hide calls.

```lua
function A.OpenSeasonTab()
    local ok = A.RegisterSeasonTab()
    if not ok then return false end
    Collections:GoToTab(Collections.Tabs.Season)
    A.Refresh(A.viewSeason)
    return true
end
```

- [ ] **Step 5: Add load-order repair coverage.** Simulate `ADDON_LOADED` with Collections unavailable first and available later; verify a later call registers exactly once. Also assert registration never calls `RemoveAllTabs`, never hides Wardrobe/Vanity, and never patches `CollectionsMixin:SetupTabSystem` globally.

- [ ] **Step 6: Update `.toc` load order** to `Protocol.lua`, `SeasonTab.lua`, `SeasonUI.lua`, `RewardPicker.lua`, `AdminUI.lua` (RewardPicker may be absent until Task 3; add it to the TOC only in Task 3 if Lua loading an absent file would break the client).

- [ ] **Step 7: Run** `test_season_tab.lua`, `test_season_ui.lua`, `test_protocol.lua`, then `git diff --check`.

- [ ] **Step 8: Commit** `feat: register season as Ascension collections tab`.

### Task 2: Add session-local GM admin mode and gate all privileged UI

**Files:**
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/SeasonUI.lua`
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/AdminUI.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_season_ui.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_admin_ui.lua`

**Interfaces:**
- Produces `A.IsAdminMode() -> boolean`.
- Produces `A.SetAdminMode(enabled) -> boolean`.
- Produces `A.ToggleAdminMode() -> boolean`.
- Consumes `A.OpenSeasonTab()` from Task 1.
- GM controls are visible iff `A.state.admin and A.adminMode`.

- [ ] **Step 1: Write failing policy tests** for the three command forms and UI gating.

```lua
A.state.admin = true
assert(not A.IsAdminMode())
assert(A.SetAdminMode(true) and A.IsAdminMode())
assert(A.SetAdminMode(false) and not A.IsAdminMode())
A.state.admin = false
assert(not A.SetAdminMode(true), "non-GM cannot enable admin mode")
```

Also assert a GM with admin mode off has the same `Season Admin`/`Edit Tier Rewards` visibility as a normal player: hidden.

- [ ] **Step 2: Run `test_season_ui.lua` and `test_admin_ui.lua` and verify RED** against the current unconditional `state.admin` controls.

- [ ] **Step 3: Implement session-local mode state** in `SeasonUI.lua`; do not store it in `CoASeasonSaved`.

```lua
function A.IsAdminMode()
    return A.adminMode == true and A.state and A.state.admin == true
end

function A.SetAdminMode(enabled)
    enabled = enabled == true
    if enabled and (not A.state or not A.state.admin) then
        A.adminMode = nil
        A.Notify("error", "Season admin mode requires server-confirmed GM level 3.")
        return false
    end
    A.adminMode = enabled or nil
    if not A.adminMode then
        if CoASeasonAdminFrame then CoASeasonAdminFrame:Hide() end
        if A.CloseRewardPicker then A.CloseRewardPicker("admin-off") end
    end
    A.Paint()
    return true
end
```

- [ ] **Step 4: Replace slash parsing** so ordinary navigation and admin-mode control are distinct.

```lua
SlashCmdList.COASEASON = function(text)
    local command = (text or ""):lower():match("^%s*(.-)%s*$")
    if command == "" then return A.OpenSeasonTab() end
    if command == "admin" then
        if A.SetAdminMode(not A.IsAdminMode()) then A.OpenSeasonTab() end
        return
    end
    if command == "admin on" then
        if A.SetAdminMode(true) then A.OpenSeasonTab() end
        return
    end
    if command == "admin off" then A.SetAdminMode(false); return end
    A.Notify("error", "Usage: /coaseason [admin [on|off]]")
end
```

- [ ] **Step 5: Gate Season-tab controls** in `A.Paint()` with `A.IsAdminMode()` rather than `state.admin` alone. Ordinary GM mode-off behavior must be indistinguishable from non-GM behavior.

- [ ] **Step 6: Gate the standalone admin frame** so `A.ShowAdmin()` requires both server GM state and admin mode. Fold in the current uncommitted coexistence fix: opening the compact admin frame must not hide the Season tab.

```lua
if not A.IsAdminMode() then
    A.Notify("error", "Enable season admin mode first with /coaseason admin.")
    return
end
```

- [ ] **Step 7: Add privilege-loss regression.** Feed a new `state` snapshot with `admin=false` while admin mode/admin frame are open and assert mode becomes off, GM frames close, and `A.OpenSeasonTab()`/player tier display remain usable.

- [ ] **Step 8: Remove the old `A.Open()` manual frame choreography** (`AppearanceWardrobeFrame:Hide()`, `StoreCollectionFrame:Hide()`, direct `SeasonCollectionFrame:Show()`) and route all opening through `A.OpenSeasonTab()`.

- [ ] **Step 9: Run all existing Lua suites plus `test_season_tab.lua`; verify `git diff --check`.**

- [ ] **Step 10: Commit** `feat: add explicit season GM admin mode`.

### Task 3: Replace normal-browser assignment hooks with a dedicated GM Reward Picker

**Files:**
- Create: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/RewardPicker.lua`
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/SeasonUI.lua`
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/CoA_SeasonProgression.toc`
- Create: `modules/mod-coa-season-progression/tests/test_reward_picker.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_season_ui.lua`

**Interfaces:**
- Produces `A.OpenRewardPicker(tier) -> boolean`.
- Produces `A.CloseRewardPicker(reason?)`.
- Produces `A.SetRewardCandidate(kind,target,preview,count,name) -> boolean`.
- Produces `A.QueryAppearanceCandidates(type,category,search,page) -> candidates,totalPages`.
- Produces `A.QueryVanityCandidates(search,flags,page) -> candidates,totalPages`.
- Produces `A.SubmitRewardCandidate() -> requestId|nil`.
- Consumes existing server mutation `A.Request("ADMIN","ASSIGN",season,revision,tier,type,target,preview,count,A.Encode(name))`.
- Candidate selection previews through `SeasonCollectionFrame.RewardModel`; it never mutates/sends until explicit Assign.

- [ ] **Step 1: Write a failing isolation/confirmation test.** Stub native Wardrobe/Vanity buttons with click counters and verify opening the picker installs no hooks/scripts on them. Select a candidate and assert no request is sent until `SubmitRewardCandidate()`.

```lua
assert(A.OpenRewardPicker(4))
assert(#requests == 0)
assert(A.SetRewardCandidate("appearance", 4404, 4404, 1, "Appearance Four"))
assert(#requests == 0, "selection only previews")
assert(A.SubmitRewardCandidate() == "req-1")
assert(requests[1][2] == "ASSIGN" and requests[1][5] == 4)
```

- [ ] **Step 2: Run `test_reward_picker.lua` and verify RED** because the dedicated picker APIs do not exist.

- [ ] **Step 3: Remove the temporary normal-browser integration from `SeasonUI.lua`:** delete `hookNativeAssignmentModels`, `InstallAssignmentHooks`, `ensureAssignmentButton`, `OpenAssignmentBrowser`, `CaptureAppearanceSelection`, `CaptureVanitySelection`, and every hook attached to `AppearanceWardrobeFrame.Collection.Models` or `StoreCollectionItemFrame*.Button`.

- [ ] **Step 4: Change tier-edit behavior** so GM edit mode + tier click calls only `A.OpenRewardPicker(index)`; ordinary tier clicks still call `A.SelectTier(index)`.

```lua
if A.tierEditMode then
    return A.OpenRewardPicker(index)
end
A.SelectTier(index)
return true
```

- [ ] **Step 5: Implement picker authorization/context.** `OpenRewardPicker` requires `A.IsAdminMode()`, editable season status, tier 1-7, and snapshots `season/revision/tier`. A state revision change closes the picker and clears its candidate.

- [ ] **Step 6: Implement appearance query adapter** using Ascension's existing data API without showing or hooking the normal Wardrobe UI:

```lua
local types = C_AppearanceCollection.GetAppearanceTypes() or {}
local categories = C_AppearanceCollection.GetCategoriesForType(appearanceType) or {}
C_AppearanceCollection.ApplyCategoryFilter(categoryID, search or "", filter, sorting)
local maxPages = math.max(C_AppearanceCollection.GetCategoryMaxPages() or 1, 1)
local ids = C_AppearanceCollection.GetCategoryAppearances(page) or {}
```

Normalize results to `{type="appearance",target=id,preview=id,count=1,name=displayName}` using `C_Appearance.GetAppearanceDisplayInfo(id)`. Preserve any already-loaded Wardrobe collection state (appearance type/category/search/page) before querying and restore it when the picker closes so the player's normal browser is not left changed.

- [ ] **Step 7: Implement vanity query adapter** with the query-only native API so it does not invoke Store purchase behavior:

```lua
local offset = (page - 1) * pageSize
local result = C_VanityCollection.QueryItems(search or "", flags, filterFlags, 1, offset, pageSize) or {}
```

Normalize returned item records to `{type="vanity",target=itemID,preview=appearanceID or 0,count=1,name=name}`. Resolve preview through `C_Appearance.GetItemAppearanceID(itemID)` when available.

- [ ] **Step 8: Build the GM-only picker frame** with one compact surface: Tier heading, source tabs (`Appearances`, `Vanity`, `Item ID`), search field, category/type selector, paged candidate buttons, candidate summary, **Assign This Reward to Tier N**, and **Cancel**. Candidate buttons call only `A.SetRewardCandidate(...)`.

- [ ] **Step 9: Reuse the Season reward renderer for preview** rather than constructing a second model renderer. When a candidate is selected, call `A.ShowPreview(SeasonCollectionFrame.RewardModel, candidate)`. On Cancel/Close, call `A.SelectTier(originalTier)` to restore the assigned player-facing reward.

- [ ] **Step 10: Move the physical-item fallback** out of `AdminUI.lua` into the picker's `Item ID` source. Validate tier is fixed by picker context, item ID/count are positive integers, display name is 1-48 characters, and selection still requires the same explicit Assign button.

- [ ] **Step 11: Implement explicit submission** binding the snapshotted season/revision/tier and candidate. Disable Assign while the mutation is pending; on `saved`, close picker, refresh state, reopen/select the edited tier; on `error/resync`, keep/clear state according to authoritative revision and never retry automatically.

- [ ] **Step 12: Add normal-browser isolation assertions** that source contains no `HookScript` against `AppearanceWardrobeFrame.Collection.Models` or `StoreCollectionItemFrame`, and picker opening/closing does not call `Collections:GoToTab(Collections.Tabs.Wardrobe/Vanity)`.

- [ ] **Step 13: Run** `test_reward_picker.lua`, `test_season_ui.lua`, `test_admin_ui.lua`, `test_protocol.lua`, `test_season_tab.lua`, and `git diff --check`.

- [ ] **Step 14: Commit** `feat: add dedicated GM season reward picker`.

### Task 4: Simplify Season Admin around native-tab admin mode

**Files:**
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/AdminUI.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_admin_ui.lua`
- Modify: `modules/mod-coa-season-progression/README.md`

**Interfaces:**
- Admin tabs remain exactly `Season`, `Economy`, `Accounts`, `History`.
- `Edit Tier Rewards` calls `A.EnterTierEditMode()` / picker flow from Task 3.
- No item-ID assignment form remains in AdminUI.

- [ ] **Step 1: Rewrite the admin test** to require admin mode as well as GM status, require four tabs, require `Edit Tier Rewards`, and explicitly forbid `Assign item ID`, `Rewards`, `BROWSE`, and normal-browser assignment language.

- [ ] **Step 2: Run the admin test and verify RED** because the current Season panel still contains the item-ID fallback.

- [ ] **Step 3: Remove the physical-item fallback controls** from `seasonPanel()`; the Season tab/picker is now the only tier reward editing entry point.

- [ ] **Step 4: Update copy** from “native Ascension browser” to “GM Reward Picker” and make clear that seven assigned tier rewards are required before activation.

- [ ] **Step 5: Preserve the compact centered 530x560 layout** and coexistence behavior. Add test assertions that showing the admin frame does not hide `SeasonCollectionFrame` or change `Collections` current tab.

- [ ] **Step 6: Update README** with player navigation (`N` → Season tab), optional `/coaseason`, and GM mode commands.

- [ ] **Step 7: Run the full Lua suite and `git diff --check`.**

- [ ] **Step 8: Commit** `fix: align season admin with GM picker workflow`.

### Task 5: Manual isolated-client acceptance and finish the existing full-stack runtime gate

**Files:**
- Modify only for defects proven by acceptance: client addon files/tests/docs above.
- Update GitHub Issue #1 after evidence is collected.

**Interfaces:**
- Existing isolated world/auth/db remain the acceptance target: DB clone on `127.0.0.1:3310`, auth `13724`, world `18085`.
- The already-built staged backend contains the cumulative-points/tier-grant service; client-only Lua changes can be copied into `/games/coa/client/Interface/AddOns/CoA_SeasonProgression` and picked up by `/reload`.

- [ ] **Step 1: Run the complete static client gate**: all five Lua suites (`protocol`, `season_tab`, `season_ui`, `reward_picker`, `admin_ui`) and `git diff --check`.

- [ ] **Step 2: Copy only the current addon files into the isolated test client** and verify source/client hashes match. Do not modify Ascension's shipped addon files.

- [ ] **Step 3: Perform client interaction manually.** Do not run `xdotool`, forced workspace switching, or scripts that type commands into the game. The user controls the client during this acceptance pass.

- [ ] **Step 4: Normal-player UI acceptance:** open Ascension via `N`; verify Season is a normal tab alongside existing tabs, switching among Character Advancement/Vanity/Wardrobe/Season causes no overlap, and `/coaseason` merely selects Season.

- [ ] **Step 5: GM mode acceptance:** while logged into the GM test account, verify Season initially looks like the player view; run `/coaseason admin on` manually and verify `Season Admin`/`Edit Tier Rewards` appear; `/coaseason admin off` removes them without closing/breaking the Season tab.

- [ ] **Step 6: Reward picker acceptance:** enable admin mode, choose Edit Tier Rewards, click a tier, search/browse candidates in the dedicated picker, preview several candidates without any DB mutation, press **Assign This Reward to Tier N**, then verify the tier refreshes to that reward. Confirm ordinary Wardrobe/Vanity behavior remains unchanged before and after picker use.

- [ ] **Step 7: Authorization acceptance:** verify a non-GM account sees Season but no GM controls and cannot enable admin mode; if a crafted mutation is attempted through the test harness, server rejects it.

- [ ] **Step 8: Complete the previously pending backend acceptance:** assign all seven rewards; confirm activation is blocked at six and succeeds at seven; earn/adjust Season Points to cross one and multiple tiers; verify immutable one-time grants, relog persistence, threshold lowering behavior, and reward reassignment not affecting already completed accounts.

- [ ] **Step 9: Bazaar/rollover acceptance:** verify Bazaar Token earning/spending and that activation of the next season resets Season Points/tier completion while preserving permanent rewards and item `975001`.

- [ ] **Step 10: Restore client test-session configuration** (normal realmlist, no test-only state), stop/remove temporary auth/world test containers as appropriate, and leave the live realm untouched.

- [ ] **Step 11: Run final verification**: complete focused C++ backend tests already used by the branch, all Lua suites, `git diff --check`, and fresh `git status`. If any C++ files changed while fixing runtime defects, rerun syntax/build gates for those files before claiming completion.

- [ ] **Step 12: Commit runtime-proven fixes**, push the branch, and update GitHub Issue #1 with exact build/test/manual acceptance evidence plus the remaining live-deployment checkpoint.

- [ ] **Step 13: Request a fresh whole-branch review** using the configured Gemini 3.8 Antigravity route; address only verified Critical/Important findings and rerun affected tests before the live-deployment decision.
