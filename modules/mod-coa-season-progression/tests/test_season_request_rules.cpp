#include "SeasonRequestRules.h"

#include <iostream>
#include <string>
#include <vector>

using Fields = std::vector<std::string>;

int main()
{
    using namespace CoASeason;
    if (ClassifyRequest(Fields{"1", "r", "GET"}) != RequestClass::Read)
        return 1;
    if (ClassifyRequest(Fields{"1", "r", "BUY", "1", "2", "3"}) != RequestClass::Mutation)
        return 2;
    if (ClassifyRequest(Fields{"1", "r", "BUY", "1", "2"}) != RequestClass::Invalid)
        return 3;

    for (Fields const& fields : {
        Fields{"1", "r", "ADMIN", "LIST"},
        Fields{"1", "r", "ADMIN", "GET", "1"},
        Fields{"1", "r", "ADMIN", "BROWSE", "hat", "0"},
        Fields{"1", "r", "ADMIN", "ACCOUNT", "7"},
        Fields{"1", "r", "ADMIN", "HISTORY", "1", "0"}})
        if (ClassifyRequest(fields) != RequestClass::Read)
            return 4;
    for (Fields const& fields : {
        Fields{"1", "r", "ADMIN", "CREATE", "0", "Season"},
        Fields{"1", "r", "ADMIN", "SETTING", "1", "2", "quest", "3"},
        Fields{"1", "r", "ADMIN", "TIER", "1", "2", "1", "100", "25"},
        Fields{"1", "r", "ADMIN", "REWARD", "1", "2", "0", "appearance", "100", "100", "1", "25", "0", "1", "0", "Hat", "Cosmetic"},
        Fields{"1", "r", "ADMIN", "DISABLE", "1", "2", "7"},
        Fields{"1", "r", "ADMIN", "RESET", "1", "2"},
        Fields{"1", "r", "ADMIN", "ACTIVATE", "1", "2", "RESET%20SEASON"},
        Fields{"1", "r", "ADMIN", "ADJUST", "1", "2", "7", "10", "test"}})
        if (ClassifyRequest(fields) != RequestClass::Mutation)
            return 5;

    if (ClassifyRequest(Fields{"1", "r", "ADMIN", "SETTING", "1", "2", "quest"}) != RequestClass::Invalid)
        return 6;
    if (ClassifyRequest(Fields{"1", "r", "ADMIN", "UNKNOWN"}) != RequestClass::Invalid)
        return 7;
    if (!ShouldServeAdminBootstrap(0, true) || ShouldServeAdminBootstrap(1, true) ||
        ShouldServeAdminBootstrap(0, false))
        return 8;

    std::cout << "Season request shape validation passed\n";
    return 0;
}
