# CoA Seasonal Progression and Bazaar Economy Design

Date: 2026-09-21
Status: Approved for final review and implementation by user on 2026-09-21
Target: `jealous-sound/azerothcore-wotlk-coa` forked as `xryanv/azerothcore-wotlk-coa`

## 1. Purpose

Restore a gameplay-earned progression economy for the local Conquest of Azeroth realm without automatically granting the former cash-shop catalog.

The system has two intentionally separate economies:

1. **Season Progress / Seasonal Points** — account-wide seasonal progression shown through Ascension's existing Seasonal Collection UI. Progress resets when a new season starts. Seasonal Points also reset. Purchased/unlocked rewards remain permanent.
2. **Bazaar Tokens (item 975001)** — the existing Ethereal Bazaar currency. Tokens are earned from leveling and boss farming and are never reset by a season rollover.

Normal World of Warcraft acquisition remains authoritative. Quest rewards, world drops, dungeon/raid gear, crafted items, and other normally obtainable items do not appear in a collection until the player obtains them through their normal source.

## 2. Design principles

- Reuse Ascension's existing Seasonal Collection visual experience rather than replace it.
- Keep all economy and authorization decisions server-authoritative.
- Make balance values editable live by GM accounts without recompiling or restarting.
- Keep permanent collections separate from seasonal state so a reset can never remove earned cosmetics/items.
- Preserve the existing Ethereal Bazaar and Bazaar Token item rather than invent a replacement currency.

## 3. Existing assets to reuse

The current client already contains the original seasonal presentation code and related data:

- `Interface/AddOns/Ascension_SeasonCollection/`
- `SeasonCollectionUI.xml`
- `SeasonCollectionMixin.lua`
- `SeasonProgressBarMixin.lua`
- `SeasonRewardMixin.lua`
- `SeasonalAppearances.dbc`
- `VanityCollection.dbc`
- `ChallengeRewards.dbc`, `ChallengeGroupRewards.dbc`, `AchievementRewards.dbc`, and `TutorialRewards.dbc`

`SeasonRewardMixin` already previews individual items, complete item sets, creatures/mount-style appearances, weapon illusions, static spell visuals, and animated spell visuals. That rendering logic should remain intact.

The client also contains legacy custom-point APIs/events for Seasonal Points and Bazaar Tokens, but the reconstructed server does not contain the corresponding public seasonal backend. The new module therefore owns authoritative balances and sends state through the existing addon-message transport rather than modifying `Extensions.dll` or depending on undocumented proprietary packets.

The current CoA server already uses `CHAT_MSG_ADDON` self-whispers successfully for Character Advancement/resource synchronization. The seasonal system will use the same proven transport with bounded/chunked payloads.

## 4. Components

### 4.1 Server module

Add `modules/mod-coa-season-progression/`. It owns season state, progression, currencies, reward catalog, rollover, GM commands/API, audit history, and client synchronization.

### 4.2 Client companion addon

Add a small `CoA_SeasonProgression` addon/patch that integrates with Ascension's existing Seasonal Collection frame. It replaces only the static data-provider/purchase portions while retaining the Ascension artwork, controls, tier bar, animations, and preview model code.

### 4.3 GM administration UI

GM level 3 accounts receive an additional Season Admin frame. The server must authorize every mutation; hiding the frame from non-GMs is convenience only, not security.

## 5. Seasonal progression model

Season Progress is an account-wide integer scoped to the active season. All characters on the same account contribute to the same total.

Default progression values:

| Activity | Season Progress |
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

All values are per-season settings editable from the GM UI. Changes affect future awards only; previously earned progress is not recalculated.

### 5.1 Elite/rare anti-farm rule

Elite, rare, and rare-elite progress is awarded only once per creature entry, per account, during a configurable lockout window. The default lockout is a rolling 24 hours and is GM-configurable.

Dungeon, heroic, raid, and world bosses are intentionally repeatable. Boss farming is a supported progression/currency path.

### 5.2 Human-player eligibility

Playerbot-controlled characters must not earn Season Progress, Seasonal Points, or Bazaar Token level rewards. Only human-controlled player sessions participate in the economy. This prevents the realm's large bot population from creating currency/progress or polluting account state.

Level rewards are ledgered per character and attained level so a character cannot gain rewards repeatedly by delevel/relevel manipulation.

## 6. Seasonal tier curve and point awards

Reuse Ascension's seven-node seasonal progress presentation. The client visual remains a seven-tier bar; the authoritative thresholds and completion state come from the server instead of hard-coded achievement criteria.

