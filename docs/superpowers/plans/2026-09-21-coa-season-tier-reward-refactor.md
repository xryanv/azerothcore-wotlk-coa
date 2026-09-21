# CoA Season Tier Reward Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the superseded spendable Seasonal Point shop with cumulative account-wide Season Points that automatically grant exactly one permanent reward at each of seven tiers, while Bazaar Tokens remain the only spendable shop currency.

**Architecture:** Keep the existing `mod-coa-season-progression` service, gameplay hooks, Bazaar integration, GM authorization, request replay protection, and Ascension frame adapter. Refactor persistence/protocol around a seven-row tier threshold table plus a one-row-per-tier reward assignment table; remove `BUY`, price/catalog synchronization, and purchase ledgers. GMs assign rewards by entering Tier Edit Mode from the native Ascension season frame, browsing the native Appearance/Vanity collection UI, previewing normally, and sending a validated `ADMIN|ASSIGN` mutation back to the server.

**Tech Stack:** AzerothCore C++20, prepared CharacterDatabase statements, MySQL/InnoDB, Lua 5.1, Ascension native `SeasonCollectionFrame`, `AppearanceWardrobeFrame`, `StoreCollectionFrame`, and existing `C_Appearance*` / `C_VanityCollection*` APIs.

**Spec:** `docs/superpowers/specs/2026-09-21-coa-season-progression-design.md`

## Global Constraints

- Season Points are account-wide, cumulative, non-spendable, and reset to zero only on season rollover.
- Exactly one automatic permanent reward is assigned to each of seven tier bubbles; all seven assignments are required before activation.
- Bazaar Tokens remain inventory item `975001`, remain spendable through the existing Ethereal Bazaar, and never reset on season rollover.
- Previously earned cosmetics, appearances, mounts, pets, vanity rewards, heirlooms, physical items, and Bazaar Tokens are never revoked by season edits or rollover.
- Playerbots must not earn Season Points or Bazaar Token level rewards.
- Elite/rare progress uses the configurable per-account/per-entry lockout; bosses remain repeatable.
- GM level 3 is checked server-side for every mutation; client visibility is not authorization.
- Preserve native Ascension rendering and browsing. Do not copy proprietary client Lua/XML into the public repo; add only original adapter code.
- Do not deploy schema/config changes to the live realm until isolated-clone acceptance passes again.
- The existing pending migration has only been applied to an isolated clone, so it may be replaced in-place before live deployment.

## Review Focus

1. Crossing multiple thresholds in one award must grant every newly completed tier exactly once, even across retry/relog boundaries.
2. Reassigning a tier reward must affect only accounts that have not already completed that tier; previously granted rewards remain untouched.
3. Activation must fail unless tiers 1–7 each have one valid assignment and thresholds are strictly increasing.
4. GM Tier Edit Mode must never turn a normal Appearance/Vanity browser click into an assignment unless a specific tier is armed and the server still confirms GM/revision state.
5. Opening the standalone admin frame and native season frame must be mutually exclusive so the overlap/glitches seen in runtime testing cannot recur.

---

### Task 1: Replace the spendable-points domain model and pending schema

**Files:**
- Modify: `modules/mod-coa-season-progression/src/SeasonRules.h`
- Delete: `modules/mod-coa-season-progression/src/SeasonRewardRules.h`
- Modify: `modules/mod-coa-season-progression/tests/test_season_rules.cpp`
- Delete/replace coverage: `modules/mod-coa-season-progression/tests/test_season_reward_rules.cpp`
- Modify: `data/sql/updates/pending_db_characters/rev_1789994614936680410.sql`
- Modify: `src/server/database/Database/Implementation/CharacterDatabase.h`
- Modify: `src/server/database/Database/Implementation/CharacterDatabase.cpp`

