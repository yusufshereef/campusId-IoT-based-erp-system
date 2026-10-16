#pragma once
#include "Arduino.h"
#include <cstring>
#include <deque>

constexpr uint8_t FINGERPRINT_OK = 0;
constexpr uint8_t FINGERPRINT_PACKETRECIEVEERR = 1;
constexpr uint8_t FINGERPRINT_NOFINGER = 2;
constexpr uint8_t FINGERPRINT_IMAGEFAIL = 3;
constexpr uint8_t FINGERPRINT_IMAGEMESS = 6;
constexpr uint8_t FINGERPRINT_FEATUREFAIL = 7;
constexpr uint8_t FINGERPRINT_NOMATCH = 8;
constexpr uint8_t FINGERPRINT_NOTFOUND = 9;
constexpr uint8_t FINGERPRINT_ENROLLMISMATCH = 10;
constexpr uint8_t FINGERPRINT_BADLOCATION = 11;
constexpr uint8_t FINGERPRINT_INVALIDIMAGE = 21;
constexpr uint8_t FINGERPRINT_FLASHERR = 24;

struct SensorFixture {
  std::deque<uint8_t> images;
  uint8_t occupied[128] = {};
  uint16_t capacity = 64;
  uint8_t search = FINGERPRINT_NOTFOUND;
  uint8_t conversion = FINGERPRINT_OK;
  uint8_t create = FINGERPRINT_OK;
  uint8_t store = FINGERPRINT_OK;
  unsigned stores = 0;
  unsigned empty_calls = 0;
  uint16_t stored_slot = 0;
  uint8_t empty_result = FINGERPRINT_OK;
};
inline SensorFixture sensor_fixture;

class Adafruit_Fingerprint {
 public:
  explicit Adafruit_Fingerprint(HardwareSerial*) {}
  uint16_t capacity = 64;
  uint16_t templateCount = 0;
  uint16_t fingerID = 1;
  uint16_t confidence = 100;
  void begin(uint32_t) {}
  bool verifyPassword() { return true; }
  uint8_t getParameters() {
    capacity = sensor_fixture.capacity;
    return FINGERPRINT_OK;
  }
  uint8_t getTemplateCount() {
    templateCount = 0;
    for (unsigned slot = 0; slot < capacity; ++slot)
      if (sensor_fixture.occupied[slot / 8] & (1u << (slot % 8))) ++templateCount;
    return FINGERPRINT_OK;
  }
  uint8_t emptyDatabase() {
    ++sensor_fixture.empty_calls;
    if (sensor_fixture.empty_result == FINGERPRINT_OK)
      std::memset(sensor_fixture.occupied, 0, sizeof(sensor_fixture.occupied));
    return sensor_fixture.empty_result;
  }
  uint8_t getImage() {
    if (sensor_fixture.images.empty()) return FINGERPRINT_NOFINGER;
    const auto next = sensor_fixture.images.front();
    sensor_fixture.images.pop_front();
    return next;
  }
  uint8_t image2Tz(uint8_t = 1) { return sensor_fixture.conversion; }
  uint8_t fingerSearch(uint8_t = 1) { return sensor_fixture.search; }
  uint8_t fingerFastSearch() { return sensor_fixture.search; }
  uint8_t createModel() { return sensor_fixture.create; }
  uint8_t storeModel(uint16_t slot) {
    ++sensor_fixture.stores;
    sensor_fixture.stored_slot = slot;
    if (sensor_fixture.store == FINGERPRINT_OK)
      sensor_fixture.occupied[slot / 8] |= 1u << (slot % 8);
    return sensor_fixture.store;
  }
};
