#ifndef COA_SEASON_REWARD_RULES_H
#define COA_SEASON_REWARD_RULES_H

#include <cstdint>
#include <set>
#include <string>

namespace CoASeason
{
inline bool RewardOwned(std::string const& type, uint32_t target, uint32_t rewardId,
    std::set<uint32_t> const& appearances, std::set<uint32_t> const& vanities,
    std::set<uint32_t> const& purchases)
{
    if (purchases.contains(rewardId))
        return true;
    if (type == "appearance")
        return appearances.contains(target);
    if (type == "vanity")
        return vanities.contains(target);
    return false;
}
}

#endif
