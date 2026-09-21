# CoA season progression

This module adds account-wide seasonal progression and a companion Lua addon that adapts Ascension's existing Seasonal Collection UI. It does not redistribute Ascension client files or modify the client binary.

The feature is disabled by default. Source tests are not a substitute for a successful worldserver build and isolated in-game acceptance run.

## Gameplay

- Quests award **3 Season Points** by default.
- Levels award **10 Season Points**.
- Elite / rare / rare-elite kills award **1 / 2 / 3 Season Points**.
- Dungeon / heroic / raid / world bosses award **12 / 18 / 30 / 40 Season Points**.
- Season Points are account-wide, cumulative progression. They are never spent.
- Seven configurable thresholds each grant exactly one permanent reward when crossed.
- Crossing several thresholds at once grants every newly completed tier exactly once.
- Elite/rare entries use a configurable account-wide rolling lockout (24 hours by default); bosses remain repeatable.
- Level rewards use a persistent character high-water mark, so lowering and re-raising a level cannot repeat the award.
- Bot-controlled sessions cannot earn Season Points, tier rewards, or level-based Bazaar Tokens.

A new season begins at 0 Season Points with no completed tiers. Rollover never removes permanent collection ownership, previously delivered items, or Bazaar Tokens.

## Tier rewards

Each season has seven tier bubbles and exactly one GM-assigned reward per tier. A draft may be incomplete while being edited, but activation is rejected until all seven assignments are valid.

Supported grant types are:

- permanent Ascension appearance;
- permanent Ascension vanity item/mount/pet entry;
- physical item delivered durably by mail when required.

Tier grants are recorded in an immutable `(season, account, tier)` ledger. Reconnects, retries, threshold edits and duplicate gameplay events therefore cannot grant the same tier twice. Reassigning a tier changes what future completions receive and never revokes a reward already granted.

## Bazaar Tokens

Bazaar Tokens remain item **975001** and are the only spendable shop currency in this design.

Default season-owned earning is:

- level: 2 tokens;
- dungeon boss: 1-3;
- heroic dungeon boss: 2-4;
- raid boss: 4-8;
- world boss: 8-15.

Boss chances/ranges are configurable. The older Ethereal Bazaar quest/ordinary-creature token script is suppressed while this season module is active and automatically resumes if the season module is disabled.

## Addon and GM flow

Deploy `addon/CoA_SeasonProgression/` under the client's `Interface/AddOns/` directory. The Ascension Seasonal Collection, Appearance and Vanity collection addons must remain available in the client.

The ordinary player view stays inside Ascension's native season window and shows cumulative Season Points, seven thresholds, completion state and the one reward assigned to each tier. There is no Seasonal Point purchase button or second seasonal shop.

A server-confirmed GM level 3 account can enter **Tier Edit Mode** from the season window, click a tier bubble, browse Ascension's native collection UI with its normal model/item previews, and assign the selected reward to that tier. The companion addon adds only the assignment affordance; Ascension remains responsible for browsing and preview rendering.

The standalone Season Admin frame contains only **Season**, **Economy**, **Accounts** and **History**. It is mutually exclusive with the large native season management surface to prevent frame overlap.

## Deployment gate

1. Build the feature branch with `mod-coa-season-progression` and `mod-ascension-compat` included.
2. Back up realm databases using the normal operational backup procedure.
3. Let the AzerothCore character-database updater apply the pending season migration. Do not manually import it and then run it again through the updater.
4. Install the companion addon.
5. Before enabling the season economy, configure:

   ```ini
   AscensionCompat.UnlockAllVanity = 0
   AscensionCompat.UnlockLocalAppearanceCatalog = 0
   CoASeason.Enable = 1
   ```

6. Preserve all existing permanent ownership rows and Bazaar Tokens.
7. Run the isolated acceptance sequence below before promoting the build to the live realm.

## Focused checks

Lua:

```sh
luajit modules/mod-coa-season-progression/tests/test_protocol.lua
luajit modules/mod-coa-season-progression/tests/test_season_ui.lua
luajit modules/mod-coa-season-progression/tests/test_admin_ui.lua
```

Standalone C++ tests cover cumulative tier accounting, numeric overflow, eligibility/bot policy, settings, lockouts and request parsing. Run repository C++/SQL style checks on changed files and a full server build before runtime acceptance.

## In-game acceptance

Use a GM plus a separate non-GM human account on an isolated database clone:

- create a draft and confirm activation is rejected until all seven tier rewards are assigned;
- assign rewards through native Ascension preview/browse surfaces and confirm no GM-window overlap;
- earn quest and level Season Points and verify account-wide persistence across two characters;
- kill the same elite/rare entry twice inside the lockout and verify only the first awards points;
- repeat eligible boss kills and verify they remain repeatable;
- test a pet/bot killing blow with an entitled nearby human group member; the human may receive credit but bot accounts must remain ineligible;
- cross one and multiple thresholds and verify every tier reward is granted exactly once;
- lower an active threshold and verify newly satisfied accounts are reconciled without re-granting old tiers;
- verify appearance/vanity rewards remain permanently owned and physical rewards survive relog;
- verify Bazaar Token level/boss earning and an existing Bazaar purchase;
- activate a new season and verify Season Points/tier state reset while permanent rewards and Bazaar Tokens remain;
- send forged/non-GM/stale admin requests and confirm no unauthorized mutation occurs.

## Rollback

Disable `CoASeason.Enable` and return to the known-good server/client deployment if required. Keep the season tables and permanent collection rows intact. Disabling the module stops new season operations and restores the legacy Ethereal Bazaar token-income script; it does not revoke earned rewards or delete history.
