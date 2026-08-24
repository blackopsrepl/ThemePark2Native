#pragma once

#include <cstdint>

// Room tokens are offsets held by the original `ThisRoomFlagPtr` global. They
// are stable identifiers within this retail executable and contain no assets.
bool widescreenAllowedForRoom(std::uint16_t roomToken);