**Interfaces:**
- Produces `CoASeason::Tier { uint32_t threshold; }` and `Account { uint32_t points; uint32_t mask; }`.
- Produces `NewlyCompleted(Account const& before, Account const& after) -> uint32_t bitmask` through testable rule helpers.
- Produces DB tables `coa_season_tier`, `coa_season_tier_reward`, `coa_season_account`, `coa_season_tier_grant`, plus existing settings/kill/level/request/audit tables.

- [ ] **Step 1: Rewrite rule tests red-first** so a 0→600 award yields points `600`, mask bits 1–3, and no spendable balance/earned/spent fields; a repeated reconcile yields no new bits.
- [ ] **Step 2: Run** `g++ -std=c++20 -Wall -Wextra -Werror -Imodules/mod-coa-season-progression/src modules/mod-coa-season-progression/tests/test_season_rules.cpp -o /tmp/coa-season-rules && /tmp/coa-season-rules` and verify RED against the old payout model.
- [ ] **Step 3: Replace `Tier`/`Account` helpers** with threshold-only cumulative-point logic. `AddPoints(account, amount, tiers)` must overflow-check, update `account.points`, set newly satisfied mask bits, and never subtract points.
- [ ] **Step 4: Replace the pending migration** with clean pre-live tables: `coa_season_tier(season,tier,threshold)`, `coa_season_tier_reward(season,tier,type,target,preview,count,name,PRIMARY KEY(season,tier))`, `coa_season_account(season,account,points,mask)`, and `coa_season_tier_grant(season,account,tier,character_guid,type,target,count,created, UNIQUE(season,account,tier))`. Remove `coa_season_reward` and `coa_season_purchase`; retain durable `coa_season_request` and `coa_season_audit`.
- [ ] **Step 5: Replace prepared statements** for old reward/purchase rows with select/replace tier-reward and insert/select tier-grant statements. Keep all SQL parameter ordering mirrored in enum registration and implementation.
- [ ] **Step 6: Run** focused C++ rule tests, `python apps/codestyle/codestyle-sql.py --files data/sql/updates/pending_db_characters/rev_1789994614936680410.sql`, and `git diff --check`.
- [ ] **Step 7: Commit** `refactor: make season points cumulative tier progress`.

### Task 2: Refactor `SeasonService` around automatic tier grants

**Files:**
- Modify: `modules/mod-coa-season-progression/src/SeasonService.cpp`
- Modify: `modules/mod-coa-season-progression/src/SeasonService.h`
- Modify: `modules/mod-coa-season-progression/src/SeasonRequestRules.h`
- Modify: `modules/mod-coa-season-progression/tests/test_season_request_rules.cpp`
- Modify: `modules/mod-ascension-compat/src/AscensionSeasonCollection.h`
- Modify: `modules/mod-ascension-compat/src/AscensionCompat.cpp`

**Interfaces:**
- `GET` snapshot rows become `TIER|index|threshold|rewardType|target|preview|count|encodedName|completed`.
- Mutations are `ADMIN|TIER|season|revision|index|threshold` and `ADMIN|ASSIGN|season|revision|tier|type|target|preview|count|encodedName`.
- `AscensionSeasonCollection::Validate(type,target,preview)` remains the authoritative server validator.
- A successful point award returns newly completed tier bits; service persists account state and exactly-once grants in one serialized mutation path.

