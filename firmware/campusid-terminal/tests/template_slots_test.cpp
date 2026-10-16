#include "../template_slots.h"

#include <assert.h>
#include <string.h>

int main() {
  uint8_t index[32];
  uint8_t reserved[128];
  memset(index, 0, sizeof(index));
  memset(reserved, 0, sizeof(reserved));
  assert(firstFreeTemplateSlot(index, reserved, 1, 64) == 1);

  // A sensor-only orphan occupies slot 1 and must remain untouched.
  index[0] = 0b00000010;
  assert(templateSlotOccupied(index, 1));
  assert(firstFreeTemplateSlot(index, reserved, 1, 64) == 2);

  // Gaps and an occupied slot after a gap are based on the index, not count.
  index[0] = 0b00001010;
  assert(firstFreeTemplateSlot(index, reserved, 1, 64) == 2);
  assert(templateSlotOccupied(index, 3));

  // A full page has no verified free location.
  memset(index, 0xff, sizeof(index));
  assert(firstFreeTemplateSlot(index, reserved, 1, 255) == 0);

  // The next page starts at slot 256, not at templateCount + 1.
  memset(index, 0, sizeof(index));
  index[0] = 1;
  assert(firstFreeTemplateSlot(index, reserved, 256, 511) == 257);

  // A backend mapping is reserved even when its sensor bit is clear.
  memset(index, 0, sizeof(index));
  reserved[2 / 8] |= 1u << (2 % 8);
  assert(firstFreeTemplateSlot(index, reserved, 2, 64) == 3);
  reserved[300 / 8] |= 1u << (300 % 8);
  assert(templateSlotReserved(reserved, 300));
  assert(!templateSlotReserved(reserved, 44));
}
