/*
 * Copyright (C) 2016+ AzerothCore <www.azerothcore.org>, released under GNU AGPL v3.
 */

#ifndef COA_SEASON_PROGRESSION_STATE_H
#define COA_SEASON_PROGRESSION_STATE_H

#include <atomic>

// The default keeps legacy income available when the optional season module is absent.
namespace CoASeasonState
{
    inline std::atomic<bool> active{false};

    inline bool Active()
    {
        return active.load(std::memory_order_acquire);
    }

    inline void SetActive(bool value)
    {
        active.store(value, std::memory_order_release);
    }
}

#endif
