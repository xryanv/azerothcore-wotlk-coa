# CoA Seasonal Progression and Bazaar Economy Design

Date: 2026-09-21
Status: Revised after in-client acceptance review; pending user review
Target: `jealous-sound/azerothcore-wotlk-coa` forked as `xryanv/azerothcore-wotlk-coa`

## 1. Purpose

Restore a gameplay-earned seasonal progression system for the local Conquest of Azeroth realm without automatically granting the former cash-shop catalog.

The final design has one seasonal progression track and one spendable shop currency:

1. **Season Points** — account-wide, cumulative seasonal progress. They are earned through normal play, are never spent, unlock the seven season tiers, and reset to zero when a new season starts.
2. **Bazaar Tokens (item 975001)** — the existing Ethereal Bazaar currency. Tokens are earned from leveling and boss farming, are spent on additional former shop/vanity items, and never reset on season rollover.

Each season tier has exactly **one automatic reward** chosen by a GM. Reaching the tier threshold grants that reward permanently. There is no second Seasonal Point shop.

Normal World of Warcraft acquisition remains authoritative. Quest rewards, world drops, dungeon/raid gear, crafted items, and other normally obtainable items stay obtainable through their normal sources and are not automatically added to the season system.

## 2. Design principles

- Reuse Ascension's existing Seasonal Collection and Collections/vanity browsing experience rather than replace it.
- Keep Season Points cumulative and non-spendable; Bazaar Tokens are the only shop currency introduced by this system.
- Keep all progression, reward granting, and GM authorization server-authoritative.
- Make progression values, tier thresholds, Bazaar Token values, and tier reward assignments editable live by GM accounts.
- Keep permanent ownership separate from seasonal state so rollover can never remove earned cosmetics/items.
- Avoid overlapping custom windows with Ascension's existing UI; use the native frames for reward browsing and preview whenever possible.

## 3. Existing assets to reuse

The client already contains the original seasonal presentation code and related data:

- `Interface/AddOns/Ascension_SeasonCollection/`
- `SeasonCollectionUI.xml`
- `SeasonCollectionMixin.lua`
- `SeasonProgressBarMixin.lua`
- `SeasonRewardMixin.lua`
- `SeasonalAppearances.dbc`
- `Appearances.dbc`
- `VanityCollection.dbc`

`SeasonRewardMixin` already previews individual items, complete item sets, creatures/mount-style appearances, weapon illusions, static spell visuals, and animated spell visuals. That renderer remains the preferred preview path.

The existing tier circles are real `SeasonTierMixin` buttons and can be adapted for GM editing without replacing the seven-node progress bar.

The stock reward renderer already calls `C_Appearance.GetAppearanceDisplayInfo(appearanceID)`, and the client exposes native collection/store opening behavior such as `OpenStoreCollectionToCategory(...)`. The companion addon should use those native interfaces for reward selection rather than recreating an item browser.

The current CoA server already uses hidden `CHAT_MSG_ADDON` self-whispers successfully for custom client/server synchronization. The season system uses the same bounded transport.

## 4. Components

### 4.1 Server module

`modules/mod-coa-season-progression/` owns active-season state, account-wide Season Points, tier completion/grants, anti-farm tracking, Bazaar Token earning rules, GM mutations, audit history, and client synchronization.

### 4.2 Client companion addon

`CoA_SeasonProgression` adapts Ascension's existing Seasonal Collection frame. It supplies server-authoritative season state, threshold values, tier reward assignments, completion state, and GM edit behavior while retaining Ascension's artwork, tier bar, animations, and preview model code.

### 4.3 GM administration UI

GM level 3 accounts receive a compact Season Admin frame for season lifecycle, economy/progression settings, account diagnostics, and history. Reward browsing is deliberately removed from this custom frame and moved into Ascension's native collection UI.

The server authorizes every admin mutation. Client-side visibility is never treated as authorization.

## 5. Season Points progression model

Season Points are an account-wide integer scoped to the active season. All human-controlled characters on the same account contribute to the same total.

Default earning values:

| Activity | Season Points |
| --- | ---: |
| Complete quest | 3 |
| Gain a level | 10 |
| Elite kill | 1 |
| Rare kill | 2 |
| Rare elite kill | 3 |
| Dungeon boss | 12 |
| Heroic dungeon boss | 18 |
| Raid boss | 30 |
| World boss | 40 |

All values are per-season settings editable from the GM UI. Changes affect future awards only; previously earned Season Points are not recalculated.

Season Points are cumulative. Unlocking Tier 2 at 250 points does not subtract 250; the account continues toward Tier 3 from the same cumulative total.

### 5.1 Elite/rare anti-farm rule

Elite, rare, and rare-elite Season Points are awarded only once per creature entry, per account, during a configurable lockout window. The default lockout is a rolling 24 hours and is GM-configurable.

Dungeon, heroic, raid, and world bosses remain repeatable. Boss farming is intentionally supported.

### 5.2 Human-player eligibility

Playerbot-controlled characters must not earn Season Points or Bazaar Token level rewards. Only human-controlled sessions participate in the economy.

Level rewards are ledgered per character and attained level so delevel/relevel manipulation cannot repeatedly produce rewards.

## 6. Seven-tier season track

Reuse Ascension's seven-node seasonal presentation. The server supplies the authoritative cumulative thresholds and completion state rather than relying on the client's old hard-coded achievement criteria.

The initial implementation uses one seven-tier track per active season. The old four-chapter timed achievement schedule is bypassed for authoritative progression.

Default thresholds:

| Tier | Cumulative Season Points |
| ---: | ---: |
| 1 | 100 |
| 2 | 250 |
| 3 | 500 |
| 4 | 900 |
| 5 | 1,400 |
| 6 | 2,100 |
| 7 | 3,000 |

Each tier has exactly one GM-assigned reward. Crossing a threshold performs two durable actions exactly once for that account and season:

1. record the tier as completed;
2. grant the tier's assigned permanent reward.

Crossing several thresholds in one award grants every newly completed tier in order exactly once.

Thresholds are editable from the GM UI and must remain strictly increasing. If a GM lowers an active threshold below an account's current Season Points, the server immediately evaluates newly satisfied tiers and grants their rewards once. Raising a threshold never revokes an already completed tier or reward.

## 7. Tier rewards and permanent ownership

There is no Seasonal Point purchase catalog.

Each tier reward assignment contains:

- season id;
- tier number 1-7;
- reward type;
- permanent grant target id;
- client preview/appearance id when applicable;
- item quantity when the reward is a physical item;
- display name/metadata needed for the UI.

Exactly one reward assignment exists per tier. A draft may temporarily have unassigned tiers while it is being edited, but activation is rejected until all seven tiers have valid reward assignments. Reassigning a reward changes what future accounts receive from that tier; it never revokes or replaces rewards already granted to accounts that completed the tier.

Appearance and vanity rewards write through the existing permanent account collection mechanisms used by `mod-ascension-compat`. Those ownership records are not season-scoped and survive every rollover.

Physical item rewards are delivered to the character whose action completed the tier, using durable inventory/mail delivery. Once delivered, they behave as normal items and are never removed by season reset.

The server maintains a per-account/per-season/per-tier grant ledger so retries, reconnects, lowered thresholds, and duplicate events cannot grant the same tier reward twice.

## 8. Bazaar Token economy

Bazaar Tokens remain inventory item `975001` and are the only spendable shop currency managed by this design.

Default earning rules:

| Activity | Bazaar Tokens |
| --- | ---: |
| Gain a level | 2 |
| Dungeon boss | 1-3 |
| Heroic dungeon boss | 2-4 |
| Raid boss | 4-8 |
| World boss | 8-15 |

Token ranges and boss drop chances are editable from the GM UI. Season rollover never removes Bazaar Tokens.

Eligible boss kills may place Bazaar Tokens into normal boss loot when the core's playerbot loot semantics are safe. If bots can reserve or consume the reward incorrectly, direct durable delivery to eligible human participants is allowed while preserving the same farming rules.