- [ ] **Step 1: Change request-shape tests** to reject `BUY`, `BROWSE`, `REWARD`, and `DISABLE`; accept the new `TIER` arity and `ASSIGN` mutation arity.
- [ ] **Step 2: Run request tests** and verify RED against the old classifier.
- [ ] **Step 3: Remove catalog/purchase state** from `Season`, `Snapshot`, `Handle`, and `Admin`; remove `Buy(...)`, price/min-tier validation, purchase ownership checks, and purchase response handling.
- [ ] **Step 4: Add `TierReward` state** indexed 1–7 and load it with each season. `Snapshot()` emits exactly seven `TIER` rows so the client always has threshold + assignment + completion together.
- [ ] **Step 5: Implement `ADMIN|ASSIGN`**: require GM3, draft/active season + exact revision, tier 1–7, validated reward type/target/preview/count, then replace only `(season,tier)`, bump revision, and audit `Assign tier N reward ...`.
- [ ] **Step 6: Harden `ACTIVATE`**: reject unless seven valid assignments exist and thresholds are strictly increasing. Preserve typed `RESET SEASON` confirmation and rollover behavior.
- [ ] **Step 7: Refactor `AwardProgress` to `AwardPoints` semantics**: after adding points, compute newly completed bits; for each bit, insert the unique tier-grant ledger and permanent reward/mail operations in the same character-DB transaction before publishing updated state. A duplicate unique grant must not duplicate collection/mail delivery.
- [ ] **Step 8: Preserve reassignment semantics**: completed accounts keep old grants because grant rows are immutable; a changed assignment is used only for accounts whose tier bit/grant does not yet exist.
- [ ] **Step 9: Run** rule/request tests, source codestyle, and syntax-only compiler checks for `SeasonService.cpp` and `AscensionCompat.cpp` using the known-good compile flags.
- [ ] **Step 10: Commit** `refactor: grant one permanent reward per season tier`.

### Task 3: Preserve gameplay/Bazaar behavior while renaming progress semantics

**Files:**
- Modify: `modules/mod-coa-season-progression/src/SeasonScripts.cpp`
- Modify: `modules/mod-coa-season-progression/src/SeasonService.h`
- Modify: `modules/mod-coa-season-progression/src/SeasonSettings.h`
- Modify: `modules/mod-coa-season-progression/tests/test_season_eligibility.cpp`
- Modify: `modules/mod-ethereal-bazaar/src/EtherealBazaarTokens.cpp`
- Modify: `modules/mod-coa-season-progression/README.md`

**Interfaces:**
- Gameplay hooks continue calling one service award API with account/player/event context; only the meaning changes from “progress then payout points” to “award cumulative Season Points directly.”
- Bazaar Token settings and delivery remain unchanged.

- [ ] **Step 1: Update tests/text names** so quest=3, level=10, elite=1, rare=2, rare-elite=3, dungeon=12, heroic=18, raid=30, world=40 are explicitly Season Point awards.
- [ ] **Step 2: Verify bot/pet/group eligibility tests** still pass unchanged; add a regression asserting bot-controlled characters cannot create tier completion/grants.
- [ ] **Step 3: Rename service methods/fields only where it removes ambiguity** (`AwardProgress` → `AwardPoints`, snapshot `progress` → `points`); do not refactor unrelated hook code.
- [ ] **Step 4: Keep Bazaar Token level/boss ranges and suppression behavior unchanged**; confirm season rollover code never edits item `975001`.
- [ ] **Step 5: Run eligibility/settings tests and syntax checks** for `SeasonScripts.cpp` and `EtherealBazaarTokens.cpp`.
- [ ] **Step 6: Commit** `refactor: treat season points as cumulative progress`.

### Task 4: Simplify addon protocol and normal-player season UI

**Files:**
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/Protocol.lua`
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/SeasonUI.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_protocol.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_season_ui.lua`

**Interfaces:**
- `CoASeason.state.points` is cumulative progress; there is no spendable balance.
- Each `state.tiers[i]` contains `threshold,type,target,preview,count,name,completed`.
- Player UI never sends `BUY` and never enables a purchase button.

