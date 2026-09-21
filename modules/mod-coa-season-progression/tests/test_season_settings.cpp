#include "SeasonSettings.h"

#include <iostream>

int main()
{
    using namespace CoASeason;

    Settings settings = DefaultSettings();
    if (settings.size() != 24 || !ValidSettings(settings))
        return 1;
    for (auto const& [key, expected] : std::map<std::string, uint32_t>{
        {"quest", 3}, {"level", 10}, {"elite", 1}, {"rare", 2}, {"rare_elite", 3},
        {"dungeon", 12}, {"heroic", 18}, {"raid", 30}, {"world", 40}})
        if (settings.at(key) != expected)
            return 10;
    if (!ValidSettingKey("quest") || !ValidSettingKey("world_chance") || ValidSettingKey("bogus"))
        return 2;

    settings["dungeon_min"] = 4;
    settings["dungeon_max"] = 3;
    if (ValidSettings(settings))
        return 3;

    settings = DefaultSettings();
    settings["world_chance"] = 101;
    if (ValidSettings(settings))
        return 4;

    settings = DefaultSettings();
    settings["lockout_enabled"] = 2;
    if (ValidSettings(settings))
        return 5;

    settings = DefaultSettings();
    settings["lockout_seconds"] = 604801;
    if (ValidSettings(settings))
        return 6;

    settings = DefaultSettings();
    settings["level_tokens"] = 101;
    if (ValidSettings(settings))
        return 7;

    settings = DefaultSettings();
    settings["quest"] = 1000001;
    if (ValidSettings(settings))
        return 8;

    settings = DefaultSettings();
    settings.erase("quest");
    if (ValidSettings(settings))
        return 9;

    std::cout << "Season settings validation passed\n";
    return 0;
}