The existing Ethereal Bazaar remains the place to spend Bazaar Tokens on additional cosmetics, former shop items, heirlooms, and vanity rewards. This avoids maintaining a second seasonal shop.

## 9. Boss classification

Centralize classification in one helper so Season Points and Bazaar Token rewards agree on boss type.

Use authoritative map/difficulty/encounter data first, with creature rank as a fallback:

- world boss: `CREATURE_ELITE_WORLDBOSS` or configured override;
- raid boss: boss/encounter creature in a raid map;
- heroic dungeon boss: boss/encounter creature in heroic dungeon difficulty;
- dungeon boss: boss/encounter creature in a dungeon map;
- rare elite / rare / elite: creature-template rank.

## 10. Player Seasonal Collection UI

The ordinary player experience stays inside Ascension's existing `SeasonCollectionFrame`.

The companion addon supplies:

- active season name/status;
- current cumulative Season Points;
- seven thresholds;
- completed/locked tier state;
- the one assigned reward for each tier;
- permanent ownership/grant status.

The seven tier circles remain the primary progression affordance. Selecting or hovering a tier shows its assigned reward through Ascension's existing reward/model renderer.

There is no purchase button or Seasonal Point balance-to-spend. For a locked tier the UI communicates the required cumulative Season Points. For a completed tier it communicates that the reward has been earned/granted.

The addon must clear stale native reward state when changing tiers/seasons so old previews, buttons, or collection data cannot overlap the current tier.

## 11. GM tier-reward assignment flow

Reward assignment is performed from the native Ascension UI, not from a custom text catalog.

For a server-confirmed GM viewing a draft or editable season:

1. enter **GM Tier Edit Mode** from the season window;
2. click one of the seven tier circles;
3. the addon records the selected tier and opens Ascension's native collection/store browser;
4. the GM browses/searches normally and uses Ascension's native preview experience to inspect the reward;
5. while an eligible collection entry is selected, the addon adds one compact action such as **Assign to Tier 4**;
6. pressing that action sends the selected grant/preview metadata to the server;
7. the server validates GM security and reward validity, saves the one-to-one tier assignment, increments the season revision, and invalidates clients;
8. returning to the season window immediately shows the assigned reward on that tier.

The native collection browser remains responsible for category navigation, search, appearance/model preview, and collection presentation. The companion addon should add only the minimum selection/assignment affordance needed to capture the chosen reward.

When GM Tier Edit Mode is not active, Ascension's collection UI behaves normally.

If a reward type cannot be represented by the native collection browser, a narrow fallback "assign by validated ID" control may exist in the GM admin frame, but it is secondary and should not become a second full reward browser.

## 12. GM Season Admin UI

The custom Season Admin frame contains four responsibilities:

1. **Season** — create draft, select season, copy previous settings, activate/archive, and confirm rollover.
2. **Economy** — edit activity Season Point awards, Bazaar Token level/boss values and chances, elite/rare lockout, and seven tier thresholds.
3. **Accounts** — inspect account Season Points/tier completion and perform explicit GM test adjustments with an audit reason.
4. **History** — inspect rollover, settings changes, tier-reward assignments, tier grants, and GM adjustments.

The old custom **Rewards** browser/tab is removed.

To prevent the graphical overlap seen during acceptance testing, opening the standalone Season Admin configuration frame hides/closes the large native season frame. Choosing **Edit Tier Rewards** closes/hides the admin configuration frame and returns to the native season frame in GM Tier Edit Mode. The two large management surfaces should not be displayed over one another.

The UI provides Save, Discard Changes, Reset to Defaults, and Copy Previous Season Settings where applicable. Invalid min/max token ranges, negative values, non-increasing tier thresholds, and attempts to activate a season without all seven tier rewards are rejected both client-side and server-side.

## 13. Client/server transport

Use the existing hidden addon-message self-whisper pattern.

Logical message families are reduced to:

- `COA_SEASON_STATE` — season metadata, cumulative Season Points, tier completion, tier assignments, admin flag;
- `COA_SEASON_ADMIN` — authenticated GM read/write requests, including threshold changes and tier reward assignment;
- `COA_SEASON_RESULT` — mutation result, invalidation, and refreshed state.

There is no player `PURCHASE` request and no season-shop catalog synchronization.

Payloads remain versioned, bounded below the chat packet limit, and idempotent for durable GM mutations. No client-supplied progress, ownership, reward validity, or GM status is trusted.

## 14. Season rollover semantics

Starting a new season requires typed GM confirmation such as `RESET SEASON`.

Rollover performs one serialized server operation:

- archive the outgoing season;
- activate the incoming season;
- reset every account's active Season Points to 0;
- clear active tier-completion/grant state for the new season;
- clear elite/rare lockout state for the new season;
- preserve all permanent collections and previously delivered items;
- preserve Bazaar Tokens and unrelated currencies;
- preserve archived season/tier/grant history;
- write a rollover audit record.

Previously earned cosmetics, appearances, mounts, pets, vanity rewards, heirlooms, and physical items remain owned permanently.

## 15. Persistence model

Use module-owned tables rather than arena-season tables.

Logical tables:

- `coa_season` — season metadata/status/timestamps;
- `coa_season_settings` — per-season Season Point and Bazaar economy settings;
- `coa_season_tier` — seven strictly ordered threshold rows per season;
- `coa_season_tier_reward` — exactly one reward assignment per `(season, tier)`;
- `coa_season_account` — account cumulative Season Points and current completed tier state;
- `coa_season_tier_grant` — immutable per-account/per-season/per-tier completion/grant ledger;
- `coa_season_daily_kill` — account/creature-entry anti-farm tracking;
- `coa_season_level_reward` — per-character/per-level Bazaar reward ledger;
- `coa_season_audit` — GM/config/rollover/grant history.

The previously designed spendable-point purchase catalog and purchase ledger are removed from the target schema.

The current feature branch contains an earlier in-progress schema implementing spendable Seasonal Points. It has only been exercised against an isolated cloned test database, not the live realm. The implementation revision must replace that pending schema before live deployment and rebuild the isolated test clone from the pre-season backup before runtime acceptance is repeated.

## 16. Security and consistency

- Every admin mutation checks the authenticated session's server-side GM level.
- Every tier completion re-reads authoritative season, threshold, assignment, account state, and permanent ownership before grant.
- Tier completion plus durable reward grant bookkeeping is transactional where multiple writes must remain consistent.
- Rollover is serialized against progress/tier mutations.
- Durable requests use request ids for idempotent retry.
- Malformed or oversized addon payloads are rejected without mutation.
- Playerbots cannot create Season Points, tier grants, or Bazaar Token level rewards.
- A draft tier assignment is visible/editable to authorized GMs; ordinary players receive only the active season.

## 17. Live configuration behavior

All activity values, thresholds, token values, and tier assignments are database-backed and update live without restarting worldserver.

Changing an activity value affects future awards only.

Lowering a threshold can immediately complete the tier for accounts already above it; those rewards are granted exactly once.

Changing a tier reward affects future tier completions only. Accounts that already completed that tier keep the reward they previously received and are not retroactively given the replacement.

## 18. Initial realm migration

Before enabling the final system on the live realm:

1. set `AscensionCompat.UnlockAllVanity = 0`;
2. set `AscensionCompat.UnlockLocalAppearanceCatalog = 0`;
3. preserve all genuine permanent ownership records;
4. create Season 1 with the approved default progression/Bazaar settings;
5. assign one curated reward to each of the seven season tiers using the GM native-browser workflow;
6. keep the existing Ethereal Bazaar and item `975001` intact;
7. verify additional former shop/vanity items remain available through Bazaar configuration rather than a second Seasonal Point shop;
8. verify normal quest/drop/crafting acquisition remains unchanged.

## 19. Testing strategy

### Server coverage

