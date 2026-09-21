#ifndef COA_SEASON_ELIGIBILITY_H
#define COA_SEASON_ELIGIBILITY_H

#include <string_view>

namespace CoASeason
{
    // Encounter and world-boss credits use activity caps, not a creature-entry lockout.
    inline bool RequiresEntryLockout(std::string_view activity)
    {
        return activity == "elite" || activity == "rare" || activity == "rare_elite";
    }
}

#endif
