# CoA season progression

This module adds an account-wide season economy and an original Lua companion addon
that adapts Ascension's existing Seasonal Collection window. It does not redistribute
Ascension's client files or alter the client binaries.

The feature is disabled by default. A source commit is not evidence of a successful
worldserver build or an in-game acceptance test.

## Gameplay

- Quests, levels, elite/rare kills and bosses earn Season Progress.
- Seven configurable tiers award Seasonal Points once per account and season.
- Elite, rare and rare-elite entries use a configurable account-wide rolling lockout
  (24 hours by default). Bosses remain repeatable.
- Level rewards use a persistent character high-water mark; lowering a character's
  level and raising it again does not generate more currency.
- Human accounts participate; bot-controlled sessions cannot earn their own currency.
- Bazaar Tokens remain item **975001**, separate from the Seasonal Point balance.
- Existing Bazaar quest/ordinary-mob token grants are suppressed while this module
  owns the economy, preventing double rewards.

A new season starts with zero progress and zero Seasonal Points. Archived season
history, permanent collection ownership, already delivered items and Bazaar Tokens
remain intact. Normal quest/drop/crafted items retain their normal acquisition paths.

## Addon

The source folder is:

```text
addon/CoA_SeasonProgression/
```

For deployment, copy that whole folder into the client's `Interface/AddOns/`
directory. The actual Ascension Seasonal Collection addon must be available in the
client. Restart the client after installing a new addon folder.

- `/coaseason` opens the existing Ascension seasonal window.
- `/coaseason admin` opens administration for a server-confirmed GM level 3 account.
- The player window shows the server's balance, tiers, catalog and unlock action.
- Existing Ascension rendering handles known appearance previews. Item/vanity rewards
  use its item preview machinery. An unknown client appearance reports that its
  preview is unavailable instead of inventing a model.
- Addon messages are hidden self-whispers. Client balances, costs and GM visibility
  never authorize a server-side grant.

The administration tabs are **Season**, **Economy**, **Rewards**, **Accounts** and
**History**. Create a draft with defaults or copy a selected season, browse/search
server-known rewards, preview a selection, and set its price and tier requirement.
Normal equipment is not imported into the reward catalog automatically.

Each Economy row has its own Save button. The tier rows save threshold and payout
together. Discard restores the values last received from the server. Reset to Defaults
restores the selected season's economy/tier defaults; read the warning before changing
an active season. Increase a token range's maximum before raising its minimum above
the old maximum. Server validation rejects invalid ranges and tier ordering.

Starting a draft season requires typing **RESET SEASON**. It archives the outgoing
season and activates the draft; it does not revoke purchases.

## Deployment gate

Follow the repository's build and database-updater instructions. Do not import a
pending migration manually and then run it again through another migration path.

1. Review and build the feature branch with the season and Ascension compatibility
   modules included. The module is intended for this CoA fork.
2. Back up the realm databases through the existing operational backup procedure.
3. Let the normal character-database updater apply the new pending season migration.
   Verify both the schema and the recorded migration entry.
4. Install the companion addon.
5. Before enabling the new economy, configure:
   ```ini
   AscensionCompat.UnlockAllVanity = 0
   AscensionCompat.UnlockLocalAppearanceCatalog = 0
   CoASeason.Enable = 1
   ```
6. Preserve all existing permanent ownership rows. Do not clear collections to make
   the test account look fresh; use a new human test account.
7. Run the acceptance checks below before treating this as ready for normal play.

The initial catalog must be curated. Add former store/cosmetic rewards deliberately;
do not bulk-import normal gameplay loot.

## Focused checks

Run the original Lua implementation with the LuaJIT interpreter:

```sh
luajit modules/mod-coa-season-progression/tests/test_protocol.lua
luajit modules/mod-coa-season-progression/tests/test_season_ui.lua
luajit modules/mod-coa-season-progression/tests/test_admin_ui.lua
```

The standalone C++ test source documents its compile command and checks tier
accounting, numeric overflow, lockouts and request parsing without starting a realm.
Those helper tests do not validate C++ integration with the full server.

Run repository C++/SQL style checks on changed files only, then perform a full server
build and the following runtime checks when authorized.

## In-game acceptance

Use one GM and a separate non-GM human account in a disposable test season:

- Earn quest and level progress; verify level token amounts and persistence on relog.
- Earn progress with two characters on one account and verify the shared balance.
- Kill the same elite/rare entry twice inside the lockout: only the first counts.
- Farm a dungeon boss twice; verify both awards. Repeat with a pet/bot killing blow
  and a nearby entitled human player. Bot accounts must remain ineligible.
- Cross multiple tier thresholds in one event and verify each is paid exactly once.
- Buy an appearance, vanity reward and physical item; retry the same request and
  verify it cannot duplicate a purchase. Test full bags and relog persistence.
- Open the original seasonal window and inspect item, set, mount/creature, illusion
  and spell-visual examples present in the client's own catalog.
- Send a forged admin request from the non-GM account; confirm no mutation occurs.
- Edit activity rates and thresholds live, including a lowered threshold. Check the
  audit history and verify already-completed tiers are never paid twice.
- Activate another draft. Verify progress/points/tier visuals reset, while purchased
  ownership, delivered items and Bazaar Tokens survive.
- Test a stale purchase, incomplete catalog reply and disconnect during a purchase.
  No partial catalog should become actionable and no uncommitted success should appear.

A passing Lua harness or source linter does not replace these checks.

## Rollback

Disable `CoASeason.Enable` and use the known-good server/client deployment if
necessary. Keep all module tables and permanent collection rows. Disabling the module
stops new seasonal operations; do not delete historical purchases or earned items.
The legacy Bazaar income path resumes when the new economy is disabled.