- [ ] **Step 1: Rewrite Lua protocol tests** to require seven assignment-bearing `TIER` rows, reject old `REWARD` rows, and ensure no `BUY` request is durable/generated.
- [ ] **Step 2: Run** `lua modules/mod-coa-season-progression/tests/test_protocol.lua` and verify RED.
- [ ] **Step 3: Remove catalog/buy state** (`rewards`, `buyPending`, `coaReward` purchase target, purchase error recovery) while preserving request IDs, staged snapshots, invalidation, timeout recovery, and GM bootstrap.
- [ ] **Step 4: Render the selected tier’s assigned reward** through the existing Ascension reward model using its preview ID/target metadata; locked tiers show required cumulative points, completed tiers show earned/granted state. Do not display a spendable Seasonal Point balance or purchase button.
- [ ] **Step 5: Keep normal tier clicks normal** for non-GMs and for GMs outside edit mode; no admin action is triggered merely because the account is GM.
- [ ] **Step 6: Run** protocol/UI Lua suites and verify native frame reopen/invalidation tests still pass.
- [ ] **Step 7: Commit** `refactor: simplify season client to tier rewards`.

### Task 5: Implement native GM Tier Edit Mode and remove the custom reward browser

**Files:**
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/SeasonUI.lua`
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/AdminUI.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_admin_ui.lua`
- Add test fixture helpers only inside: `modules/mod-coa-season-progression/tests/test_season_ui.lua`

**Interfaces:**
- `A.EnterTierEditMode()` arms editing; `A.assignmentTier` is 1–7 only while armed.
- Clicking a native season tier in edit mode opens the native collection surface and records that tier.
- Appearance selection source: native `AppearanceModelMixin` instances expose `appearanceID`, `displayName`, and `entry` after `SetAppearanceID(...)`.
- Vanity selection source: native `StoreCollectionFrame` keeps the previewed item in `Store.ItemInternal` and already provides normal artwork/model previews.
- Assignment sends `ADMIN|ASSIGN|season|revision|tier|type|target|preview|count|encodedName`.

- [ ] **Step 1: Add Lua tests** for edit-mode arming/disarming, tier 1–7 validation, non-GM denial, stale revision clearing, and normal player clicks remaining untouched.
- [ ] **Step 2: Add an `Edit Tier Rewards` GM control** to the native season frame. Entering it closes/hides `CoASeasonAdminFrame`, visibly marks edit mode, and makes the seven existing tier buttons assignment selectors without replacing their artwork.
- [ ] **Step 3: On tier click in edit mode**, store the tier number and open the native collection browser rather than the custom Rewards tab. Prefer the Ascension Appearance collection for appearance IDs; hook the existing collection model instances' `OnMouseUp` only while edit mode is armed to copy the clicked model's `appearanceID` into `A.assignmentCandidate`, then expose a small `Assign to Tier N` button adjacent to the native browser. Do not replace `AppearanceModelMixin` globally.
- [ ] **Step 4: Support Vanity collection selections** by reading `StoreCollectionFrame.ItemInternal`/the existing vanity metadata and showing the same `Assign to Tier N` control while preserving Ascension’s normal preview paper/model. Do not invoke the store purchase action.
- [ ] **Step 5: Validate client-side selection shape before sending**: appearance→`type=appearance,target=appearanceID,preview=appearanceID,count=1`; vanity→`type=vanity,target=itemID,preview=<known appearance preview or 0>,count=1`. The server remains authoritative and rejects invalid IDs.
- [ ] **Step 6: After `ASSIGN` success**, close assignment mode, refresh season state, return to the native season window, select that tier, and show its newly assigned reward through Ascension’s renderer.
- [ ] **Step 7: Remove the custom Rewards tab/search/list/editor** from `AdminUI.lua`. Keep a narrow validated-ID fallback only if the native browser cannot represent a supported reward type; it must be a single assignment form, not another catalog.
- [ ] **Step 8: Enforce mutual exclusion**: `A.ShowAdmin()` hides the native season frame; `A.EnterTierEditMode()` hides the standalone admin frame. Add a test that both large frames are never simultaneously shown.
- [ ] **Step 9: Run** `test_admin_ui.lua`, `test_season_ui.lua`, and `test_protocol.lua`.
- [ ] **Step 10: Commit** `feat: assign season tier rewards through Ascension browser`.

