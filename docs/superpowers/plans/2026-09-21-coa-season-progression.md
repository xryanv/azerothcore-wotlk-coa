# CoA Seasonal Progression Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans or subagent-driven-development task by task.

**Goal:** Implement gameplay-earned, account-wide seasons with Ascension previews and live GM administration.
**Architecture:** A disabled-by-default C++ module owns MySQL persistence, serialized economy operations and hidden self-whisper RPC. A companion addon adapts existing Ascension frame instances and provides GM editors. Permanent collection writes and durable item delivery stay separate from season rollover.
**Tech Stack:** AzerothCore C++20, prepared CharacterDatabase statements, MySQL/InnoDB, Lua 5.1.
**Spec:** docs/superpowers/specs/2026-09-21-coa-season-progression-design.md

## Global constraints

- Season Progress and Seasonal Points are account-wide; Bazaar Tokens remain inventory item 975001.
- Rollover creates a new active season and archives old records; never delete permanent ownership, items, tokens or level-award ledgers.
- Preserve Ascension preview renderers; replace data and interactions on actual frame instances, not only mixin tables.
- GM security level 3 is checked server-side on every admin request.
- Human sessions only; elites/rares have account-entry rolling 86400-second lockouts by default.
- Existing Bazaar quest/kill token grants must be suppressed while the new module is active.
- Existing source is in /games/coa/server-update, already a linked worktree. Work on feat/season-progression-system.
- SQL changes belong in data/sql/updates/pending_db_characters/.
- User authorized final design revision and implementation; no repeated design approval needed.
- Repository prohibits unrequested full builds/deployment. Complete source and focused checks; do not restart the realm or modify live databases/configuration.
- Never copy client proprietary Lua/XML into this public repository. Add original adapter code only.

## Review focus

1. Lost responses, retries and DB failures must not duplicate grants or spend points without delivering.
2. Bot or pet killing blows must credit eligible nearby human group members once per account, not bot accounts.
3. Missing, stale or reordered addon rows must not show an actionable partial catalog.
4. Rollover and settings edits invalidate stale purchase/admin revisions and preserve earned ownership.
5. Lua mixins were copied into existing frames: patch frame methods and invalidate all completion visuals on rollover.

## Final design refinements

- Purchase protocol binds season, catalog revision, reward and request nonce. Same nonce retries return the recorded result.
- Use durable mail delivery for physical items and tokens when needed; item creation/mail and currency debit share the character DB transaction.
- No success notification or cache update before confirmed database commit.
- Global economy serialization includes all account writers; different character map threads cannot race account awards.
- Validate grant targets and known client preview metadata; ordinary gameplay items are not automatically imported.
- Quest hook is verified to run at the end of RewardQuest in this fork.
- Award levels above a persisted character high-water mark, initialized at current level on first login. No retroactive level rewards.
- Use human group participation/tap/range checks for kills; skip summons, pets, critters, totems and noncombat farming.
- Active threshold edits reconcile completed tiers exactly once; completed tiers are permanent within their season.
- Initial reward catalog must be curated explicitly by GM, not a blind import of normal loot.
- Runtime collection caches must refresh after committed account grants.

## Shared addon protocol (version 1)

Prefix: COASEASON (under the legacy 16-byte limit).
Self whispers only, LANG_ADDON; each whole wire message including prefix is at most 255 bytes.
Delimiter is |. Text fields are percent-encoded UTF-8 (percent and delimiter included); decoded length is bounded.
Every request starts 1|requestId|operation. Request ID: 1..32 ASCII letters/digits/underscore/hyphen.
Response starts 1|requestId|kind. All rows of a snapshot carry the same requestId.
State uses BEGIN / rows / END with row count and revision. The client stages rows and swaps only on complete END; expires incomplete snapshots.
Every mutation includes expected season and revision; stale requests fail and force refresh.

Requests:
- GET
- BUY|season|revision|rewardId
- ADMIN|LIST
- ADMIN|GET|seasonId
- ADMIN|CREATE|sourceSeasonId|encodedName (source 0 means defaults)
- ADMIN|SETTING|season|revision|key|value
- ADMIN|TIER|season|revision|index|threshold|points
- ADMIN|REWARD|season|revision|id|type|target|preview|count|cost|minTier|enabled|order|encodedName|encodedCategory
- ADMIN|DISABLE|season|revision|rewardId
- ADMIN|RESET|season|revision (restore economy/tier defaults)
- ADMIN|ACTIVATE|draftSeason|revision|encodedConfirmation (must equal RESET SEASON)
- ADMIN|ACCOUNT|accountId
- ADMIN|ADJUST|season|revision|accountId|signedPoints|encodedReason
- ADMIN|HISTORY|season|offset

Responses:
- ERROR|encodedMessage
- OK|encodedMessage (mutation success; addon requests refresh)
- BEGIN|season|revision|encodedName|progress|points|tierMask|admin|status
- SETTING|key|value
- TIER|index|threshold|points
- REWARD|id|type|target|preview|count|cost|minTier|enabled|order|encodedName|encodedCategory|owned
- END|rowCount
- SEASON|id|status|revision|encodedName (LIST terminated by OK)
- ACCOUNT|accountId|season|progress|points
- HISTORY|timestamp|accountId|encodedAction (bounded page, terminated by OK)

