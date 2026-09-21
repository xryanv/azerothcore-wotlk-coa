# CoA Seasonal Progression and Bazaar Economy Design

Date: 2026-09-21
Status: Revised after native-tab/admin-mode clarification; pending user review
Target: `jealous-sound/azerothcore-wotlk-coa` forked as `xryanv/azerothcore-wotlk-coa`

## 1. Purpose

Restore a gameplay-earned seasonal progression system for the local Conquest of Azeroth realm without automatically granting the former cash-shop catalog.

The final design has one seasonal progression track and one spendable shop currency:

1. **Season Points** — account-wide, cumulative seasonal progress. They are earned through normal play, are never spent, unlock the seven season tiers, and reset to zero when a new season starts.
2. **Bazaar Tokens (item 975001)** — the existing Ethereal Bazaar currency. Tokens are earned from leveling and boss farming, are spent on additional former shop/vanity items, and never reset on season rollover.

Each season tier has exactly **one automatic reward** chosen by a GM. Reaching the tier threshold grants that reward permanently. There is no second Seasonal Point shop.

Normal World of Warcraft acquisition remains authoritative. Quest rewards, world drops, dungeon/raid gear, crafted items, and other normally obtainable items stay obtainable through their normal sources and are not automatically added to the season system.

## 2. Design principles

- Keep `CoA_SeasonProgression` as a separate companion addon that extends Ascension at runtime rather than patching or replacing Ascension's shipped addon files.
- Register Season as a first-class tab inside Ascension's normal Collections window so ordinary players experience it alongside Vanity, Wardrobe, Trees, and other existing Ascension tabs.
- Give GMs the same player-facing Season tab plus additional GM-only controls; do not create a different player experience for GM accounts.
- Keep the ordinary Ascension Wardrobe/Vanity browsers unchanged for normal players. Administrative reward selection must use a separate GM-only editing surface.
- Reuse Ascension's existing preview/model/data components inside the GM picker where practical rather than rebuilding rendering from scratch.
- Keep Season Points cumulative and non-spendable; Bazaar Tokens are the only shop currency introduced by this system.
- Keep all progression, reward granting, and GM authorization server-authoritative.
- Make progression values, tier thresholds, Bazaar Token values, and tier reward assignments editable live by GM accounts.
- Keep permanent ownership separate from seasonal state so rollover can never remove earned cosmetics/items.
- Avoid graphical overlap by integrating the player Season page through Ascension's tab system and keeping GM management surfaces compact and explicit.

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

The existing tier circles are real `SeasonTierMixin` buttons. For ordinary players they remain progression selectors; for a server-confirmed GM they may additionally launch the dedicated GM Reward Picker without replacing the seven-node progress bar.

The stock reward renderer already calls `C_Appearance.GetAppearanceDisplayInfo(appearanceID)`, and the client exposes appearance/vanity data and preview APIs. The GM Reward Picker should reuse those data and rendering components where practical, while leaving Ascension's normal player Wardrobe/Vanity browser behavior untouched.

The current CoA server already uses hidden `CHAT_MSG_ADDON` self-whispers successfully for custom client/server synchronization. The season system uses the same bounded transport.

## 4. Components

### 4.1 Server module

`modules/mod-coa-season-progression/` owns active-season state, account-wide Season Points, tier completion/grants, anti-farm tracking, Bazaar Token earning rules, GM mutations, audit history, and client synchronization.

### 4.2 Client companion addon

`CoA_SeasonProgression` remains a separate addon from Ascension's shipped addons. It registers a **Season** tab into Ascension's normal Collections window and supplies server-authoritative season state, thresholds, tier reward assignments, completion state, and previews while retaining Ascension's overall Collections shell and visual language.

For a normal account, the addon exposes only the player-facing Season tab. It must not alter the behavior of Ascension's ordinary Wardrobe, Vanity, Store, or other collection pages.

### 4.3 GM extensions

A server-confirmed GM level 3 sees the exact same player-facing Season tab plus a small set of additional controls such as **Season Admin** and **Edit Tier Rewards**. These controls are absent for ordinary players.

The GM administration frame owns season lifecycle, progression/economy settings, account diagnostics, and history. Tier-reward selection uses a dedicated GM-only reward picker owned by `CoA_SeasonProgression`. The picker may reuse Ascension's model renderer, item/appearance/vanity data APIs, search/filter concepts, and visual assets, but it must not convert Ascension's normal player Wardrobe or Vanity pages into administrative editors.

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

## 10. Player Season tab inside Ascension Collections

The ordinary player experience is a first-class **Season** tab inside Ascension's existing Collections window, alongside the player's normal Ascension tabs such as Vanity, Wardrobe, Trees, and related collection pages.

Season is registered through the same Ascension tab/navigation mechanism used by the existing Collections/Character Advancement pages, so opening Ascension normally (for example with its existing `N` key behavior) exposes Season alongside the other tabs.

An optional `/coaseason` shortcut may remain as convenience behavior for macros, action-bar bindings, debugging, or direct navigation; it simply opens Ascension and selects the Season tab. It is not required for ordinary access.