### Task 6: Simplify the standalone GM admin surface

**Files:**
- Modify: `modules/mod-coa-season-progression/addon/CoA_SeasonProgression/AdminUI.lua`
- Modify: `modules/mod-coa-season-progression/tests/test_admin_ui.lua`
- Modify: `modules/mod-coa-season-progression/README.md`

**Interfaces:**
- Tabs are exactly `Season`, `Economy`, `Accounts`, `History`.
- Economy edits thresholds only; there are no tier payout fields.
- Account adjustment changes cumulative Season Points and cannot reduce below zero; decreasing points never clears completed tier bits or revokes a reward already granted.

- [ ] **Step 1: Rewrite admin tests** to assert four tabs, no Rewards tab, no Seasonal Point payout/cost controls, and no overlapping season frame.
- [ ] **Step 2: Simplify Economy** to activity Season Point awards, Bazaar Token ranges/chances, lockout settings, and seven threshold fields.
- [ ] **Step 3: Keep Season lifecycle** create/copy/list/activate with typed `RESET SEASON`; surface activation error when any tier lacks an assignment.
- [ ] **Step 4: Keep Accounts/History** but rename labels from balance/progress to cumulative Season Points and completed tiers; add a regression where a GM lowers points below a completed threshold and the tier mask/grant remains intact.
- [ ] **Step 5: Run admin Lua tests** and manually inspect widget coordinates in the isolated client at 2560×1440 and the existing 1264×692 windowed size used in prior tests.
- [ ] **Step 6: Commit** `fix: streamline season admin layout`.

### Task 7: Rebuild and repeat isolated runtime acceptance before live deployment

**Files:**
- Modify only as required by verified defects: feature source/tests/docs above.
- Update: GitHub Issue #1 after evidence is collected.

**Interfaces:**
- Build environment: existing Ubuntu `coa-build` container with Oracle MySQL client, source mounted `/coa/server-update`.
- Staged install: `/games/coa/install-season`.
- Test DB: recreate `coa-db-season-test` from `/games/coa/backups/pre-season-runtime-20260921-133357.sql.zst` so the obsolete schema from the previous isolated run is gone.

- [ ] **Step 1: Run the complete focused gate**: all C++ unit tests, all three Lua suites, C++/SQL codestyle, `git diff --check`, and syntax-only checks.
- [ ] **Step 2: Run a full containerized build** of `worldserver` and `authserver`; require 100% successful link/install with `mod-coa-season-progression` discovered.
- [ ] **Step 3: Recreate the isolated MySQL clone from the pre-season backup**, start staged worldserver on alternate loopback ports, and verify the revised migration creates `coa_season_tier_reward`/`coa_season_tier_grant` and does not create the obsolete purchase/catalog tables.
- [ ] **Step 4: Client acceptance as GM**: verify no overlap, create draft, assign all seven rewards by clicking tier circles and using native previews, confirm activation fails at six assignments and succeeds at seven.
- [ ] **Step 5: Progression acceptance**: award/earn enough Season Points to cross one and multiple thresholds; verify each tier reward grants once, survives relog, and reassignment does not alter prior grants.
- [ ] **Step 6: Bazaar acceptance**: verify level/boss Token earning and an existing Bazaar purchase; confirm season rollover leaves item `975001` balance intact.
- [ ] **Step 7: Rollover acceptance**: create/activate the next season; verify points/tier state reset to zero while permanent collections/items/tokens remain.
- [ ] **Step 8: Run a focused Gemini 3.8 review** through `omniroute-live/antigravity/gemini-3.8-flash-tiered`; address only verified Critical/Important findings, then rerun affected tests.
- [ ] **Step 9: Push final commits and update Issue #1** with build/runtime evidence and any remaining live-deployment gate. Do not switch the live realm until acceptance is green.
