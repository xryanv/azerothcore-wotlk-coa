/*
 * Copyright (C) 2016+ AzerothCore <www.azerothcore.org>, released under GNU AGPL v3.
 */

#include "SeasonService.h"
#include "SeasonEligibility.h"
#include "Configuration/Config.h"
#include "Creature.h"
#include "Group.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

#include <atomic>
#include <unordered_set>

namespace
{
    std::atomic<bool> configuredEnabled{false};
    std::atomic<bool> pendingReload{false};

    bool Human(Player const* player)
    {
        return player && player->GetSession() && !player->GetSession()->IsBot();
    }

    void Credit(Player* player, std::string const& activity, uint32 creature = 0, bool lockout = false)
    {
        if (!Human(player) || !CoASeason::Service::Instance().Enabled())
            return;

        CoASeason::Service::Instance().Enqueue({player->GetSession()->GetAccountId(), player->GetGUID(),
            player->GetGUID().GetCounter(), player->GetLevel(), activity, creature, lockout});
    }

    bool EncounterBoss(Creature const* creature, Map* map)
    {
        if (creature->IsDungeonBoss() || creature->GetCreatureTemplate()->rank == CREATURE_ELITE_WORLDBOSS)
            return true;

        if (DungeonEncounterList const* encounters = sObjectMgr->GetDungeonEncounterList(
            map->GetId(), map->GetDifficulty()))
            for (DungeonEncounter const* encounter : *encounters)
                if (encounter->creditType == ENCOUNTER_CREDIT_KILL_CREATURE &&
                    encounter->creditEntry == creature->GetEntry())
                    return true;
        return false;
    }

    std::string Activity(Creature const* creature, Map* map)
    {
        if (map->IsDungeon() && EncounterBoss(creature, map))
            return map->IsRaid() ? "raid" : (map->IsHeroic() ? "heroic" : "dungeon");
        if (!map->IsDungeon() && (creature->isWorldBoss() ||
            creature->GetCreatureTemplate()->rank == CREATURE_ELITE_WORLDBOSS))
            return "world";

        switch (creature->GetCreatureTemplate()->rank)
        {
            case CREATURE_ELITE_ELITE: return "elite";
            case CREATURE_ELITE_RARE: return "rare";
            case CREATURE_ELITE_RAREELITE: return "rare_elite";
            default: return {};
        }
    }

    bool IsSeasonMessage(std::string const& message)
    {
        // Also reserve malformed messages bearing our prefix so they never reach chat.
        return message.starts_with("COASEASON");
    }
}

class coa_season_world final : public WorldScript
{
public:
    coa_season_world() : WorldScript("coa_season_world",
        {WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_STARTUP, WORLDHOOK_ON_UPDATE}) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        configuredEnabled.store(sConfigMgr->GetOption<bool>("CoASeason.Enable", false));
        pendingReload.store(true);
    }

    void OnStartup() override
    {
        // The first world update runs after every module has loaded its client metadata.
        pendingReload.store(true);
    }

    void OnUpdate(uint32 /*diff*/) override
    {
        if (pendingReload.exchange(false))
            CoASeason::Service::Instance().Load(configuredEnabled.load());
        CoASeason::Service::Instance().Update();
    }
};

class coa_season_player final : public PlayerScript
{
public:
    coa_season_player() : PlayerScript("coa_season_player") { }

    void OnPlayerLogin(Player* player) override
    {
        Credit(player, "login");
    }

    void OnPlayerUpdate(Player* player, uint32 /*diff*/) override
    {
        if (Human(player))
            CoASeason::Service::Instance().Deliver(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        CoASeason::Service::Instance().Logout(player);
    }

    void OnPlayerLevelChanged(Player* player, uint8 oldLevel) override
    {
        if (player && player->GetLevel() > oldLevel)
            Credit(player, "level");
    }

    void OnPlayerCompleteQuest(Player* player, Quest const* quest) override
    {
        // This core calls the hook at the end of RewardQuest, after the reward is accepted.
        if (quest)
            Credit(player, "quest");
    }

    bool OnPlayerCanUseChat(Player* player, uint32 type, uint32 language,
        std::string& message, Player* receiver) override
    {
        if (!IsSeasonMessage(message))
            return true;
        if (Human(player) && receiver == player && type == CHAT_MSG_WHISPER &&
            language == LANG_ADDON && message.size() <= 255 && message.starts_with("COASEASON\t"))
            CoASeason::Service::Instance().Request(player, message.substr(10));
        message.clear();
        return false;
    }

    void OnPlayerBeforeSendChatMessage(Player* /*player*/, uint32& type,
        uint32& language, std::string& message) override
    {
        // The receiver-aware hook alone handles whispers. Other routes cannot carry RPCs.
        if (IsSeasonMessage(message) && (type != CHAT_MSG_WHISPER || language != LANG_ADDON))
            message.clear();
    }
};

class coa_season_kills final : public UnitScript
{
public:
    coa_season_kills() : UnitScript("coa_season_kills", true, {UNITHOOK_ON_UNIT_DEATH}) { }

    void OnUnitDeath(Unit* victim, Unit* /*killer*/) override
    {
        if (!CoASeason::Service::Instance().Enabled() || !victim)
            return;
        Creature* creature = victim->ToCreature();
        if (!creature || creature->IsSummon() || creature->IsPet() ||
            creature->IsCritter() || creature->IsTotem())
            return;
        Map* map = creature->FindMap();
        if (!map || map->IsBattlegroundOrArena())
            return;
        std::string const activity = Activity(creature, map);
        if (activity.empty())
            return;

        bool const lockout = CoASeason::RequiresEntryLockout(activity);
        std::unordered_set<uint32> credited;
        auto credit = [&](Player* player)
        {
            if (Human(player) && player->IsInWorld() && player->FindMap() == map &&
                creature->isTappedBy(player) && player->IsAtGroupRewardDistance(creature) &&
                credited.insert(player->GetSession()->GetAccountId()).second)
                Credit(player, activity, creature->GetEntry(), lockout);
        };
        // Loot entitlement is authoritative even when another group, a pet or a bot lands the last hit.
        if (Group* group = creature->GetLootRecipientGroup())
            for (GroupReference* member = group->GetFirstMember(); member; member = member->next())
                credit(member->GetSource());
        else
            credit(creature->GetLootRecipient());
    }
};

void AddCoASeasonScripts()
{
    new coa_season_world();
    new coa_season_player();
    new coa_season_kills();
}
