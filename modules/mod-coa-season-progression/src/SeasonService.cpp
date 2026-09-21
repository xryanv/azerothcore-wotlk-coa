#include "SeasonService.h"
#include "SeasonProtocol.h"
#include "SeasonRules.h"
#include "SeasonSettings.h"
#include "SeasonRequestRules.h"
#include "SeasonRewardRules.h"
#include "../../mod-ascension-compat/src/AscensionSeasonCollection.h"
#include "AsyncCallbackProcessor.h"
#include "Chat.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Item.h"
#include "Log.h"
#include "Mail.h"
#include "MailMgr.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QueryCallback.h"
#include "Random.h"
#include "SeasonProgressionState.h"
#include "Transaction.h"
#include "WorldSession.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <deque>
#include <functional>
#include <map>
#include <mutex>
#include <set>
#include <tuple>
#include <utility>

namespace CoASeason
{
namespace
{
using AccountKey = std::pair<uint32, uint32>;
using KillKey = std::tuple<uint32, uint32, uint32>;

uint64 Now()
{
    return static_cast<uint64>(GameTime::GetGameTime().count());
}

struct Reward
{
    uint32 id = 0;
    std::string type;
    uint32 target = 0;
    uint32 preview = 0;
    uint32 count = 1;
    uint32 cost = 0;
    uint32 minimumTier = 0;
    uint32 enabled = 1;
    uint32 order = 0;
    std::string name;
    std::string category;
};

std::string RewardRow(Reward const& reward, bool owned)
{
    return "REWARD|" + std::to_string(reward.id) + "|" + reward.type + "|" +
        std::to_string(reward.target) + "|" + std::to_string(reward.preview) + "|" +
        std::to_string(reward.count) + "|" + std::to_string(reward.cost) + "|" +
        std::to_string(reward.minimumTier) + "|" + std::to_string(reward.enabled) + "|" +
        std::to_string(reward.order) + "|" + Encode(reward.name) + "|" + Encode(reward.category) + "|" +
        (owned ? "1" : "0");
}

bool ValidReward(Reward const& reward)
{
    if (!reward.id || reward.name.empty() || reward.name.size() > 48 || reward.category.size() > 24 ||
        reward.minimumTier > 7 || reward.enabled > 1 || !reward.count || reward.count > 1000 ||
        RewardRow(reward, false).size() + 35 > MaxPayloadBytes ||
        !AscensionSeasonCollection::Validate(reward.type, reward.target, reward.preview))
        return false;
    if (reward.type != "item")
        return reward.count == 1;
    ItemTemplate const* item = sObjectMgr->GetItemTemplate(reward.target);
    return item && reward.count <= uint64(item->GetMaxStackSize()) * MAX_MAIL_ITEMS;
}

struct Season
{
    uint32 id = 0;
    std::string name;
    std::string status = "draft";
    uint32 revision = 1;
    uint64 created = 0;
    uint64 activated = 0;
    Settings settings = DefaultSettings();
    std::array<Tier, 7> tiers = DefaultTiers;
    std::map<uint32, Reward> rewards;
};

struct RequestContext
{
    uint32 account = 0;
    ObjectGuid guid;
    uint32 character = 0;
    bool admin = false;
    std::string payload;
    std::vector<std::string> fields;
    std::string Id() const { return fields.size() > 1 ? fields[1] : "error"; }
};

struct MailDelivery
{
    ObjectGuid guid;
    uint32 account = 0;
    std::unique_ptr<Mail> mail;
    std::vector<std::unique_ptr<Item>> items;
};

template<typename... Values>
CharacterDatabasePreparedStatement* Statement(CharacterDatabaseStatements id, Values const&... values)
{
    auto* statement = CharacterDatabase.GetPreparedStatement(id);
    uint8 index = 0;
    (statement->SetData(index++, values), ...);
    return statement;
}

void SaveAccount(CharacterDatabaseTransaction const& transaction, AccountKey key, Account const& account)
{
    transaction->Append(Statement(CHAR_REP_COA_ACCOUNT, key.first, key.second, account.progress,
        account.points, account.earned, account.spent, account.mask));
}

void SaveSeason(CharacterDatabaseTransaction const& transaction, Season const& season)
{
    transaction->Append(Statement(CHAR_REP_COA_SEASON, season.id, season.name, season.status,
        season.revision, season.created, season.activated));
    for (auto const& [key, value] : season.settings)
        transaction->Append(Statement(CHAR_REP_COA_SETTING, season.id, key, value));
    for (uint32 i = 0; i < season.tiers.size(); ++i)
        transaction->Append(Statement(CHAR_REP_COA_TIER, season.id, i + 1,
            season.tiers[i].threshold, season.tiers[i].points));
    for (auto const& [id, reward] : season.rewards)
    {
        (void)id;
        transaction->Append(Statement(CHAR_REP_COA_REWARD, season.id, reward.id, reward.type, reward.target,
            reward.preview, reward.count, reward.cost, reward.minimumTier, reward.enabled, reward.order,
            reward.name, reward.category));
    }
}
}

struct Service::Impl
{
    std::atomic<bool> ready{false};
    bool busy = false;
    int reload = -1;
    uint32 active = 0;
    std::map<uint32, Season> seasons;
    std::map<AccountKey, Account> accounts;
    std::map<KillKey, uint64> kills;
    std::map<uint32, uint32> levels;
    AsyncCallbackProcessor<QueryCallback> queries;
    AsyncCallbackProcessor<TransactionCallback> transactions;
    std::mutex mutex;
    std::deque<std::function<void()>> jobs;
    std::map<ObjectGuid, std::deque<std::string>> output;
    std::map<ObjectGuid, std::deque<std::shared_ptr<MailDelivery>>> mail;
    std::map<ObjectGuid, std::pair<uint32, std::chrono::steady_clock::time_point>> sessions;

