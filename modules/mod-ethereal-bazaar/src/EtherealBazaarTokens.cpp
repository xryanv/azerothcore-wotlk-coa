/*
 * Legacy/fallback Bazaar Token income.
 *
 * When CoASeasonState is active, mod-coa-season-progression owns level/boss token earning and this script
 * deliberately returns before granting anything. When the season module is disabled, these historical
 * quest/creature ranges resume so the Bazaar still has a gameplay currency source.
 */

#include "EtherealBazaar.h"

#include "Chat.h"
#include "Configuration/Config.h"
#include "Creature.h"
#include "GameTime.h"
#include "Log.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "Mail.h"
#include "Random.h"
#include "ScriptMgr.h"
#include "SeasonProgressionState.h"

#include <atomic>
#include <memory>

namespace
{
    struct RewardRange
    {
        uint32 Min;
        uint32 Max;
    };

    struct TokenConfig
    {
        bool Enabled = true;
        bool Announce = false;
        uint32 BonusLevel = 60;
        uint32 BonusPercent = 150;
        RewardRange Quest{0, 12};
        RewardRange Creature{0, 3};
        RewardRange DungeonBoss{14, 22};
        RewardRange RaidBoss{41, 53};
    };

    std::atomic<std::shared_ptr<TokenConfig const>> tokenConfig{std::make_shared<TokenConfig>()};

    RewardRange LoadRange(char const* name, RewardRange defaults)
    {
        uint32 const low = sConfigMgr->GetOption<uint32>(
            Acore::StringFormat("EtherealBazaar.Tokens.{}.Min", name), defaults.Min);
        uint32 const high = sConfigMgr->GetOption<uint32>(
            Acore::StringFormat("EtherealBazaar.Tokens.{}.Max", name), defaults.Max);
        return {low, std::max(low, high)};
    }

    uint32 RollAmount(RewardRange const& range)
    {
        return urand(range.Min, range.Max);
    }

    // At 150 a character at the bonus level earns half again as much.
    uint32 ApplyLevelBonus(Player const* player, uint32 amount, TokenConfig const& config)
    {
        if (!amount || player->GetLevel() < config.BonusLevel)
            return amount;
        uint64 const bonus = uint64(amount) * config.BonusPercent / 100;
        return static_cast<uint32>(std::clamp<uint64>(bonus, 1, UINT32_MAX));
    }

    void Grant(Player* player, uint32 amount, char const* grund, TokenConfig const& config)
    {
        if (!player || !amount)
            return;

        amount = ApplyLevelBonus(player, amount, config);
        if (!amount)
            return;

        // A full bag must not swallow the reward. Mail is the only honest
        // fallback: the player keeps what they earned and notices it.
        ItemPosCountVec dest;
        InventoryResult const check =
            player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, BAZAAR_TOKEN_ITEM, amount);
        if (check == EQUIP_ERR_OK)
        {
            Item* item = player->StoreNewItem(dest, BAZAAR_TOKEN_ITEM, true);

            // Der Einsammel-Hinweis oben rechts kommt aus SendNewItem. Bei
            // Tokens faellt er bei jedem zweiten Mob an und wird schnell zum
            // Rauschen; die Tasche aktualisiert sich auch ohne ihn. Wer ihn
            // will, schaltet ihn an.
            if (item && config.Announce)
                player->SendNewItem(item, amount, true, false);
        }
        else if (Item* item = Item::CreateItem(BAZAAR_TOKEN_ITEM, amount, player))
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            item->SaveToDB(trans);
            MailDraft("Bazaar Tokens",
                      "Your bags were full, so Tiraxis had these sent on.")
                .AddItem(item)
                .SendMailTo(trans, MailReceiver(player), MailSender(MAIL_CREATURE, BAZAAR_NPC_TIRAXIS));
            CharacterDatabase.CommitTransaction(trans);
        }

        LOG_DEBUG("module.bazaar", "Ethereal Bazaar: {} earned {} token(s) from {}.",
                  player->GetName(), amount, grund);
    }
}

class ethereal_bazaar_token_config final : public WorldScript
{
public:
    ethereal_bazaar_token_config() : WorldScript("ethereal_bazaar_token_config",
        {WORLDHOOK_ON_AFTER_CONFIG_LOAD}) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        auto config = std::make_shared<TokenConfig>();
        config->Enabled = sConfigMgr->GetOption<bool>("EtherealBazaar.Tokens.Enable", true);
        config->Announce = sConfigMgr->GetOption<bool>("EtherealBazaar.Tokens.Announce", false);
        config->BonusLevel = sConfigMgr->GetOption<uint32>("EtherealBazaar.Tokens.BonusLevel", 60);
        config->BonusPercent = sConfigMgr->GetOption<uint32>("EtherealBazaar.Tokens.BonusPercent", 150);
        config->Quest = LoadRange("Quest", config->Quest);
        config->Creature = LoadRange("Creature", config->Creature);
        config->DungeonBoss = LoadRange("DungeonBoss", config->DungeonBoss);
        config->RaidBoss = LoadRange("RaidBoss", config->RaidBoss);
        tokenConfig.store(std::move(config));
    }
};

class ethereal_bazaar_tokens : public PlayerScript
{
public:
    ethereal_bazaar_tokens() : PlayerScript("ethereal_bazaar_tokens") { }

    void OnPlayerCompleteQuest(Player* player, Quest const* quest) override
    {
        auto config = tokenConfig.load();
        if (!config->Enabled || CoASeasonState::Active() || !player || !quest)
            return;

        Grant(player, RollAmount(config->Quest), "a quest", *config);
    }

    void OnPlayerCreatureKill(Player* killer, Creature* killed) override
    {
        auto config = tokenConfig.load();
        if (!config->Enabled || CoASeasonState::Active() || !killer || !killed)
            return;

        // Nothing for what a player made themselves, and nothing for the
        // harmless: a totem farm should not be a token farm.
        if (killed->IsSummon() || killed->IsCritter() || killed->IsTotem())
            return;

        // Bosses are worth a real amount, and a raid boss more than a dungeon
        // one. IsDungeonBoss covers the flagged encounters; the world bosses
        // outside an instance are deliberately left with the ordinary rate.
        if (killed->IsDungeonBoss())
        {
            Map const* map = killed->FindMap();
            bool const raid = map && map->IsRaid();
            Grant(killer, RollAmount(raid ? config->RaidBoss : config->DungeonBoss),
                  raid ? "a raid boss" : "a dungeon boss", *config);
            return;
        }

        Grant(killer, RollAmount(config->Creature), "a creature", *config);
    }
};

void AddEtherealBazaarTokenScripts()
{
    new ethereal_bazaar_token_config();
    new ethereal_bazaar_tokens();
}
