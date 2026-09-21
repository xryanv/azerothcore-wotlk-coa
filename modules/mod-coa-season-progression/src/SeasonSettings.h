#ifndef COA_SEASON_SETTINGS_H
#define COA_SEASON_SETTINGS_H

#include <cstdint>
#include <map>
#include <string>

namespace CoASeason
{
using Settings = std::map<std::string, uint32_t>;

inline Settings DefaultSettings()
{
    // Cumulative Season Point awards per eligible activity; Bazaar Token settings remain separate below.
    return {{"quest", 3}, {"level", 10}, {"elite", 1}, {"rare", 2}, {"rare_elite", 3},
        {"dungeon", 12}, {"heroic", 18}, {"raid", 30}, {"world", 40}, {"level_tokens", 2},
        {"dungeon_min", 1}, {"dungeon_max", 3}, {"dungeon_chance", 100},
        {"heroic_min", 2}, {"heroic_max", 4}, {"heroic_chance", 100},
        {"raid_min", 4}, {"raid_max", 8}, {"raid_chance", 100},
        {"world_min", 8}, {"world_max", 15}, {"world_chance", 100},
        {"lockout_enabled", 1}, {"lockout_seconds", 86400}};
}

inline bool ValidSettingKey(std::string const& key)
{
    return DefaultSettings().contains(key);
}

inline bool ValidSettings(Settings const& settings)
{
    Settings const defaults = DefaultSettings();
    if (settings.size() != defaults.size())
        return false;

    for (auto const& [key, unused] : defaults)
    {
        (void)unused;
        auto const found = settings.find(key);
        if (found == settings.end() || found->second > 1000000)
            return false;
    }

    if (settings.at("lockout_enabled") > 1 || settings.at("level_tokens") > 100 ||
        settings.at("lockout_seconds") > 604800)
        return false;

    for (std::string const category : {"dungeon", "heroic", "raid", "world"})
        if (settings.at(category + "_min") > settings.at(category + "_max") ||
            settings.at(category + "_max") > 1000 || settings.at(category + "_chance") > 100)
            return false;

    return true;
}
}

#endif