Reward types: appearance, vanity, item. Mounts/pets use validated vanity targets; unsafe arbitrary spell grants are excluded.
Settings keys: quest, level, elite, rare, rare_elite, dungeon, heroic, raid, world, level_tokens,
dungeon_min, dungeon_max, dungeon_chance, heroic_min, heroic_max, heroic_chance,
raid_min, raid_max, raid_chance, world_min, world_max, world_chance, lockout_enabled, lockout_seconds.
Defaults: progress 3,10,1,2,3,12,18,30,40; level tokens 2; boss ranges 1..3,2..4,4..8,8..15; chance 100;
lockout_enabled 1, lockout_seconds 86400; tiers 100/25,250/40,500/60,900/90,1400/125,2100/175,3000/250.

## Task 1: Persistence, rules and safe economy service

Files: modules/mod-coa-season-progression/src/SeasonRules.h, SeasonService.h/.cpp,
data/sql/updates/pending_db_characters/rev_202609210001.sql,
src/server/database/Database/Implementation/CharacterDatabase.h/.cpp,
modules/mod-coa-season-progression/tests/.

Interface: service owns active season/settings/catalog and exposes state, progress, purchase and admin handlers.
- [ ] Write rule tests for multi-tier crossing, retained tier bits, level high-water marks and lockout boundaries.
- [ ] Test expected red before implementing helpers; implement checked arithmetic and full numeric parsing.
- [ ] Add idempotent CREATE TABLE IF NOT EXISTS migrations; never seed destructively over existing economy.
- [ ] Register prepared statements; use transactions with observable results and serialize mutations.
- [ ] Test stale revisions, replayed requests, insufficient funds, duplicate ownership, failed commit and rollover preservation.
- [ ] Commit source with focused lint evidence.

## Task 2: Gameplay and permanent rewards

Files: modules/mod-coa-season-progression/src/SeasonScripts.cpp, season_loader.cpp,
conf/coa_season.conf.dist, modules/mod-ethereal-bazaar/src/EtherealBazaarTokens.cpp,
modules/mod-ascension-compat/src/AscensionCompat.cpp and a small collection API header.

Interfaces: gameplay hooks call service award API; collection API validates/grants and refreshes actual compatibility caches.
- [ ] Verify real hook signatures and mapless lifecycle handling.
- [ ] Add failing eligibility/classification tests for bots, pets, group bosses and raid trash.
- [ ] Wire login, quest turn-in, level increases, direct/pet kills; deduplicate account group credit.
- [ ] Suppress old token generator only when new economy active; disabled module preserves legacy behavior.
- [ ] Create durable token/item mail in the same committed grant transaction; reconcile collection caches after success.
- [ ] Add disabled-by-default configuration and fail closed on missing schema/invalid settings.
- [ ] Commit with no live configuration/database changes.

## Task 3: Hidden RPC and GM administration

Files: modules/mod-coa-season-progression/src/SeasonProtocol.h/.cpp, SeasonAdmin.cpp.
Interfaces: the shared version-1 protocol above is the contract with client; no arbitrary SQL or executable Lua.
- [ ] Test exact prefix, self-recipient, size bounds, invalid encoding/numbers and non-GM forged admin requests.
- [ ] Bind mutations to season/revision and durable request ID; bound catalog size and output rate.
- [ ] Implement draft create/copy, settings, seven tiers, catalog edits, account adjustment, history and typed rollover.
- [ ] Validate ranges, strict thresholds, target IDs, prices, name lengths and enabled states.
- [ ] Snapshot rows are counted, revisioned and read from one coherent state.
- [ ] Commit with parser and authorization test evidence.

## Task 4: Ascension adapter and GM Lua UI

Files: modules/mod-coa-season-progression/addon/CoA_SeasonProgression/{CoA_SeasonProgression.toc,Protocol.lua,SeasonUI.lua,AdminUI.lua},
modules/mod-coa-season-progression/tests/test_protocol.lua.
Interfaces: Protocol.lua owns CoASeason global with Request, Refresh, callbacks and atomic state snapshots.
- [ ] Write executable Lua tests for percent encoding, missing/out-of-order rows, stale requests and frame rollover.
- [ ] Implement bounded request queue, timeout recovery, source validation and coherent snapshots.
- [ ] Patch SeasonCollectionFrame, RewardModel, ProgressBar and Tier instances; preserve renderer methods.
- [ ] Remove cash-store interactions inside this adapted season screen; no global unrelated API overrides.
- [ ] Implement five GM tabs, editable values, save/discard/default/copy, reward search/preview, account/history views.
- [ ] Hook addon load ordering and /coaseason; ordinary users never see admin controls without server confirmation.
- [ ] Commit focused Lua validation.

## Task 5: Review, operations and GitHub tracking

Files: modules/mod-coa-season-progression/README.md, spec/plan updates.
- [ ] Run focused source checks; inspect a fresh Gemini review and address important findings.
- [ ] Document migration, enable/disable, addon install, acceptance sequence, rollback and remaining runtime gates.
- [ ] Verify no secrets, extracted proprietary client assets or unrelated work are staged.
- [ ] Push feature branch to user's fork; update issue 1 with actual completed work and explicit unrun acceptance checks.
- [ ] Report source implementation status separately from build/deployment and in-game verification.