The Season tab supplies:

- active season name/status;
- current cumulative Season Points;
- seven thresholds;
- completed/locked tier state;
- the one assigned reward for each tier;
- permanent ownership/grant status;
- native-style reward preview for the selected tier.

The seven tier circles remain the primary progression affordance. Selecting or hovering a tier shows its assigned reward and required cumulative points. Completed tiers show that the reward has been earned/granted.

There is no purchase button or Seasonal Point balance-to-spend.

For ordinary players, the Season tab contains **no GM controls** and never changes the behavior of Ascension's normal Wardrobe, Vanity, Store, Trees, or other tabs.

The companion addon must clear stale reward state when changing tiers/seasons so old previews, buttons, or collection data cannot overlap the current tier.

## 11. GM-only reward assignment flow

GM reward assignment is an extension layered on top of the same Season tab, not a modification of the ordinary player collection browser.

For a server-confirmed GM viewing an editable season:

1. the Season tab shows the normal player view plus **Edit Tier Rewards** and **Season Admin**;
2. selecting **Edit Tier Rewards** arms GM edit mode without changing normal player tabs;
3. the GM clicks one of the seven tier circles;
4. `CoA_SeasonProgression` opens a dedicated **GM Reward Picker** for that tier;
5. the picker lets the GM browse/search eligible appearances, vanity rewards, and supported items using Ascension data sources and preview/rendering components;
6. selecting an entry updates the preview but does not immediately save it;
7. the picker shows an explicit action such as **Assign This Reward to Tier 4** plus **Cancel**;
8. pressing Assign sends the selected grant/preview metadata to the server;
9. the server validates GM security, season revision, tier number, reward type/id, and one-reward-per-tier rules, then saves the assignment and invalidates clients;
10. the Season tab refreshes and immediately shows the newly assigned reward on that tier.

The GM picker is available only while the server-authoritative state says the account is an eligible GM **and** session-local admin mode is enabled. Closing it returns to the normal Season tab while preserving the current admin-mode setting.

The normal Ascension Wardrobe/Vanity/Store pages remain unchanged and usable as ordinary player interfaces even on a GM account, including while admin mode is enabled. The season addon must not globally hook a normal collection click so that it silently becomes an admin assignment.

For physical item rewards that do not exist in Ascension's collection datasets, the GM picker may expose a narrow validated item-ID fallback within the same GM-only surface. This is not a second shop or a general text catalog.

## 12. GM Season Admin UI

The compact Season Admin frame contains four responsibilities:

1. **Season** — create draft, select season, copy previous settings, activate/archive, and confirm rollover.
2. **Economy** — edit activity Season Point awards, Bazaar Token level/boss values and chances, elite/rare lockout, and seven tier thresholds.
3. **Accounts** — inspect account Season Points/tier completion and perform explicit GM test adjustments with an audit reason.
4. **History** — inspect rollover, settings changes, tier-reward assignments, tier grants, and GM adjustments.

The old custom **Rewards** browser/tab remains removed. Reward selection belongs only to the dedicated GM Reward Picker launched from the Season tab.

Opening Season Admin does not replace the player-facing Season experience. The Season tab may remain visible behind or beside the compact admin frame so a GM can compare configuration with what players see. The admin frame must be sized/positioned so it does not obscure or corrupt the Collections tab strip or tier presentation.

GM editing is controlled by a separate session-local admin mode. `/coaseason admin` toggles that mode, while `/coaseason admin on` and `/coaseason admin off` provide deterministic forms suitable for macros/testing. The mode may reveal GM-only controls only after the server has confirmed GM level 3. On a non-GM account these commands cannot enable privileged controls or authorize mutations.

Admin mode does not replace or reopen the Ascension window by itself. When Ascension is opened normally, the Season tab reflects the current admin-mode state: ordinary view when off; ordinary view plus privileged controls when on.

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
5. assign one curated reward to each of the seven season tiers using the dedicated GM Reward Picker;
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

- `CoA_SeasonProgression` remains a separate addon and does not overwrite Ascension's shipped addon files;
- Season appears as a proper tab in the normal Ascension Collections window;
- Season is registered through the same native tab/navigation system as Ascension's existing pages and is reachable through the normal Ascension UI opened with `N`;
- optional `/coaseason` direct-opens Ascension to Season for macros/keybinds without being required for normal use;
- ordinary players see tier progression/rewards but no GM buttons or admin reward picker;
- normal Wardrobe, Vanity, Store, Trees, and other Ascension tabs retain their normal behavior;
- seven tier circles reflect server thresholds/completion and no obsolete point-payout/purchase semantics;
- selecting a tier shows its one assigned reward through the reused/native-style renderer;
- GM accounts see the same player Season tab by default; GM-only controls appear only when server-confirmed admin mode is enabled;
- `/coaseason admin` toggles admin mode and `/coaseason admin on|off` sets it deterministically;
- GM Tier Edit Mode opens the dedicated GM Reward Picker rather than repurposing the normal Wardrobe/Vanity pages;
- selecting a candidate only previews it; **Assign This Reward to Tier N** is an explicit second action;
- successful assignment refreshes the selected tier immediately;
- closing/cancelling the GM picker leaves the ordinary Ascension collection pages unchanged;
- Season Admin can coexist with the Season tab without graphical corruption or hiding the player view;
- non-GM accounts cannot invoke assignment/admin mutations even with crafted addon messages.