The initial implementation uses one active seven-tier track per season. Ascension's hard-coded four-chapter achievement/event schedule is bypassed for progression, while the surrounding Seasonal Collection UI is retained. The schema/protocol should leave room for multiple chapters later without changing permanent ownership or season-reset semantics.

Default thresholds and Seasonal Point rewards:

| Tier | Cumulative Progress | Seasonal Points |
| ---: | ---: | ---: |
| 1 | 100 | 25 |
| 2 | 250 | 40 |
| 3 | 500 | 60 |
| 4 | 900 | 90 |
| 5 | 1,400 | 125 |
| 6 | 2,100 | 175 |
| 7 | 3,000 | 250 |

A completed tier is recorded once for the account/season. Crossing multiple thresholds in one award grants every newly completed tier exactly once.

All thresholds and tier payouts are editable from the GM UI. Validation requires strictly increasing thresholds and non-negative point awards.

If a GM lowers an active threshold below an account's existing progress, the server evaluates newly satisfied tiers and grants their points once. Raising a threshold never revokes a completed tier or already awarded Seasonal Points.

## 7. Seasonal Points wallet

Seasonal Points are account-wide and season-scoped. They are not implemented as normal inventory items.

The server persists current balance, lifetime earned/spent for the season, and a transaction ledger. The client balance shown in the Ascension seasonal frame is populated from the server's synchronized state.

Purchases are atomic: validate season, reward availability, ownership, price, balance, and GM-configured restrictions; debit points; grant permanent unlock/item; write ledger; then send updated state.

## 8. Bazaar Token economy

Bazaar Tokens remain the existing inventory item `975001` and remain separate from Seasonal Points. They use normal item/inventory semantics rather than the account-wide Seasonal Point wallet.

Default earning rules:

| Activity | Bazaar Tokens |
| --- | ---: |
| Gain a level | 2 |
| Dungeon boss | 1-3 |
| Heroic dungeon boss | 2-4 |
| Raid boss | 4-8 |
| World boss | 8-15 |

Token ranges are inclusive random quantities and are editable from the GM UI. Season rollover never removes Bazaar Tokens.

Eligible boss kills add Bazaar Tokens to the boss's loot so the currency can be farmed through normal gameplay. The default drop chance is 100% for an eligible boss, with quantity determined by boss category. Drop chance and min/max quantity are independently configurable.

The implementation must avoid playerbots consuming or reserving the currency in a way that makes it unavailable to the human player. Preferred behavior is a loot entry reserved/eligible for participating human players where the core permits it; if 3.3.5 loot semantics make that unreliable with playerbots, the module may deliver the same configured boss reward directly to eligible human participants while retaining normal boss-farming semantics.

The Ethereal Bazaar continues to use existing ExtendedCost/vendor behavior, including recovered prices such as Bazaar Token item `975001` where present. Bazaar shop prices are independent of seasonal reward prices.

## 9. Boss classification

Centralize classification in one server helper so both Season Progress and Bazaar Token rewards agree on boss type.

Classification should use authoritative map/difficulty/encounter information first, with creature rank as a fallback:

- world boss: `CREATURE_ELITE_WORLDBOSS` or configured override;
- raid boss: boss/encounter creature in a raid map;
- heroic dungeon boss: boss/encounter creature in heroic dungeon difficulty;
- dungeon boss: boss/encounter creature in a dungeon map;
- rare elite / rare / elite: creature template rank.

## 10. Reward catalog and permanent ownership

Each season has a server-side reward catalog. A catalog entry contains at least:

- season id;
- reward id;
- reward type;
- client preview/appearance id when applicable;
- display name/category/order;
- Seasonal Point cost;
- enabled flag;
- optional tier/minimum-progress requirement;
- permanent grant target (appearance collection, vanity collection, spell/mount/pet unlock, or physical item).

Purchasing a cosmetic/appearance writes to the existing permanent account collection used by `mod-ascension-compat`, such as `account_appearance_collection` / `account_vanity_collection` as appropriate. These records are not season-scoped and are never deleted during rollover.

Physical items already delivered remain normal character inventory/bank/mail items. A season reset never deletes previously awarded items. Consumables continue to obey normal item behavior after delivery.

The server rejects purchasing an already-owned permanent cosmetic unless a reward type is explicitly marked repeatable.

Normal gameplay loot is not imported into the seasonal catalog automatically and is not unlocked merely because it exists in the client catalog.

## 11. Ascension Seasonal Collection UI integration

Retain Ascension's existing `SeasonCollectionFrame`, tier visuals, animations, navigation, and `SeasonRewardMixin` preview implementation.

The companion addon replaces the static reward-list/data-provider path with server-synchronized active-season data. It must not require rebuilding `SeasonalAppearances.dbc` whenever a GM changes a season.