    void Send(ObjectGuid guid, std::string const& request, std::string const& row)
    {
        std::string message = "1|" + request + "|" + row;
        if (message.size() > MaxPayloadBytes)
        {
            LOG_ERROR("module.coa_season", "Refused oversized response ({} bytes)", message.size());
            message = "1|" + request + "|ERROR|Response exceeds protocol limit";
        }
        std::lock_guard<std::mutex> lock(mutex);
        if (!sessions.contains(guid))
            return;
        auto& queue = output[guid];
        if (queue.size() < 2048)
            queue.push_back(std::move(message));
    }

    void Error(RequestContext const& request, std::string const& error)
    {
        Send(request.guid, request.Id(), "ERROR|" + Encode(error));
        busy = false;
    }

    void Invalidate(uint32 account = 0)
    {
        uint32 revision = active ? seasons.at(active).revision : 0;
        std::lock_guard<std::mutex> lock(mutex);
        for (auto const& [guid, session] : sessions)
            if ((!account || account == session.first) && output[guid].size() < 2048)
                output[guid].push_back("1|push|INVALIDATE|" + std::to_string(active) + "|" +
                    std::to_string(revision));
    }

    void FailLoad()
    {
        ready.store(false);
        CoASeasonState::SetActive(false);
        busy = false;
        LOG_ERROR("module.coa_season", "Season state failed validation/load; economy remains disabled");
    }

    void LoadStep(uint32 step);
    void Handle(RequestContext request);
    void Admin(RequestContext const& request);
    void BootstrapSnapshot(RequestContext const& request);
    void Snapshot(RequestContext const& request, uint32 seasonId);
    void Buy(RequestContext const& request);
    void AwardProgress(Award const& award);
    void Load(bool enabled);

    void ReadOwnership(uint32 season, uint32 account,
        std::function<void(bool, std::set<uint32>, std::set<uint32>, std::set<uint32>)> callback)
    {
        queries.AddCallback(CharacterDatabase.AsyncQuery(Statement(CHAR_SEL_COA_APPEARANCES, account))
            .WithPreparedCallback([this, season, account, callback](PreparedQueryResult result)
        {
            if (!result)
            {
                callback(false, {}, {}, {});
                return;
            }
            std::set<uint32> appearances;
            do
            {
                Field* fields = result->Fetch();
                if (fields[0].Get<uint32>())
                    appearances.insert(fields[1].Get<uint32>());
            } while (result->NextRow());
            queries.AddCallback(CharacterDatabase.AsyncQuery(Statement(CHAR_SEL_COA_VANITIES, account))
                .WithPreparedCallback([this, season, account, callback, appearances](PreparedQueryResult vanity)
            {
                if (!vanity)
                {
                    callback(false, {}, {}, {});
                    return;
                }
                std::set<uint32> vanities;
                do
                {
                    Field* fields = vanity->Fetch();
                    if (fields[0].Get<uint32>())
                        vanities.insert(fields[1].Get<uint32>());
                } while (vanity->NextRow());
                queries.AddCallback(CharacterDatabase.AsyncQuery(Statement(CHAR_SEL_COA_PURCHASES, season, account))
                    .WithPreparedCallback([callback, appearances, vanities](PreparedQueryResult purchase)
                {
                    if (!purchase)
                    {
                        callback(false, {}, {}, {});
                        return;
                    }
                    std::set<uint32> purchases;
                    do
                    {
                        Field* fields = purchase->Fetch();
                        if (fields[0].Get<uint32>())
                            purchases.insert(fields[1].Get<uint32>());
                    } while (purchase->NextRow());
                    callback(true, appearances, vanities, purchases);
                }));
            }));
        }));
    }

    void Commit(CharacterDatabaseTransaction const& transaction, RequestContext const* request,
        uint32 seasonId, std::string const& action, std::function<void()> success, uint32 auditAccount = 0)
    {
        RequestContext context;
        if (request)
        {
            context = *request;
            transaction->Append(Statement(CHAR_INS_COA_REQUEST, context.account, context.Id(), context.payload,
                std::string("OK|Saved"), Now()));
        }
        if (!action.empty())
            transaction->Append(Statement(CHAR_INS_COA_AUDIT, seasonId,
                request ? context.account : auditAccount, action, Now()));
        transactions.AddCallback(CharacterDatabase.AsyncCommitTransaction(transaction))
            .AfterComplete([this, context, success](bool committed)
        {
            if (committed)
            {
                success();
                if (!context.payload.empty())
                    Send(context.guid, context.Id(), "OK|Saved");
            }
            else
            {
                // A failed/ambiguous commit may have reached durable storage: stop every writer and reload.
                // Request nonce lookup on retry recovers a committed result without a second grant.
                ready.store(false);
                CoASeasonState::SetActive(false);
                reload = 1;
                if (!context.payload.empty())
                    Send(context.guid, context.Id(), "ERROR|Database commit failed; refreshing state");
                LOG_ERROR("module.coa_season", "Commit failed; suspending economy until authoritative reload");
            }
            busy = false;
        });
    }

