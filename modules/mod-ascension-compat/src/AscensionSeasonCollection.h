#ifndef ASCENSION_SEASON_COLLECTION_H
#define ASCENSION_SEASON_COLLECTION_H

#include "Define.h"
#include <string>

namespace AscensionSeasonCollection
{
    // Metadata is immutable after Ascension startup. No ownership is inferred from unlock-all mode.
    bool Validate(std::string const& type, uint32 target, uint32 preview);
    // Call only after a successful transaction. Each online character refreshes on its own update thread.
    void Refresh(uint32 account);
}

#endif