For rewards that map to client-known appearance IDs, pass those IDs into the existing preview code. For supported physical-item rewards without a seasonal appearance row, use the same model frame and item-preview primitives so the visual experience remains consistent.

### 11.1 Client/server transport

Use the existing hidden addon-message self-whisper pattern already proven by `mod-ascension-compat`.

Logical message families:

- `COA_SEASON_STATE` — active season metadata, progress, tier completion, Seasonal Point balance, admin flag;
- `COA_SEASON_CATALOG` — chunked reward catalog payload;
- `COA_SEASON_PURCHASE` — client purchase request;
- `COA_SEASON_ADMIN` — authenticated GM read/write requests;
- `COA_SEASON_RESULT` — success/error response and refreshed state.

Payloads must be versioned, bounded below the chat packet limit, chunked when necessary, and tolerant of missing/out-of-order catalog chunks. No client-supplied balance, price, ownership, or GM status is trusted.

## 12. GM Season Admin UI

Only a server-confirmed GM level 3 session may mutate season configuration. The addon should expose these tabs:

1. **Season** — create draft season, name/id, activate/archive, copy previous settings, rollover preview.
2. **Progression & Economy** — edit every activity progress value, Bazaar Token level reward, boss token min/max/chance, elite/rare lockout, and seven tier thresholds/payouts.
3. **Rewards** — search/browse client-known rewards, preview them with Ascension's model viewer, set cost/category/order/requirements, add/remove/enable/disable entries.
4. **Accounts** — inspect account progress/balance and perform explicit GM test adjustments with reason text.
5. **History** — view season rollover, economy changes, reward-catalog changes, purchases, and GM adjustments.

The UI provides Save, Discard Changes, Reset to Defaults, and Copy Previous Season Settings actions. Invalid min/max ranges, negative values, duplicate catalog keys, and non-increasing tier thresholds are rejected before save and again server-side.

Editing an active season is allowed. The UI warns that progression-rate changes affect future awards only. Tier threshold changes show how lowering a threshold can immediately complete tiers for accounts whose stored progress already qualifies.

## 13. Season rollover semantics

Starting a new season is a destructive economy operation and requires a typed confirmation in the GM UI, for example `RESET SEASON`.

Rollover first enters a short server-side economy lock so purchases and season mutations cannot race the transition, then performs one atomic server operation:

- archive the outgoing season;
- create/activate the incoming season;
- reset every account's active Season Progress to 0;
- reset every account's active Seasonal Point balance to 0;
- clear active tier-completion state;
- clear elite/rare daily tracking for the new season;
- preserve all permanent collections and previously delivered items;
- preserve Bazaar Tokens and all unrelated currencies;
- write a complete rollover audit record.

Previously owned cosmetics, appearances, mounts, pets, vanity rewards, heirlooms, and physical items remain owned. Rollover never deletes rows from permanent ownership tables.

The outgoing season's progress, points earned/spent, purchases, and GM adjustments remain queryable in history even though the active balances reset.

## 14. Persistence model

Use explicit module-owned tables rather than overloading unrelated arena-season tables.

Proposed logical tables:

- `coa_season` — season metadata/status/timestamps;
- `coa_season_settings` — per-season progression/economy configuration;
- `coa_season_tier` — seven threshold/payout rows per season;
- `coa_season_account` — account progress, current points, earned/spent totals;
- `coa_season_account_tier` — completed tier ledger;
- `coa_season_reward` — active/archived reward catalog;
- `coa_season_purchase` — immutable purchase/grant ledger;
- `coa_season_daily_kill` — account/creature-entry anti-farm tracking;
- `coa_season_level_reward` — per-character/per-level reward ledger;
- `coa_season_audit` — GM/config/rollover history.

Indexes must cover active season lookups, account+season, daily account+creature entry, reward catalog ordering, and transaction history.

## 15. Security and consistency

- Every admin mutation checks the authenticated session's server-side GM level; client visibility is not authorization.
- Every purchase re-reads authoritative balance, catalog entry, season state, and ownership before commit.
- Rollover, purchases, tier grants, and GM balance adjustments use database transactions where multiple writes must stay consistent.
- Client requests include a protocol version and request id so retries can be made idempotent where practical.
- Malformed/oversized addon payloads are rejected and logged without mutating state.
- A GM may preview/edit a draft season, but players only receive catalog/state for the active season.

## 16. Live configuration behavior

All progression/economy values are stored in database-backed season settings and cached by the module. A successful GM save invalidates/reloads the relevant cache immediately; no worldserver restart is required.

Changing activity reward values affects only future events. Existing progress and transaction history remain unchanged.