    bool MakeMail(CharacterDatabaseTransaction const& transaction, Award const& recipient,
        uint32 itemId, uint32 count, std::vector<std::shared_ptr<MailDelivery>>& deliveries)
    {
        if (!count)
            return true;
        ItemTemplate const* itemTemplate = sObjectMgr->GetItemTemplate(itemId);
        if (!itemTemplate || !itemTemplate->GetMaxStackSize() || count > 10000)
            return false;
        uint32 stackSize = itemTemplate->GetMaxStackSize();
        while (count)
        {
            auto delivery = std::make_shared<MailDelivery>();
            delivery->guid = recipient.guid;
            delivery->account = recipient.account;
            delivery->mail = std::make_unique<Mail>();
            Mail& message = *delivery->mail;
            message.messageID = sObjectMgr->GenerateMailID();
            message.messageType = MAIL_NORMAL;
            message.stationery = MAIL_STATIONERY_GM;
            message.sender = 0;
            message.receiver = recipient.character;
            message.subject = "Season reward";
            message.body = "Your gameplay reward is enclosed.";
            message.deliver_time = static_cast<time_t>(Now());
            message.expire_time = message.deliver_time + 90 * DAY;
            message.checked = MAIL_CHECK_MASK_NONE;
            message.state = MAIL_STATE_UNCHANGED;
            while (count && delivery->items.size() < MAX_MAIL_ITEMS)
            {
                uint32 quantity = std::min(count, stackSize);
                std::unique_ptr<Item> item(Item::CreateItem(itemId, quantity));
                if (!item)
                    return false;
                item->SetOwnerGUID(recipient.guid);
                item->SaveToDB(transaction);
                message.AddItem(item->GetGUID().GetCounter(), itemId);
                transaction->Append(Statement(CHAR_INS_MAIL_ITEM, message.messageID,
                    item->GetGUID().GetCounter(), recipient.character));
                delivery->items.push_back(std::move(item));
                count -= quantity;
            }
            transaction->Append(Statement(CHAR_INS_MAIL, message.messageID, uint8(message.messageType),
                int8(message.stationery), uint16(0), uint32(0), recipient.character, message.subject,
                message.body, true, uint32(message.expire_time), uint32(message.deliver_time),
                uint32(0), uint32(0), uint8(message.checked)));
            deliveries.push_back(std::move(delivery));
        }
        return true;
    }