### Full-stack acceptance

On an isolated clone, run a complete draft and active season with both a GM and non-GM account. Verify the non-GM Collections window has the Season tab and no privileged controls. On the GM account, assign all seven rewards through the dedicated picker with explicit confirmation, earn Season Points through several event types, cross multiple tiers, verify permanent grants, farm/spend Bazaar Tokens, relog, and roll to a new season. Confirm Season Points reset while all earned tier rewards and Bazaar Tokens survive.

## 20. Deployment and rollback

Ship disabled by default until the revised schema, server hooks, Collections-tab integration, GM-only picker, and full-stack acceptance pass.

Recommended revised rollout order:

1. keep the cumulative Season Points + one reward per tier backend already established;
2. register Season as a first-class tab inside Ascension Collections from the separate `CoA_SeasonProgression` addon;
3. ensure the normal player Season tab contains no privileged controls and does not alter normal Ascension tabs;
4. replace the temporary normal-browser assignment hooks with a dedicated GM Reward Picker using reusable Ascension preview/data components;
5. keep Season Admin compact and able to coexist visually with the player-facing Season tab;
6. rebuild/reload the addon and repeat isolated GM/non-GM full-stack acceptance;
7. only then prepare live migration/config deployment.

Rollback remains non-destructive: disabling the module stops new progression/grants while leaving permanent collection records untouched. The global unlock flags may be temporarily re-enabled for diagnosis without deleting season history.

## 21. Alternatives considered

### Keep a spendable Seasonal Point shop plus Bazaar

Rejected after in-client review. It duplicates shop responsibilities, requires two reward catalogs/economies, complicates the GM workflow, and creates UI overlap without improving the desired gameplay loop.

### Keep the custom text/list reward browser

Rejected as the main reward editor. It technically works but loses the polished Ascension browsing and preview experience.

### Repurpose Ascension's normal Wardrobe/Vanity browser for GM assignment

Rejected after runtime testing. Although it reuses native browsing, it makes the ordinary player browser context-dependent, lacks an obvious explicit confirmation step, and risks admin hooks leaking into normal player behavior.

### Hide Ascension's other Collections tabs when opening Season

Rejected. Players should see Season as one normal tab alongside their existing Vanity, Wardrobe, Trees, and other Ascension pages.

### Rewrite `SeasonalAppearances.dbc` every season

Rejected because routine reward changes would require repatching client data.

### Selected: cumulative Season Points + player Season tab + GM-only extensions

Season Points are progression only. Each tier grants one permanent reward. Bazaar Tokens buy everything else. All players get the same Season tab in Ascension Collections; GM status adds admin controls and a dedicated reward picker without modifying the ordinary player collection pages.

## 22. Success criteria

The design is complete when an ordinary player can open Ascension Collections, select the Season tab, see cumulative progression, all seven tier thresholds, and the reward available at each tier without seeing any GM controls or altered Wardrobe/Vanity behavior; a GM sees that same Season tab plus explicit administrative controls, can open a dedicated preview-capable reward picker, select a candidate and deliberately confirm **Assign This Reward to Tier N**, and can manage season/economy/account/history settings without corrupting the normal Collections UI. The server must still grant each earned tier reward exactly once, preserve permanent ownership/Bazaar Tokens across rollover, and reject all unauthorized mutations.

## 23. Revision note

This revision incorporates the native-tab/admin-mode clarification. Season is now explicitly treated as one more Ascension tab reached through Ascension's normal navigation (including the existing `N` entry point), with `/coaseason` retained only as an optional direct-navigation shortcut. GM privileges are exposed through a separate session-local `/coaseason admin [on|off]` editing mode layered on the same Season tab. It also preserves the earlier in-client GM/player separation clarification. The previous revision correctly simplified the economy to cumulative Season Points and one automatic reward per tier, but its interim plan of repurposing Ascension's ordinary Wardrobe/Vanity pages for GM assignment proved too invasive. The target design now treats Season as a normal player Collections tab provided by the separate `CoA_SeasonProgression` addon, with GM status only adding privileged controls and a dedicated reward-picker surface. Temporary normal-browser assignment hooks are implementation scaffolding to be removed before acceptance.



This revision supersedes the earlier spendable Seasonal Point purchase model already partially implemented on the feature branch. The isolated runtime test proved the server migration, GM bootstrap, addon transport, and native season-frame integration are viable, but also exposed graphical overlap and confirmed that reward selection belongs in Ascension's native browser. The next implementation plan must explicitly remove the superseded purchase/catalog behavior rather than layering the new design on top of it.
