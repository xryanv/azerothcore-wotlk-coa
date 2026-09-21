// Standalone policy checks; no server build or database is required.
#include "SeasonEligibility.h"
#include "SeasonProgressionState.h"
#include <iostream>

int main()
{
    if (!CoASeason::EligibleHumanSession(true, false))
    {
        std::cerr << "Human session should be eligible for Season Points and tier grants\n";
        return 1;
    }
    if (CoASeason::EligibleHumanSession(true, true) || CoASeason::EligibleHumanSession(false, false))
    {
        std::cerr << "Bot or missing session must not enter Season Point/tier grant flow\n";
        return 1;
    }
    for (char const* activity : {"elite", "rare", "rare_elite"})
        if (!CoASeason::RequiresEntryLockout(activity))
        {
            std::cerr << "Missing creature-entry lockout: " << activity << '\n';
            return 1;
        }
    for (char const* activity : {"world", "dungeon", "heroic", "raid", "quest", "login", "level", ""})
        if (CoASeason::RequiresEntryLockout(activity))
        {
            std::cerr << "Unexpected creature-entry lockout: " << activity << '\n';
            return 1;
        }
    if (CoASeasonState::Active())
        return 1;
    CoASeasonState::SetActive(true);
    if (!CoASeasonState::Active())
        return 1;
    CoASeasonState::SetActive(false);
    if (CoASeasonState::Active())
        return 1;
    std::cout << "Season eligibility and optional-module state tests passed\n";
    return 0;
}
