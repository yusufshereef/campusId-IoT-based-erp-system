#pragma once

#include <stdint.h>

// A 32-byte R307S index page covers 256 physical slot addresses. A set bit
// means occupied, regardless of whether CampusID has a database mapping.
inline bool templateSlotOccupied(const uint8_t index[32], uint16_t slot) {
  const uint8_t bit = slot % 256;
  return (index[bit / 8] & (1u << (bit % 8))) != 0;
}

inline bool templateSlotReserved(const uint8_t reserved[128], uint16_t slot) {
  return (reserved[slot / 8] & (1u << (slot % 8))) != 0;
}

inline uint16_t firstFreeTemplateSlot(const uint8_t index[32],
                                      const uint8_t reserved[128], uint16_t first,
                                      uint16_t last) {
  for (uint16_t slot = first; slot <= last; ++slot) {
    if (!templateSlotOccupied(index, slot) &&
        !templateSlotReserved(reserved, slot)) return slot;
  }
  return 0;
}
