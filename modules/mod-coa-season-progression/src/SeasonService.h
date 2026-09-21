#ifndef COA_SEASON_SERVICE_H
#define COA_SEASON_SERVICE_H

#include "ObjectGuid.h"
#include <memory>
#include <string>

class Player;

namespace CoASeason
{
struct Award
{
    uint32 account;
    ObjectGuid guid;
    uint32 character;
    uint8 level;
    std::string activity;
    uint32 entry = 0;
    bool lockout = false;
};

// Only Update owns economy state. Cross-thread ingress and per-player delivery are synchronized.
class Service
{
public:
    static Service& Instance();
    Service();
    ~Service();
    bool Enabled() const;
    void Load(bool enabled);
    void Update();
    void Enqueue(Award const& award);
    void Request(Player* player, std::string const& payload);
    void Deliver(Player* player);
    void Logout(Player* player);

private:
    struct Impl;
    std::unique_ptr<Impl> _impl;
};
}

#endif