- account-wide Season Points shared across characters;
- exact point awards for quest, level, elite, rare, rare elite, dungeon, heroic, raid, and world-boss events;
- elite/rare once-per-account/per-entry lockout;
- repeatable boss progression;
- playerbot exclusion;
- level reward idempotency;
- crossing one or multiple tier thresholds;
- exactly one reward assignment per tier;
- tier completion and reward grant exactly once;
- permanent ownership survives relog and rollover;
- physical-item delivery survives disconnect/retry;
- Bazaar Token quantity bounds and boss classification;
- live threshold/settings changes;
- rollover resets Season Points/tier state but preserves permanent rewards/Bazaar Tokens;
- GM authorization and malformed addon-message rejection.

### Client validation

- existing Ascension seasonal frame opens without Lua errors;
- no overlap between standalone Season Admin and the native season frame;
- seven tier circles reflect server thresholds/completion and no longer display obsolete point-payout/purchase semantics;
- selecting a tier shows its one assigned reward through the native renderer;
- GM Tier Edit Mode makes tier circles editable without changing normal player behavior;
- clicking a tier opens the native Ascension collection browser;
- item/set/creature/mount/illusion/spell-visual previews remain native;
- **Assign to Tier N** saves and immediately refreshes the tier reward;
- no custom reward list is required for normal assignment;
- non-GM accounts cannot invoke tier assignment even with crafted addon messages.

### Full-stack acceptance

On an isolated clone, run a complete draft and active season with a GM and non-GM account. Assign all seven rewards through the native browser, earn Season Points through several event types, cross multiple tiers, verify permanent grants, farm/spend Bazaar Tokens, relog, and roll to a new season. Confirm Season Points reset while all earned tier rewards and Bazaar Tokens survive.

## 20. Deployment and rollback

Ship disabled by default until the revised schema, server hooks, native UI adaptation, and full-stack acceptance pass.

Recommended revised rollout order:

1. replace the pending spendable-point schema with cumulative Season Points + one reward per tier;
2. refactor server progression/tier-grant logic and remove season purchase handling;
3. simplify client protocol/state by removing purchase/catalog paths;
4. clean up the native season frame integration and stale visual state;
5. implement GM Tier Edit Mode and native collection-browser assignment;
6. simplify the standalone admin window to Season/Economy/Accounts/History;
7. rebuild and repeat isolated full-stack acceptance;
8. only then prepare live migration/config deployment.

Rollback remains non-destructive: disabling the module stops new progression/grants while leaving permanent collection records untouched. The global unlock flags may be temporarily re-enabled for diagnosis without deleting season history.

## 21. Alternatives considered

### Keep a spendable Seasonal Point shop plus Bazaar

Rejected after in-client review. It duplicates shop responsibilities, requires two reward catalogs/economies, complicates the GM workflow, and creates UI overlap without improving the desired gameplay loop.

### Keep the custom text/list reward browser

Rejected as the main reward editor. It technically works but loses the polished Ascension browsing and preview experience and produced unnecessary graphical overlap during acceptance testing.

### Rewrite `SeasonalAppearances.dbc` every season

Rejected because routine reward changes would require repatching client data.

### Selected: cumulative Season Points + native tier assignment

Season Points are progression only. Each tier grants one permanent reward. Bazaar Tokens buy everything else. GMs assign tier rewards by clicking the existing tier circles and selecting through Ascension's native collection/preview UI.

## 22. Success criteria

The design is complete when a GM can create/configure a season, tune Season Point/Bazaar values, click any tier circle, browse and preview rewards in Ascension's native collection UI, and assign exactly one permanent reward to that tier; a normal human account can earn cumulative Season Points, automatically receive each tier reward exactly once, earn/spend Bazaar Tokens for additional items, and then enter a new season with Season Points reset while every previously earned reward and Bazaar Token remains intact.

## 23. Revision note

This revision supersedes the earlier spendable Seasonal Point purchase model already partially implemented on the feature branch. The isolated runtime test proved the server migration, GM bootstrap, addon transport, and native season-frame integration are viable, but also exposed graphical overlap and confirmed that reward selection belongs in Ascension's native browser. The next implementation plan must explicitly remove the superseded purchase/catalog behavior rather than layering the new design on top of it.