Changing a reward's price affects future purchases only. Existing unlocks are never repriced or revoked.

Disabling a reward removes it from new purchase availability but does not remove it from accounts that already own it.

## 17. Initial realm migration

Before enabling the progression economy:

1. set `AscensionCompat.UnlockAllVanity = 0`;
2. set `AscensionCompat.UnlockLocalAppearanceCatalog = 0`;
3. do not delete existing permanent ownership records;
4. create Season 1 with the approved default settings;
5. seed a curated initial seasonal reward catalog from client-known appearances;
6. keep the existing Ethereal Bazaar and item `975001` intact;
7. verify normal quest/drop/crafting acquisition still behaves unchanged.

For the current test account, any cosmetics that were visible only because the two unlock-all flags were enabled should become locked unless a real ownership row exists. Genuine permanent ownership rows remain valid.

## 18. Testing strategy

### Server unit/integration coverage

- account-wide progress shared across characters;
- exact progress values for quest, level, elite, rare, rare elite, dungeon, heroic, raid, and world-boss events;
- elite/rare once-per-account/per-entry rolling-24-hour lockout enforcement;
- repeatable boss progress;
- playerbot exclusion;
- level reward idempotency;
- crossing one or multiple tier thresholds;
- tier reward exactly-once behavior;
- atomic Seasonal Point purchase and insufficient-funds rejection;
- permanent ownership grant and duplicate-purchase rejection;
- Bazaar Token quantity bounds and boss classification;
- live settings reload;
- rollover is serialized against purchases, resets seasonal state, and preserves permanent unlocks/Bazaar Tokens;
- GM authorization and malformed addon-message rejection.

### Client validation

- existing Ascension seasonal frame opens without Lua errors;
- seven-tier progress bar reflects server values and updates live;
- balance updates after tier rewards and purchases;
- reward navigation previews item, set, creature/mount, illusion, and spell-visual examples;
- purchase button reports success/error cleanly;
- GM editor can preview, edit, save, discard, and roll over a test season;
- non-GM accounts cannot invoke admin mutations even with manually crafted addon messages.

### Full-stack acceptance test

Run a fresh test season with a human GM and at least one non-GM test account. Exercise questing, leveling, elite/rare lockout, dungeon boss repeat farming, Bazaar purchase, Seasonal purchase, logout/login persistence, and a complete rollover. Confirm owned cosmetics/items survive while progress and Seasonal Points reset to zero.

## 19. Deployment and rollback

Ship the system disabled by default behind a module/config enable flag until database migrations, server hooks, client addon, and full-stack tests all pass.

Recommended rollout order:

1. database schema and read-only season state;
2. server progression accounting with GM diagnostic commands;
3. client seasonal-state synchronization and existing UI integration;
4. reward purchase/permanent ownership path;
5. Bazaar Token level/boss rewards;
6. GM Season Admin editor;
7. rollover path and destructive-action confirmation;
8. disable global vanity/appearance unlock flags and run acceptance test.

Rollback must be non-destructive: disabling the module stops new progress/purchases but leaves module tables and permanent collection records untouched. The two global unlock-all flags can be temporarily re-enabled for diagnosis without deleting season data.

## 20. Alternatives considered

### Rewrite `SeasonalAppearances.dbc` for every season

Rejected as the primary mechanism. It preserves the stock data path but requires client MPQ/DBC repatching for routine GM reward changes and undermines live administration.

### Build a completely new Seasonal UI

Rejected. It duplicates polished Ascension functionality already present in the client and loses the existing item/set/creature/spell preview experience.

### Selected: dynamic data-provider integration

Keep Ascension's frame and preview implementation while supplying active-season progression, balance, catalog, pricing, and purchase actions from the new server module through a companion addon. This preserves the original look while making seasons server-configurable.

## 21. Success criteria

The design is complete when a GM can create/configure a season in game, choose and preview rewards, tune all progression/token/tier values live, and activate the season; a normal human account can earn shared Season Progress through gameplay, receive tier Seasonal Points, spend them on permanent rewards in the existing Ascension seasonal UI, earn Bazaar Tokens from leveling/boss farming, and then experience a season rollover that resets only seasonal progress/points while preserving all permanent unlocks, physical items, and Bazaar Tokens.
## 22. Implementation review refinements

The implementation plan records the concrete RPC contract, legacy Bazaar grant suppression, durable delivery/commit acknowledgement, account serialization, group human credit, and real frame-instance adaptation. The initial catalog is explicitly curated through the GM editor to avoid importing ordinary gameplay loot. Runtime activation is a separate validation gate; source ships disabled by default.
