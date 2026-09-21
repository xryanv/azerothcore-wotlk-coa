#ifndef ASCENSION_SEASON_COLLECTION_H
#define ASCENSION_SEASON_COLLECTION_H

#include "Define.h"
#include <string>
#include <vector>

namespace AscensionSeasonCollection
{
    struct Entry
    {
        std::string Type;
        uint32 Target = 0;
        // Appearance ID for appearances; zero for items and vanity.
        uint32 PreviewItem = 0;
        std::string Name;
    };

    // Metadata is immutable after Ascension startup. No ownership is inferred from unlock-all mode.
    bool Validate(std::string const& type, uint32 target, uint32 preview);
    // Empty type searches all types. Case-insensitive name / numeric-ID filter; at most 25 results.
    // Ordinary items require an exact ID. Results are ordered by type, then target.
    std::vector<Entry> Browse(std::string const& type, std::string const& search, uint32 offset = 0);
    // Call only after a successful transaction. Each online character refreshes on its own update thread.
    void Refresh(uint32 account);
}

#endif