    void PublishMail(std::vector<std::shared_ptr<MailDelivery>> const& deliveries)
    {
        // Database mail is already committed; only now may live objects/notifications be published.
        for (auto const& delivery : deliveries)
            sMailMgr->OnMailSent(delivery->mail->receiver);
        std::lock_guard<std::mutex> lock(mutex);
        for (auto const& delivery : deliveries)
            if (sessions.contains(delivery->guid))
                mail[delivery->guid].push_back(delivery);
    }
};

void Service::Impl::Load(bool enabled)
{
    ready.store(false);
    CoASeasonState::SetActive(false);
    if (busy)
    {
        reload = enabled ? 1 : 0;
        return;
    }
    {
        std::lock_guard<std::mutex> lock(mutex);
        jobs.clear();
    }
    if (!enabled)
        return;
    busy = true;
    active = 0;
    seasons.clear();
    accounts.clear();
    levels.clear();
    kills.clear();
    LoadStep(0);
}

void Service::Impl::LoadStep(uint32 step)
{
    static CharacterDatabaseStatements const statements[] = {CHAR_SEL_COA_SCHEMA, CHAR_SEL_COA_SEASONS,
        CHAR_SEL_COA_SETTINGS, CHAR_SEL_COA_TIERS, CHAR_SEL_COA_ACCOUNTS, CHAR_SEL_COA_REWARDS,
        CHAR_SEL_COA_LOCKOUTS, CHAR_SEL_COA_LEVELS};
    if (step == std::size(statements))
    {
        for (auto const& [id, season] : seasons)
        {
            Account validation;
            if (!id || !season.revision || season.name.empty() || season.rewards.size() > 128 ||
                !ValidSettings(season.settings) || !Reconcile(validation, season.tiers))
            {
                FailLoad();
                return;
            }
            if (season.status == "active")
            {
                if (active)
                {
                    FailLoad();
                    return;
                }
                active = id;
            }
            else if (season.status != "draft" && season.status != "archived")
            {
                FailLoad();
                return;
            }
            for (auto const& [rewardId, reward] : season.rewards)
            {
                (void)rewardId;
                if (!ValidReward(reward))
                {
                    FailLoad();
                    return;
                }
            }
        }
        ready.store(true);
        CoASeasonState::SetActive(true);
        busy = false;
        Invalidate();
        return;
    }
    queries.AddCallback(CharacterDatabase.AsyncQuery(Statement(statements[step]))
        .WithPreparedCallback([this, step](PreparedQueryResult result)
    {
        if (!result)
        {
            FailLoad();
            return;
        }
        if (step)
        {
            do
            {
                Field* f = result->Fetch();
                if (!f[0].Get<uint32>())
                    continue;
                uint32 id = f[1].Get<uint32>();
                if (step >= 2 && step <= 6 && !seasons.contains(id))
                {
                    FailLoad();
                    return;
                }
                switch (step)
                {
                    case 1:
                    {
                        Season season;
                        season.id = id;
                        season.name = f[2].Get<std::string>();
                        season.status = f[3].Get<std::string>();
                        season.revision = f[4].Get<uint32>();
                        season.created = f[5].Get<uint64>();
                        season.activated = f[6].Get<uint64>();
                        // Missing configuration is invalid, never silently default existing DB records.
                        season.settings.clear();
                        season.tiers = {};
                        seasons[id] = std::move(season);
                        break;
                    }
                    case 2:
                        seasons.at(id).settings[f[2].Get<std::string>()] = f[3].Get<uint32>();
                        break;
                    case 3:
                    {
                        uint32 tier = f[2].Get<uint32>();
                        if (!tier || tier > 7)
                        {
                            FailLoad();
                            return;
                        }
                        seasons.at(id).tiers[tier - 1] = {f[3].Get<uint32>(), f[4].Get<uint32>()};
                        break;
                    }
                    case 4:
                        accounts[{id, f[2].Get<uint32>()}] = {f[3].Get<uint32>(), f[4].Get<uint32>(),
                            f[5].Get<uint32>(), f[6].Get<uint32>(), f[7].Get<uint32>()};
                        break;
                    case 5:
                    {
                        Reward reward{f[2].Get<uint32>(), f[3].Get<std::string>(), f[4].Get<uint32>(),
                            f[5].Get<uint32>(), f[6].Get<uint32>(), f[7].Get<uint32>(), f[8].Get<uint32>(),
                            f[9].Get<uint32>(), f[10].Get<uint32>(), f[11].Get<std::string>(),
                            f[12].Get<std::string>()};
                        seasons.at(id).rewards[reward.id] = std::move(reward);
                        break;
                    }
                    case 6:
                        kills[{id, f[2].Get<uint32>(), f[3].Get<uint32>()}] = f[4].Get<uint64>();
                        break;
                    case 7:
                        levels[id] = f[2].Get<uint32>();
                        break;
                }
            } while (result->NextRow());
        }
        LoadStep(step + 1);
    }));
}

void Service::Impl::Handle(RequestContext request)
{
    if (!ready.load())
    {
        Error(request, "Season system is not ready.");
        return;
    }

    RequestClass const requestClass = ClassifyRequest(request.fields);
    if (requestClass == RequestClass::Invalid)
    {
        Error(request, "Invalid season request.");
        return;
    }
    if (request.fields[2] == "ADMIN" && !request.admin)
    {
        Error(request, "Season Admin requires GM level 3.");
        return;
    }

    auto dispatch = [this](RequestContext const& context)
    {
        if (context.fields[2] == "GET")
        {
            if (ShouldServeAdminBootstrap(active, context.admin))
                BootstrapSnapshot(context);
            else
                Snapshot(context, active);
            return;
        }
        if (context.fields[2] == "BUY")
        {
            Buy(context);
            return;
        }
        Admin(context);
    };

    if (requestClass == RequestClass::Read)
    {
        dispatch(request);
        return;
    }

    queries.AddCallback(CharacterDatabase.AsyncQuery(Statement(CHAR_SEL_COA_REQUEST, request.account, request.Id()))
        .WithPreparedCallback([this, request, dispatch](PreparedQueryResult result)
    {
        if (!result)
        {
            Error(request, "Could not verify request history.");
            return;
        }
        bool found = false;
        std::string payload;
        std::string response;
        do
        {
            Field* fields = result->Fetch();
            if (!fields[0].Get<uint32>())
                continue;
            found = true;
            payload = fields[1].Get<std::string>();
            response = fields[2].Get<std::string>();
            break;
        } while (result->NextRow());

        if (!found)
        {
            dispatch(request);
            return;
        }
        if (payload != request.payload)
        {
            Error(request, "Request ID was already used for another mutation.");
            return;
        }
        Send(request.guid, request.Id(), response);
        busy = false;
    }));
}

void Service::Impl::Admin(RequestContext const& request)
{
    std::string const& action = request.fields[3];
    if (action == "LIST")
    {
        for (auto const& [id, season] : seasons)
            Send(request.guid, request.Id(), "SEASON|" + std::to_string(id) + "|" + season.status + "|" +
                std::to_string(season.revision) + "|" + Encode(season.name));
        Send(request.guid, request.Id(), "OK|Listed");
        busy = false;
        return;
    }
    if (action == "GET")
    {
        uint32 seasonId = 0;
        if (!Number(request.fields[4], seasonId))
            return Error(request, "Invalid season ID.");
        Snapshot(request, seasonId);
        return;
    }
    if (action == "BROWSE")
    {
        std::string search;
        uint32 offset = 0;
        if (!Decode(request.fields[4], search, 80) || !Number(request.fields[5], offset) || offset > 100000)
            return Error(request, "Invalid reward search.");
        for (AscensionSeasonCollection::Entry const& entry : AscensionSeasonCollection::Browse("", search, offset))
            Send(request.guid, request.Id(), "BROWSE|" + entry.Type + "|" + std::to_string(entry.Target) + "|" +
                std::to_string(entry.PreviewItem) + "|" + Encode(entry.Name));
        Send(request.guid, request.Id(), "OK|Listed");
        busy = false;
        return;
    }
    if (action == "ACCOUNT")
    {
        uint32 accountId = 0;
        if (!Number(request.fields[4], accountId) || !accountId)
            return Error(request, "Invalid account ID.");
        Account account;
        if (active)
            if (auto found = accounts.find({active, accountId}); found != accounts.end())
                account = found->second;
        Send(request.guid, request.Id(), "ACCOUNT|" + std::to_string(accountId) + "|" +
            std::to_string(active) + "|" + std::to_string(account.progress) + "|" + std::to_string(account.points));
        busy = false;
        return;
    }
    if (action == "HISTORY")
    {
        uint32 seasonId = 0;
        uint32 offset = 0;
        if (!Number(request.fields[4], seasonId) || !Number(request.fields[5], offset) ||
            !seasons.contains(seasonId) || offset > 100000)
            return Error(request, "Invalid history request.");
        queries.AddCallback(CharacterDatabase.AsyncQuery(Statement(CHAR_SEL_COA_HISTORY, seasonId, offset))
            .WithPreparedCallback([this, request](PreparedQueryResult result)
        {
            if (!result)
                return Error(request, "Could not read season history.");
            do
            {
                Field* fields = result->Fetch();
                if (!fields[0].Get<uint32>())
                    continue;
                Send(request.guid, request.Id(), "HISTORY|" + std::to_string(fields[1].Get<uint64>()) + "|" +
                    std::to_string(fields[2].Get<uint32>()) + "|" + Encode(fields[3].Get<std::string>()));
            } while (result->NextRow());
            Send(request.guid, request.Id(), "OK|Listed");
            busy = false;
        }));
        return;
    }

    if (action == "CREATE")
    {
        uint32 source = 0;
        std::string name;
        if (!Number(request.fields[4], source) || !Decode(request.fields[5], name, 64) || name.empty() ||
            Encode(name).size() > 120 || (source && !seasons.contains(source)))
            return Error(request, "Invalid draft season.");
        uint32 id = seasons.empty() ? 1 : seasons.rbegin()->first + 1;
        if (!id || (!seasons.empty() && seasons.rbegin()->first == UINT32_MAX))
            return Error(request, "Season ID space is exhausted.");
        Season season = source ? seasons.at(source) : Season{};
        season.id = id;
        season.name = name;
        season.status = "draft";
        season.revision = 1;
        season.created = Now();
        season.activated = 0;
        auto transaction = CharacterDatabase.BeginTransaction();
        SaveSeason(transaction, season);
        Commit(transaction, &request, id, "Create draft season " + std::to_string(id),
            [this, season] { seasons[season.id] = season; });
        return;
    }

    uint32 seasonId = 0;
    uint32 revision = 0;
    if (!Number(request.fields[4], seasonId) || !Number(request.fields[5], revision))
        return Error(request, "Invalid season revision.");
    auto seasonItr = seasons.find(seasonId);
    if (seasonItr == seasons.end() || seasonItr->second.revision != revision)
        return Error(request, "Season changed; refresh before saving.");
    if (seasonItr->second.status == "archived")
        return Error(request, "Archived seasons are read-only.");

    if (action == "ADJUST")
    {
        uint32 accountId = 0;
        int32 amount = 0;
        std::string reason;
        if (!Number(request.fields[6], accountId) || !accountId || !SignedNumber(request.fields[7], amount) ||
            !Decode(request.fields[8], reason, 48) || reason.empty() || Encode(reason).size() > 120)
            return Error(request, "Invalid account adjustment.");
        AccountKey const key{seasonId, accountId};
        Account account;
        if (auto found = accounts.find(key); found != accounts.end())
            account = found->second;
        if (!Adjust(account, amount))
            return Error(request, "Point adjustment would underflow or overflow.");
        auto transaction = CharacterDatabase.BeginTransaction();
        SaveAccount(transaction, key, account);
        Commit(transaction, &request, seasonId,
            "Adjust account " + std::to_string(accountId) + " by " + std::to_string(amount) + ": " + reason,
            [this, key, account, accountId, seasonId, request]
        {
            accounts[key] = account;
            if (seasonId == active)
                Invalidate(accountId);
            else
                Invalidate(request.account);
        });
        return;
    }

    Season updated = seasonItr->second;
    if (updated.revision == UINT32_MAX)
        return Error(request, "Season revision is exhausted.");

    if (action == "SETTING")
    {
        uint32 value = 0;
        std::string const& key = request.fields[6];
        if (!ValidSettingKey(key) || !Number(request.fields[7], value))
            return Error(request, "Invalid season setting.");
        updated.settings[key] = value;
        if (!ValidSettings(updated.settings))
            return Error(request, "Setting conflicts with economy limits.");
        ++updated.revision;
        auto transaction = CharacterDatabase.BeginTransaction();
        SaveSeason(transaction, updated);
        Commit(transaction, &request, seasonId, "Set " + key + " = " + std::to_string(value),
            [this, updated] { seasons[updated.id] = updated; Invalidate(); });
        return;
    }

    if (action == "TIER" || action == "RESET")
    {
        if (action == "TIER")
        {
            uint32 tier = 0;
            uint32 threshold = 0;
            uint32 points = 0;
            if (!Number(request.fields[6], tier) || !Number(request.fields[7], threshold) ||
                !Number(request.fields[8], points) || tier < 1 || tier > 7 || !threshold)
                return Error(request, "Invalid tier setting.");
            updated.tiers[tier - 1] = {threshold, points};
        }
        else
        {
            updated.settings = DefaultSettings();
            updated.tiers = DefaultTiers;
        }
        Account validation;
        if (!ValidSettings(updated.settings) || !Reconcile(validation, updated.tiers))
            return Error(request, "Tier thresholds must increase strictly.");
        ++updated.revision;

        std::map<AccountKey, Account> reconciled;
        for (auto const& [key, account] : accounts)
        {
            if (key.first != seasonId)
                continue;
            Account next = account;
            if (!Reconcile(next, updated.tiers))
                return Error(request, "Tier change would overflow an account balance.");
            reconciled.emplace(key, next);
        }
        auto transaction = CharacterDatabase.BeginTransaction();
        SaveSeason(transaction, updated);
        for (auto const& [key, account] : reconciled)
            SaveAccount(transaction, key, account);
        Commit(transaction, &request, seasonId,
            action == "RESET" ? "Reset economy and tiers to defaults" : "Update tier settings",
            [this, updated, reconciled]
        {
            seasons[updated.id] = updated;
            for (auto const& [key, account] : reconciled)
                accounts[key] = account;
            Invalidate();
        });
        return;
    }

    if (action == "REWARD")
    {
        Reward reward;
        if (!Number(request.fields[6], reward.id) || !Number(request.fields[8], reward.target) ||
            !Number(request.fields[9], reward.preview) || !Number(request.fields[10], reward.count) ||
            !Number(request.fields[11], reward.cost) || !Number(request.fields[12], reward.minimumTier) ||
            !Number(request.fields[13], reward.enabled) || !Number(request.fields[14], reward.order) ||
            !Decode(request.fields[15], reward.name, 48) || !Decode(request.fields[16], reward.category, 24))
            return Error(request, "Invalid reward values.");
        reward.type = request.fields[7];
        if (!reward.id)
        {
            if (updated.rewards.size() >= 128 ||
                (!updated.rewards.empty() && updated.rewards.rbegin()->first == UINT32_MAX))
                return Error(request, "Reward catalog is full.");
            reward.id = updated.rewards.empty() ? 1 : updated.rewards.rbegin()->first + 1;
        }
        if (!updated.rewards.contains(reward.id) && updated.rewards.size() >= 128)
            return Error(request, "Reward catalog is full.");
        if (!ValidReward(reward))
            return Error(request, "Reward is not valid for this client/server catalog.");
        updated.rewards[reward.id] = reward;
        ++updated.revision;
        auto transaction = CharacterDatabase.BeginTransaction();
        SaveSeason(transaction, updated);
        Commit(transaction, &request, seasonId, "Save reward " + std::to_string(reward.id),
            [this, updated] { seasons[updated.id] = updated; Invalidate(); });
        return;
    }

    if (action == "DISABLE")
    {
        uint32 rewardId = 0;
        if (!Number(request.fields[6], rewardId) || !updated.rewards.contains(rewardId))
            return Error(request, "Reward does not exist.");
        updated.rewards[rewardId].enabled = 0;
        ++updated.revision;
        auto transaction = CharacterDatabase.BeginTransaction();
        SaveSeason(transaction, updated);
        Commit(transaction, &request, seasonId, "Disable reward " + std::to_string(rewardId),
            [this, updated] { seasons[updated.id] = updated; Invalidate(); });
        return;
    }

    if (action == "ACTIVATE")
    {
        std::string confirmation;
        if (!Decode(request.fields[6], confirmation, 20) || confirmation != "RESET SEASON" ||
            updated.status != "draft")
            return Error(request, "Season activation requires a draft and RESET SEASON confirmation.");
        Season incoming = updated;
        incoming.status = "active";
        incoming.activated = Now();
        ++incoming.revision;

        Season outgoing;
        bool const hasOutgoing = active && active != incoming.id;
        if (hasOutgoing)
        {
            outgoing = seasons.at(active);
            if (outgoing.revision == UINT32_MAX)
                return Error(request, "Outgoing season revision is exhausted.");
            outgoing.status = "archived";
            ++outgoing.revision;
        }
        auto transaction = CharacterDatabase.BeginTransaction();
        if (hasOutgoing)
            SaveSeason(transaction, outgoing);
        SaveSeason(transaction, incoming);
        transaction->Append(Statement(CHAR_DEL_COA_ACCOUNTS, incoming.id));
        transaction->Append(Statement(CHAR_DEL_COA_LOCKOUTS, incoming.id));
        Commit(transaction, &request, incoming.id,
            "Activate season " + std::to_string(incoming.id) +
                (hasOutgoing ? "; archive season " + std::to_string(outgoing.id) : ""),
            [this, incoming, outgoing, hasOutgoing]
        {
            if (hasOutgoing)
                seasons[outgoing.id] = outgoing;
            seasons[incoming.id] = incoming;
            active = incoming.id;
            for (auto itr = accounts.begin(); itr != accounts.end();)
            {
                if (itr->first.first == incoming.id)
                    itr = accounts.erase(itr);
                else
                    ++itr;
            }
            for (auto itr = kills.begin(); itr != kills.end();)
            {
                if (std::get<0>(itr->first) == incoming.id)
                    itr = kills.erase(itr);
                else
                    ++itr;
            }
            Invalidate();
        });
        return;
    }

    Error(request, "Unsupported admin operation.");
}

void Service::Impl::BootstrapSnapshot(RequestContext const& request)
{
    Settings const settings = DefaultSettings();
    Send(request.guid, request.Id(), "BEGIN|0|0|No active season|0|0|0|1|unconfigured");
    uint32 rows = 0;
    for (auto const& [key, value] : settings)
    {
        Send(request.guid, request.Id(), "SETTING|" + key + "|" + std::to_string(value));
        ++rows;
    }
    for (uint32 i = 0; i < DefaultTiers.size(); ++i)
    {
        Tier const& tier = DefaultTiers[i];
        Send(request.guid, request.Id(), "TIER|" + std::to_string(i + 1) + "|" +
            std::to_string(tier.threshold) + "|" + std::to_string(tier.points));
        ++rows;
    }
    Send(request.guid, request.Id(), "END|" + std::to_string(rows));
    busy = false;
}

void Service::Impl::Snapshot(RequestContext const& request, uint32 seasonId)
{
    auto seasonItr = seasons.find(seasonId);
    if (!seasonId || seasonItr == seasons.end() || (!request.admin && seasonId != active))
    {
        Error(request, "Season is not available.");
        return;
    }

    Season const season = seasonItr->second;
    Account account;
    if (auto found = accounts.find({seasonId, request.account}); found != accounts.end())
        account = found->second;

    ReadOwnership(seasonId, request.account,
        [this, request, season, account](bool ok, std::set<uint32> appearances,
            std::set<uint32> vanities, std::set<uint32> purchases)
    {
        if (!ok)
        {
            Error(request, "Could not read permanent reward ownership.");
            return;
        }
        auto current = seasons.find(season.id);
        if (current == seasons.end() || current->second.revision != season.revision)
        {
            Error(request, "Season changed while state was loading; refresh.");
            return;
        }

        Send(request.guid, request.Id(), "BEGIN|" + std::to_string(season.id) + "|" +
            std::to_string(season.revision) + "|" + Encode(season.name) + "|" +
            std::to_string(account.progress) + "|" + std::to_string(account.points) + "|" +
            std::to_string(account.mask) + "|" + (request.admin ? "1" : "0") + "|" + season.status);

        uint32 rows = 0;
        for (auto const& [key, value] : season.settings)
        {
            Send(request.guid, request.Id(), "SETTING|" + key + "|" + std::to_string(value));
            ++rows;
        }
        for (uint32 i = 0; i < season.tiers.size(); ++i)
        {
            Tier const& tier = season.tiers[i];
            Send(request.guid, request.Id(), "TIER|" + std::to_string(i + 1) + "|" +
                std::to_string(tier.threshold) + "|" + std::to_string(tier.points));
            ++rows;
        }
        for (auto const& [id, reward] : season.rewards)
        {
            (void)id;
            bool const owned = RewardOwned(reward.type, reward.target, reward.id,
                appearances, vanities, purchases);
            Send(request.guid, request.Id(), RewardRow(reward, owned));
            ++rows;
        }
        Send(request.guid, request.Id(), "END|" + std::to_string(rows));
        busy = false;
    });
}

void Service::Impl::Buy(RequestContext const& request)
{
    uint32 seasonId = 0;
    uint32 revision = 0;
    uint32 rewardId = 0;
    if (!Number(request.fields[3], seasonId) || !Number(request.fields[4], revision) ||
        !Number(request.fields[5], rewardId))
    {
        Error(request, "Invalid purchase request.");
        return;
    }

    auto seasonItr = seasons.find(seasonId);
    if (!active || seasonId != active || seasonItr == seasons.end() || seasonItr->second.status != "active" ||
        seasonItr->second.revision != revision)
    {
        Error(request, "Season changed; refresh before purchasing.");
        return;
    }
    auto rewardItr = seasonItr->second.rewards.find(rewardId);
    if (rewardItr == seasonItr->second.rewards.end())
    {
        Error(request, "Reward is not available.");
        return;
    }

    Season const season = seasonItr->second;
    Reward const reward = rewardItr->second;
    ReadOwnership(seasonId, request.account,
        [this, request, season, reward](bool ok, std::set<uint32> appearances,
            std::set<uint32> vanities, std::set<uint32> purchases)
    {
        if (!ok)
        {
            Error(request, "Could not verify reward ownership.");
            return;
        }
        auto currentSeason = seasons.find(season.id);
        if (currentSeason == seasons.end() || currentSeason->second.status != "active" ||
            currentSeason->second.revision != season.revision || active != season.id)
        {
            Error(request, "Season changed; refresh before purchasing.");
            return;
        }

        bool const owned = RewardOwned(reward.type, reward.target, reward.id,
            appearances, vanities, purchases);
        AccountKey const key{season.id, request.account};
        Account account;
        if (auto found = accounts.find(key); found != accounts.end())
            account = found->second;
        if (!Purchase(account, season.id, season.revision, season.id, season.revision,
            reward.cost, reward.minimumTier, owned, reward.enabled != 0))
        {
            Error(request, owned ? "Reward is already owned." : "Reward cannot be purchased.");
            return;
        }

        auto transaction = CharacterDatabase.BeginTransaction();
        SaveAccount(transaction, key, account);
        std::vector<std::shared_ptr<MailDelivery>> deliveries;
        if (reward.type == "appearance")
            transaction->Append(Statement(CHAR_INS_COA_APPEARANCE, request.account, reward.target));
        else if (reward.type == "vanity")
            transaction->Append(Statement(CHAR_INS_COA_VANITY, request.account, reward.target));
        else
        {
            Award recipient{request.account, request.guid, request.character, 0, "purchase", 0, false};
            if (!MakeMail(transaction, recipient, reward.target, reward.count, deliveries))
            {
                Error(request, "Could not prepare reward delivery.");
                return;
            }
        }
        transaction->Append(Statement(CHAR_INS_COA_PURCHASE, season.id, request.account,
            request.character, reward.id, reward.type, reward.target, reward.count, reward.cost,
            request.Id(), Now()));

        Commit(transaction, &request, season.id,
            "Purchase reward " + std::to_string(reward.id),
            [this, key, account, request, reward, deliveries]
        {
            accounts[key] = account;
            PublishMail(deliveries);
            if (reward.type == "appearance" || reward.type == "vanity")
                AscensionSeasonCollection::Refresh(request.account);
            Invalidate(request.account);
        });
    });
}

void Service::Impl::AwardProgress(Award const& award)
{
    if (!ready.load() || (!active && award.activity != "login"))
    {
        busy = false;
        return;
    }
    auto transaction = CharacterDatabase.BeginTransaction();
    if (award.activity == "login" && !levels.contains(award.character))
    {
        transaction->Append(Statement(CHAR_REP_COA_LEVEL, award.character, uint32(award.level)));
        Commit(transaction, nullptr, active, "", [this, award]
        {
            levels[award.character] = award.level;
        });
        return;
    }
    if (award.activity == "login" || !active)
    {
        busy = false;
        return;
    }
    Season const& season = seasons.at(active);
    uint32 multiplier = 1;
    uint32 tokens = 0;
    if (award.activity == "level")
    {
        // A missed first login initializes rather than retroactively rewarding existing levels.
        if (!levels.contains(award.character))
        {
            transaction->Append(Statement(CHAR_REP_COA_LEVEL, award.character, uint32(award.level)));
            Commit(transaction, nullptr, active, "", [this, award]
            {
                levels[award.character] = award.level;
            });
            return;
        }
        multiplier = NewLevels(static_cast<uint8>(levels.at(award.character)), award.level);
        if (!multiplier)
        {
            busy = false;
            return;
        }
        tokens = multiplier * season.settings.at("level_tokens");
        transaction->Append(Statement(CHAR_REP_COA_LEVEL, award.character, uint32(award.level)));
    }
    KillKey key{active, award.account, award.entry};
    uint64 now = Now();
    bool lockout = award.lockout && season.settings.at("lockout_enabled");
    if (lockout && kills.contains(key) &&
        !LockoutReady(now, kills.at(key), season.settings.at("lockout_seconds")))
    {
        busy = false;
        return;
    }
    auto rate = season.settings.find(award.activity);
    if (rate == season.settings.end())
    {
        busy = false;
        return;
    }
    if (award.activity == "dungeon" || award.activity == "heroic" ||
        award.activity == "raid" || award.activity == "world")
    {
        if (urand(1, 100) <= season.settings.at(award.activity + "_chance"))
            tokens = urand(season.settings.at(award.activity + "_min"),
                season.settings.at(award.activity + "_max"));
    }
    AccountKey accountKey{active, award.account};
    Account account = accounts[accountKey];
    uint64 amount = uint64(rate->second) * multiplier;
    if (amount > UINT32_MAX || !AddProgress(account, static_cast<uint32>(amount), season.tiers))
    {
        LOG_ERROR("module.coa_season", "Award overflow for account {}", award.account);
        busy = false;
        return;
    }
    SaveAccount(transaction, accountKey, account);
    if (lockout)
        transaction->Append(Statement(CHAR_REP_COA_LOCKOUT, active, award.account, award.entry, now));
    std::vector<std::shared_ptr<MailDelivery>> deliveries;
    if (!MakeMail(transaction, award, 975001, tokens, deliveries))
    {
        LOG_ERROR("module.coa_season", "Cannot create token mail; award rejected for {}", award.account);
        busy = false;
        return;
    }
    Commit(transaction, nullptr, active, "", [this, accountKey, account, key, lockout, now, award, deliveries]
    {
        accounts[accountKey] = account;
        if (lockout)
            kills[key] = now;
        if (award.activity == "level")
            levels[award.character] = award.level;
        PublishMail(deliveries);
        Invalidate(award.account);
    }, award.account);
}

Service& Service::Instance()
{
    static Service instance;
    return instance;
}

Service::Service() : _impl(std::make_unique<Impl>()) { }
Service::~Service() = default;

bool Service::Enabled() const
{
    return _impl->ready.load();
}

void Service::Load(bool enabled)
{
    _impl->Load(enabled);
}

void Service::Update()
{
    _impl->queries.ProcessReadyCallbacks();
    _impl->transactions.ProcessReadyCallbacks();

    if (!_impl->busy && _impl->reload >= 0)
    {
        bool const enabled = _impl->reload != 0;
        _impl->reload = -1;
        _impl->Load(enabled);
        return;
    }
    if (_impl->busy)
        return;

    std::function<void()> job;
    {
        std::lock_guard<std::mutex> lock(_impl->mutex);
        if (!_impl->jobs.empty())
        {
            job = std::move(_impl->jobs.front());
            _impl->jobs.pop_front();
        }
    }
    if (!job)
        return;
    _impl->busy = true;
    job();
}

void Service::Enqueue(Award const& award)
{
    std::lock_guard<std::mutex> lock(_impl->mutex);
    if (_impl->jobs.size() >= 8192)
    {
        LOG_ERROR("module.coa_season", "Season economy queue is full; gameplay award was dropped");
        return;
    }
    _impl->jobs.emplace_back([this, award] { _impl->AwardProgress(award); });
}

void Service::Request(Player* player, std::string const& payload)
{
    if (!player || !player->GetSession())
        return;
    std::vector<std::string> fields;
    if (!Parse(payload, fields))
    {
        LOG_WARN("module.coa_season", "Rejected malformed season RPC from account {}",
            player->GetSession()->GetAccountId());
        return;
    }

    RequestContext request;
    request.account = player->GetSession()->GetAccountId();
    request.guid = player->GetGUID();
    request.character = player->GetGUID().GetCounter();
    request.admin = player->GetSession()->GetSecurity() >= SEC_ADMINISTRATOR;
    request.payload = payload;
    request.fields = std::move(fields);

    std::lock_guard<std::mutex> lock(_impl->mutex);
    _impl->sessions[request.guid] = {request.account, std::chrono::steady_clock::now()};
    if (_impl->jobs.size() >= 8192)
    {
        auto& queue = _impl->output[request.guid];
        if (queue.size() < 2048)
            queue.push_back("1|" + request.Id() + "|ERROR|Season service is busy; retry shortly");
        return;
    }
    _impl->jobs.emplace_back([this, request = std::move(request)]() mutable
    {
        _impl->Handle(std::move(request));
    });
}

void Service::Deliver(Player* player)
{
    if (!player || !player->GetSession())
        return;
    ObjectGuid const guid = player->GetGUID();
    std::deque<std::string> messages;
    std::deque<std::shared_ptr<MailDelivery>> deliveries;
    {
        std::lock_guard<std::mutex> lock(_impl->mutex);
        _impl->sessions[guid] = {player->GetSession()->GetAccountId(), std::chrono::steady_clock::now()};
        auto output = _impl->output.find(guid);
        if (output != _impl->output.end())
        {
            for (uint32 i = 0; i < 12 && !output->second.empty(); ++i)
            {
                messages.push_back(std::move(output->second.front()));
                output->second.pop_front();
            }
            if (output->second.empty())
                _impl->output.erase(output);
        }
        auto mail = _impl->mail.find(guid);
        if (mail != _impl->mail.end())
        {
            deliveries.swap(mail->second);
            _impl->mail.erase(mail);
        }
    }

    for (std::string const& message : messages)
    {
        std::string const wire = "COASEASON\t" + message;
        WorldPacket packet;
        ChatHandler::BuildChatPacket(packet, CHAT_MSG_WHISPER, LANG_ADDON, guid, guid,
            wire, 0, player->GetName(), player->GetName(), 0, false);
        player->GetSession()->SendPacket(&packet);
    }
    for (auto const& delivery : deliveries)
        if (!player->GetMail(delivery->mail->messageID))
        {
            player->AddMail(new Mail(*delivery->mail));
            for (auto& item : delivery->items)
                if (item && !player->GetMItem(item->GetGUID().GetCounter()))
                    player->AddMItem(item.release());
            player->AddNewMailDeliverTime(delivery->mail->deliver_time);
        }
}
void Service::Logout(Player* player)
{
    if (!player)
        return;
    ObjectGuid const guid = player->GetGUID();
    std::lock_guard<std::mutex> lock(_impl->mutex);
    _impl->sessions.erase(guid);
    _impl->output.erase(guid);
    _impl->mail.erase(guid);
}

}
