#ifndef COA_SEASON_REQUEST_RULES_H
#define COA_SEASON_REQUEST_RULES_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace CoASeason
{
enum class RequestClass
{
    Invalid,
    Read,
    Mutation
};

inline bool ShouldServeAdminBootstrap(uint32_t activeSeason, bool admin)
{
    return activeSeason == 0 && admin;
}

inline RequestClass ClassifyRequest(std::vector<std::string> const& fields)
{
    if (fields.size() < 3)
        return RequestClass::Invalid;
    if (fields[2] == "GET")
        return fields.size() == 3 ? RequestClass::Read : RequestClass::Invalid;
    if (fields[2] == "BUY")
        return fields.size() == 6 ? RequestClass::Mutation : RequestClass::Invalid;
    if (fields[2] != "ADMIN" || fields.size() < 4)
        return RequestClass::Invalid;

    std::string const& action = fields[3];
    auto exact = [&fields](std::size_t count, RequestClass type)
    {
        return fields.size() == count ? type : RequestClass::Invalid;
    };
    if (action == "LIST") return exact(4, RequestClass::Read);
    if (action == "GET") return exact(5, RequestClass::Read);
    if (action == "BROWSE") return exact(6, RequestClass::Read);
    if (action == "ACCOUNT") return exact(5, RequestClass::Read);
    if (action == "HISTORY") return exact(6, RequestClass::Read);
    if (action == "CREATE") return exact(6, RequestClass::Mutation);
    if (action == "SETTING") return exact(8, RequestClass::Mutation);
    if (action == "TIER") return exact(9, RequestClass::Mutation);
    if (action == "REWARD") return exact(17, RequestClass::Mutation);
    if (action == "DISABLE") return exact(7, RequestClass::Mutation);
    if (action == "RESET") return exact(6, RequestClass::Mutation);
    if (action == "ACTIVATE") return exact(7, RequestClass::Mutation);
    if (action == "ADJUST") return exact(9, RequestClass::Mutation);
    return RequestClass::Invalid;
}
}

#endif
