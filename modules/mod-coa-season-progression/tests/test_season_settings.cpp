#include "SeasonSettings.h"

#include <iostream>

int main()
{
    using namespace CoASeason;

    Settings settings = DefaultSettings();
    if (settings.size() != 24 || !ValidSettings(settings))
        return 1;
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
