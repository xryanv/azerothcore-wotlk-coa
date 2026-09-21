#include "SeasonRewardRules.h"

#include <iostream>
#include <set>

int main()
{
    using namespace CoASeason;
    std::set<uint32_t> appearances{100};
    std::set<uint32_t> vanities{200};
    std::set<uint32_t> purchases{7};

    if (!RewardOwned("appearance", 100, 1, appearances, vanities, purchases))
        return 1;
    if (!RewardOwned("vanity", 200, 2, appearances, vanities, purchases))
        return 2;
    if (!RewardOwned("item", 300, 7, appearances, vanities, purchases))
        return 3;
    if (RewardOwned("item", 300, 8, appearances, vanities, purchases))
        return 4;
    if (RewardOwned("appearance", 101, 3, appearances, vanities, purchases))
        return 5;
    if (!RewardOwned("appearance", 101, 7, appearances, vanities, purchases))
        return 6;

    std::cout << "Season reward ownership rules passed\n";
    return 0;
}
