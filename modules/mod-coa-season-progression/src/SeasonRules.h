#ifndef COA_SEASON_RULES_H
#define COA_SEASON_RULES_H

#include <array>
#include <cstdint>
#include <limits>
#include <string>

namespace CoASeason
{
struct Tier
{
    uint32_t threshold;
    uint32_t points;
};

struct Account
{
    uint32_t progress = 0;
    uint32_t points = 0;
    uint32_t earned = 0;
    uint32_t spent = 0;
    uint32_t mask = 0;
};

inline constexpr std::array<Tier, 7> DefaultTiers =
{{
    {100, 25}, {250, 40}, {500, 60}, {900, 90}, {1400, 125}, {2100, 175}, {3000, 250}
}};
inline constexpr auto Defaults = DefaultTiers;

// False means validation/overflow failure; the account is unchanged on failure.
inline bool Reconcile(Account& account, std::array<Tier, 7> const& tiers)
{
    uint32_t previous = 0;
    uint32_t mask = account.mask;
    uint64_t payout = 0;
    for (std::size_t i = 0; i < tiers.size(); ++i)
    {
        Tier const& tier = tiers[i];
        if (tier.threshold <= previous)
            return false;
        previous = tier.threshold;
        uint32_t bit = uint32_t{1} << i;
        if (account.progress >= tier.threshold && !(mask & bit))
        {
            payout += tier.points;
            mask |= bit;
        }
    }
    constexpr uint32_t Max = std::numeric_limits<uint32_t>::max();
    if (payout > Max - account.points || payout > Max - account.earned)
        return false;
    account.points += static_cast<uint32_t>(payout);
    account.earned += static_cast<uint32_t>(payout);
    account.mask = mask;
    return true;
}

inline bool AddProgress(Account& account, uint32_t amount, std::array<Tier, 7> const& tiers)
{
    if (amount > std::numeric_limits<uint32_t>::max() - account.progress)
        return false;
    Account updated = account;
    updated.progress += amount;
    if (!Reconcile(updated, tiers))
        return false;
    account = updated;
    return true;
}

// Decimal only: no signs, whitespace, partial parses, or overflow.
inline bool Number(std::string const& value, uint32_t& out)
{
    if (value.empty())
        return false;
    uint32_t result = 0;
    for (char c : value)
    {
        if (c < '0' || c > '9')
            return false;
        uint32_t digit = static_cast<uint32_t>(c - '0');
        if (result > (std::numeric_limits<uint32_t>::max() - digit) / 10)
            return false;
        result = result * 10 + digit;
    }
    out = result;
    return true;
}

inline bool SignedNumber(std::string const& value, int32_t& out)
{
    bool negative = !value.empty() && value.front() == '-';
    uint32_t magnitude = 0;
    if (!Number(negative ? value.substr(1) : value, magnitude))
        return false;
    constexpr uint32_t Max = static_cast<uint32_t>(std::numeric_limits<int32_t>::max());
    if (magnitude > Max + static_cast<uint32_t>(negative))
        return false;
    out = static_cast<int32_t>(negative ? -static_cast<int64_t>(magnitude) : magnitude);
    return true;
}

inline bool Purchase(Account& account, uint32_t season, uint32_t revision, uint32_t expectedSeason,
    uint32_t expectedRevision, uint32_t cost, uint32_t minimumTier, bool owned, bool enabled)
{
    if (!enabled || owned || !season || season != expectedSeason || revision != expectedRevision ||
        minimumTier > 7 || (minimumTier && !(account.mask & (uint32_t{1} << (minimumTier - 1)))) ||
        account.points < cost || account.spent > std::numeric_limits<uint32_t>::max() - cost)
        return false;
    account.points -= cost;
    account.spent += cost;
    return true;
}

inline bool Adjust(Account& account, int32_t amount)
{
    uint32_t magnitude = static_cast<uint32_t>(amount < 0 ? -int64_t(amount) : amount);
    if (amount < 0)
    {
        if (account.points < magnitude || account.spent > std::numeric_limits<uint32_t>::max() - magnitude)
            return false;
        account.points -= magnitude;
        account.spent += magnitude;
    }
    else
    {
        if (account.points > std::numeric_limits<uint32_t>::max() - magnitude ||
            account.earned > std::numeric_limits<uint32_t>::max() - magnitude)
            return false;
        account.points += magnitude;
        account.earned += magnitude;
    }
    return true;
}

inline bool LockoutReady(uint64_t now, uint64_t last, uint32_t seconds)
{
    return now >= last && now - last >= seconds;
}

inline uint32_t NewLevels(uint8_t highest, uint8_t current)
{
    return current > highest ? static_cast<uint32_t>(current - highest) : 0;
}
}

#endif
